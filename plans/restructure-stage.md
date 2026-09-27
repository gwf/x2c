# Restructure src/stage.x

> Status: needs author review - 2026-09-27. Read-only review of
> `src/stage.x` at `origin/meta-integration` 87d79f00 (1,311 lines). No
> source was changed. Waiting for Gary's review before implementation.

## Goal

Split `src/stage.x` by responsibility, delete its hand-rolled compiler
state save/restore, and share the helper wire framing, with no change in
behavior, group C output, or compile-time performance. Settled: the REPL
stays Lisp-interpreted for submissions; the native meta helper
architecture stays.

## Current map

Line ranges at 87d79f00. Callers are from `git grep` over `src lib etc
commands`.

| Lines | Responsibility | Functions | External callers |
|---|---|---|---|
| 50-200 (~150) | Argument conversion: constant folding, `meta` arguments | `literal_text_value`, `_meta_constant_leaf`, `Compiler.folded_constant`, `Compiler.meta_argument` | `repl-lower.x` (folded_constant x2, literal_text_value), `macros.x:2425` |
| 200-400 (~200) | Result conversion to C expressions | `_meta_value_type`, `_meta_immutable`, `_meta_hex_float`, `_meta_refuse`, `_meta_data`, `Compiler.meta_value_expression`, `check_meta_call`, `meta_is_comptime_only` | `compiler.x`, `macros.x` x2, `expressions.x`, `parse.x` |
| 405-440 (~35) | Toolchain state for group builds | `_meta_headers`, `use_meta_toolchain`, `meta_cc` | `frontend.x:93`, `meta-project.x:413` |
| 440-500 (~60) | Group membership and reachability | `stage_meta_in_process`, `groups_meta`, `_function_identity`, `group_meta_function`, `record_meta_import`, `meta_reaches_compile_time` | `frontend.x:403`, `macros.x`, `parse.x` |
| 500-860 (~360) | Group emission | `_meta_local_include`, `_meta_group_units`, `_meta_entry_function`, `_meta_call`, `_meta_braced`, `_meta_initial_copies`, `_meta_group_entry`, `_meta_template_calls`, `_meta_native_targets`, `_meta_group_code` | internal (2 callers of `_meta_group_code`) |
| 860-900 (~40) | C compiler identity and error extraction | `meta_cc_identity`, `_meta_cc_error`, `meta_cc_run` | `meta-project.x` x3 |
| 900-930 (~30) | Unbound-prototype check | `_meta_unbound_callee`, `_meta_group_unbound` | internal (2) |
| 930-968 (~40) | Project meta build output | `use_meta_build_directory`, `write_meta_build` | `meta-project.x` x2, `compiler.x:2097` |
| 968-1235 (~270) | Helper process client: state, lifecycle, framing, timeout, reply dispatch | `stop_meta_helper`, `_helper_shutdown`, `use_meta_helper`, `begin_meta_unit`, `_helper_stop/start/send/limit/now/receive/ending/missing/refuse`, `meta_helper_call` | `main.x:228`, `meta-project.x` x2, `frontend.x:285`, `macros.x:2389` |
| 1236-1311 (~75) | In-process session staging | `_stage_meta_group`, `stage_meta_group`, `bind_meta_group` | `macros.x:2390` (bind_meta_group only) |

Findings:

- In-process staging is live. `Frontend.open_session` (`frontend.x:403`)
  calls `Compiler.stage_meta_in_process`; `commands/repl/repl.x:287` and
  `commands/repl/tests/api-check.x:358` call `open_session`. REPL
  submissions are interpreted, but a `meta` function defined in a session
  is compiled into a native group and loaded in process. It is not dead.
- `Compiler.stage_meta_group` is exported but has one caller,
  `bind_meta_group`; make it static.
- Toolchain and C compiler helpers (405-440, 860-900) serve
  `meta-project.x` (5 calls) and `_stage_meta_group` (1 call).
  `meta-project.x:141` `_meta_cc` is a one-line wrapper of `meta_cc_run`.
  They belong with the project build in `meta-project.x`.
- The helper client is a second, independent owner of process state
  (`helper_path`, `helper_failures`, `helper_units`, pid, pipes, buffer,
  table, reset flag) populated only by `meta-project.x`
  (`use_meta_helper`). Its producer and consumer are split across units.
- `_helper_now` repeats `clock_gettime(CLOCK_MONOTONIC)` that
  `lib/logger.x:327` and the `$time` macro in `lib/system-macros.xmacro:63`
  already use; there is no exported monotonic-seconds operation to reuse,
  so keep it (6 lines), but move it with the client.
- `lib/process.x` `Job` covers one-way capture, kill, and wait. It has no
  bidirectional request/reply pipe or read deadline, so it does not replace
  `_helper_start/_helper_receive`. Extending `Job` for one caller would
  enlarge the requirement; not proposed.

## `_meta_group_code` save/restore

`_meta_group_code` (784-858) copies `struct Compiler` and `struct
GenNames` by value, opens a `SymTxn`, then overwrites 23 fields: copies of
`names.adapters`, `names.file_scope_owners`, `id_keys`, `key_ids`,
`origins`, `fn_defs`, `protocol_helpers`, `meta_regions`; fresh `inits`,
`early_decls`, `init_tokens`, `static_init_deps`, `deps`; zeroed
`needs_exception`, `macro_stack`, `macro_holes`, `meta_body`,
`return_type`, `lambda_scopes`, `source_facts`; plus `recovery_depth + 1`,
`filename`, and a private `Diagnostics`. After `transform` and
`generate_code_text` it restores both structs and rolls back the
transaction.

Why each group is needed: the backend (`transform`, `generate_code_text`)
appends to per-unit emission state (inits, declarations, adapters,
helpers, cache ids, deps). The group borrows the unit's bindings and types
but must not leave its generated names, cache rows, or helpers in the
unit's C.

The ordinary operation is a child compiler: `Compiler.new_shared(c)` via
`_new(owner)` (`compiler.x:335`) already gives fresh `inits`,
`early_decls`, `init_tokens`, `static_init_deps`, `deps`, zeroed
per-function state, inherited `recovery_depth`, and its own diagnostics;
`borrow_unit_semantics` (`compiler.x:297`) is the documented way to share
`sym` and the semantic tables, as `macros.x:1513` does for macro imports.
Two differences decide the shape:

1. `_new(owner)` shares `owner.names` and `borrow_unit_semantics` shares
   `fn_defs`, `id_keys`, `key_ids`, `protocol_helpers`, `meta_regions` by
   reference. The group must not mutate them, so the child needs copies of
   exactly those six tables plus `names` (and `origins`). That is one
   private helper, `_meta_group_compiler(c)`, of about 15 lines: new
   child, `borrow_unit_semantics`, then replace the mutated tables with
   `.copy()` and `names` with a copied `GenNames`. The `SymTxn` stays,
   because `sym` is shared by design.
2. The child needs whatever else `transform` reads from the unit
   (`macros`, `macro_lisp`, `unit_nodes`, `meta_defs`, `meta_build`,
   include dirs, package state). `_new(owner)` covers package state,
   `include_dirs`, `meta_build`; the step's first task is to list fields
   `transform`/`generate_code_text` read and add only those. If that list
   grows past the current 23 assignments, stop and keep the save/restore
   with a comment; the child is not worth more code.

Evidence that output is preserved: the group C for every meta fixture and
for the project build must be byte-identical before and after. Capture it
by setting the project build directory (`write_meta_build` writes
`group-K.c/.h`) and the session cache (`$root/meta/<key>/group.c`, whose
key is the SHA-256 of the C, so an unchanged key proves unchanged C).
Also compare the unit's own emitted C for the same fixtures, which proves
nothing leaked in either direction.

Expected result: about 40 lines of `_meta_group_code` become about 20,
and restore bugs (a missed field) become impossible because nothing is
restored. It does not touch emitted C.

## Helper protocol

Both ends hand-write the same framing: decimal length, newline, a
`datum_write(..., 1)` payload. Compiler side: `_helper_send` and the frame
parse inside `_helper_receive` (stage.x 1075-1140). Helper side:
`_frame_read` / `_frame_write` (etc/meta-helper.x 32-53). The payload
encoding is already shared (`lib/datum.x`). The difference is transport:
the helper uses blocking `FILE *`; the client needs a poll deadline and
SIGPIPE suppression, so the I/O loops cannot be one function.

Share the pure part in `lib/datum.x`: `datum_frame(Buffer out, Var
value)` (length prefix + tagged datum) and `datum_unframe(String input,
size_t &used, Var &value)` (returns 1 with a complete frame, 0 when more
bytes are needed, raises on malformed). Client `_helper_receive` then
keeps only its poll/read loop; helper `_frame_read` keeps only `fread`.
Saves about 25 lines net and removes the risk of the two ends drifting.
This adds runtime surface in `lib/`, which changes `lib/x2c.x`; if Gary
prefers `lib/` untouched, put the pair in `etc/meta-helper.x`'s shared
header instead (see Decisions).

The message vocabulary (`reset`, `call`, `quit` / `value`, `void`,
`warning`, `error`, `dependency`, `missing`, `failure`) is a single
`match` on each side and is already minimal.

## Target structure

| File | Contents | Lines after (est.) |
|---|---|---|
| `src/stage.x` | Argument and result conversion, `check_meta_call`, `meta_is_comptime_only` | ~370 |
| `src/meta-group.x` (new) | Membership and reachability, group emission with the child compiler, unbound check, `write_meta_build`, in-process session staging | ~430 |
| `src/meta-project.x` | Existing project build plus toolchain state (`use_meta_toolchain`, `meta_cc`, `meta_cc_identity`, `meta_cc_run`, `_meta_cc_error`) and the helper client (state, lifecycle, `meta_helper_call`); `_meta_cc` wrapper deleted | ~780 |
| `etc/meta-helper.x` | Uses the shared framing | ~310 |
| `lib/datum.x` | Adds `datum_frame` / `datum_unframe` | +~30 |

Alternative for the client: its own unit `src/meta-helper-client.x`
(~250) instead of `meta-project.x`. Preferred placement is
`meta-project.x`, because it is the only producer of the client's inputs
and the natural owner of the process the project build produces; the
separate unit is the fallback if `meta-project.x` reads as too large.

Net source change: about -80 lines (save/restore, framing, wrapper,
duplicated file-header includes), plus relocation. The native-meta target
of under 500 lines for "stage.x plus the helper client" is met by
`src/stage.x` alone; the client lands in `meta-project.x`.

## Steps

Each step is one commit, verifiable alone. Focused checks per step:
`make x2c`, `make verify-fixtures`, the meta fixtures
(`unittest/fixtures` entries matching `meta`), `unittest/probes/run-meta-helper.sh`,
`unittest/probes/run-meta-cache-key.sh`, `make check-native-modules`,
`make commands-check` (REPL session staging). The integrator runs
`tools/gate-state.py ensure agent-pr-check` once for the batch, which owns
the bootstrap stage comparison.

1. Capture baselines: group C from the project build directory and the
   session cache keys for the meta fixtures and `run-meta-helper.sh`
   projects, and each fixture's unit C. Store under `/tmp`.
2. Replace the save/restore in `_meta_group_code` with
   `_meta_group_compiler(c)` (child + `borrow_unit_semantics` + copies).
   Gate: baselines byte-identical, meta fixtures, `run-meta-helper.sh`,
   `check-native-modules`, `commands-check`. Emitted compiler C changes
   (bootstrap refresh, one round).
3. Make `stage_meta_group` static; delete `meta-project.x` `_meta_cc`.
   Gate: `make x2c`, `verify-fixtures`. Changes bootstrap C and the
   generated compiler API doc (`make doc-generate`).
4. Move toolchain helpers and the helper client into `meta-project.x`.
   Pure relocation. Gate: `run-meta-helper.sh`, `run-meta-cache-key.sh`,
   meta fixtures, `check-native-modules`. Changes bootstrap C layout.
5. Move membership, emission, build output, and session staging into
   `src/meta-group.x`; add it to the source list and the implementation
   map (`docs/src/internals/implementation-map.md`). Gate: as step 4 plus
   `commands-check`. Changes bootstrap C layout and generated docs.
6. Add `datum_frame` / `datum_unframe` to `lib/datum.x`, use them in both
   ends. Gate: `run-meta-helper.sh` (covers timeout, crash, warning,
   dependency replies), `run-meta-cache-key.sh` (helper identity includes
   `etc/meta-helper.x`), unit suites for datum. Regenerates `lib/x2c.x`.
   The helper object is rebuilt because its source changed; cache keys
   change once, which is expected.

Two-round refresh: none of these steps changes how the compiler emits C
for user programs, so a single bootstrap refresh per batch should hold.
If step 2 or 6 produces a stage-diff on the first gate run, that is the
known two-round case (a compiler source change that alters its own
translation); refresh twice before investigating.

## Risks

- Step 2: a field `transform` reads that the child does not inherit
  would change group C silently at runtime but show in the byte
  comparison. The baseline comparison is the guard; do not skip it.
- Step 2: `_new(owner)` allocates fresh maps per group emission. One
  emission per unit (project build) or per staged session group; cost is
  negligible, but confirm with the stage-3 build time the mitigation plan
  already tracks.
- Steps 4-5 move file-static state (`helper_*`, `meta_cc`,
  `meta_build_directory`, `session_meta_scope`); each must move with every
  reader, or the build fails to link, which is loud.
- The concurrent lint pass edits the same files; land these steps after
  it, or rebase relocations mechanically.

## Decisions

- Framing lives in `lib/datum.x`. `docs/library-manifest.txt` already
  classifies that module as internal, so the pair adds no public API.
  Step 6 can be dropped without affecting steps 1-5.
