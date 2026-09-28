> Status: active -- not yet started.
> Prerequisite: meta-integration must land on dev first.
> This refactor precedes core support and is independent of try migration.

# Share the macro capture projection schema

Research evidence is retained on `codex/compiler-dual-macro-spike` at
[`1e2d5607`](https://github.com/gwf/x2c/commit/1e2d5607be514c7205507d3f6e39c889e0cff7ec).
Source offsets refer to the research baseline;
verify current owners before implementation. All `.context/` paths below name
repository paths on that pinned research branch, not files delivered to dev.
The research branch contains compiler snapshots and must not be merged.

Give `_capture_pattern` and `_capture_row` one private role table for capture
projection names, cardinality and row-layout policy. Preserve their different
jobs: the former constructs ordinary Match patterns; the latter preserves
captured code and source. Do not replace either with another matching engine.

Owners are src/macros.x, specifically `_capture_pattern`, `_capture_row`,
`_forwarded_capture`, `_forwarded_prefix_list`, `_replacement_binder`, and
`_member_bindings`. Source offsets move; the research baseline has the two
entries at 2832 and 2965, not the earlier survey's 2868 and 3001.
The detailed read-only scope and traced call graph are in
[capture-scope.md](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase4/capture-scope.md). This is the
first production change named by
[the compiler contract](compiler-dual-macro-contract.md); it is independent of
[try migration](archive/dual-macro-try-migration.md).

## Shared schema and exact compatibility

Use a compact file-private static table. Each row supplies role name,
scalar/sequence binder policy and storage location. Keep explicit ordinary
code for Function, Unit and Name special projections. Keep both public-to-file
entry points thin and direction-specific; their callers and existing outputs
remain unchanged.

| Projection | Policy that must remain unchanged |
| --- | --- |
| author | Hole's own binder aliases source; not a serialized field |
| source | Source field, preserving wrappers and forwarded source capture |
| value | Unwrapped value field, preserving ordinary binding identities |
| expression | Scalar field; sequences alias value through existing `!and` |
| splice | List binder for scalar and sequence; sequence aliases value |
| Function return/declarator | Virtual nested value subfields, scalar only |
| Unit construction | Trailing requirements under existing precise used-role condition |
| Name member | Direct replacement from retained original source name facts, not a row field |

A scalar row keeps source/value/expression/splice in its present order. A
sequence row keeps only source/value and trailing Unit construction material;
never add scalar expression/splice fields to sequences. Keep Function virtual
subfields virtual and Name member replacements separate from serialized rows.
Unit requirements activate under the existing author/source/value/splice/
construction condition, not whenever any projection is used.

Keys continue to come from `_replacement_binder`. Preserve the existing
question-mark sentinel handling, empty/multiple nonsequence fallback,
forwarding boundaries and source capture. Do not add arity, origin or List
shape validation. Existing hole inference, member parsing, ordinary binding,
freshening and supplied Name identity remain authoritative.

## Implementation and deletion

1. Establish current-dev output with the existing focused fixtures below.
   Trace callers again before editing because the research source baseline
   is not necessarily current dev.
2. Introduce one private schema/key operation and a common row-layout owner
   for pattern and row directions. Reuse `_replacement_binder`, `_projection`,
   `_source_unwrap` and forwarding rather than inventing callbacks or another
   representation. Feed explicit kind-specific behavior into the existing
   directions.
3. Delete duplicated role strings, cardinality choices and row ordering from
   `_capture_pattern`/`_capture_row`; update forwarding to use the same role
   owner where it currently repeats projection-key policy. A table that only
   renames four strings does not accomplish the consolidation.
4. Compare focused fixture outcomes and canonical/generated artifacts with
   the pre-change current-dev baseline. Review and fix the authored diff,
   then run the existing ordinary publication gate and deliver on dev. The
   refactor requires no new-form bootstrap transition; ordinary regeneration
   remains owned by the existing publication command.

## Focused validation

These are existing, verified source filenames under
`unittest/compiler-fixtures/`; preserve their checked-in expectations:

- `macro-hole-grouping.x`, `macro-kind-ambiguous.x`.
- `macro-sequences.x`, `macro-sequence-nonfinal.x`.
- `macro-source-parity.x`, `macro-source-text.x`,
  `macro-source-text-derived.x`, `macro-source-text-constructed.x`.
- `macro-decorators.x`, `macro-decorator-variadic-target.x`,
  `macro-decorator-public-two-level-drop.x`.
- `macro-function-style-syntax.x`, `macro-unit-name-hole.x`,
  `macro-unit-typedef.x`, `macro-unit-struct.x`, `macro-unit-bitfield.x`.
- `macro-binding-spelling.x`, `macro-name-stability.x`,
  `meta-template-calls.x`.

These exercise current capture/forwarding, construction obligations and Name
facts; they do not prove all future dual-Macro recognition semantics. Use
additional existing Function consumers identified from current source when
necessary, without creating a new recurring test requirement. Run the
ordinary gate once the coherent refactor is ready; do not broaden process.

## Delivery boundary

Author fresh on current dev; do not merge the research branch, which stores
full compiler snapshots under .context and isolated implementation scaffolding.
This deliverable changes no public forms, helper transport, macro resolution
policy or template stage contract. It proceeds after meta-integration lands on dev and before core dual-Macro
support. Do not include try lowering or general open-name work in its diff.

## Plan review

Hole parsing already determines kind and sequence; ordinary capture, forwarding
and binding already establish identity and source facts. The shared table
records those facts rather than rechecking them. It deletes duplicated schema
policy, reuses Match and existing List construction, and keeps special behavior
in explicit x2c branches instead of a callback framework. No lasting traversal,
cache, AST language, semantic validator, dedicated diagnostic or negative
fixture is proposed. Existing expectations detect compatibility regressions;
the ordinary publication checks remain unchanged.
