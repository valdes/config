# java-lsp

A Linux CLI for semantic Java navigation and refactoring. A short-lived client
connects to a persistent daemon, which owns one JDT LS instance per canonical
project root. Rust std handles processes, sockets, threads and files;
`serde_json` is the only direct external crate.

## Build and install

From the workstation config repo:

```sh
make prepare-java-lsp       # fetch locked Cargo dependencies explicitly
make check-java-lsp         # offline unit and protocol tests
nix build path:.#java-lsp   # package, without activating Home Manager
make test-java-lsp-integration  # disposable Maven/Gradle fixtures; may download dependencies
```

Home Manager includes the binary and pins its default JDT LS executable to the
same Nix package as the editor. Normal workstation sync/activation installs it;
these are separate operator actions. Direct development builds use `jdtls` on
PATH. `JAVA_LSP_JDTLS` overrides the executable (not a shell command). Rust 1.89+
is required. JDT LS manages its own Java runtime; project JDK/build setup must
already be usable by JDT LS.

## Commands

The Git worktree root is the default; outside Git pass `--root PATH`. Explicit
roots also support nested projects. Paths are root-relative or absolute inside
that root. Symlink paths and `..` are rejected for editing.

```sh
java-lsp status                       # no automatic startup
java-lsp start                        # wait for JDT LS startup
java-lsp capabilities                 # actual server capabilities and adapter baseline
java-lsp symbols --query PaymentService
java-lsp symbols --file src/main/java/example/PaymentService.java
java-lsp definition --file src/main/java/example/PaymentService.java --at 24:10
java-lsp references --file src/main/java/example/PaymentService.java --at 24:10
java-lsp implementations --file src/main/java/example/PaymentService.java --at 24:10
java-lsp hover --file src/main/java/example/PaymentService.java --at 24:10
java-lsp hierarchy --kind callers --file src/main/java/example/PaymentService.java --at 24:10
java-lsp diagnostics --file src/main/java/example/PaymentService.java
java-lsp actions --file src/main/java/example/PaymentService.java --at 24:10 --end 28:6
java-lsp refresh
java-lsp stop
java-lsp restart
```

Hierarchy kinds: `callers`, `callees`, `supertypes`, `subtypes`. Positions are
**one-based Unicode scalar columns**, not bytes, UTF-16 units, or visual tab
columns. Selection ends are exclusive. The client converts them to UTF-16 LSP
positions. Diagnostics and other raw LSP results retain their native zero-based
UTF-16 ranges; do not copy those directly into CLI positions.

Output is one JSON envelope: `{"ok":true,"result":...}` or
`{"ok":false,"error":{"code":...,"message":...,"details":...}}`.
`--human` pretty-prints results and displays preview diffs. List results have
`items`, `total`, and `truncated`; `--limit N` defaults to 200 and caps at 10,000.
Use narrower queries when truncated. Exit status is 0 for success, 2 for usage
errors, and 1 for other failures.

`--timeout SECONDS` defaults to 60 per server request; `--init-timeout SECONDS`
defaults to 300 per startup phase. Both cap at 3600. Timeout sends LSP cancellation;
it does not mean the query returned zero results. A daemon serializes requests.
Use separate worktrees for concurrent writers. It exits after 30 minutes idle.

## Refactoring workflow

```sh
java-lsp refactor rename --file src/main/java/example/PaymentService.java --at 24:10 --name charge
java-lsp plan show PLAN_ID --human
java-lsp plan apply PLAN_ID
```

Every refactoring produces a **stored preview**, including original contents,
expected file existence, modes, edits and annotations. Preview never writes Java
sources. Applying uses those stored edits, not a rerun of the refactoring. Plans
survive daemon restarts and may only be applied once. The agent reviews the diff
and applies within the user's authorized task, then runs the project's tests.

| Operation | Input |
| --- | --- |
| `rename` | `--at`, `--name` |
| `imports` | `--file` |
| `extract-method`, `extract-variable`, `extract-constant` | `--at`, `--end`, optional `--name` |
| `inline`, `quickfix` | `--at`, optional `--end`; `--describe` lists candidates; choose exact `--action TITLE` if ambiguous |
| `change-signature`, `extract-interface`, `move` | `--describe`, followed by a selected `--spec FILE` or `--spec -` |

Standard navigation/rename and edit-only code actions use LSP. JDT-specific
adapters are restricted to server version **1.60.0**, including its `-SNAPSHOT`
build. Other versions report `incompatible_server` for those operations until
validated. Pull-up, push-down and extract-superclass are explicitly unsupported;
no Java server plugin is installed. Location-dependent operations can be
unavailable even when the underlying server supports the operation.

### Change signature

Use `refactor change-signature ... --at LINE:COLUMN --describe`. Copy the returned
object into a JSON specification, then edit these fields:

```json
{
  "methodName": "charge",
  "modifier": "public",
  "returnType": "int",
  "delegate": false,
  "parameters": [
    {"type":"int","name":"amount","defaultValue":"0","originalIndex":0}
  ],
  "exceptions": []
}
```

Preserve `originalIndex` for existing parameters; array order sets the new order.
Use `originalIndex: -1` and an explicit call-site `defaultValue` for new
parameters. Omitted fields retain the described method's settings. The CLI
resolves the method identity again at the selected position, rather than trusting
an opaque identifier from an old specification.

### Extract interface

`--describe` returns members with `handleIdentifier` and package destinations.
Supply selected handles and an exact destination object from that result:

```json
{"name":"Payment","members":["HANDLE_FROM_DESCRIBE"],"destination":{"...":"COPY_DESTINATION_OBJECT"}}
```

### Move

Default kind is `moveResource` (move a Java source file to a package).
`--describe` returns destinations. Supply:

```json
{"kind":"moveResource","destination":{"...":"COPY_DESTINATION_OBJECT"}}
```

JDT's `moveInstanceMethod`, `moveStaticMember` and `moveTypeToNewFile` are protocol
adapter options; they are location-dependent and may return unsupported or
semantic-conflict errors. Type-to-new-file needs no destination. Resource moves
always update references. Directory moves/deletes and overwrite collisions are
rejected by the edit layer. Error-level JDT refactoring conditions are not
silently confirmed.

## State, synchronization and recovery

Sockets and locks live under `$XDG_RUNTIME_DIR/java-lsp` (fallback: a private
per-user directory in `/tmp`). Indexes use `$XDG_CACHE_HOME/java-lsp`; plans and
logs use `$XDG_STATE_HOME/java-lsp`. Standard HOME-based XDG defaults apply.
Each root has a stable key and a full-root collision check. State directories are
user-private. State is separate from Eglot; neither client shares a JDT data lock.

Commands reconcile saved source/build files and update opened documents. Build
configuration changes trigger JDT reimport. Generated/output directories are
excluded from scanning. JDT may create build output or download dependencies;
Eclipse metadata is redirected to its own data area. Unsaved editor buffers are
not inputs. Avoid editing the same files in another process during application.

JDT's `Started` signal establishes startup readiness, not proof that all
project dependencies resolved. Diagnostics report whether a publication arrived
after validation was requested and whether its document version was supplied.
Versionless publications cannot prove correspondence to an exact document
snapshot. Empty diagnostics are never a substitute for a successful build.

All target files are checked before writing. Application rejects stale previews,
symlink paths, out-of-root edits and overlapping ranges. Files are replaced via
same-directory temporary files with a durable journal. This provides recovery,
not filesystem-wide atomicity or locking against editors that ignore our lock.

```sh
java-lsp plan show PLAN_ID --human
java-lsp plan recover PLAN_ID
```

Recovery rolls an interrupted transaction back to its original files. It refuses
to overwrite intervening edits, and incomplete recovery blocks further writes.
New empty parent directories may remain. Source plans contain private code;
remove obsolete state only when no recovery is pending and the daemon is stopped.

Limits: 32 MiB protocol/plan messages, 8 MiB edited files, 512 files per plan,
100,000 scanned Java/build files, and a bounded 256-event LSP queue. Exceeding a
limit produces an error rather than silently applying a partial result.

## Validation

Offline tests cover framing, Unicode positions, overlapping edits, ordered
resource edits, stale plans, recovery conflicts, concurrent startup, callbacks,
cancellation, crashes, and restart. Real-server tests use temporary projects,
verify sources are unchanged by previews, apply each preview, and compile the
result with `javac`. Maven/Gradle import is performed by JDT LS. This avoids
mistaking build-tool plugin download availability for Java compilation success.
