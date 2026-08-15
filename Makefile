### REPOSITORY SETTINGS BLOCK
# GHCR settings
GHCR_HANDLE ?= klepac-ceraj-lab## your GitHub org
GHCR_USER ?= ## your GitHub org or username
GHCR_PAT ?= ## must be set in your environment (e.g. via .env)
# ECR settings
AWS_REGION ?= us-east-1## AWS region for the account
AWS_PROFILE ?= default## AWS profile to use for login
ECR_REPO ?=	## must be set in your environment (e.g. via .env)
# GENERAL REPO SETTINGS
REPO_TYPE := ghcr## valid values: ghcr or ecr
REGISTRY_ghcr := ghcr.io/$(GHCR_HANDLE)
REGISTRY_ecr := $(ECR_REPO)
REGISTRY := $(REGISTRY_$(REPO_TYPE))
### IMAGE SETTINGS BLOCK
VERSION ?= latest## Version tag on the Image
### HOME STORAGE SETTINGS BLOCK
CONTAINER_HOME ?=$(HOME)/containers
DATABASE_HOME ?=$(HOME)/containers
### MAKEFILE SETTINGS BLOCK
IMAGES := bzip2 halla/0820 omixer_rpm kneaddata/012 metaphlan/3 metaphlan/4 humann/3 humann/4
IMAGE_ALIASES := $(subst /,-,$(IMAGES))

.PHONY: all login build push apptainer clean $(IMAGE_ALIASES)

all: build

login:
	$(info    ECR_REPO is $(ECR_REPO))
	$(info    REGISTRY_ghcr is $(REGISTRY_ghcr))
	$(info    REGISTRY_ecr is $(REGISTRY_ecr))
	$(info    REGISTRY is $(REGISTRY))
ifeq ($(REPO_TYPE),ghcr)
	@[ -n "$(GHCR_PAT)" ] || (echo "GHCR_PAT ENV variable not found! Please set GHCR_PAT"; exit 1)
	@echo "$(GHCR_PAT)" | docker login ghcr.io -u $(GHCR_USER) --password-stdin
else ifeq ($(REPO_TYPE),ecr)
	@[ -n "$(ECR_REPO)" ] || (echo "ECR_REPO ENV variable not found! Please set ECR_REPO"; exit 1)
	@echo "Logging in to ECR with profile $(AWS_PROFILE) in $(AWS_REGION)"
	@aws ecr get-login-password --region $(AWS_REGION) --profile $(AWS_PROFILE) \
	| docker login --username AWS --password-stdin $(REGISTRY)
endif

build: $(IMAGE_ALIASES)

$(IMAGE_ALIASES):
	docker build -t $(REGISTRY)/$@:$(VERSION) \
	             -f $(subst -,/,$@)/Dockerfile \
	             $(subst -,/,$@)

push: login
	@for img in $(IMAGE_ALIASES); do \
	  echo "Pushing $(REGISTRY)/$$img:$(VERSION)"; \
	  docker push $(REGISTRY)/$$img:$(VERSION); \
	done

apptainer: $(IMAGE_ALIASES:%=apptainer-%)

apptainer-%:
	$(info    ECR_REPO is $(ECR_REPO))
	$(info    REGISTRY_ghcr is $(REGISTRY_ghcr))
	$(info    REGISTRY_ecr is $(REGISTRY_ecr))
	$(info    REGISTRY is $(REGISTRY))
	mkdir -p $(CONTAINER_HOME)
	echo "$(GHCR_PAT)" | apptainer registry login --username "$(GHCR_USER)" --password-stdin docker://ghcr.io
	apptainer build $(CONTAINER_HOME)/$*.sif \
	                docker://$(REGISTRY)/$*:$(VERSION)

install: apptainer postinstall
# --password $(GHCR_PAT)
postinstall:
	@SHELL_NAME=$$(basename "$$SHELL"); \
	case "$$SHELL_NAME" in \
		bash) PROFILE_FILE="$$HOME/.bashrc";; \
		zsh)  PROFILE_FILE="$$HOME/.zshrc";; \
		fish) PROFILE_FILE="$$HOME/.config/fish/config.fish";; \
		*)    echo "Unknown shell: $$SHELL_NAME. Please update your PATH manually."; exit 1;; \
	esac; \
	echo "Adding $(PWD)/bin to PATH in $$PROFILE_FILE"; \
	ECHO_LINE='export PATH="$(PWD)/bin:$$PATH"'; \
	if ! grep -Fq "$$ECHO_LINE" "$$PROFILE_FILE"; then \
		echo "$$ECHO_LINE" >> "$$PROFILE_FILE"; \
		echo "PATH updated. Restart your shell or run: source $$PROFILE_FILE"; \
	else \
		echo "PATH already set in $$PROFILE_FILE"; \
	fi

clean:
	rm -f $(CONTAINER_HOME)/*.sif