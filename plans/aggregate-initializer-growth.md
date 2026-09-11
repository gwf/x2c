> Status: active
> Implementation authorized on 2026-09-11. The compiler repair and focused
> acceptance pass; final publication validation and delivery are in progress.

# Bound symbolic aggregate initializer growth

## Problem and outcome

A small brace-elided initializer made the compiler carry forward every
possible history of native array-boundary crossings. Merging destinations
combined their histories rather than eliminating them. The original twelve
string values in `String names[N][N]`, followed by a `Var` field, generated
1,659,809 bytes of C and took 7.78 seconds with `#define N 4`. Literal `[4][4]`
dimensions generated 507 bytes in 0.037 seconds.

The implemented traversal numbers the supplied scalar values and calculates
their destinations directly. The same macro case now generates 16,703 bytes
in 0.067 seconds. Literal output remains 507 bytes. These are local single-run
measurements, not statistical performance claims.

The initial proposal covered rectangular scalar-array spans. Investigation
also reproduced growth in arrays of records containing another array and a
scalar field. Collapsing adjacent array dimensions alone would not fix that
case. The chosen recursive layout covers both shapes through the same code.

## Implementation and compatibility

`src/expressions.x` owns all three private operations:

- `_initializer_layout` counts scalar destinations through the existing type
  and ordered-field operations. Its temporary `(type count children)` Lists
  pair children with ordinary initializer path frames. Arrays multiply native
  extent by the child count; records sum their field counts.
- `_initializer_ordinal` maps a supplied value's ordinal through that layout.
  Division and remainder produce proper nested subscripts; record fields use
  cumulative counts. Array elements are never enumerated or flattened through
  pointer casts. Empty unselected subobjects use safe divisors.
- `_initializer_scalar_rows` emits the existing condition/path/type/value
  cases and native excess fallback. Conversion, source capture, ownership,
  and deferred static assignment remain with their existing owners.

Literal-only layouts retain their existing output. Whole aggregate values,
explicit braces at the current level, designators, prepared initializer
cases, unions, incomplete arrays, and character arrays initialized by whole
strings retain the existing walker. Nested explicit braces may independently
contain eligible scalar runs. Growth in unsupported mixed forms is not
claimed fixed; the scope is scalar positional initializers.

The native compiler still owns dimensions, constant expressions, and bounds
errors. No C macro evaluator, public AST form, runtime storage, general
predicate optimizer, or recurring gate was added. Invalid inputs remain
rejected; speculative alternatives can move an incompatible-value diagnostic
from x2c to native C.

Broader destination selection exposed two existing consumer limitations.
`_initializer_zero` now uses a bitfield's declared base type because native C
forbids `typeof` on a bitfield. `Emitter._capture_source` handles `initcode`
through the same capture boundary as `initval`, preventing an outer static
initializer macro from recapturing an inner macro's generated body.

## Acceptance evidence

| Shape | Values | Generated C bytes | Translation seconds |
| --- | ---: | ---: | ---: |
| rectangular | 4 | 5,863 | 0.046 |
| rectangular | 8 | 11,267 | 0.054 |
| rectangular | 12 | 16,703 | 0.067 |
| rectangular | 16 | 22,171 | 0.074 |
| rectangular | 32 | 44,043 | 0.112 |
| rectangular | 64 | 87,787 | 0.186 |
| mixed records/arrays | 16 | 49,221 | 0.120 |
| mixed records/arrays | 32 | 98,213 | 0.203 |
| mixed records/arrays | 64 | 196,197 | 0.370 |

The original rectangular sixteen-value case timed out after twenty seconds.
The mixed sixteen-value baseline produced 906,055 bytes in roughly six
seconds. Dimensions are four for the smaller cases and eight for 32/64.
Both repaired series grow in proportion to the supplied values.

The `initializer-ordinal` fixture checks every position in a non-square
array, custom destination conversion, exactly-once calls, local and compound
literal initialization, file-static initialization, static arrays of mixed
records, nested mixed arrays, and selected/unselected bitfields. Its expected
stdout and status pass. Eleven existing focused fixtures also pass, covering
macro chronology and redefinition, native type identity, canonical syntax,
designators, braces, aliases, unions, strings, and static qualifiers.

Separate before/after probes retain excess-value side effects and accepted
empty unselected arrays; invalid dimensions and initialized VLAs remain
rejected. The publication gate first found a stale bootstrap copy of the
runtime's character-array zero initializer. Stages zero, one, and two agree
on all 156 generated C/H files; the normal gate is refreshing the seed.

Raw sources, generated output, logs, measurements, and compatibility evidence
are retained outside the worktree:
`/Users/gary/Documents/x2c-evidence/aggregate-initializer-fix-20260911/`.
Original proposal evidence remains at
`/Users/gary/Documents/x2c-evidence/closeout-20260910/research/aggregate-initializer-growth/`.

## Plan and source review

Existing type resolution and ordered fields establish the layout facts. The
new traversal does not repeat binding, conversion, lifetime, or diagnostic
validation. Its temporary tree prevents repeated type traversal and replaces
boundary histories for eligible inputs; it does not create a second semantic
AST. Three private operations separate layout construction, ordinal mapping,
and row production. The generic walker remains necessary for whole-object
and designated consumption.

Canonical List templates and existing path frames keep the change local and
ordinary x2c. The emitter repair unifies two existing capture cases. The
bitfield repair reuses the declared base type. No validator or dedicated
diagnostic was introduced. The added regression protects actual destination
values, side-effect counts, and the two reproduced invalid native outputs.
Authored changes were reviewed before publication validation; generated
changes are reviewed before delivery. The existing publication gate remains
unchanged.
