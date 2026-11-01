# Contextual x2c keywords

> Status: done, 2026-10-30.
> Implemented in the batch beginning `c5ed5ae99`, through generated-artifact
> commit `234eec5b3`. The full `agent-pr-check` passed on that tree.
> Nine additions are contextual; `defer` and C keywords remain reserved.
> Gary selected lexical priority for ambiguous percent/angle forms.

## Result and scope

Make these nine x2c additions contextual:

```
associated catch delegate finally import protocol raise threaded try
```

Keep the tenth addition, `defer`, reserved. Keep C keywords and alternate C
spellings unchanged, including `thread_local` and `_Thread_local`.
Recognize `with` only by its complete `with (...) { ... }` statement head;
allow direct `with(args);` calls and ordinary variables named `with`.

Preserve the current `in` and `match` rules, macro invocation precedence,
protected keyword aliases, runtime ABI, exception behavior, and canonical AST.
Existing match collisions are evidence, not additional implementation scope.

## Required simplification

Gary expects this change to tighten the implementation as well as improve
identifier compatibility. Replace the individual ad hoc decisions with the
selected rules and delete superseded checks. The result must be cleaner,
more direct, and simpler to understand.

Do not layer fallback paths, caches, binding registries, another parser, or a
general recognition framework over the current implementation. Share identical
recognition decisions and keep genuine grammar differences explicit. Fewer
lines alone do not establish simplification; passing tests do not replace it.
The completed source review must identify removed decisions and justify the
remaining distinctions. Revise the approach if it adds needless complexity.

## Language rules

Each construct recognizes its word at its grammar position. Elsewhere the word
is an identifier, including declarations, calls, fields, typedefs, and labels.
A visible ordinary binding wins when the following tokens can continue an
ordinary expression or declaration. An ill-typed ordinary use remains an
ordinary error; do not retry keyword syntax after failure.

Use the existing symbol table's namespace and visibility contracts. Functions,
objects, parameters, enumerators, typedefs, and ordinary expression aliases
participate. Unrelated fields and struct tags do not shadow an ordinary name.
The full parse already sees collected declarations, including functions; use
that visibility rather than adding a source-order registry. Source-ordered
local scope and existing macro/include rules remain owned by their current
operations. The original draft's blanket source-order assumption is corrected
by the existing collection/full-parse contract.

Unambiguous syntax retains its meaning even with a same-named binding:
`try { ... } finally { ... }` and `with (...) { ... }` remain constructs.
A completed governed body establishes its continuation position. Calls named
`catch` or `finally` inside that body are ordinary statements, not handlers.

| Word | Owning grammar position |
| --- | --- |
| `import` | Unit-scope import followed by a quoted package name, with existing `as`/`with` clauses. |
| `raise` | Statement head followed by its required payload literal. |
| `try` | Statement head governing a braced or unbraced body and required handler continuation. |
| `catch` | Pending try/handler continuation, followed by a filter or default colon. |
| `finally` | Pending finalizer continuation governing its body. |
| `delegate` | Delegate modifier at a field declaration head. |
| `associated` | Associated-type declaration inside a protocol body. |
| `protocol` | Unit-scope protocol/adoption declaration, including `meta`/`static` markers. |
| `threaded` | Declaration storage specifier, including its existing late placement. A declarator named `threaded` must remain a name. |
| `with` | Complete parenthesized header followed by a braced body. |
| `defer` | Reserved cleanup statement, unchanged. |

`defer(f());` could otherwise mean either an immediate call to a function
named defer or deferred execution of f. Gary chose to preserve reservation.
No braced-only restriction or replacement spelling is selected.

### Selected lexical exception

Keep the scanner's current lexical priority for percent and angle forms.
After the nine spellings, adjacent `%(`, `%{`, `%!`, and `<...>` retain their
existing literal interpretation before bindings are known. Literal contents
retain their existing protection from C macro expansion. Do not rescan or
reconstruct another interpretation after parsing discovers a binding.

For an ordinary operator use, `(raise) %(a+b)` selects C modulo and addition;
`raise % (a+b)` also selects modulo. Parenthesize a name before a comparison
that could resemble an angle literal, as in `(raise) < a`.
At statement start, `raise %(code);` retains payload meaning even when a
same-named ordinary binding exists. Document these exceptions explicitly.

### Compatibility

Previously rejected ordinary identifier uses become valid. Overlapping keyword
prefixes can change meaning when an ordinary binding is visible, except for
the selected lexical priority. `with(args);` becomes an ordinary call instead
of a missing-body error. `(with)(args);` remains valid. Existing macro and
keyword-alias invocation precedence and replacement restrictions remain.

## Feasibility evidence

At baseline `a208671ba`, a temporary real-parser harness accepted all 80
identifier cases after demoting each of the ten original additions to ident.
That experiment established parser/binder feasibility, not lexical parity.

The subsequent probe compared `return value %(a+b);` with the same expression
using a parameter named raise. The first parsed as modulo. Demoting raise
only after scanning failed because `%(` and one Atom `a+b` were already
chosen. C scanning would instead produce `%`, `(`, `a`, `+`, `b`, `)`.
C scanning can also reject escaped atom text, and CPP processes identifiers
before bindings exist while quoted atoms deliberately avoid CPP.

This rejected retagging as full binding-sensitive lexical compatibility.
It did not reject contextual keyword parsing. Gary explicitly selected the
smaller lexical-priority exception above, so no lexical/CPP architecture
change is needed. Temporary evidence is under `/tmp/x2c-keyword-spike/`;
these examples preserve the essential evidence if that directory is absent.

## Connected implementation

1. Retain scanner keyword types through lexing and CPP. Retag the nine x2c
   spellings to ident afterward; preserve C thread-local aliases. Reuse this
   operation when the script driver scans its synthetic main template.
2. Use one parser query for a contextual word and ordinary-binding precedence,
   with handler macro precedence confined to statement continuations.
   Recognize complete with heads once for both
   statements and macro invocation. Keep late threaded storage recognition
   in the existing declaration owner so a threaded declarator is not consumed.
3. Update statement/clause dispatch, unit/import/protocol recognition, fields,
   associated types, and storage parsing. Pass the recognized statement kind
   to the existing binder. Preserve AST heads and all ordinary binding,
   typing, lowering, cleanup, and source-origin operations.
4. Cover collection and full parsing, source templates, headers/CPP, completion,
   scripts, and indentation through their existing owners. No scope-dependent
   token mutation or second semantic implementation.
5. Update language and scanner/pipeline documentation. Replace obsolete with
   rejection fixtures with positive ordinary-name/call coverage. Reuse existing
   checks; add no recurring gate or validation requirement.
6. Review and fix the complete authored diff for duplicated decisions,
   unnecessary machinery, changed precedence outside scope, and remaining
   simplification opportunities before publication validation.

## Verification and delivery

Verify the nine words as globals, locals, parameters, function definitions,
expression and statement calls, fields, typedefs, and labels. Compile/run
representative outputs and verify effects. Mix ordinary names and keyword
constructs in one unit, including shadowing, handler nesting, and direct with
calls. A wrong-arity ordinary call must report its ordinary call error.

Verify lexical priority together with the documented operator boundaries.
Reuse existing coverage for C/defer reservation, thread-local aliases,
protocols, delegation, macros/templates, CPP/headers, scripts, and indentation.
Keep generated artifacts owned by their documented targets.

Implementation uses the root direct-delivery workflow, publication gate, and
applicable compiler performance checkpoint. Do not advance main. Archive this
plan with actual delivery and verification evidence when implementation lands.

## Delivered verification

The final publication gate passed: 1,352 compiler fixtures, 1,126 unit tests
with 99,192 assertions, bootstrap/self-host and cold-collection proofs,
command checks, documentation audit, and 136 documentation output samples.
The temporary native matrix passed all 72 identifier-use cases.

The source review removed duplicate with checks and diagnostics, its forwarding
function, an obsolete rejection fixture, and the duplicate early protocol
branch in collection. Shared word recognition reuses the symbol table and
alias owner. Applicable macro precedence remains with each grammar owner.
No token representation, parser, cache, registry, or retokenization was added.

A converged baseline at `8a85f6a6b` and candidate `234eec5b3` translated the
same copied language-tour, scan-hot-paths, and scope-hot-paths sources with
`-j 1`. Five alternating samples had median retired instructions of
1,516,494,509 and 1,518,649,957 respectively: +2,155,448 (+0.142%). All six
C/H outputs were byte-identical. This small difference is close to run
variation; no performance improvement or full-build result is claimed.

## Plan review

The scanner owns token boundaries and literal modes; CPP owns macro expansion;
normal symbol lookup owns visibility. Recognition trusts those facts and does
not reconstruct them in a second representation. Existing parsers own valid
constructs, typing, and diagnostics. No semantic retry or speculative binding.

Reuse clause binders, declaration/protocol parsing, canonical AST/lowering, and
the built-in with decorator. Replace fixed-token parser dispatch and the
unconditional with claim. Remove duplicate with header/body checks and their
obsolete rejection fixtures. The only additional declaration distinction is
whether threaded precedes another specifier/declarator or is itself the name.

Small grammar queries and normal Sym lookup fit the current recursive-descent
implementation. No runtime machinery, cache, provenance state, general parser
framework, or new caller obligations are proposed. The completed source review
must show the common rules and the removed ad hoc decisions.

No new validator or dedicated diagnostic is proposed. Reuse C/defer reservation
coverage and existing invalid-construct checks. The wrong-arity negative fixture
protects the deliberate ordinary-binding-wins behavior, without fallback to
keyword syntax. Do not add negative fixtures merely for earlier diagnostics.
