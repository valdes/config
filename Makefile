SHELL := /usr/bin/env bash

REPO_ROOT := $(CURDIR)
HOME_DIR := $(HOME)
CONFIG_DIR := $(HOME_DIR)/.config
BIN_DIR := $(HOME_DIR)/bin
LOCAL_BIN_DIR := $(HOME_DIR)/.local/bin
BACKGROUND_DIR := $(HOME_DIR)/.local/share/backgrounds
NEWSBOAT_DIR := $(HOME_DIR)/.newsboat
HOME_MANAGER_DIR := $(CONFIG_DIR)/home-manager
HOME_MANAGER_REF ?= home-manager/master
NIX_FLAKE_FLAGS := --extra-experimental-features "nix-command flakes"

.PHONY: help sync sync-core sync-hidden sync-bin prepare switch apply reload-waybar toggle-waybar status doctor check

help:
	@printf "%s\n" \
		"Targets:" \
		"  make prepare        Bootstrap Home Manager using the repo flake" \
		"  make sync           Copy repo-managed files into place" \
		"  make switch         Run home-manager --impure switch" \
		"  make apply          sync + switch" \
		"  make check          Validate repo-managed files and scripts" \
		"  make reload-waybar  Send SIGUSR2 to waybar" \
		"  make toggle-waybar  Send SIGUSR1 to waybar" \
		"  make status         Show repo status" \
		"  make doctor         Check required commands"

sync: sync-core sync-hidden sync-bin

sync-core:
	install -d "$(HOME_MANAGER_DIR)" "$(CONFIG_DIR)/alacritty" "$(CONFIG_DIR)/ghostty" "$(CONFIG_DIR)" "$(BACKGROUND_DIR)"
	cp "$(REPO_ROOT)/home.nix" "$(HOME_MANAGER_DIR)/"
	cp "$(REPO_ROOT)/flake.nix" "$(HOME_MANAGER_DIR)/"
	cp -r "$(REPO_ROOT)/niri" "$(CONFIG_DIR)/"
	cp -r "$(REPO_ROOT)/waybar" "$(CONFIG_DIR)/"
	cp "$(REPO_ROOT)/zenburn.toml" "$(CONFIG_DIR)/alacritty/alacritty.toml"
	cp "$(REPO_ROOT)/ghostty/config" "$(CONFIG_DIR)/ghostty/config"
	cp "$(REPO_ROOT)/background.jpg" "$(BACKGROUND_DIR)/background.jpg"
	cp "$(REPO_ROOT)/plantuml-1.2023.10.jar" "$(HOME_DIR)/"

sync-hidden:
	cp "$(REPO_ROOT)/.emacs" "$(HOME_DIR)/"
	cp "$(REPO_ROOT)/.tmux.conf" "$(HOME_DIR)/"
	install -d "$(NEWSBOAT_DIR)"
	cp "$(REPO_ROOT)/urls" "$(NEWSBOAT_DIR)/urls"

sync-bin:
	install -d "$(BIN_DIR)" "$(LOCAL_BIN_DIR)"
	install -m 0755 "$(REPO_ROOT)/bin/niri-ctl" "$(BIN_DIR)/niri-ctl"
	install -m 0755 "$(REPO_ROOT)/bin/reload-waybar" "$(LOCAL_BIN_DIR)/reload-waybar"
	install -m 0755 "$(REPO_ROOT)/bin/toggle-waybar" "$(LOCAL_BIN_DIR)/toggle-waybar"

switch:
	home-manager --impure switch

apply: sync switch

prepare:
	nix $(NIX_FLAKE_FLAGS) run $(HOME_MANAGER_REF) -- switch -b backup --flake "path:$(REPO_ROOT)#vals"

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

check:
	test -f "$(REPO_ROOT)/home.nix"
	test -f "$(REPO_ROOT)/niri/config.kdl"
	test -f "$(REPO_ROOT)/waybar/config.jsonc"
	test -f "$(REPO_ROOT)/waybar/style.css"
	test -f "$(REPO_ROOT)/ghostty/config"
	test -f "$(REPO_ROOT)/background.jpg"
	test -f "$(REPO_ROOT)/urls"
	test -f "$(REPO_ROOT)/bin/niri-ctl"
	test -f "$(REPO_ROOT)/bin/reload-waybar"
	test -f "$(REPO_ROOT)/bin/toggle-waybar"
	bash -n "$(REPO_ROOT)/bin/niri-ctl"
	bash -n "$(REPO_ROOT)/bin/reload-waybar"
	bash -n "$(REPO_ROOT)/bin/toggle-waybar"
