# Four-dot List rest parameters

> Status: done
> Delivered in 075623030 on 2026-10-25. On 2026-10-27 the source spelling
> `.... name` was replaced by `List @name`; the semantic Type `(....)`, call
> packing, and native List ABI described below are unchanged. Map and Array
> rest parameters are scoped in
> [map-and-array-rest-parameters.md](../map-and-array-rest-parameters.md).

A final `.... name` parameter receives an ordinary List. The compiler packs
separate trailing arguments at the call site; an absent tail becomes nil.
An ordinary List, including a Type alias, contributes one element. Only an
explicit `@list` contributes its elements. Mixed splices use existing ordered
List construction. Fixed arguments retain ordinary call evaluation semantics.
C `...` remains unchanged. The native ABI ends in an ordinary List parameter.
The source callable type preserves the rest convention, distinct from List.

## Required succession

Land after `codex/collection-reading-and-unquote`. Rebase onto its tokenizer
and parser changes for `$(` and `@(`. Call splices must have the same
semantics as its evaluated List elements, including `@xs` and `@(expr)`.
Use its public `Compiler.list_expression` operation in rest packing and
remove the local loop over `literal_cell`; there is one List builder.

Add `List List.new(.... items) => items;` as the named, passable equivalent
of `$(...)`. The syntax remains a direct List construction, not a call to
List.new. No other proposed library additions are authorized.

A separate meta-group header-guard repair derives guards from paths relative
to x2c home. If it lands before this change, regenerate bootstrap, generated
headers, and affected fixture expectations through their targets. Do not
hand-merge generated outputs. Run final publication validation only after
these dependencies are integrated.

Direct calls, methods, typed pointers, generic Func, and explicit meta calls
must agree. Func supports both zero and nonzero fixed prefixes. Existing Var
conversion, List element rules, allocation, and lifetime contracts apply.
There is no sentinel scan, implicit splicing, or new ownership regime.

Implementation follows existing parser/type owners, call lowering and ordered
List construction, Func adapters/runtime, and meta call evaluation. Preserve
compiler-created calls and declaration/definition propagation. Bootstrap is
regenerated only through repository targets.

Verify zero/many/mixed values, nested Lists and Type values, empty/mixed
splices, fixed-prefix arity, evaluation once and tail order, methods, pointers,
Func, meta calls, and C varargs. Review the integrated source, measure relevant
packing/Func performance and unchanged fixed-call paths, then run the required
publication gate on current origin/dev before direct publication.

## Plan review

The parser owns final-parameter structure. Callable typing retains the calling
convention; downstream code relies on that representation. Existing ordered
List construction owns boxing, explicit splices, and tail evaluation. Func's
existing checked argument readers retain native crossing guarantees. Reuse
these owners instead of introducing a parallel packing or ownership system.
Arity checks protect missing fixed arguments and native adapter reads. Existing
List conversion rules reject invalid elements. Negative tests cover those
public contracts and incompatible callable conventions, not redundant checks.

## Implementation review

The semantic parameter marker is `(....)`; its bound local and emitted ABI
are List. `Compiler.pack_rest_arguments` uses `Compiler.list_expression`, the
same List builder used by the evaluated-List constructor. There is no
separate List allocation, boxing, or splice implementation in call lowering.
`Func.apply` retains its fixed-call path and packs only the rest suffix.

Generated forwarding calls splice their received List. Meta helper bridges
expand only the signature's packed rest tail before invoking another Func.
REPL lowering shares compiler packing and the existing helper argument
envelopes. Callable conversion checks preserve the convention in nested
callback parameters and return types because C sees only the List ABI.

Focused fixtures cover direct calls, methods, global and local pointer
typedefs, Func and capturing lambdas, meta calls, generated protocol
forwarders, ordered SDK calls, and C varargs. Negative fixtures protect
missing fixed arguments and incompatible source calling conventions.
The first publication attempt stopped on three redundant int casts; focused
fatal-warning translation passed after their removal.

## Validation before dependency integration

The subsequent gate passed 1,047 unit tests (27,255 assertions), REPL command
and load/reload checks, documentation auditing, 120 documented outputs, and
cold-collection comparison. Its lint width failure was repaired; the focused
lint suite then passed. The full native-module probe passed independently.
The next gate was stopped when the required dependency order was specified.
These results are not final publication proof for the eventual integrated tree.

List.new passes a fixture covering empty and nested Lists, mixed splices,
typed pointers, and Func conversion. Its public documentation audit passes.
Moving rest storage into a helper removes the VLA stack protector from fixed
Func calls. Five alternating local samples of the fixed-call workload retired
7,803,882,438 instructions at the original baseline and 7,803,310,255 with the
change. Each sample performs one million calls in each of three paths.
A separate small-int workload measured medians of 15.480 ns/call for an
explicit one-element List, 15.877 ns/call for direct rest, and 72.699 ns/call
through Func. The first two emit the same cons operation. Final performance
and publication validation remain due after dependency integration.

## Integrated checks

The capability bootstrap was refreshed before adopting List.new. All eleven
List rest compiler fixtures pass after replay onto the dependency. The
constructor fixture compares direct and Func construction with evaluated
List syntax, including empty, nested, named-splice, and grouped-splice cases.
Read-only compiler and runtime reviews found no further issues. Final gate
and performance evidence is retained with the publication attempt.
