# REPL semantic completion

> Status: active
> Implementation is authorized on `codex/repl-spike`.
> Delivery is limited to local commits until Gary clears integration after the
> repository-wide syntax change.

## Result

Tab completion in interactive `x2c repl` uses the compiler's live namespace.
It completes visible identifiers and members on typed receivers, including
session definitions and the functions and methods available to compile-time
evaluation. Piped input and submission semantics remain unchanged.

## Implementation

- Add `ReplSession.complete(source, cursor)`, returning byte replacement bounds
  and sorted candidates borrowed from the session unit.
- Parse the pending submission through the cursor in a rollback-only semantic
  transaction. A private completion marker stops ordinary parsing after it has
  established lexical scope or a postfix receiver type.
- Enumerate visible source-name keys from active `Sym` scopes. Enumerate fields,
  direct methods, typedef ancestors, protocol methods, imported methods, and
  delegated methods from their existing compiler owners. Use normal member
  resolution for final selection and the live macro Lisp binding for REPL
  callability. Retain no completion catalog or cache.
- Give `ReplInput.read` a synchronous completion callback. Tab inserts the
  longest common extension; a sole match replaces the token; repeated Tab
  lists sorted alternatives and redraws the buffer. `src/repl.x` only combines
  pending and edited source and adjusts replacement offsets.
- Document completion behavior and extend the optional REPL spike checks for
  namespace updates, receiver methods, pending locals, unavailable native
  methods, cursor replacement, listing, wrapping, cancellation, and unchanged
  piped behavior.

## Compatibility and delivery

Completion is advisory and publishes no semantic state. Existing parsing,
lowering, diagnostics, history, cancellation, EOF, and evaluation interruption
remain authoritative. Review and simplify the authored diff, then validate the
local final tree with `git diff --check` and
`tools/gate-state.py ensure agent-pr-check`. Commit locally and stop; do not
integrate or push to `dev` until Gary gives the explicit clearance recorded
above.

## Plan review

The tokenizer establishes byte positions, parsing establishes lexical scope
and receiver type, semantic maps establish declarations, member resolution
selects implementations, and the live Lisp session establishes evaluator
callability. Completion consumes those facts without revalidating them.

The design reuses submission rollback, recursive-descent parsing, postfix
resolution, and the existing Linenoise-derived editor. The new lasting pieces
are one result type, one visible-name traversal, one member-candidate traversal,
and one synchronous editor callback. Each exposes enumeration where the owner
currently supplies only lookup. No alternate parser, API catalog, cache,
backend interface, validator, dedicated diagnostic, or negative compiler
fixture is added.
