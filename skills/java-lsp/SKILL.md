---
name: java-lsp
description: Use the local java-lsp CLI for Java symbol navigation, diagnostics, and semantic refactoring through JDT LS. Apply when Java changes need reference-aware rename, extraction, signature changes, or moves.
---

# Java semantic operations

Run `java-lsp --help` for the command interface. The current Git worktree is the
project root; use `--root` for other projects. JSON is the default output.
Positions are one-based lines and Unicode scalar columns, with exclusive range
ends. Read the exact current source before choosing a position.

Use `symbols`, `references`, `definition`, and `implementations` to resolve Java
symbols. Prefer file positions when methods are overloaded. `capabilities` reports
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
