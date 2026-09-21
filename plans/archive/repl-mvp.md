> Status: done
> Implemented on 2026-09-20. Direct API, 39 terminal checks, native parity,
> and installed-layout checks pass. Delivery uses the final-tree gate below.

# Experimental x2c REPL

Deliver `x2c repl` in the normal compiler and installation. Preserve the
spike's initialized values, function definitions, statement execution,
inspection, failed-publication policy, and borrowed unit lifetime. Full native
execution, redefinition, AST installation, undo, history, completion, and a
collector remain deferred. Memory growth is documented, not a landing blocker.

## Implementation

- Move the session and terminal into `src/repl-session.x` and `src/repl.x`.
  Reuse `CliRequest`, normal command parsing, and main's command Context.
- Open an empty in-memory frontend unit with the ordinary prelude and macro
  libraries. Remove the launcher's separate executable and physical seed.
- Keep `:help`, `:cancel`, `:quit`, `:symbols`, `:ast`, and `:lowered`, plus
  combinable `--dump` and `--stats`. Inspection preserves pending input.
- Piped errors continue processing and produce final status 1. Interactive
  recoverable errors preserve the session and do not change normal exit 0.
  Incomplete EOF is status 1; invalid CLI is status 2. Ctrl-C exits via the
  ordinary SIGINT action; `:cancel` discards pending source.
- The book owns the supported subset and experimental contract. Research
  measurements stay with the optional probes under `tools/repl-spike`.

## Validation and delivery

Focused evidence: `debug/repl-dev-check.log`, `debug/repl-installed-check.log`,
and `debug/repl-installed-layout.log`. The first full gate found outdated CLI
help snapshots; the reviewed command-list updates pass the focused CLI probe.
The existing publication gate must pass on the final tree before pushing.


Adapt existing direct API, terminal recovery, and native parity checks to the
integrated command, including interactive and interrupt behavior. Verify a
normal installation from outside the checkout without compiler objects or a
seed. Keep these probes optional; add no recurring gate. Review and simplify
the authored diff, generate documentation, then run the existing
`tools/gate-state.py ensure agent-pr-check` on the final integrated tree.
Inspect generated changes and deliver to dev; do not advance main or publish
a release. The earlier local review-base ref stays unchanged.

## Plan review

The ordinary parser and binder establish types and binding identity. The
adapter consumes their canonical Lists and existing lowering; it does not
introduce another AST, type checker, symbol table, or evaluator. The existing
name map retains inspection entries only after successful initialization.
The frontend retains unit initialization and teardown ownership, including the
new empty-session entry point. The standalone build/seed path and duplicate
option parser are deleted.

The piped error accumulator is needed for reliable command status. CLI operand
rejection preserves the no-file command contract; command errors preserve
pending source. Existing subset checks protect reproduced wrong output or
unsupported native crossings, and existing failed-publication checks protect
binding identity. Review reproduced local static reinitialization and unresolved extern reads.
The existing syntax traversal also rejects static, extern, and threaded
declarations before lowering; these require native storage semantics. Tests exercise
those public contracts through the existing optional probe, without changing
the repository's readiness sequence.
