# ─── dotenv-sec Makefile ─────────────────────────────────
DOTSEC_HOME  := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
BIN_DIR      := $(HOME)/.local/bin
CONFIG_DIR   := $(HOME)/.config/dotenvsec

.PHONY: install setup update build clean uninstall help

##@ Main targets
install: setup  ## Full install (symlinks + config + shell + images)
setup: symlinks config shell build  ## Alias for install
update: git-pull build  ## Pull latest + rebuild images
uninstall: clean-symlinks clean-config  ## Remove everything

##@ Components
symlinks:  ## Symlink dotsec binaries to ~/.local/bin
	@echo "[*] Creating symlinks..."
	@mkdir -p $(BIN_DIR)
	@for bin in $(DOTSEC_HOME)/bin/*; do \
		ln -sf $$bin $(BIN_DIR)/$$(basename $$bin); \
		echo "  → $(BIN_DIR)/$$(basename $$bin)"; \
	done
	@echo "[+] Symlinks done"

config:  ## Create ~/.config/dotenvsec/config
	@echo "[*] Setting up global config..."
	@mkdir -p $(CONFIG_DIR)/templates
	@if [ ! -f $(CONFIG_DIR)/config ]; then \
		cp $(DOTSEC_HOME)/config/global-defaults $(CONFIG_DIR)/config; \
		echo "  → $(CONFIG_DIR)/config (created)"; \
	else \
		echo "  → $(CONFIG_DIR)/config (already exists, skipped)"; \
	fi
	@echo "[+] Config done"

shell:  ## Add shell integration to ~/.zshrc
	@echo "[*] Shell integration..."
	@grep -q "dotenv-sec" $(HOME)/.zshrc 2>/dev/null && { \
		echo "  Already in .zshrc, skipping"; \
	} || { \
		echo "" >> $(HOME)/.zshrc; \
		echo "# dotenv-sec" >> $(HOME)/.zshrc; \
		echo 'export PATH="$$HOME/.local/bin:$$PATH"' >> $(HOME)/.zshrc; \
		echo 'export DOTSEC_HOME="$(DOTSEC_HOME)"' >> $(HOME)/.zshrc; \
		echo 'eval "$$(dotsec completions zsh 2>/dev/null)"' >> $(HOME)/.zshrc; \
		echo "  Added to .zshrc"; \
	}
	@echo "[+] Shell done"

build:  ## Build all Docker images
	@echo "[*] Building mitmproxy image..."
	@docker build -t dotenv-sec/mitmproxy:latest $(DOTSEC_HOME)/mitmproxy
	@echo "[+] mitmproxy done"
	@echo "[*] Building chromium image..."
	@docker build -t dotenv-sec/chromium:latest $(DOTSEC_HOME)/chromium
	@echo "[+] chromium done"

##@ Maintenance
git-pull:  ## Pull latest changes from git
	@echo "[*] Pulling latest..."
	@git -C $(DOTSEC_HOME) pull
	@echo "[+] Updated"

clean:  ## Stop all mitmproxy containers + remove dotsec network
	@echo "[*] Cleaning containers..."
	@docker ps -q --filter "name=mitmproxy-" | xargs -r docker stop 2>/dev/null || true
	@docker ps -aq --filter "name=mitmproxy-" | xargs -r docker rm 2>/dev/null || true
	@docker network rm dotsec-proxy-net 2>/dev/null || true
	@echo "[+] Clean"

clean-symlinks:  ## Remove dotsec symlinks from ~/.local/bin
	@echo "[*] Removing symlinks..."
	@for bin in $(DOTSEC_HOME)/bin/*; do \
		rm -f $(BIN_DIR)/$$(basename $$bin); \
		echo "  ✗ $(BIN_DIR)/$$(basename $$bin)"; \
	done
	@echo "[+] Symlinks removed"

clean-config:  ## Remove ~/.config/dotenvsec
	@echo "[*] Removing config dir..."
	@rm -rf $(CONFIG_DIR)
	@echo "[+] Config removed"

##@ Help
help:  ## Show this help
	@echo "dotenv-sec — Pentest Environment Launcher"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\033[1m%-20s %s\033[0m\n", "Target", "Description"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "\033[32m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
