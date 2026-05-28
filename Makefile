IMAGE_NAME ?= osac-dev
DISTROBOX_NAME ?= osac
HOME_DIR ?= $(HOME)
ARGS ?=

.PHONY: image enter claude stop rm rebuild status help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

image: ## Build the distrobox image
	podman build -t $(IMAGE_NAME) -f Containerfile .

enter: image ## Enter the distrobox (creates it on first run)
	@if ! distrobox list 2>/dev/null | grep -q "$(DISTROBOX_NAME)"; then \
		distrobox create --image $(IMAGE_NAME) --name $(DISTROBOX_NAME) --home $(HOME_DIR); \
	fi
	distrobox enter $(DISTROBOX_NAME)

claude: image ## Run Claude Code inside distrobox (ARGS="--flag" to pass flags)
	@if ! distrobox list 2>/dev/null | grep -q "$(DISTROBOX_NAME)"; then \
		distrobox create --image $(IMAGE_NAME) --name $(DISTROBOX_NAME) --home $(HOME_DIR); \
	fi
	distrobox enter $(DISTROBOX_NAME) -- claude $(ARGS)

stop: ## Stop the running distrobox container
	podman stop $(DISTROBOX_NAME)

rm: ## Remove the distrobox and its container
	distrobox rm $(DISTROBOX_NAME)

rebuild: rm image enter ## Rebuild image from scratch and enter

status: ## Show distrobox and image status
	@echo "=== Images ==="
	@podman images --filter reference=$(IMAGE_NAME) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.Created}}"
	@echo ""
	@echo "=== Distrobox ==="
	@distrobox list 2>/dev/null | head -1; distrobox list 2>/dev/null | grep "$(DISTROBOX_NAME)" || echo "  (not created)"
