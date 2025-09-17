SHELL := /bin/bash

VERSION_FILE := build/versions.mk

include $(VERSION_FILE)

# Export version manifest variables for subshells
export $(shell awk -F= '/^[A-Z0-9_]+=/ {print $$1}' $(VERSION_FILE))

IMAGE ?= $(IMAGE_NAME):$(IMAGE_TAG)
SERVICE ?= postgres
ENV_FILE ?= .env
COMPOSE_BASE := deploy/docker-compose.yml
COMPOSE_HARDENED := deploy/docker-compose.hardened.yml
COMPOSE_FILE_SECURE := $(COMPOSE_BASE):$(COMPOSE_HARDENED)
BUILD_CMD ?= docker build

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Available targets:\n"
	@echo "  make build            # Build the Docker image with pinned extension versions"
	@echo "  make up               # Start services with base compose file"
	@echo "  make up-secure        # Start services with hardened compose settings"
	@echo "  make down             # Stop services"
	@echo "  make test             # Spin up stack, run test suite, tear down"
	@echo "  make logs             # Follow postgres logs"
	@echo "  make scan             # Run security scan"
	@echo "  make sync-versions    # Update docs and metadata from versions.mk"
	@echo "  make clean            # Stop services and remove volumes"
	@echo "  make print-versions   # Show current extension versions"

.PHONY: verify-env
verify-env:
	@if [[ ! -f $(ENV_FILE) ]]; then \
		echo "Creating $(ENV_FILE) from template"; \
		cp .env.example $(ENV_FILE); \
	fi

.PHONY: build
build:
	$(BUILD_CMD) \
	  --build-arg PGVECTOR_VERSION=$(PGVECTOR_VERSION) \
	  --build-arg PGVECTOR_COMMIT=$(PGVECTOR_COMMIT) \
	  --build-arg AGE_BRANCH=$(AGE_BRANCH) \
	  --build-arg AGE_VERSION=$(AGE_VERSION) \
	  --build-arg AGE_COMMIT=$(AGE_COMMIT) \
	  -t $(IMAGE) \
	  -f build/Dockerfile .

.PHONY: up
up: verify-env
	COMPOSE_FILE=$(COMPOSE_BASE) docker compose up -d

.PHONY: up-secure
up-secure: verify-env
	COMPOSE_FILE=$(COMPOSE_FILE_SECURE) docker compose up -d

.PHONY: down
down:
	COMPOSE_FILE=$(COMPOSE_BASE) docker compose down

.PHONY: clean
clean:
	COMPOSE_FILE=$(COMPOSE_BASE) docker compose down -v

.PHONY: logs
logs:
	COMPOSE_FILE=$(COMPOSE_BASE) docker compose logs -f $(SERVICE)

.PHONY: test
test: verify-env
	@set -euo pipefail; \
	cleanup() { COMPOSE_FILE=$(COMPOSE_FILE_SECURE) docker compose down; }; \
	trap cleanup EXIT; \
	COMPOSE_FILE=$(COMPOSE_FILE_SECURE) docker compose up -d; \
	COMPOSE_FILE=$(COMPOSE_FILE_SECURE) ./tests/test.sh $(SERVICE)

.PHONY: scan
scan:
	COMPOSE_FILE=$(COMPOSE_BASE) scripts/security/scan.sh

.PHONY: sync-versions
sync-versions:
	scripts/tools/sync-versions.sh

.PHONY: print-versions
print-versions:
	@echo "pgvector: $(PGVECTOR_VERSION) (${PGVECTOR_COMMIT})"
	@echo "Apache AGE: v$(AGE_VERSION) ($(AGE_BRANCH)@$(AGE_COMMIT))"
