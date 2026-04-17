# Container runtime (default: sudo podman)
RUNTIME ?= sudo podman

# Image configuration
REGISTRY  ?= docker.io
NAMESPACE ?= slaclab
IMAGE     ?= opencode

# Resolve the latest opencode version from GitHub releases unless overridden.
# Override at the command line: make build TAG=1.0.180
TAG ?= $(shell curl -sf https://api.github.com/repos/anomalyco/opencode/releases/latest \
         | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')

FULL_IMAGE   = $(REGISTRY)/$(NAMESPACE)/$(IMAGE):$(TAG)
LATEST_IMAGE = $(REGISTRY)/$(NAMESPACE)/$(IMAGE):latest

# Apptainer / SIF configuration
SIF_DIR  ?= /sdf/sw/opencode
SIF_FILE  = $(SIF_DIR)/opencode_$(TAG).sif

.PHONY: all build build-no-cache push login apptainer clean help

## all: build and push the image (versioned tag + latest)
all: build push

## build: build the container image tagged with the opencode version
build:
	@test -n "$(TAG)" || (echo "ERROR: could not resolve opencode version from GitHub API" && exit 1)
	@echo "Building $(FULL_IMAGE)"
	$(RUNTIME) build -t $(FULL_IMAGE) -t $(LATEST_IMAGE) .

## build-no-cache: build the container image without cache
build-no-cache:
	@test -n "$(TAG)" || (echo "ERROR: could not resolve opencode version from GitHub API" && exit 1)
	@echo "Building $(FULL_IMAGE) (no cache)"
	$(RUNTIME) build --no-cache -t $(FULL_IMAGE) -t $(LATEST_IMAGE) .

## push: push both the versioned tag and latest to DockerHub
push:
	$(RUNTIME) push $(FULL_IMAGE)
	$(RUNTIME) push $(LATEST_IMAGE)

## apptainer: pull the versioned DockerHub image and write a SIF to $(SIF_DIR)
apptainer:
	@test -n "$(TAG)" || (echo "ERROR: could not resolve opencode version from GitHub API" && exit 1)
	@echo "Writing $(SIF_FILE)"
	mkdir -p $(SIF_DIR)
	apptainer pull --force $(SIF_FILE) docker://$(FULL_IMAGE)

## login: log in to DockerHub
login:
	$(RUNTIME) login $(REGISTRY)

## clean: remove the local images
clean:
	$(RUNTIME) rmi $(FULL_IMAGE) || true
	$(RUNTIME) rmi $(LATEST_IMAGE) || true

## help: show this help message
help:
	@echo ""
	@echo "Usage: make [target] [TAG=x.y.z ...]"
	@echo ""
	@echo "Targets:"
	@grep -E '^## ' Makefile | sed 's/^## /  /'
	@echo ""
	@echo "Variables (current values):"
	@echo "  RUNTIME      = $(RUNTIME)"
	@echo "  REGISTRY     = $(REGISTRY)"
	@echo "  NAMESPACE    = $(NAMESPACE)"
	@echo "  IMAGE        = $(IMAGE)"
	@echo "  TAG          = $(TAG)"
	@echo "  FULL_IMAGE   = $(FULL_IMAGE)"
	@echo "  LATEST_IMAGE = $(LATEST_IMAGE)"
	@echo "  SIF_DIR      = $(SIF_DIR)"
	@echo "  SIF_FILE     = $(SIF_FILE)"
	@echo ""
