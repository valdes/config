# AGENTS

This repo contains personal Linux configuration. Do not normalize it into a generic setup.

## Purpose

- Maintain and extend the existing Nix/Home Manager driven environment.
- Respect the repo as an operator-focused workstation, not a demo project.
- Optimize for fast daily use on the current multi-monitor setup.

## Working Style

- Prefer doing the change over proposing a long plan.
- Be concise, direct, and technical.
- Avoid hype, fluff, and motivational language.
- State tradeoffs plainly when they matter.
- If a choice is subjective, bias toward the simpler and more controllable option.

## Repo Preferences

- Terminal-first beats GUI-first.
- Explicit config beats hidden behavior.
- Small scripts beat heavy wrappers when they solve the problem cleanly.
- Workflow-oriented naming beats app-oriented naming.
- Preserve rough but useful local conventions.
- Do not rewrite working config just to make it look cleaner.

## Source Of Truth

- Prefer `home.nix` and related Nix/Home Manager config for managed packages and dotfiles.
- Treat local scripts in `bin/` as intentional workflow glue, not incidental clutter.
- Keep `niri/` and `waybar/` aligned with the existing workspace-driven desktop model.

## UI And UX Taste

- Favor muted, functional, Zenburn-adjacent visuals.
- Prefer readable contrast, compact spacing, and low-noise chrome.
- Avoid trendy UI patterns, decorative gradients, glassmorphism, oversized cards, and ornamental motion.
- Use icons only when they help recognition.
- Respect the current multi-monitor layout and named workspaces: `build`, `debug`, `review`, `ops`, `comm`, `write`, `scratch`.

## Editing Rules

- Make the smallest change that solves the problem.
- Keep files easy to scan.
- Use comments sparingly; only add them when they provide operational context.
- Do not hide important behavior behind magic.
- Prefer reversible edits.
- If introducing a new dependency, justify it through concrete utility.

## Tool Bias

- Reach for fast CLI tools first: `rg`, `fd`, `jq`, `yq`, `fzf`, `bat`, `eza`, `zoxide`.
- Prefer direct shell commands and targeted edits over broad refactors.
- Preserve editor and terminal workflows as first-class paths.

## Change Guardrails

- Do not remove or replace existing tools without a clear payoff.
- Do not flatten opinionated workspace semantics into generic defaults.
- Do not introduce complexity to impress future maintainers.
- Do not treat this repo like a public starter template.

## When Unsure

- Follow the current repo style.
- Choose the option with less ceremony and more operator control.
- Preserve behavior over aesthetic cleanup.
