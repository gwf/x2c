# Ordinary switch over String

> Status: active
> Planned 2026-10-07 against `dev` `0916ff92`. Source read and one probe of
> the lowered shape; no implementation yet. Obtain Gary's execution
> instruction before changing production code.

## Result

An ordinary C `switch` accepts a selector of static type `String`, or an
alias reaching `String`, with string-literal `case` labels:

```x2c
int classify(String color) {
  switch (color) {
    case "red": return 1;
    case "green":
    case "blue": return 2;
    case "": return 3;
    default: return 0;
  }
}
```

A label matches exactly when `color == "label"` holds under ordinary x2c
comparison. A string literal opposite a `String` already converts to that
type and compares through its `equal` member
([language reference](../docs/src/reference/language.md), operator
comparisons), so the switch adds no new equality rule. `case ""` matches the
empty `String`, which is null. Everything else is C `switch`: adjacent
labels, `default` in any position, fallthrough, `break`, an enclosing loop's
`continue`, nested switches, and labels inside nested blocks of the body.

This is not `match`, and `$switch` in `lib/system-macros.x` is unchanged.
It also serves as the second design check from the archived
[unit initialization plan](archive/unit-initialization-and-assembly.md): the
feature contributes one helper to unit support and its literals to the
literal cache, through existing owners only.

## Current behavior

`_switch_statement` (statements.x) parses `switch`, `_bind_switch`
(parse.x) resolves the selector and binds the body, transform has no switch
lowering, and emit writes a native `switch`. A `String` selector and string
labels therefore reach C, which rejects both ("statement requires expression
of integer type"). Case labels bind as `(case (expr (* char) (literal ...)))`.
Symbol labels such as `case <help>:` already work, because Symbols are
integer constants.

## Settled choices

- **Selector types.** Static `String` and aliases reaching it
  (`Sym.is_string_type`). `char *`, `const char *`, and `Var` selectors keep
  native behavior.
- **Labels.** Every case owned by a `String` switch must be a string literal,
  including adjacent-literal concatenation and an object macro that expands
  to one. This keeps C's constant-label meaning. One new diagnostic reports
  any other label: "a case in a String switch takes a string literal". It
  is justified because an integer label would otherwise silently select a
  dispatch index, and a non-constant label cannot be evaluated in the
  helper.
- **Duplicates.** Equal labels map to the same dispatch index, so the C
  compiler rejects them as it rejects duplicate integer labels. No x2c check.
- **Dispatch.** A static helper per distinct (selector type, label sequence)
  compares the selector against each label in source order and returns the
  label's index, or 0 when none matches. The switch then dispatches on the
  helper's result. The selector is evaluated once, as the argument, with no
  temporary, wrapper block, or hidden loop. Linear comparison is the first
  algorithm; `String.equal` already short-circuits on equal pointers.
  Hash-based dispatch can replace the helper body later without changing the
  switch.

## Implementation

1. **Recognize.** Add `case <switch>:` to `Compiler._step_tag`
   ([transform.x](../src/transform.x)), beside `<match>`, calling
   `Compiler._switch_node`. Recognize the input with the `switched` grammar
   macro ([grammar.x](../src/grammar.x)). Return the node unchanged unless
   the selector's type reaches `String`.
2. **Collect owned labels.** Walk the body with `$ast.rewrite_children`,
   looking through `at` wrappers and stopping at a nested `switch`. Each
   owned `(case ...)` must hold a string literal; otherwise report the new
   diagnostic through a `$report.xform` macro. Assign indices from 1 by
   distinct label content in source order, and rewrite each label to
   `(case (expr (int) (literal (int) "N")))` with `x2c_literal_int`.
3. **Contribute the helper.** Under `$adapter.memo`
   ([adapter-memo.x](../src/adapter-memo.x)) keyed by
   `(string-switch TYPE LABELS)`, introduce a fresh name, build
   `static int NAME(TYPE s) { if (s == LABEL) return N; ... return 0; }` with
   a `$!Unit` template whose tests are a spliced statement sequence, bind it
   with `bind_syntax(..., AST_UNIT, NULL)`, and queue it with
   `add_support`. The transform drain lowers it, so literal conversion and
   protocol `equal` dispatch come from ordinary lowering and the literals
   enter the literal cache.
4. **Rewrite.** Return `switch (NAME(selector)) BODY` with the rewritten
   body, built with the `switched` macro. `_step` then normalizes it as an
   ordinary integer switch, so `Walk._rewrite_switch` bounds `break` and
   emit writes it natively.
5. **Document.** Add the rule and the example above to "C control flow" in
   [language.md](../docs/src/reference/language.md).
6. Review and fix the completed authored diff before publication
   validation.

## Compatibility

Integer, enum, and Symbol switches are unchanged: the new step returns them
as they are. The runtime-static check in `emit.x` ("switch cannot bypass
dynamic static initialization") still applies to the rewritten switch.
Generated C changes only for units that contain a `String` switch.

## Validation

- **Probe (done).** A hand-written helper and integer switch over a `String`
  alias dispatched `"red"`, a built `"gr" + "een"`, `"blue"`, `""`, `NULL`,
  and a non-match correctly through `x2c run`.
- **Positive fixture** `string-switch` with run output. It covers adjacent
  labels, fallthrough, `default` first and last, no match without `default`,
  `case ""` against `NULL`, an alias selector, a selector expression with a
  side effect (evaluated once), `break` and `continue` inside a loop, a
  nested integer switch, a nested `String` switch, a label inside a nested
  block, and two switches with the same labels sharing one helper (checked in
  the `.c` phase).
- **Negative fixture** `string-switch-label` for the new diagnostic, with an
  integer label and a `String` variable label.
- Focused existing fixtures that exercise `switch`, plus the publication gate
  from current `AGENTS.md`.

## Plan review

Binding establishes the selector type; ordinary comparison establishes
equality; the literal cache owns the label storage; unit support and
`$adapter.memo` own the helper and its once-per-unit generation; cleanup and
emit own switch control flow. The lowering consumes those facts and adds one
diagnostic for a label the helper cannot evaluate. It adds no runtime
module, no new equality semantics, and no second dispatch path.
