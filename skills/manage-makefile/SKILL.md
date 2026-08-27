---
name: manage-makefile
description: Create or maintain GNU Makefiles as small, self-documented project workflow interfaces. Use when adding or changing Make targets, variables, help output, or project command orchestration; do not replace useful native build-tool behavior.
---

# Manage Makefiles

Read the repository instructions and inspect its existing build files, scripts, and commands before editing. Preserve working conventions and make the smallest change that gives the project a clear command interface.

## Keep Make thin

- Delegate compilation, testing, formatting, and packaging to the project's native tools.
- Put substantial reusable logic in a small script instead of a long recipe.
- Add only targets backed by useful behavior. Do not create placeholder targets to satisfy a fixed template.
- Prefer workflow names such as `prepare`, `dev`, `build`, `check`, `test`, `lint`, `fmt`, `status`, and `clean` when they match the project.
- Use overridable variables for paths, tools, and environment-dependent values when operator control is useful.
- Set a non-default shell only when recipes require it.

## Make every target discoverable

Every explicit target, including helper targets, must carry a concise description on its definition line:

```make
check: ## Run validation without rewriting tracked files
```

Provide `help` as the default goal and generate its output from the `##` descriptions in the Makefile. Keep `.PHONY` declarations aligned with targets that do not produce files. Treat special declarations such as `.PHONY` and `.DEFAULT_GOAL` as metadata, not user targets requiring help entries.

Descriptions must state the observable action. Do not maintain a second handwritten target list that can drift.

## Preserve operational boundaries

- Keep `check` non-mutating with respect to tracked source files. Give formatting or code generation separate explicit targets.
- Make `clean` delete only known build artifacts with resolved, narrowly scoped paths.
- Keep setup, synchronization, deployment, and live-environment changes explicit in target names and descriptions.
- Compose targets through prerequisites when their ordering and behavior are stable and visible.
- Do not hide credentials, network access, privilege escalation, or destructive behavior inside an ordinary build or check target.

## Verify

Run `make help` and confirm every explicit target appears once with a useful description. Use `make -n <target>` where a dry run gives meaningful coverage, then run the narrowest safe targets needed to verify behavior. Run repository-required checks and inspect the final diff.
