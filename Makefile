# ==============================================================================
# Makefile for MyFirstiOSApp
# ==============================================================================
# Usage: make <target>
# Run `make help` to see all available targets.

# --- Configuration -----------------------------------------------------------
SCHEME    := MyFirstiOSApp
PROJECT   := MyFirstiOSApp.xcodeproj
SDK       := iphonesimulator
CONFIG    := Debug
SIMULATOR := iPhone 17 Pro
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)

MODEL_FILENAME := Qwen2.5-1.5B-Instruct-Q4_K_M.gguf
MODEL_DIR      := models
MODEL_PATH     := $(MODEL_DIR)/$(MODEL_FILENAME)
MODEL_URL      := https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf
CACHE_PATH     := $(MODEL_DIR)/system-prompt-cache.bin
CACHE_TOOL_DIR := tools/generate-cache

# xcodebuild base command
XCODEBUILD := xcodebuild -scheme $(SCHEME) -project $(PROJECT)

# --- Phony targets -----------------------------------------------------------
.PHONY: help build test lint format fix clean open install download-model generate-cache check preflight

# --- Default target -----------------------------------------------------------
.DEFAULT_GOAL := help

# --- Help --------------------------------------------------------------------
help: ## Show this help message
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Build -------------------------------------------------------------------
build: ## Build for simulator (Debug)
	$(XCODEBUILD) -sdk $(SDK) -configuration $(CONFIG) build

# --- Test --------------------------------------------------------------------
test: ## Run tests on simulator
	$(XCODEBUILD) test \
		-sdk $(SDK) \
		-destination '$(DESTINATION)' \
		-parallel-testing-enabled NO \
		-test-timeouts-enabled YES \
		-default-test-execution-time-allowance 300

# --- Lint --------------------------------------------------------------------
lint: ## Lint with SwiftLint and SwiftFormat (no changes)
	swiftlint lint
	swiftformat --lint .

# --- Format / Fix ------------------------------------------------------------
format: ## Auto-fix with SwiftLint and SwiftFormat
	swiftlint lint --fix
	swiftformat .

fix: format ## Alias for format

# --- Clean -------------------------------------------------------------------
clean: ## Remove build artifacts and DerivedData
	$(XCODEBUILD) clean
	rm -rf DerivedData/
	rm -rf build/

# --- Open in Xcode -----------------------------------------------------------
open: ## Open project in Xcode
	open $(PROJECT)

# --- Install prerequisites ---------------------------------------------------
install: ## Install dev tools (SwiftLint, SwiftFormat) via Homebrew
	@command -v brew >/dev/null 2>&1 || { echo "Error: Homebrew not installed. See https://brew.sh"; exit 1; }
	brew install swiftlint swiftformat

# --- Download LLM model ------------------------------------------------------
download-model: ## Download Qwen2.5-1.5B model (~1.1 GB) for local LLM extraction
	@if [ -f "$(MODEL_PATH)" ]; then \
		echo "Model already exists at $(MODEL_PATH), skipping download."; \
	else \
		echo "Downloading $(MODEL_FILENAME) (~1.1 GB)..."; \
		mkdir -p $(MODEL_DIR); \
		curl -L -o "$(MODEL_PATH)" "$(MODEL_URL)"; \
		echo "Model downloaded to $(MODEL_PATH)"; \
	fi

# --- Generate system prompt KV cache -----------------------------------------
generate-cache: ## Pre-compute the system prompt KV cache for Llama (~30s on Apple Silicon)
	@if [ ! -f "$(MODEL_PATH)" ]; then \
		echo "Error: Model not found at $(MODEL_PATH). Run: make download-model"; \
		exit 1; \
	fi
	@if [ -f "$(CACHE_PATH)" ]; then \
		echo "Cache already exists at $(CACHE_PATH). Delete it to regenerate."; \
	else \
		echo "Building cache generator tool..."; \
		cd "$(CURDIR)/$(CACHE_TOOL_DIR)" && swift build -c release 2>&1; \
		echo "Generating system prompt KV cache..."; \
		cd "$(CURDIR)/$(CACHE_TOOL_DIR)" && swift run -c release --skip-build generate-cache \
			"$(CURDIR)/$(MODEL_PATH)" "$(CURDIR)/$(CACHE_PATH)"; \
	fi

# --- Check prerequisites -----------------------------------------------------
check: ## Verify all required tools and files are present
	@echo "Checking prerequisites..."
	@command -v xcodebuild >/dev/null 2>&1 && echo "  ✓ xcodebuild" || echo "  ✗ xcodebuild (install Xcode)"
	@command -v swiftlint  >/dev/null 2>&1 && echo "  ✓ swiftlint"  || echo "  ✗ swiftlint  (run: make install)"
	@command -v swiftformat >/dev/null 2>&1 && echo "  ✓ swiftformat" || echo "  ✗ swiftformat (run: make install)"
	@command -v brew       >/dev/null 2>&1 && echo "  ✓ brew"        || echo "  ✗ brew (see https://brew.sh)"
	@[ -f "$(MODEL_PATH)" ] && echo "  ✓ LLM model"  || echo "  ✗ LLM model (run: make download-model)"
	@[ -f "$(CACHE_PATH)" ] && echo "  ✓ LLM cache"  || echo "  ✗ LLM cache (run: make generate-cache)"

# --- Preflight ---------------------------------------------------------------
preflight: format lint build test ## Format, lint, build, and test
