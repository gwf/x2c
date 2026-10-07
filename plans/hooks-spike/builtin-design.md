# Independent design: string case labels in `switch`

> Status: reference. Independent design sketch and working prototype on
> branch `independent-case-design`, started from dev f36c0808 on
> 2026-10-07. Written for comparison with other approaches; not scheduled
> for delivery.

## Result

`switch` accepts a `String` or C string subject with string-literal case
labels. The compiler lowers such a switch, in the transform phase, to an
integer switch over the same body. Each distinct label becomes an arm
number, and the subject is compared with the labels through the ordinary
`String` `==`. Because the body stays a C switch, every C control-flow rule
holds without new code: fallthrough, `break`, `continue`, `default` in any
position, labels in nested blocks, nested switches, `defer` boundaries, and
the existing static-initializer and cleanup-region checks.

The prototype adds 123 lines to `src/transform.x` and removes none. It adds
three compiler fixtures and one checked book sample.

## Semantics

| Question | Decision | Reason |
| --- | --- | --- |
| Which switches change | Subject type is `String` (including aliases and `const String`) or char-pointer-like (`char *`, `const char *`, `char[]`). Every other subject is untouched. | C rejects these subjects today, so no valid program changes meaning. Integer, enum, and Symbol switches keep their exact C. |
| Equality | `String` `==` (`String_equal`): byte content. | It is the comparison x2c users already write. The lowering resolves `==` through the ordinary operator owner, so it inherits that rule instead of defining another. |
| Null `String` | Matches `case "":`. | x2c defines the null pointer as the empty `String`; `==` already says so. |
| Null C string | Matches no label; selects `default`. | In C a null `char *` is not a string. This also separates "unset" from "empty" for `getenv`-style values. **Needs Gary** (see below). |
| C string comparison | The subject is viewed as `String` by a cast, not converted. | A conversion (`String_new`) would intern and allocate on every dispatch. The cast compares in place. |
| Label kinds | A string literal, adjacent literals, a parenthesized literal, or a native macro that x2c types as a string literal. | Only constants keep a switch a switch: no label evaluation, no order-dependent side effects, and compile-time duplicate detection. |
| Rejected labels | Identifiers, calls, `%"..."` interpolations, conditional expressions, integer labels in a string switch. | They are runtime values. `match` and `if` chains already express computed comparisons. |
| Duplicates | An error when two literal labels decode to the same bytes (`"a"` and `"\x61"`), or the same macro name appears twice. | C makes equal integer labels a constraint violation; a silent duplicate would be a dead arm. Adjacent literals decode per segment before joining, as C does. |
| Order | Labels are tested in source order; the first equal label wins. | With duplicates rejected, order never changes the result; it only fixes the generated code. |
| Evaluation | Subject evaluated once into a temporary. | C switch semantics. |
| Other types with `==` | Not included. | See "Generalization". |

### Generalization

The mechanism generalizes: the selector is built from ordinary `==`
expressions, so any subject type with an equality operator could reuse
it unchanged. I would not admit other types now:

- Symbol, enum, and integer subjects already work as C switches.
- Floating-point equality in a dispatch is a trap, and C rejects it today.
- `Var` and `List` subjects with structural labels are what `match` does,
  with patterns, captures, and head dispatch. A second dispatch surface for
  the same values would compete with it.
- User records with a protocol `==` have no literal label form, so their
  labels would be runtime values. That loses the switch's properties.

If a later need appears, widening the subject test in
`Compiler._string_switch` and the label rule in `_case_key` is the whole
change.

## Implementation

All code is in `src/transform.x`.

- `Compiler._step_tag` gains one arm: `case <switch>: next =
  c._string_switch(ast); break;`. It sits beside the existing `<match>`
  lowering. An integer switch returns unchanged and continues through
  `_default_node` as before.
- `Compiler._string_switch` checks the subject type with
  `Sym.is_string_type` and `Type.is_char_pointer_like`. It numbers the
  body's labels, introduces a temporary with `Sym.introduce` and
  `Compiler.fresh_name`, and returns
  `{ T tmp = subject; switch (selector) body }`. The fixed-point driver
  then normalizes the new block, so the subject, the comparisons, and the
  body are lowered by their ordinary owners.
- `StringCases.number` rewrites the `case` nodes this switch owns. It stops
  at nested `switch`, `match`, `matchcases`, `function`, and `expr` nodes,
  and tracks `(at ORIGIN ...)` wrappers so diagnostics point at the label's
  statement.
- `StringCases.arm` validates one label, rejects duplicates, and returns the
  arm number literal.
- `StringCases.selector` builds `t == L1 ? 1 : t == L2 ? 2 : ... : 0`. Each
  `==` goes through `Compiler.resolve_expression`, which converts the raw
  literal to a cached `String` and selects `String_equal`. The `?:` nodes
  are built directly as `int`, because both arms are `int` literals.
- `_case_key` and `_literal_bytes` compute a label's identity for duplicate
  detection.
- Two report macros: `$report.xform.string_case_label` and
  `$report.xform.string_case_duplicate`.

Reused owners: the transform fixed-point driver, `Sym.introduce`,
`Compiler.fresh_name`, `Compiler.resolve_expression` (operator resolution
and String literal caching), `source_operator_expression`,
`source_block_content`, `Type.declaration_parts`, `$ast.rewrite_children`,
and `String.unescape`. Parsing and binding are unchanged: the parser already
accepts `case EXPR:`, and the binder already resolves each label.

The lowering is in the transform phase rather than the binder because
transforms own lowering (code standard AR-1, AR-3), and because the binder
also binds macro templates, where a subject or label may still be a hole.

### Generated C

Source:

```x2c
static String classify(String s) {
  String out = "";
  switch (next(s)) {
    case "apple":
      out += "apple>";
    case "pear": case "plum":
      out += "fruit";
      break;
    default:
      out += "other";
      break;
    case "":
      out += "empty";
      break;
  }
  return out;
}
```

Generated (abridged; `_0` to `_3` are the file's cached `String` literals):

```c
{
  String _x2c_switch_subject_0 = next(s);
  switch(String_equal(_x2c_switch_subject_0, _1) ? 1 :
         String_equal(_x2c_switch_subject_0, _2) ? 2 :
         String_equal(_x2c_switch_subject_0, _3) ? 3 :
         String_equal(_x2c_switch_subject_0, _0) ? 4 : 0){
    case 1 : _x2c_proto_string_add_update(&(out), 56, _4);
    case 2 : case 3 : _x2c_proto_string_add_update(&(out), 56, _5);
    break;
    default: _x2c_proto_string_add_update(&(out), 56, _6);
    break;
    case 4 : _x2c_proto_string_add_update(&(out), 56, _7);
    break;
  }
}
```

A C string subject adds a null guard and a cast:

```c
{
  const char * _x2c_switch_subject_3 = words[i];
  switch(_x2c_switch_subject_3 ?
         String_equal((String) _x2c_switch_subject_3, _19) ? 1 :
         String_equal((String) _x2c_switch_subject_3, _20) ? 2 : 0 : 0){
    case 1 : continue;
    case 2 : return kept;
    default: kept ++;
  }
}
```

## Diagnostics

```text
string-switch-label.x:5:5: xform: a case label in a string switch must be a string literal
      case other: return 2;
      ^^^^
  note: compare computed values with an if chain or match

string-switch-duplicate.x:7:5: xform: duplicate case label in a string switch
      case "\x61": return 3;
      ^^^^
  note: label: "a"
```

Both report at the label's statement origin. The caret covers `case`
because origins are recorded per statement; pointing at the literal itself
would need a per-expression origin.

No other diagnostic is added. A switch on any other non-integer type still
reaches the C compiler, as today.

## Validation

- `make build`, then `make bootstrap-refresh` and `make build-safe`. The
  refreshed bootstrap translated all of `lib/` and `src/` through the new
  arm with no change to any existing switch's output.
- New fixtures: `string-switch` (stdout, status), `string-switch-duplicate`
  and `string-switch-label` (compile-status, diagnostics).
- Existing fixtures that contain `switch`, all passing:
  `cleanup-loop-boundary`, `static-local-switch`, `static-local-once`,
  `c-body-directive`, `meta-c-semantics`, `comptime-lowering`,
  `percent-after-condition`, `macro-enumerator-projections`,
  `meta-native-constructs`, and `adjacent-c-literals`.
- Scratch probes: `defer` inside an arm with `continue` and `break`, the
  `$switch` decorator from `system-macros.x` on a String subject, a
  `typedef String Name` subject, a `const String` subject, and a null
  `String`, transient empty `String`, `char[]`, and native-macro label.
- The book sample in `docs/src/reference/language.md` was built and run.

`cleanup-loop-boundary` fails its `transform` artifact when stage 0 is built
from changed `src/` but bootstrap is not refreshed. The cause is the
prelude: `builds/0/lib/x2c.xi` carries the identity of `bin/x2c`, so a
changed stage-0 compiler cannot replay it and parses `x2c.x` in full, which
shifts origin numbers. This affects any compiler change, not this feature.

## Measurements

Translation of one file, `x2c translate FILE --out-dir DIR`, with
`/usr/bin/time -l` "instructions retired", minimum of three runs. Each file
has N functions `int fI(String s)` with three labels `"aI"`, `"bI"`, `"cI"`
(the last two share an arm) and a default, or the hand-written equivalent.

| Form | N = 50 | N = 400 | Slope per use |
| --- | ---: | ---: | ---: |
| string `switch` | 2,198,617,381 | 4,359,783,310 | 6,174,760 |
| `if` chain with `==` | 2,149,755,883 | 4,064,467,848 | 5,470,606 |
| `if` chain with `strcmp` | 2,235,076,431 | 4,753,515,310 | 7,195,540 |

The string switch costs 704,154 more instructions per use than the `==`
chain (12.9%), and 1,020,780 fewer than the `strcmp` chain. The extra work
is the temporary declaration, the block, the arm-number literals, and the
label walk. All three forms resolve the same three comparisons.

Runtime dispatch is a linear chain of `String_equal` calls, the same work a
hand-written `==` chain does. Interned subjects compare by pointer first.

## Design review

- **Reuse.** The lowering adds no runtime helper, no new AST form, and no
  emitter case. It produces forms the transform already normalizes.
- **Alternatives rejected.**
  - Emit-time lowering, as `match` does, would print comparisons as text
    and bypass operator resolution and literal caching (AR-4).
  - Lowering in `_bind_switch` works but puts a lowering in the binder and
    needs a guard for macro templates.
  - A runtime table helper with a memoized index would add a unit-support
    function and an initialization path. Three to ten labels do not repay
    that. It is the right follow-up if long label lists become common.
- **Checks that earn their place.** Label validation prevents wrong output:
  a non-constant label would otherwise compare a runtime value silently.
  Duplicate detection preserves a C constraint. No other validation was
  added.
- **Possible follow-ups.** Dispatch on length before comparing, for long
  label lists. Point the diagnostic caret at the label expression.

## Needs Gary

1. Null C string subject: the prototype selects `default`. The other
   choice is to match `case "":`, as a null `String` does. That choice
   removes the null guard and makes both subject kinds follow one rule, but
   it hides the C distinction between unset and empty.

Everything else above is decided.
