> Status: done
> Completed locally on 2026-09-20 on codex/repl-spike.
> Structured submission, parser recovery, and failed initialization are tested.
> Fine-grained reclamation remains future work; no publication authorized.

# Incremental compiler session spike

Make the existing REPL a client of a structured submission API. Continue using
ordinary typed syntax and existing comptime execution; coverage improvements
belong to another session.

Decisions:

- `ReplSession.submit` returns incomplete, rejected, defined, executed, value,
  or failed, with borrowed results and diagnostics. It does not print.
- `Compiler.parse_submission` owns one-item parsing, the optional supplied
  input boundary, and parser-scratch recovery. Grammar operations signal a
  need for more input; semantic errors keep ordinary diagnostics.
- Only successfully initialized declarations publish new names. Failed
  initialization removes its provisional global cells before binding IDs can
  be reused. Effects on previously published values survive.
- Redeclarations remain disabled. Function replacement is future work.
- The existing unit Context owns results, syntax and values until close.
  Whole-session teardown is tested. Fine-grained reclamation cannot be
  implemented by freeing a caller Scope: Lisp lambdas borrow canonical
  bodies/captures, Lisp entry points allocate in their session Scope, and
  compiler caches retain syntax. Explicit roots/ownership remain future work.

Implementation and validation: extract the session from the terminal; add
parser-boundary and canonical scope cleanup; exercise the API independently
of the terminal, including nested failed bodies, multiline input, failed
multi-binding initialization, ID reuse, state preservation and session close.
Retain native/interpreted parity checks and run ordinary compiler fixtures.
Review authored changes before the final local commit. Keep checks optional
and leave comptime/lisp execution coverage unchanged.

## Plan review

The parser already establishes expression types and binding identities;
submission handling uses those results. Its required-token operations now
signal incomplete source without inspecting diagnostic text. Existing
semantic transactions control publication, while canonical parser defers and
one submission boundary restore scratch scopes. No new evaluator or binding
representation is introduced. The existing unresolved-identifier guard still
prevents the reproduced unwritten-global zero result; new negative checks
protect malformed-input recovery and prevent failed initializers publishing
partial bindings. No recurring validation or publication step is added.

Validation: 22 direct API outcomes in three sessions, 18 terminal cases,
native parity, and 747 compiler fixtures (1,746 artifacts) pass. Repeated
teardown matches empty frontend collection allocation growth and closes all
session scopes. The collection baseline grows by ten allocations per round;
this is not attributed to the REPL or described as full memory stability.
