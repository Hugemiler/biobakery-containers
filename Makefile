### REPOSITORY SETTINGS BLOCK
# GHCR settings
GHCR_HANDLE ?= klepac-ceraj-lab
GHCR_USER ?=
GHCR_PAT ?=
# ECR settings
AWS_REGION ?= us-east-1
AWS_PROFILE ?= default
ECR_REPO ?=
# Registry destinations (publication only, never used as local build identity)
REGISTRY_ghcr := ghcr.io/$(GHCR_HANDLE)
REGISTRY_ecr := $(ECR_REPO)
# ECR_REPO is the full namespace, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/biobakery
ECR_HOST = $(firstword $(subst /, ,$(ECR_REPO)))
# Place in the system to look for LOCAL databases
BUILD_LOCAL_DATABASE_SOURCE ?= /murray/databases

### STORAGE SETTINGS BLOCK
CONTAINER_HOME ?= $(HOME)/containers
DATABASE_HOME ?= $(HOME)/containers

### INVENTORY SETTINGS BLOCK
PYTHON ?= python3
CATALOG_DIR ?= image-catalog
INVENTORY ?= $(CATALOG_DIR)
INVENTORY_TOOL := scripts/image_inventory.py
ARCHIVE_TOOL := scripts/archive_image.py
ARTIFACT_HOME ?= dist
IMAGE_IDS := $(shell $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) ids 2>/dev/null)
APPTAINER_TARGETS := $(IMAGE_IDS:%=apptainer-%)
ARCHIVE_TARGETS := $(IMAGE_IDS:%=archive-%)

# TAG overrides the canonical inventory tag for local/experimental builds.
TAG ?=

.PHONY: all images catalog-json validate login login-ghcr login-aws build push push-ghcr push-aws \
        push-aliases push-ghcr-aliases push-aws-aliases archive apptainer \
        install postinstall clean $(IMAGE_IDS) \
        $(APPTAINER_TARGETS) $(ARCHIVE_TARGETS)

all: build

images: validate
	@$(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) list $(if $(PACKAGE),--package $(PACKAGE),)

catalog-json: validate
	@$(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) json

validate:
	@$(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) validate

# Login is never required for a destination with no eligible images.
login: login-ghcr login-aws

login-ghcr: validate
	@[ -n "$${GHCR_USER:-}" ] || { echo "Set GHCR_USER" >&2; exit 1; }
	@[ -n "$${GHCR_PAT:-}" ] || { echo "Set GHCR_PAT" >&2; exit 1; }
	@printf '%s' "$${GHCR_PAT}" | docker login ghcr.io -u "$${GHCR_USER}" --password-stdin

login-aws: validate
	@[ -n "$(ECR_REPO)" ] || { echo "Set ECR_REPO (full AWS registry namespace)" >&2; exit 1; }
	@aws ecr get-login-password --region "$(AWS_REGION)" --profile "$(AWS_PROFILE)" | \
		docker login --username AWS --password-stdin "$(ECR_HOST)"

build: $(IMAGE_IDS)

# Build wrapper handles optional private S3 authentication before invoking Docker.
# No AWS profile is consulted for ordinary, local, or public-HTTPS builds.
$(IMAGE_IDS): validate
	@$(PYTHON) scripts/build_image.py --inventory "$(INVENTORY)" --id "$@" \
		--tag "$(TAG)" --artifact-home "$(ARTIFACT_HOME)" \
		--aws-db-profile "$(AWS_DB_PROFILE)" --archive-tool "$(ARCHIVE_TOOL)"

# The two registry destinations are independent. Neither build nor save publishes.
push: push-ghcr push-aws

push-ghcr: validate
	@[ -z "$(TAG)" ] || { echo "TAG overrides cannot be pushed" >&2; exit 1; }
	@selected=0; for image_id in $(IMAGE_IDS); do \
		[ "$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" push_ghcr )" = "true" ] || continue; \
		selected=1; break; \
	done; \
	if [ "$$selected" = 0 ]; then echo "No GHCR images selected"; exit 0; fi; \
	[ -n "$${GHCR_USER:-}" ] && [ -n "$${GHCR_PAT:-}" ] || { echo "Set GHCR_USER and GHCR_PAT" >&2; exit 1; }; \
	printf '%s' "$${GHCR_PAT}" | docker login ghcr.io -u "$${GHCR_USER}" --password-stdin || exit 1; \
	for image_id in $(IMAGE_IDS); do \
		[ "$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" push_ghcr )" = "true" ] || continue; \
		repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" repository )"; \
		tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" tag )"; \
		src="$$repository:$$tag"; dst="$(REGISTRY_ghcr)/$$repository:$$tag"; \
		docker image inspect "$$src" >/dev/null 2>&1 || { echo "Missing $$src; build $$image_id first" >&2; exit 1; }; \
		docker tag "$$src" "$$dst" && docker push "$$dst" || exit 1; \
	done

push-aws: validate
	@[ -z "$(TAG)" ] || { echo "TAG overrides cannot be pushed" >&2; exit 1; }
	@selected=0; for image_id in $(IMAGE_IDS); do \
		[ "$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" push_aws )" = "true" ] || continue; \
		selected=1; break; \
	done; \
	if [ "$$selected" = 0 ]; then echo "No ECR images selected"; exit 0; fi; \
	[ -n "$(ECR_REPO)" ] || { echo "Set ECR_REPO" >&2; exit 1; }; \
	aws ecr get-login-password --region "$(AWS_REGION)" --profile "$(AWS_PROFILE)" | docker login --username AWS --password-stdin "$(ECR_HOST)" || exit 1; \
	for image_id in $(IMAGE_IDS); do \
		[ "$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" push_aws )" = "true" ] || continue; \
		repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" repository )"; \
		tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" tag )"; \
		src="$$repository:$$tag"; dst="$(REGISTRY_ecr)/$$repository:$$tag"; \
		docker image inspect "$$src" >/dev/null 2>&1 || { echo "Missing $$src; build $$image_id first" >&2; exit 1; }; \
		docker tag "$$src" "$$dst" && docker push "$$dst" || exit 1; \
	done

# Alias promotion is opt-in and operates separately in each selected registry.
push-aliases: push-ghcr-aliases push-aws-aliases

push-ghcr-aliases: push-ghcr
	@for image_id in $(IMAGE_IDS); do \
		[ "$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" push_ghcr )" = "true" ] || continue; \
		repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" repository )"; \
		tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" tag )"; \
		aliases="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" aliases )"; \
		for alias in $$aliases; do \
			docker buildx imagetools create --tag "$(REGISTRY_ghcr)/$$repository:$$alias" "$(REGISTRY_ghcr)/$$repository:$$tag" || exit 1; \
		done; \
	done

push-aws-aliases: push-aws
	@for image_id in $(IMAGE_IDS); do \
		[ "$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" push_aws )" = "true" ] || continue; \
		repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" repository )"; \
		tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" tag )"; \
		aliases="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$$image_id" aliases )"; \
		for alias in $$aliases; do \
			docker buildx imagetools create --tag "$(REGISTRY_ecr)/$$repository:$$alias" "$(REGISTRY_ecr)/$$repository:$$tag" || exit 1; \
		done; \
	done

# Archive a canonical image already built locally. Never build or push it implicitly.
archive: validate $(ARCHIVE_TARGETS)

$(ARCHIVE_TARGETS): archive-%: validate
	@[ -z "$(TAG)" ] || (echo "Archive requires canonical tags; omit TAG" >&2; exit 1)
	@repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$*" repository )"; \
	 tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$*" tag )"; \
	 [ "$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$*" save )" = "true" ] || { echo "$*: save is false"; exit 0; }; \
	 $(PYTHON) $(ARCHIVE_TOOL) --image "$$repository:$$tag" --id "$*" --tag "$$tag" --output "$(ARTIFACT_HOME)/$*/$$tag"

apptainer: $(APPTAINER_TARGETS)

# Use the already-built local image; works even for images published nowhere.
$(APPTAINER_TARGETS): apptainer-%: validate
	@repository="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$*" repository )"; \
	 tag="$(TAG)"; \
	 [ -n "$$tag" ] || tag="$$( $(PYTHON) $(INVENTORY_TOOL) --inventory $(INVENTORY) get "$*" tag )"; \
	 ref="$$repository:$$tag"; \
	 docker image inspect "$$ref" >/dev/null 2>&1 || { echo "Missing $$ref; build $* first" >&2; exit 1; }; \
	 mkdir -p "$(CONTAINER_HOME)"; \
	 apptainer build "$(CONTAINER_HOME)/$*.sif" "docker-daemon://$$ref"

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
