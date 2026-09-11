> Status: active
> Proposal only; implementation is not authorized.
> Investigated against delivered main `1dbf2582cc78a17098e89a11186912f18fd06d29`
> on 2026-09-11. The measurements below use that revision's compiler.

# Bound symbolic aggregate initializer growth

Recommend replacing repeated cursor branching with native scalar-span
arithmetic for a bounded class of positional initializers. This addresses a
small source program producing megabytes of C without evaluating C macros,
changing constant-expression semantics, or introducing a general predicate
optimizer. Estimated effort: several focused implementation days, including
compatibility probes and self-host validation.

## Current evidence

The probe initializes `struct Record { String names[N][N]; Var tail; }` with
an unbraced sequence of `"x"` values, with native `#define N 4`. The literal
control changes only the dimensions to `[4][4]`.

| Dimensions | Values | Translation seconds | Generated C bytes | `sizeof` occurrences |
| --- | ---: | ---: | ---: | ---: |
| literal | 12 | 0.037 | 507 | 0 |
| native macro | 4 | 0.075 | 9,371 | 220 |
| native macro | 8 | 0.451 | 117,543 | 3,420 |
| native macro | 10 | 1.835 | 431,381 | 12,892 |
| native macro | 12 | 7.397 | 1,659,809 | 50,076 |
| native macro | 16 | timeout at 20 | no completed output | - |

These are single local observations, not statistical timing claims. The
12-value macro case has only 105 `__builtin_choose_expr` occurrences: repeated
conditions, rather than that many distinct conversions, dominate its size.
An independent review repeated both 12-value probes with identical C sizes:
7.512 seconds for macro dimensions and 0.036 seconds for literal dimensions.

Raw source, commands, compiler hash, generated output, logs, measurements, and
native prototypes are retained outside the worktree:
`/Users/gary/Documents/x2c-evidence/closeout-20260910/research/aggregate-initializer-growth/`.
`results.json` records the compiler SHA-256 and the 20-second timeout.

## Owner and cause

`src/expressions.x` owns the shared cursor. `Compiler.initializer_rows`
returns `(original cases)` rows; each case is
`(native-condition path destination value)`. Paths contain ordinary
`(owner kind selector type following-fields)` frames.

`_initializer_next` forks at each array boundary whose dimension is not an
x2c integer literal. `_initializer_merge` merges equal cursor positions by
OR-ing their conditions. `_initializer_and` and `_initializer_drop_bound`
remove some repeated lower bounds, but merged conditions retain the histories
that reached the same position. Subsequent branches expand those histories
again. The native compiler knows `N`; the x2c cursor deliberately does not.

`_convert_composite` consumes these rows and constructs canonical
`(expr TYPE (initval [input] CASE...))` alternatives. `Ast.initializer_cases`
and `Ast.initializer_functions` in `src/ast.x` expose them. `Emitter._initializer_value`
in `src/emit.x` emits native choices; `src/cache.x` reuses the rows and paths
for deferred static assignments. Fixing only printing would leave earlier
cursor and conversion work expensive.

The language contract is [C initializers and static assertions](../docs/src/reference/language.md#c-initializers-and-static-assertions):
ordinary brace elision and destination conversions, with native C owning
dimensions, constant expressions, and bounds diagnostics.

## Proposed bounded change

1. Add an internal scalar-span path inside `Compiler.initializer_rows`.
   Admit an array, or a struct whose initialized fields are scalars or
   rectangular arrays of scalar elements, when at least one array bound is
   nonliteral. Resolve aliases and field order through the current symbol
   operations. Keep the current literal-dimension path unchanged.
2. Restrict this path to ordinary undesignated scalar positional inputs.
   Explicit nested braces, designators, strings initializing character
   arrays as a whole, incomplete arrays, unions, anonymous aggregate fields,
   arrays of heterogeneous aggregates, and already prepared `initval` inputs
   continue through the existing walker. Eligibility is an optimization
   choice, never a new rejection rule.
3. Describe each eligible field as a temporary scalar span: its existing
   path, element type, native scalar count, and array strides. For the probe,
   the first count is `sizeof(row.names) / sizeof(row.names[0][0])`; the
   following `Var` field has count one. Use cumulative counts to decide which
   span contains initializer ordinal `k`, instead of enumerating all possible
   inner-array crossings.
4. Produce the same canonical case rows. Conditions are native integer
   comparisons with span starts and ends. Reconstruct proper nested array
   selectors from the ordinal using native stride division and remainder;
   do not cast a multidimensional array to a flat pointer. Keep a native
   excess fallback and the original braces/designators in emitted C.
5. Reuse `initializer_slot`, ordinary conversion and its semantic transaction,
   native bound/index capture, `initval` emission, and static-assignment
   generation. The temporary span list stays inside the cursor owner; no new
   public AST form, parser path, symbol cache, or runtime storage is needed.

The expected work for an eligible initializer is proportional to supplied
values times its field spans and array rank, rather than the number of
possible boundary histories. The implementation must retain native rejection
of invalid/VLA dimensions and native excess behavior. In particular, probe
zero-length native extensions and unselected alternatives before accepting
the arithmetic lowering; avoid introducing division-by-zero diagnostics from
synthetic selectors. Do not silently widen this proposal if an edge requires
a different semantic model.

## Feasibility and validation

A native C prototype in `span-native/` uses the capacity comparison directly
in `__builtin_choose_expr` and proper nested subscripts. At widths 1, 2, 3,
and 4, it initializes every `String` element followed by the `Var` field,
verifies all resulting values, and counts exactly one input call per value.
All four programs compile and run successfully; the 17-value prototype is
2,241 bytes. This establishes native ICE selection and scalar-span mapping
for the motivating shape, not an implemented compiler optimization or proof
of every fallback boundary.

Implementation should first exercise that boundary in the shared cursor,
then verify local, compound-literal, and file-static consumers. Cover a full
array, continuation into a differently typed field, side effects, aliases,
source-position `__COUNTER__` bounds, and the existing symbolic/designated
initializer fixtures. Preserve diagnostics through original native syntax;
do not add a validator merely to reject an input earlier.

Repeat the saved 4/8/10/12/16-value probes, then extend the successful optimized
shape to 32 and 64 values with suitable dimensions. Record generated size and
translation time; require the motivating 12-value case below 50 KiB and no
return to exponential growth in that series. This is focused acceptance
evidence, not a recurring timing gate. Existing literal behavior and general
fallback coverage must remain green. Review and fix the completed authored
diff before the normal publication command; add no gate or precommit step.

## Plan review

- Existing type resolution, ordered fields, captured native bounds, and
  canonical initializer rows establish the facts the new path consumes. It
  does not revalidate bindings, speculate about macro values, or repeat
  conversion and lifecycle rules.
- The change removes repeated boundary-history construction for eligible
  inputs. It reuses the current walker for other shapes and the current
  conversion/emission consumers everywhere. One private span construction
  operation and ordinal-to-path operation earn their place by avoiding that
  repeated work; there is no general boolean DAG, global cache, or second
  initializer AST. Existing fallback helpers are not claimed as deletions.
- Match recognizes eligible canonical shapes; ordinary Lists, field lookup,
  and expression templates produce ordinary rows and paths. This remains
  local x2c cursor code rather than a separate optimization framework.
- No validator or dedicated diagnostic is proposed. Compatibility probes
  cover invalid dimensions, excess initialization, and unsupported shapes
  only where the optimization could change native behavior or emit an unsafe
  subobject access. There is no new mandatory negative-test category.
