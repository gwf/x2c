# Removal patterns proven in x2c

Use these examples to recognize causes of over-engineering. Verify current
source before applying any old result.

## Reject a leftovers-only campaign

A failed broad pass searched the repository for low-use fields and private
names, removed redundant flags and allocation zeroing, ran the final build
gates, and declared success. A second invocation immediately found more of the
same leftovers. The edits were correct, but the campaign had never selected or
prototyped a connected architectural deletion.

Use that failure as a hard check:

- do not let identifier frequency choose the subsystem;
- do not let ease or certainty outrank the amount of machinery that can
  disappear;
- do not run final gates until a second architectural pass is empty; and
- if no connected mechanism can be removed, report that result instead of
  promoting dead fields and `calloc` conversions into the main result.

## Do not merge paths with different ownership

A rejected `Error` cleanup tried to make `Error.snapshot`, `Error.since`,
their explicit-owner variants, and handler views use one recursive copier.
The loops looked alike, but the ownership rules were different. Ordinary
snapshots created canonical Strings and Lists in the active pools and promoted
the same objects outward. The `_in` variants copied values into explicitly
supplied pools.

Routing the ordinary path through the explicit-owner copier could create a
second equal String or List in the root pool while the original still lived in
a child pool. Content and lifetime tests passed, but canonical pointer identity
changed. The consolidation also changed fatal diagnostic text for inadmissible
snapshot values.

Reject this shape before editing. Compare input domains, identity, owner,
promotion versus copying, lifetime, failure, diagnostics, and side effects.
If preserving those differences requires modes or callbacks, the repeated code
is carrying real policy and should remain separate.

## Delete the second owner

Commit `d78c641a` removed 571 net lines of hand-authored production source from
the protocol implementation. The important change was not shorter syntax. It
removed duplicate readers, indexes, scans, and reconstructed views after the
header-symbol artifact became the complete ordered source. The compiler no
longer had to keep several paths consistent.

Questions to reuse:

- Which fact is represented more than once?
- Can every consumer use the representation already produced by the real
  owner?
- What reconciliation, invalidation, and tests disappear with the copy?

## Keep the original instead of mirroring it

Commit `d2a51d85` stopped `src/main.x` from copying 18 fields out of a parsed
`CliRequest` into file statics. Consumers retained the request they actually
needed. The copied fields, assignments, and implicit synchronization rule all
disappeared.

Look for objects that unpack another object only to make the same information
available later. Passing or retaining the original often deletes both data
and lifecycle code.

## Remove an internal language nobody needs

Commit `d7d9a95e` removed `CliOptionId`, `CliGroup`, and related routing
machinery. The option spellings already carried the identity callers needed,
so the extra enum and grouping vocabulary did not describe additional
behavior. Hand-authored production source fell by 91 lines.

Commit `52bb9891` removed the private AST validator and 734 net production
lines. The compiler phases already constructed and consumed the supported AST
shapes; the parallel validator model was another implementation of facts the
real pipeline owned.

Challenge every private enum, mode, schema, registry, and validator: identify
the current decision that requires it. If all users immediately translate it
back into an existing value or operation, delete the private language.

## Strengthen one guarantee and remove defenses

The allocation and size failure work in `97c2a9e1` and `c4fee817` established
that those failures do not return to the raising call. That made downstream
null checks and fallback braces unreachable. The useful campaign was the
repository-wide sweep after the guarantee became true, not one removed check.

When several callers defend against the same outcome, inspect the producer.
Making its result precise may delete checks, recovery branches, status
propagation code, tests, and documentation everywhere downstream.

## Generate implementations, not abbreviations

Commit `d2a51d85` used existing compile-time rows and macros to remove 415 net
hand-authored production lines. It generated the 14 native Var update
functions and the Var tag decoder, and it shared String traversal mechanics.
One definition replaced real implementation families.

The typed Array and Map work in `66448562` and `7496523b` went further: one
storage algorithm now serves current typed families while generated C remains
specialized. These changes added capability as well as source, so their value
comes from eliminating future parallel implementations and drift, not from a
small landing diff.

A macro that changes ten copies of two statements into ten invocations has
not removed an implementation. Prefer generation when it erases algorithms,
fixed-fact projections, or a large family of full definitions.

## Remove runtime work with the source machinery

The `SymbolSet` Var-tag change replaced two generated 109-case switches with
one indexed representation. It removed generated code and changed lookup from
18 ns to 3 ns. The best simplifications often improve performance because the
deleted representation also required runtime lookup, copying, allocation,
dispatch, or cleanup.

Inspect both authored and generated code. A tiny macro diff can hide more
runtime work; a larger source rewrite can be a clear win when generated output
and execution shrink.

## Keep pulling after the first deletion

Commit `3b2a5dd8` removed 214 net hand-authored production lines by simplifying
compiler probes across many modules. Commit `d2a51d85` combined generated
families with removal of copied request state, four `_path_dir` copies, two
`Map.copy` reimplementations, and repeated option/operator tests. Neither
campaign stopped after its first valid edit.

After proving one fact, search all producers, consumers, helpers, tests, and
generated artifacts for consequences. Then re-read the smaller program: a
deleted adapter may expose a dead type; a deleted mirror may expose a dead
lifecycle; a shared table may expose redundant switches.

## Finish expected symbol changes instead of restoring dead code

The Map generator cleanup removed standard allocation, scope, and byte-storage
forwarders from `lib/map.x`, `lib/typed-map.x`, and its fixtures. The first
direct macro spelling failed the hygiene check. That did not prove the
forwarders necessary: exact `x2c.ident` references let the generator call the
existing operations directly.

Two attempted deletions did expose real work. Map boxing feeds a typed pointer
through `Var.new`'s variadic interface, and pair construction needs declared
`Var` inputs. Their tiny adapters stayed. Pointer extraction and iterator
initialization needed no translation and disappeared with the storage
forwarders.

The focused build then passed. `sym-check` failed because
`etc/symbols.xlisp` still named the deleted private functions. The correct next
step was `make sym-refresh` and review of those removals, not restoration of
the functions. Apply that distinction everywhere: compiler or behavior
failures require more design work; exact artifact deletions require the
documented refresh target.
