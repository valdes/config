---
name: workstation
description: Change this workstation's desktop, terminal, shell, editor, or agent configuration through its source repository. Use when editing or asked about Niri, Noctalia (bar, launcher, widgets), Foot, Herdr, tmux, Emacs, Newsboat, voxtype, keyd, Home Manager packages, keybindings, window rules, workspaces, helper commands in ~/.local/bin, or shared agent skills — including files under ~/.config/niri, ~/.config/foot, ~/.config/herdr, ~/.config/home-manager, ~/.emacs, or ~/.tmux.conf. The desktop is Niri, not Hyprland; ignore Omarchy's Hyprland paths.
---

# Workstation Configuration

The source of truth is `~/Github/config`. Live files are copies or Home Manager
links, and `make sync` overwrites them. Edit the repository, never the live copy.
Read `~/Github/config/AGENTS.md` before changing anything.

## Where things live

| Live location | Repository source |
|---|---|
| `~/.config/niri/config.kdl` | `niri/config.kdl` |
| `~/.config/foot/foot.ini` | `foot/foot.ini` |
| `~/.config/herdr/config.toml` | `herdr/config.toml` |
| `~/.config/home-manager/{home,flake,keyd}.nix` | `home.nix`, `flake.nix`, `keyd.nix` |
| Noctalia bar, widgets, plugins | `programs.noctalia` in `home.nix` |
| Packages, voxtype, user services | `home.nix` |
| `~/.emacs`, `~/.tmux.conf` | `.emacs`, `.tmux.conf` |
| `~/.newsboat/urls` | `urls` |
| `~/.local/bin/*`, `~/bin/*` | `bin/` |
| `~/.claude/skills/*`, `~/.codex/skills/*` | `skills/` (listed in `MANAGED_SKILLS`) |

Omarchy is installed as a base layer, but the session runs Niri with Noctalia.
Do not edit `~/.config/hypr`, `~/.config/omarchy`, or `~/.local/share/omarchy`
to change this desktop.

## Conventions

- Named workspaces: `build`, `debug`, `review`, `ops`, `comm`, `write`, `scratch`.
  Route windows with `window-rule` + `open-on-workspace`; do not add numbered ones.
- Launch terminals as `foot --app-id=dev.vals.<Name>` so window rules can match them.
- New helper commands go in `bin/`, are installed by `sync-bin`, and must pass
  `bash -n` and ShellCheck through `make check`.
- A new Make target needs a `## ` description, or `make check` fails.

## Verify

1. Run the narrowest check: `niri validate -c niri/config.kdl`, `bash -n`, `shellcheck`.
2. Run `make check` from the repository root.
3. Review `git diff`.

Do not run `make sync`, `make switch`, `make apply`, `make prepare`, or the keyd
targets unless explicitly asked; they change the live environment.
