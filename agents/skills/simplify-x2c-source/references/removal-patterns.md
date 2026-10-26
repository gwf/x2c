# Removal patterns proven in x2c

Use these examples to recognize causes of over-engineering. Verify current
source before applying any old result.

## Reject a leftovers-only campaign

Calibration for PR-3 in [the standard](../../../x2c-code-standard.md).

A failed broad pass searched the repository for low-use fields and private
names, removed redundant flags and allocation zeroing, ran the final build
gates, and declared success. A second invocation immediately found more of the
same leftovers. The edits were correct, but the campaign had never selected or
prototyped a connected architectural deletion.

Use that failure as a hard check:

- do not let identifier frequency choose the subsystem;
- do not let ease or certainty outrank the amount of machinery that can
  disappear;
- review the completed authored diff after deletion-before-reshape; and
- if no connected mechanism can be removed, report that result instead of
  promoting dead fields and `calloc` conversions into the main result.

## Do not merge paths with different ownership

Calibration for FA-5 in [the standard](../../../x2c-code-standard.md).

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

Calibration for PR-2 in [the standard](../../../x2c-code-standard.md).

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

Calibration for FA-3 in [the standard](../../../x2c-code-standard.md).

Commit `d2a51d85` stopped `src/main.x` from copying 18 fields out of a parsed
`CliRequest` into file statics. Consumers retained the request they actually
needed. The copied fields, assignments, and implicit synchronization rule all
disappeared.

Look for objects that unpack another object only to make the same information
available later. Passing or retaining the original often deletes both data
and lifecycle code.

## Remove an internal language nobody needs

Calibration for FA-8, FA-9 in [the standard](../../../x2c-code-standard.md).

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

Calibration for PR-2, PR-4 in [the standard](../../../x2c-code-standard.md).

The allocation and size failure work in `97c2a9e1` and `c4fee817` established
that those failures do not return to the raising call. That made downstream
null checks and fallback braces unreachable. The useful campaign was the
repository-wide sweep after the guarantee became true, not one removed check.

When several callers defend against the same outcome, inspect the producer.
Making its result precise may delete checks, recovery branches, status
propagation code, tests, and documentation everywhere downstream.

## Generate implementations, not abbreviations

Calibration for FA-5, MA-2 in [the standard](../../../x2c-code-standard.md).

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

Calibration for PR-3 in [the standard](../../../x2c-code-standard.md).

The `SymbolSet` Var-tag change replaced two generated 109-case switches with
one indexed representation. It removed generated code and changed lookup from
18 ns to 3 ns. The best simplifications often improve performance because the
deleted representation also required runtime lookup, copying, allocation,
dispatch, or cleanup.

Inspect both authored and generated code. A tiny macro diff can hide more
runtime work; a larger source rewrite can be a clear win when generated output
and execution shrink.

## Trace temporary values into their consumers

The campaign from `a92eb95f8` through `ca8f1a876` supplies small examples of
PR-3 in [the standard](../../../x2c-code-standard.md). Trace a temporary value
from construction to its consumers. If it only carries information into the
next operation, consider constructing the final result directly or consuming
the original input.

- In `a8c006e3a`, `src/cache.x` stopped splitting IDs into three temporary
  lists and then traversing them to construct declaration bindings.
  `_slot_declarations` constructs the bindings while classifying IDs. The
  change preserves List/String/Var grouping and descending slot order.
- In `113f8bc69`, `src/builtins.x` stopped constructing a filtered binding
  list solely to check for a duplicate name. The original traversal tests
  group and name together. `_binding_rows_for` remains for installation,
  whose consumer needs the selected rows in installation order.

Look for materialized selections used only for existence, counting, or one
traversal, and collections immediately converted into another representation.
Keep a selection that consumers reuse or need as a value. A lazy iterator
filter does not imply a temporary collection. In particular, distinguish
disposable intermediates from caches and indexes that avoid repeated work.
Source reduction alone does not justify removing those fast paths.

## Move live values instead of swapping discarded values

Commit `9879f04b0` simplified deletion in `lib/map/generics.x`. The old loop
swapped each successor with the deletion hole. The replacement copies each
successor into the hole and clears the final slot. It removes temporary
values and writes that only carried discarded contents forward.

Inspect deletion and compaction loops for this pattern. Establish whether
intermediate contents are observable and whether ownership, destruction, or
callbacks require each swap. The Map example does not authorize replacing
swaps in sorting or other operations that retain both values.

## Recognize smaller consequences of established contracts

These campaign examples apply existing rules in
[the standard](../../../x2c-code-standard.md), rather than adding new rules:

| Example | Existing guidance | What must remain |
| --- | --- | --- |
| `113f8bc69`: `_binding_statement` destructures the internal binding row instead of matching it and silently returning an empty result | EX-9, trusted fixed shapes | The producer's shape guarantee; checks for variable or external input |
| `fbc6cbaab`: tokenizer mode operations replace forwarding helpers, and `token_len` disappears | FA-7, forwarding chains; PR-3, unnecessary state | Deferred rollback and `mode_committed`, which carry real failure behavior |
| `e8bfac15c`: `_compile_is` uses one structural match instead of a classifier helper and manual shape tests | Matching and traversal decision table | Exact arity, accepted payloads, fallback behavior, and efficient generated operations |
| `e8bfac15c`: unconditional `xfree(l.sites)` replaces its null guard | PR-4, established guarantees | The documented `xfree(NULL)` contract; ownership guards are a different condition |
| `523ca07f4`: datum-reader `_list` returns at each outcome instead of assigning `out`, breaking, and returning later | PR-3, unnecessary state | Cleanup and any required post-loop work |

Optional searches from the repository root locate candidates:

```sh
rg -n 'if .*xfree' src lib -g '*.x' -g '!x2c.x' -g '!linked-meta.x'
rg -n '\.filter\(|selected\.push|return .*list_free' src lib -g '*.x' -g '!x2c.x' -g '!linked-meta.x'
rg -n 'swap_|return out;|static inline' src lib -g '*.x' -g '!x2c.x' -g '!linked-meta.x'
```

These are discovery signals, not automatic replacements. Trace the producers
and consumers before selecting a change. Compare generated operations when a
shorter spelling may add traversal, allocation, conversion, or lost reuse.
Keep comment, layout, and nested-ternary cleanup under Clean; those changes
alone do not demonstrate removed machinery.

## Extend the search to repeated and discarded work

The following examples were submitted for integration on 2026-10-26 and were
still open when recorded. They are provisional examples, not claims of
publication or measured speedup. Inspect the linked revision and current
source before applying them. They extend PR-3 and PR-4 in
[the standard](../../../x2c-code-standard.md).

### Reuse a result within one operation

[PR #313](https://github.com/gwf/x2c/pull/313), revision `86cf2f87e`, reuses
`_binding_of(target)` in `src/regions/walk.x`.
[PR #315](https://github.com/gwf/x2c/pull/315), revision `3ef9c2b2e`, resolves
an overlay path once in `SourceView.set`.
[PR #330](https://github.com/gwf/x2c/pull/330), revision `de4cd2ebf`, reads
the next Token already fetched instead of calling `peek` to repeat its
trivia walk.

Search within a function for repeated calls with identical inputs. Include
different helpers that repeat the same traversal. Retain the result only
where intervening operations cannot invalidate it and repeated calls have
no required effects. Reuse the existing owner rather than adding a cache or
extending the value's lifetime.

### Construct a value only on paths that consume it

[PR #322](https://github.com/gwf/x2c/pull/322), revision `ac3040c28`, moves
String-conversion AST construction behind the destination test in
`src/expressions/conversions.x`. Other destinations discarded that work.
Actual String and Var conversions retain their conversion owner and cache
behavior. The native-pointer probe reported identical emitted C; this is
unused compiler construction, not removal of an emitted runtime conversion.

Look for values constructed before a branch and used only in selected arms.
Trace construction effects, diagnostics, and cache registration before
moving the operation. Do not defer work whose effects are independently
required.

### Construct small fixed outputs directly

[PR #325](https://github.com/gwf/x2c/pull/325), revision `510501026`, builds
two adapter parameters directly in `src/callables/adapters.x`. It replaces
parallel type/name lists, `zip_with`, a callback, and a temporary `params`
wrapper whose caller immediately took its tail.

Look for general collection pipelines whose only caller supplies a small
fixed number of elements. Direct construction can remove intermediate
representations and callback work. Keep general machinery where callers
need variable-length inputs, and retain the existing element constructors.

### Remove retries after guaranteed completion

[PR #337](https://github.com/gwf/x2c/pull/337), revision `e89d72698`, replaces
an unzip-buffer refill loop with one pull. The backlog check remains first;
a successful buffer push supplies both columns and satisfies the request.

Inspect loops whose successful body necessarily satisfies their exit
condition. Trace the producer's guarantee, failure, and partial-progress
behavior before replacing repetition. Keep loops that may receive empty
chunks, short reads, or other successful results that leave work outstanding.

## Keep pulling after the first deletion

Calibration for PR-3 in [the standard](../../../x2c-code-standard.md).

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

Calibration for FA-7 in [the standard](../../../x2c-code-standard.md).

The Map generator cleanup removed standard allocation, scope, and byte-storage
forwarders from `lib/map/map.x`, `lib/typed-map.x`, and its fixtures. The first
direct macro spelling failed the hygiene check. That did not prove the
forwarders necessary: exact `x2c.ident` references let the generator call the
existing operations directly.

Two attempted deletions did expose real work. Map boxing feeds a typed pointer
through `Var.new`'s variadic interface, and pair construction needs declared
`Var` inputs. Their tiny adapters stayed. Pointer extraction and iterator
initialization needed no translation and disappeared with the storage
forwarders.

The focused build then passed, and the checked-in `bootstrap/` C still named
the deleted private functions. The correct next step was the documented
refresh through the publication command and review of those removals, not
restoration of the functions. Apply that distinction everywhere: compiler or
behavior failures require more design work; exact artifact deletions require
the documented refresh target.
