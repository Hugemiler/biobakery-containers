### REPOSITORY SETTINGS BLOCK
# GHCR settings
GHCR_HANDLE ?= klepac-ceraj-lab
GHCR_USER ?=
GHCR_PAT ?=
# ECR settings
AWS_REGION ?= us-east-1
AWS_PROFILE ?= default
ECR_REPO ?=
# General registry settings
REPO_TYPE ?= ghcr
REGISTRY_ghcr := ghcr.io/$(GHCR_HANDLE)
REGISTRY_ecr := $(ECR_REPO)
REGISTRY := $(REGISTRY_$(REPO_TYPE))

### STORAGE SETTINGS BLOCK
CONTAINER_HOME ?= $(HOME)/containers
DATABASE_HOME ?= $(HOME)/containers

### INVENTORY SETTINGS BLOCK
PYTHON ?= python3
INVENTORY ?= images.yaml
INVENTORY_TOOL := scripts/image_inventory.py
IMAGE_IDS := $(shell $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) ids 2>/dev/null)
APPTAINER_TARGETS := $(IMAGE_IDS:%=apptainer-%)

# TAG overrides the canonical inventory tag for local/experimental builds.
TAG ?=

.PHONY: all images validate login build push push-aliases apptainer \
        apptainer-login install postinstall clean $(IMAGE_IDS) \
        $(APPTAINER_TARGETS)

all: build

images: validate
	@$(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) list

validate:
	@case "$(REPO_TYPE)" in \
		ghcr|ecr) ;; \
		*) echo "REPO_TYPE must be 'ghcr' or 'ecr'" >&2; exit 1 ;; \
	esac
	@$(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) validate

login: validate
ifeq ($(REPO_TYPE),ghcr)
	@[ -n "$${GHCR_USER:-}" ] || (echo "GHCR_USER environment variable not found"; exit 1)
	@[ -n "$${GHCR_PAT:-}" ] || (echo "GHCR_PAT environment variable not found"; exit 1)
	@echo "$${GHCR_PAT}" | docker login ghcr.io -u "$${GHCR_USER}" --password-stdin
else ifeq ($(REPO_TYPE),ecr)
	@[ -n "$(ECR_REPO)" ] || (echo "ECR_REPO environment variable not found"; exit 1)
	@aws ecr get-login-password --region "$(AWS_REGION)" --profile "$(AWS_PROFILE)" \
	| docker login --username AWS --password-stdin "$(REGISTRY)"
endif

build: $(IMAGE_IDS)

$(IMAGE_IDS): validate
	@repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$@" repository )"; \
	context="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$@" context )"; \
	tag="$(TAG)"; \
	[ -n "$$tag" ] || tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$@" tag )"; \
	version="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$@" version )"; \
	version_arg="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$@" version_arg )"; \
	set --; \
	if [ -n "$$version_arg" ]; then set -- "$$@" --build-arg "$$version_arg=$$version"; fi; \
	if [ -n "$$version" ]; then set -- "$$@" --label "org.opencontainers.image.version=$$version"; fi; \
	echo "Building $(REGISTRY)/$$repository:$$tag from $$context"; \
	docker build "$$@" -t "$(REGISTRY)/$$repository:$$tag" -f "$$context/Dockerfile" "$$context"

push: login
	@[ -z "$(TAG)" ] || (echo "TAG overrides are for local builds and cannot be used with push" >&2; exit 1)
	@for image_id in $(IMAGE_IDS); do \
		repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" repository )"; \
		tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" tag )"; \
		if ! docker image inspect "$(REGISTRY)/$$repository:$$tag" >/dev/null 2>&1; then \
			echo "Canonical local image $(REGISTRY)/$$repository:$$tag is missing" >&2; \
			echo "Build it first with: make $$image_id" >&2; \
			exit 1; \
		fi; \
		echo "Pushing $(REGISTRY)/$$repository:$$tag"; \
		docker push "$(REGISTRY)/$$repository:$$tag" || exit; \
	done

# Mutable aliases (for example metaphlan:4) are deliberately opt-in.
push-aliases: push
	@[ -z "$(TAG)" ] || (echo "TAG overrides cannot be used with push-aliases" >&2; exit 1)
	@for image_id in $(IMAGE_IDS); do \
		repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" repository )"; \
		tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" tag )"; \
		aliases="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" aliases )"; \
		if [ -n "$$aliases" ]; then \
			echo "Checking canonical image $(REGISTRY)/$$repository:$$tag"; \
			docker buildx imagetools inspect "$(REGISTRY)/$$repository:$$tag" >/dev/null || { \
				echo "Canonical image is not published; run 'make push' before 'make push-aliases'" >&2; \
				exit 1; \
			}; \
		fi; \
		for alias in $$aliases; do \
			echo "Promoting $(REGISTRY)/$$repository:$$tag to :$$alias"; \
			docker buildx imagetools create \
				--tag "$(REGISTRY)/$$repository:$$alias" \
				"$(REGISTRY)/$$repository:$$tag" || exit 1; \
			docker tag "$(REGISTRY)/$$repository:$$tag" \
				"$(REGISTRY)/$$repository:$$alias" || exit 1; \
		done; \
	done

apptainer: apptainer-login $(APPTAINER_TARGETS)

apptainer-login: validate
ifeq ($(REPO_TYPE),ghcr)
	@[ -n "$${GHCR_USER:-}" ] || (echo "GHCR_USER environment variable not found"; exit 1)
	@[ -n "$${GHCR_PAT:-}" ] || (echo "GHCR_PAT environment variable not found"; exit 1)
	@echo "$${GHCR_PAT}" | apptainer registry login --username "$${GHCR_USER}" \
		--password-stdin docker://ghcr.io
else ifeq ($(REPO_TYPE),ecr)
	@echo "Apptainer ECR authentication is not configured" >&2; exit 1
endif

$(APPTAINER_TARGETS): apptainer-%: validate
	@repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$*" repository )"; \
	tag="$(TAG)"; \
	[ -n "$$tag" ] || tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$*" tag )"; \
	mkdir -p "$(CONTAINER_HOME)"; \
	echo "Building $(CONTAINER_HOME)/$*.sif from $(REGISTRY)/$$repository:$$tag"; \
	apptainer build "$(CONTAINER_HOME)/$*.sif" "docker://$(REGISTRY)/$$repository:$$tag"

install: apptainer postinstall

postinstall:
	@SHELL_NAME=$$(basename "$$SHELL"); \
	case "$$SHELL_NAME" in \
		bash) PROFILE_FILE="$$HOME/.bashrc"; ECHO_LINE='export PATH="$(CURDIR)/bin:$$PATH"' ;; \
		zsh) PROFILE_FILE="$$HOME/.zshrc"; ECHO_LINE='export PATH="$(CURDIR)/bin:$$PATH"' ;; \
		fish) PROFILE_FILE="$$HOME/.config/fish/config.fish"; ECHO_LINE='fish_add_path "$(CURDIR)/bin"' ;; \
		*) echo "Unknown shell: $$SHELL_NAME. Please update your PATH manually."; exit 1 ;; \
	esac; \
	echo "Adding $(CURDIR)/bin to PATH in $$PROFILE_FILE"; \
	if ! grep -Fq "$$ECHO_LINE" "$$PROFILE_FILE"; then \
		echo "$$ECHO_LINE" >> "$$PROFILE_FILE"; \
		echo "PATH updated. Restart your shell or reload $$PROFILE_FILE"; \
	else \
		echo "PATH already set in $$PROFILE_FILE"; \
	fi

clean:
	@for image_id in $(IMAGE_IDS); do \
		rm -f "$(CONTAINER_HOME)/$$image_id.sif"; \
	done
