SHELL := /usr/bin/env bash

REPO_ROOT := $(CURDIR)
HOME_DIR := $(HOME)
CONFIG_DIR := $(HOME_DIR)/.config
BIN_DIR := $(HOME_DIR)/bin
LOCAL_BIN_DIR := $(HOME_DIR)/.local/bin
BACKGROUND_DIR := $(HOME_DIR)/.local/share/backgrounds
NEWSBOAT_DIR := $(HOME_DIR)/.newsboat
HOME_MANAGER_DIR := $(CONFIG_DIR)/home-manager
SKILLS_DIR := $(REPO_ROOT)/skills
CODEX_SKILLS_DIR := $(HOME_DIR)/.agents/skills
CLAUDE_SKILLS_DIR := $(HOME_DIR)/.claude/skills
MANAGED_SKILLS := manage-makefile
HOME_MANAGER_REF ?= home-manager/master
NIX_FLAKE_FLAGS := --extra-experimental-features "nix-command flakes"
GITLEAKS ?= gitleaks

.DEFAULT_GOAL := help

.PHONY: help sync sync-core sync-hidden sync-bin sync-skills prepare switch apply reload-waybar toggle-waybar install-system-deps-arch install-system-deps-ubuntu26 status doctor secrets-check check

help: ## Show every available target and its purpose
	@awk 'BEGIN { FS = ":.*## "; printf "Targets:\n" } /^[[:alnum:]_.-]+:.*## / { printf "  make %-34s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

sync: sync-core sync-hidden sync-bin sync-skills ## Copy repo-managed files and link shared agent skills into place

sync-core: ## Copy Home Manager, desktop, terminal, and background files
	install -d "$(HOME_MANAGER_DIR)" "$(CONFIG_DIR)/alacritty" "$(CONFIG_DIR)/foot" "$(CONFIG_DIR)" "$(BACKGROUND_DIR)"
	cp "$(REPO_ROOT)/home.nix" "$(HOME_MANAGER_DIR)/"
	cp "$(REPO_ROOT)/flake.nix" "$(HOME_MANAGER_DIR)/"
	cp -r "$(REPO_ROOT)/niri" "$(CONFIG_DIR)/"
	cp -r "$(REPO_ROOT)/waybar" "$(CONFIG_DIR)/"
	cp "$(REPO_ROOT)/zenburn.toml" "$(CONFIG_DIR)/alacritty/alacritty.toml"
	cp "$(REPO_ROOT)/foot/foot.ini" "$(CONFIG_DIR)/foot/foot.ini"
	cp "$(REPO_ROOT)/background.jpg" "$(BACKGROUND_DIR)/background.jpg"

sync-hidden: ## Copy shell, editor, and Newsboat dotfiles
	cp "$(REPO_ROOT)/.emacs" "$(HOME_DIR)/"
	cp "$(REPO_ROOT)/.tmux.conf" "$(HOME_DIR)/"
	install -d "$(NEWSBOAT_DIR)"
	cp "$(REPO_ROOT)/urls" "$(NEWSBOAT_DIR)/urls"

sync-bin: ## Install repo-managed workflow commands
	install -d "$(BIN_DIR)" "$(LOCAL_BIN_DIR)"
	install -m 0755 "$(REPO_ROOT)/bin/dev-session" "$(BIN_DIR)/dev-session"
	install -m 0755 "$(REPO_ROOT)/bin/dev-loop" "$(BIN_DIR)/dev-loop"
	install -m 0755 "$(REPO_ROOT)/bin/niri-ctl" "$(BIN_DIR)/niri-ctl"
	install -m 0755 "$(REPO_ROOT)/bin/install-system-deps-arch" "$(BIN_DIR)/install-system-deps-arch"
	install -m 0755 "$(REPO_ROOT)/bin/install-system-deps-ubuntu26" "$(BIN_DIR)/install-system-deps-ubuntu26"
	install -m 0755 "$(REPO_ROOT)/bin/reload-waybar" "$(LOCAL_BIN_DIR)/reload-waybar"
	install -m 0755 "$(REPO_ROOT)/bin/rssadd" "$(LOCAL_BIN_DIR)/rssadd"
	install -m 0755 "$(REPO_ROOT)/bin/rssget" "$(LOCAL_BIN_DIR)/rssget"
	install -m 0755 "$(REPO_ROOT)/bin/toggle-waybar" "$(LOCAL_BIN_DIR)/toggle-waybar"

sync-skills: ## Link repo-managed skills globally for Codex and Claude
	@set -eu; \
	for skill in $(MANAGED_SKILLS); do \
		source="$(SKILLS_DIR)/$$skill"; \
		test -f "$$source/SKILL.md" || { echo "missing skill: $$source" >&2; exit 1; }; \
		for root in "$(CODEX_SKILLS_DIR)" "$(CLAUDE_SKILLS_DIR)"; do \
			target="$$root/$$skill"; \
			if { test -e "$$target" || test -L "$$target"; } && ! test -L "$$target"; then \
				echo "refusing to replace non-symlink: $$target" >&2; \
				exit 1; \
			fi; \
		done; \
	done; \
	install -d "$(CODEX_SKILLS_DIR)" "$(CLAUDE_SKILLS_DIR)"; \
	for skill in $(MANAGED_SKILLS); do \
		for root in "$(CODEX_SKILLS_DIR)" "$(CLAUDE_SKILLS_DIR)"; do \
			ln -sfn "$(SKILLS_DIR)/$$skill" "$$root/$$skill"; \
		done; \
	done

switch: ## Apply the Home Manager configuration from this repository
	nix $(NIX_FLAKE_FLAGS) run $(HOME_MANAGER_REF) -- switch --flake "path:$(REPO_ROOT)#vals"

apply: sync switch ## Sync files and apply the Home Manager configuration

prepare: ## Bootstrap Home Manager from this repository with backups
	nix $(NIX_FLAKE_FLAGS) run $(HOME_MANAGER_REF) -- switch -b backup --flake "path:$(REPO_ROOT)#vals"

reload-waybar: ## Reload the running Waybar configuration and styles
	"$(REPO_ROOT)/bin/reload-waybar"

toggle-waybar: ## Toggle Waybar visibility
	"$(REPO_ROOT)/bin/toggle-waybar"

install-system-deps-arch: ## Install host dependencies on Arch Linux
	"$(REPO_ROOT)/bin/install-system-deps-arch"

install-system-deps-ubuntu26: ## Install host dependencies on Ubuntu 26.04
	"$(REPO_ROOT)/bin/install-system-deps-ubuntu26"

status: ## Show the concise Git working-tree status
	git status --short

doctor: ## Check that required workstation commands are available
	@for cmd in home-manager cp install git glab emacs emacsclient tmux codex claude foot wl-copy wl-paste firefox keepassxc restic sops age age-keygen gitleaks mat2; do \
		command -v "$$cmd" >/dev/null || { echo "missing: $$cmd"; exit 1; }; \
	done

secrets-check: ## Scan the current branch history for committed secrets
	"$(GITLEAKS)" git --no-banner --redact "$(REPO_ROOT)"

check: ## Validate repo-managed files, scripts, and desktop configuration
	@undocumented="$$(awk '/^[[:alnum:]_-][[:alnum:]_.-]*:/ && $$0 !~ /## / { sub(/:.*/, "", $$1); print $$1 }' "$(REPO_ROOT)/Makefile")"; \
		test -z "$$undocumented" || { printf "undocumented Make targets:\n%s\n" "$$undocumented" >&2; exit 1; }
	test -f "$(REPO_ROOT)/DEVELOPMENT.org"
	test -f "$(REPO_ROOT)/home.nix"
	test -f "$(REPO_ROOT)/niri/config.kdl"
	test -f "$(REPO_ROOT)/waybar/config.jsonc"
	test -f "$(REPO_ROOT)/waybar/style.css"
	test -f "$(REPO_ROOT)/foot/foot.ini"
	test -f "$(REPO_ROOT)/background.jpg"
	test -f "$(REPO_ROOT)/urls"
	test -x "$(REPO_ROOT)/bin/dev-session"
	test -x "$(REPO_ROOT)/bin/dev-loop"
	test -f "$(REPO_ROOT)/skills/manage-makefile/SKILL.md"
	test -f "$(REPO_ROOT)/templates/agent-task.md"
	test -x "$(REPO_ROOT)/tests/dev-loop-test"
	test -x "$(REPO_ROOT)/tests/dev-session-test"
	test -f "$(REPO_ROOT)/bin/niri-ctl"
	test -f "$(REPO_ROOT)/bin/install-system-deps-arch"
	test -f "$(REPO_ROOT)/bin/install-system-deps-ubuntu26"
	test -f "$(REPO_ROOT)/bin/reload-waybar"
	test -f "$(REPO_ROOT)/bin/rssadd"
	test -f "$(REPO_ROOT)/bin/rssget"
	test -f "$(REPO_ROOT)/bin/toggle-waybar"
	niri validate -c "$(REPO_ROOT)/niri/config.kdl"
	bash -n "$(REPO_ROOT)/bin/dev-session"
	bash -n "$(REPO_ROOT)/bin/dev-loop"
	bash -n "$(REPO_ROOT)/bin/niri-ctl"
	bash -n "$(REPO_ROOT)/bin/install-system-deps-arch"
	bash -n "$(REPO_ROOT)/bin/install-system-deps-ubuntu26"
	bash -n "$(REPO_ROOT)/bin/reload-waybar"
	sh -n "$(REPO_ROOT)/bin/rssadd"
	bash -n "$(REPO_ROOT)/bin/rssget"
	bash -n "$(REPO_ROOT)/bin/toggle-waybar"
	bash -n "$(REPO_ROOT)/tests/dev-loop-test"
	bash -n "$(REPO_ROOT)/tests/dev-session-test"
	shellcheck "$(REPO_ROOT)/bin/dev-session" "$(REPO_ROOT)/bin/dev-loop" "$(REPO_ROOT)/bin/niri-ctl" "$(REPO_ROOT)/bin/install-system-deps-arch" "$(REPO_ROOT)/bin/install-system-deps-ubuntu26" "$(REPO_ROOT)/tests/dev-loop-test" "$(REPO_ROOT)/tests/dev-session-test"
	emacs --batch -Q --eval '(with-temp-buffer (insert-file-contents "$(REPO_ROOT)/.emacs") (emacs-lisp-mode) (check-parens))'
	"$(REPO_ROOT)/tests/dev-loop-test"
	"$(REPO_ROOT)/tests/dev-session-test"
