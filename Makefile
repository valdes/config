SHELL := /usr/bin/env bash

REPO_ROOT := $(CURDIR)
HOME_DIR := $(HOME)
CONFIG_DIR := $(HOME_DIR)/.config
BIN_DIR := $(HOME_DIR)/bin
LOCAL_BIN_DIR := $(HOME_DIR)/.local/bin

.PHONY: help sync sync-core sync-hidden sync-bin switch apply reload-waybar toggle-waybar status doctor

help:
	@printf "%s\n" \
		"Targets:" \
		"  make sync           Copy repo-managed files into place" \
		"  make switch         Run home-manager --impure switch" \
		"  make apply          sync + switch" \
		"  make reload-waybar  Send SIGUSR2 to waybar" \
		"  make toggle-waybar  Send SIGUSR1 to waybar" \
		"  make status         Show repo status" \
		"  make doctor         Check required commands"

sync: sync-core sync-hidden sync-bin

sync-core:
	install -d "$(CONFIG_DIR)/home-manager" "$(CONFIG_DIR)/alacritty" "$(CONFIG_DIR)"
	cp "$(REPO_ROOT)/home.nix" "$(CONFIG_DIR)/home-manager/"
	cp -r "$(REPO_ROOT)/niri" "$(CONFIG_DIR)/"
	cp -r "$(REPO_ROOT)/waybar" "$(CONFIG_DIR)/"
	cp "$(REPO_ROOT)/zenburn.toml" "$(CONFIG_DIR)/alacritty/alacritty.toml"
	cp "$(REPO_ROOT)/plantuml-1.2023.10.jar" "$(HOME_DIR)/"

sync-hidden:
	cp "$(REPO_ROOT)/.emacs" "$(HOME_DIR)/"
	cp "$(REPO_ROOT)/.tmux.conf" "$(HOME_DIR)/"

sync-bin:
	install -d "$(BIN_DIR)" "$(LOCAL_BIN_DIR)"
	install -m 0755 "$(REPO_ROOT)/bin/niri-ctl" "$(BIN_DIR)/niri-ctl"
	install -m 0755 "$(REPO_ROOT)/bin/reload-waybar" "$(LOCAL_BIN_DIR)/reload-waybar"
	install -m 0755 "$(REPO_ROOT)/bin/toggle-waybar" "$(LOCAL_BIN_DIR)/toggle-waybar"

switch:
	home-manager --impure switch

apply: sync switch

reload-waybar:
	"$(REPO_ROOT)/bin/reload-waybar"

toggle-waybar:
	"$(REPO_ROOT)/bin/toggle-waybar"

status:
	git status --short

doctor:
	@for cmd in home-manager cp install git; do \
		command -v "$$cmd" >/dev/null || { echo "missing: $$cmd"; exit 1; }; \
	done
