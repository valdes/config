---
name: java-lsp
description: Use when implementing, debugging, reviewing, or refactoring Java code and services. Provides semantic navigation, reference and caller analysis, diagnostics, and safe refactoring through the local java-lsp CLI and JDT LS.
---

# Java semantic operations

During routine Java work, use semantic navigation to understand existing behavior
and assess changes: resolve relevant symbols, implementations, callers, and
references. Prefer LSP queries over text matching when Java symbol identity
matters; use `rg` for filenames and literal text. After changes, check diagnostics
for affected Java files, then run the project's relevant build and tests.

Run `java-lsp --help` for the command interface. The current Git worktree is the
project root; use `--root` for other projects. JSON is the default output.
Positions are one-based lines and Unicode scalar columns, with exclusive range
ends. Read the exact current source before choosing a position.

Use `symbols`, `references`, `definition`, and `implementations` to resolve Java
symbols, and `hierarchy --kind callers` to inspect callers. Prefer file positions
when methods are overloaded. `capabilities` reports
the tested JDT version; `actions` reports operations available at a selection.

Refactoring commands return a stored preview, without writing sources. Inspect its
diff, then use `plan apply PLAN_ID` within the user's authorized coding task.
A preview does not require another approval by itself. Apply the stored plan;
do not reproduce its edits manually or recompute it and assume it is identical.
Stale plans must be recreated and reviewed. Plans survive daemon restarts.

For change-signature, extract-interface, and move, first use `--describe`, then
supply the selected parameters with `--spec FILE` or `--spec -`. Read the command
reference installed with the package or `tools/java-lsp/README.md` in the config
repo when constructing a complex specification. Use `--name` for extraction's
linked name. Unsupported operations are explicit errors, not successful no-ops.

The client reads saved files. Save relevant editor buffers before operating; do
not let multiple agents edit the same worktree concurrently. After ordinary file
edits, the next semantic command synchronizes the server; `refresh` does so
explicitly. Diagnostics are not a replacement for the project's build and tests.

If application is interrupted, inspect the plan and use `plan recover PLAN_ID`
to roll back. Recovery refuses to overwrite intervening user edits. Do not reset
Git state to bypass this check. `status` does not start a server; `restart`
reinitializes JDT LS while preserving edit plans.
