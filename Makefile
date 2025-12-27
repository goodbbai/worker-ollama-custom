# Makefile for Runpod Ollama Handler
# Simplifies common Docker operations

.PHONY: help verify build push test run stop clean logs shell extract clean-cache list-cache

# Default target
.DEFAULT_GOAL := help

# Load .env if present (Make does not read it automatically)
# - Prefer a repo-root .env for shared config
# - Allow a local runpod_ollama/.env to override it
-include ../.env
-include .env

# Configuration (override with environment variables)
REGISTRY ?= your-username
IMAGE_NAME ?= runpod-ollama
TAG ?= latest
# Model file selection:
# - Prefer MODEL_FILE if set
# - Else accept legacy MODEL_FILE_NAME
# - Else default to model.gguf
MODEL_FILE ?=
MODEL_FILE_NAME ?=
ifeq ($(strip $(MODEL_FILE)),)
  ifneq ($(strip $(MODEL_FILE_NAME)),)
    MODEL_FILE := $(MODEL_FILE_NAME)
  else
    MODEL_FILE := model.gguf
  endif
endif
ifeq ($(strip $(MODEL_FILE_NAME)),)
  MODEL_FILE_NAME := $(MODEL_FILE)
endif
MODEL_NAME ?= $(basename $(MODEL_FILE))
TEST_PORT ?= 11434
PORT ?= 11434
PORT_HEALTH ?= 8080
EXTRACTION_CACHE_DIR ?= ./extracted-models
COMPOSE_FILE ?= docker/docker-compose.yml

FULL_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(TAG)

# Export config for scripts invoked by recipes and docker-compose
export REGISTRY IMAGE_NAME TAG MODEL_FILE MODEL_FILE_NAME MODEL_NAME TEST_PORT PORT PORT_HEALTH EXTRACTION_CACHE_DIR FULL_IMAGE

# Extraction paths (computed lazily; using first+last 1MB fingerprint for speed)
# Hashes first 1MB + last 1MB instead of entire file (much faster for large models)
GGUF_HASH = $(shell (head -c 1048576 "$(MODEL_FILE)" 2>/dev/null; tail -c 1048576 "$(MODEL_FILE)" 2>/dev/null) | shasum -a 256 | cut -d' ' -f1)
EXTRACTION_PATH = $(EXTRACTION_CACHE_DIR)/$(GGUF_HASH)
EXTRACTED_MODELS_PATH = $(EXTRACTION_PATH)/models

# Export extraction paths for docker-compose
export EXTRACTED_MODELS_PATH

help: ## Show this help message
	@echo "Runpod Ollama Handler - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration:"
	@echo "  REGISTRY    = $(REGISTRY)"
	@echo "  IMAGE_NAME  = $(IMAGE_NAME)"
	@echo "  TAG         = $(TAG)"
	@echo "  FULL_IMAGE  = $(FULL_IMAGE)"
	@echo "  MODEL_FILE  = $(MODEL_FILE)"
	@echo "  MODEL_NAME  = $(MODEL_NAME)"
	@echo "  TEST_PORT   = $(TEST_PORT) (local testing - API)"
	@echo "  PORT        = $(PORT) (production - Ollama API)"
	@echo "  PORT_HEALTH = $(PORT_HEALTH) (production - health check)"
	@echo ""
	@echo "Example usage:"
	@echo "  make build MODEL_FILE=my-model.gguf"
	@echo "  make run"
	@echo "  make test"
	@echo ""

verify: ## Verify all variables and configuration
	@echo "=== Variable Verification ==="
	@echo ""
	@echo "Required Variables:"
	@echo "  REGISTRY           = $(REGISTRY)"
	@if [ "$(REGISTRY)" = "your-username" ]; then \
		echo "    ⚠️  WARNING: REGISTRY still set to default 'your-username'"; \
	else \
		echo "    ✅ OK"; \
	fi
	@echo "  IMAGE_NAME         = $(IMAGE_NAME)"
	@if [ -z "$(IMAGE_NAME)" ]; then \
		echo "    ❌ ERROR: IMAGE_NAME is empty"; \
	else \
		echo "    ✅ OK"; \
	fi
	@echo "  TAG                = $(TAG)"
	@if [ -z "$(TAG)" ]; then \
		echo "    ❌ ERROR: TAG is empty"; \
	else \
		echo "    ✅ OK"; \
	fi
	@echo "  MODEL_FILE         = $(MODEL_FILE)"
	@if [ -z "$(MODEL_FILE)" ]; then \
		echo "    ❌ ERROR: MODEL_FILE is empty"; \
	elif [ ! -f "$(MODEL_FILE)" ]; then \
		echo "    ❌ ERROR: File '$(MODEL_FILE)' not found"; \
	else \
		echo "    ✅ OK (file exists)"; \
	fi
	@echo "  MODEL_NAME         = $(MODEL_NAME)"
	@if [ -z "$(MODEL_NAME)" ]; then \
		echo "    ❌ ERROR: MODEL_NAME is empty"; \
	else \
		echo "    ✅ OK"; \
	fi
	@echo "  TEST_PORT          = $(TEST_PORT)"
	@if [ -z "$(TEST_PORT)" ]; then \
		echo "    ❌ ERROR: TEST_PORT is empty"; \
	else \
		echo "    ✅ OK (local testing)"; \
	fi
	@echo "  PORT               = $(PORT)"
	@if [ -z "$(PORT)" ]; then \
		echo "    ❌ ERROR: PORT is empty"; \
	else \
		echo "    ✅ OK (production)"; \
	fi
	@echo ""
	@echo "Computed Variables:"
	@echo "  FULL_IMAGE         = $(FULL_IMAGE)"
	@echo "  EXTRACTION_CACHE_DIR = $(EXTRACTION_CACHE_DIR)"
	@if [ -d "$(EXTRACTION_CACHE_DIR)" ]; then \
		echo "    ✅ Cache directory exists"; \
	else \
		echo "    ℹ️  Cache directory doesn't exist yet (will be created on first extraction)"; \
	fi
	@if [ -f "$(MODEL_FILE)" ]; then \
		echo "  GGUF_HASH          = $(GGUF_HASH)"; \
		if [ -z "$(GGUF_HASH)" ]; then \
			echo "    ⚠️  WARNING: Unable to compute fingerprint"; \
		else \
			echo "    ✅ OK (first+last 1MB fingerprint)"; \
		fi; \
		echo "  EXTRACTION_PATH    = $(EXTRACTION_PATH)"; \
		if [ -d "$(EXTRACTION_PATH)" ]; then \
			echo "    ✅ Model already extracted"; \
		else \
			echo "    ℹ️  Model not yet extracted"; \
		fi; \
		echo "  EXTRACTED_MODELS_PATH = $(EXTRACTED_MODELS_PATH)"; \
	else \
		echo "  GGUF_HASH          = (skipped - MODEL_FILE not found)"; \
		echo "  EXTRACTION_PATH    = (skipped - MODEL_FILE not found)"; \
		echo "  EXTRACTED_MODELS_PATH = (skipped - MODEL_FILE not found)"; \
	fi
	@echo ""
	@echo "Environment Files:"
	@if [ -f "../.env" ]; then \
		echo "  ../.env            ✅ Found (repo-root)"; \
	else \
		echo "  ../.env            ℹ️  Not found"; \
	fi
	@if [ -f ".env" ]; then \
		echo "  .env               ✅ Found (local)"; \
	else \
		echo "  .env               ℹ️  Not found"; \
	fi
	@echo ""
	@echo "Docker Availability:"
	@if command -v docker >/dev/null 2>&1; then \
		echo "  Docker             ✅ Available"; \
		if docker ps >/dev/null 2>&1; then \
			echo "  Docker Daemon      ✅ Running"; \
		else \
			echo "  Docker Daemon      ❌ Not running"; \
		fi; \
	else \
		echo "  Docker             ❌ Not installed"; \
	fi
	@echo ""
	@echo "Scripts:"
	@if [ -f "./scripts/extract-model.sh" ]; then \
		echo "  extract-model.sh   ✅ Found"; \
	else \
		echo "  extract-model.sh   ❌ Missing"; \
	fi
	@if [ -f "./scripts/build.sh" ]; then \
		echo "  build.sh           ✅ Found"; \
	else \
		echo "  build.sh           ❌ Missing"; \
	fi
	@if [ -f "./scripts/test.sh" ]; then \
		echo "  test.sh            ✅ Found"; \
	else \
		echo "  test.sh            ❌ Missing"; \
	fi
	@if [ -f "./docker/Dockerfile" ]; then \
		echo "  Dockerfile         ✅ Found"; \
	else \
		echo "  Dockerfile         ❌ Missing"; \
	fi
	@echo ""
	@echo "=== Verification Complete ==="

extract: ## Extract model only (use: make extract MODEL_FILE=model.gguf)
	@echo "Extracting model..."
	@if [ ! -f "$(MODEL_FILE)" ]; then \
		echo "Error: Model file '$(MODEL_FILE)' not found!"; \
		echo "Usage: make extract MODEL_FILE=your-model.gguf"; \
		exit 1; \
	fi
	@./scripts/extract-model.sh \
		--model-file "$(MODEL_FILE)" \
		--model-name "$(MODEL_NAME)" \
		--output-dir "$(EXTRACTION_PATH)"
	@echo "✅ Extraction complete"

build: ## Build Docker image (use: make build MODEL_FILE=model.gguf)
	@echo "Building Docker image for linux/amd64 platform..."
	@if [ ! -f "$(MODEL_FILE)" ]; then \
		echo "Error: Model file '$(MODEL_FILE)' not found!"; \
		echo "Usage: make build MODEL_FILE=your-model.gguf"; \
		exit 1; \
	fi
	@echo "Step 1: Extracting model..."
	@./scripts/extract-model.sh \
		--model-file "$(MODEL_FILE)" \
		--model-name "$(MODEL_NAME)" \
		--output-dir "$(EXTRACTION_PATH)"
	@echo "Step 2: Building Docker image..."
	docker build \
		--platform linux/amd64 \
		--build-arg MODEL_NAME="$(MODEL_NAME)" \
		--build-arg EXTRACTED_MODELS_PATH="$(EXTRACTED_MODELS_PATH)" \
		--build-arg PORT="$(PORT)" \
		--build-arg PORT_HEALTH="$(PORT_HEALTH)" \
		-f docker/Dockerfile \
		-t "$(FULL_IMAGE)" \
		.
	@echo "✅ Build complete: $(FULL_IMAGE)"

build-interactive: ## Interactive build using build.sh script
	./scripts/build.sh

push: ## Push image to registry
	@echo "Pushing $(FULL_IMAGE) to registry..."
	docker push "$(FULL_IMAGE)"
	@echo "✅ Push complete"

run: ## Run container locally
	@echo "Starting container..."
	@echo "Using docker-compose file: $(COMPOSE_FILE)"
	docker compose -f $(COMPOSE_FILE) up -d
	@echo "✅ Container started"
	@echo "   API endpoint:    http://localhost:$(TEST_PORT)"
	@echo "   Health endpoint: http://localhost:$(PORT_HEALTH)"
	@echo "   View logs:       make logs"
	@echo "   Stop:            make stop"

test: ## Test the running container
	@echo "Testing endpoint at http://localhost:$(TEST_PORT)..."
	./scripts/test.sh http://localhost:$(TEST_PORT) http://localhost:$(PORT_HEALTH)

test-remote: ## Test remote Runpod endpoint (use: make test-remote ENDPOINT_ID=xxx RUNPOD_API_KEY=xxx)
	@if [ -z "$(ENDPOINT_ID)" ]; then \
		echo "Error: ENDPOINT_ID not set"; \
		echo "Usage: make test-remote ENDPOINT_ID=your-endpoint-id RUNPOD_API_KEY=your-api-key"; \
		exit 1; \
	fi
	@if [ -z "$(RUNPOD_API_KEY)" ]; then \
		echo "Error: RUNPOD_API_KEY not set"; \
		echo "Usage: make test-remote ENDPOINT_ID=your-endpoint-id RUNPOD_API_KEY=your-api-key"; \
		echo "Note: You can also set RUNPOD_API_KEY in .env file"; \
		exit 1; \
	fi
	@echo "Testing endpoint at https://$(ENDPOINT_ID).api.runpod.ai..."
	RUNPOD_API_KEY=$(RUNPOD_API_KEY) REMOTE_TEST=true ./scripts/test.sh https://$(ENDPOINT_ID).api.runpod.ai

stop: ## Stop the running container
	@echo "Stopping container..."
	docker compose -f $(COMPOSE_FILE) down
	@echo "✅ Container stopped"

logs: ## Show container logs
	docker compose -f $(COMPOSE_FILE) logs -f runpod-ollama

shell: ## Open shell in running container
	docker compose -f $(COMPOSE_FILE) exec runpod-ollama /bin/bash

clean: ## Remove container and image
	@echo "Cleaning up..."
	@docker compose -f $(COMPOSE_FILE) down 2>/dev/null || true
	@docker rmi "$(FULL_IMAGE)" 2>/dev/null || true
	@echo "✅ Cleanup complete"
	@echo ""
	@echo "To also clean extraction cache, run: make clean-cache"

clean-cache: ## Clean all extraction cache
	@echo "Cleaning extraction cache at $(EXTRACTION_CACHE_DIR)..."
	@rm -rf "$(EXTRACTION_CACHE_DIR)"
	@echo "✅ Cache cleaned"

clean-model-cache: ## Clean specific model cache (use: make clean-model-cache MODEL_FILE=model.gguf)
	@if [ ! -f "$(MODEL_FILE)" ]; then \
		echo "Error: MODEL_FILE not set or file not found"; \
		echo "Usage: make clean-model-cache MODEL_FILE=your-model.gguf"; \
		exit 1; \
	fi
	@echo "Cleaning cache for $(MODEL_FILE)..."
	@rm -rf "$(EXTRACTION_PATH)"
	@echo "✅ Model cache cleaned"

list-cache: ## List cached extractions
	@echo "Cached extractions in $(EXTRACTION_CACHE_DIR):"
	@if [ -d "$(EXTRACTION_CACHE_DIR)" ]; then \
		ls -lh "$(EXTRACTION_CACHE_DIR)" 2>/dev/null || echo "Cache directory is empty"; \
	else \
		echo "No cache directory found"; \
	fi

clean-all: ## Remove all runpod-ollama images and containers
	@echo "Removing all runpod-ollama containers..."
	@docker ps -a | grep runpod-ollama | awk '{print $$1}' | xargs docker rm -f 2>/dev/null || true
	@echo "Removing all runpod-ollama images..."
	@docker images | grep runpod-ollama | awk '{print $$3}' | xargs docker rmi -f 2>/dev/null || true
	@echo "✅ All cleaned up"

info: ## Show image information
	@echo "Image Information:"
	@docker images "$(FULL_IMAGE)" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" || echo "Image not found"
	@echo ""
	@echo "Running Containers:"
	@docker compose -f $(COMPOSE_FILE) ps

quick-start: build run ## Build and run in one command
	@echo ""
	@echo "✅ Quick start complete!"
	@echo "   Container running at: http://localhost:$(TEST_PORT)"
	@echo "   Run 'make test' to verify"

deploy-info: ## Show Runpod deployment information
	@echo "Runpod Deployment Information:"
	@echo ""
	@echo "1. Push image to registry:"
	@echo "   make push"
	@echo ""
	@echo "2. Create Load Balancer endpoint at:"
	@echo "   https://www.runpod.io/console/serverless"
	@echo ""
	@echo "3. Configuration:"
	@echo "   - Type: Load Balancer (NOT Queue!)"
	@echo "   - Docker Image: $(FULL_IMAGE)"
	@echo "   - Container Disk: $(shell du -h $(MODEL_FILE) 2>/dev/null | cut -f1 || echo "N/A") + 10GB"
	@echo "   - GPU: Select based on model size"
	@echo ""
	@echo "4. Configure your Ollama client:"
	@echo "   - URL: https://ENDPOINT_ID.api.runpod.ai"
	@echo "   - Bearer Token: Your Runpod API key"
	@echo ""
	@echo "See DEPLOYMENT.md for detailed instructions"
