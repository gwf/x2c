# Diagnose a `#define` name used as a bare atom in a List literal

> Status: needs author scoping
> Written 2026-09-09 from an incident in the torch package work. The
> package-side misuse (reading a Symbol's payload as an integer) is fixed
> in `packages/torch`; the compiler-side diagnostic below is the open
> decision.

## What happened

An example wrote `#define ROWS 64` and then `Tensor.randn(%(ROWS 4), ...)`.
Inside `%(...)` a bare identifier is a Symbol by design, so the shape List
was `(ROWS 4)`. The package read the first size with `Var.integer()`, which
is documented as a payload reader that returns a Symbol's numeric value,
and allocated a tensor of 346,544,039 rows. Nothing reported the mismatch:
the preprocessor never sees the literal, the literal grammar accepted the
atom, and the reader returned a number.

Reproducer:

```x2c
#include "x2c.x"
#define ROWS 64
int main(void) {
  List shape = %(ROWS 4);
  printf("%s %ld\n", shape.repr(), shape[0].integer());   // (ROWS 4) 346544039
  return 0;
}
```

## Two owners, two fixes

1. Reading. `Var.integer` is a reader by contract (`lib/var.x`) and the
   contract already says to convert when the tag might not be what the
   caller expects. Code that turns user-supplied Vars into sizes, indexes,
   or counts must convert: assigning a `Var` to a `long` or calling
   `Var.convert` raises `<no-convert>` for a Symbol. This is a caller
   obligation, fixed in the torch package with a regression. No change to
   `Var.integer` is proposed: its payload reading is deliberate and used by
   the runtime.

2. Spelling. The author meant the macro's value and wrote the macro's name
   where the literal grammar produces a Symbol. The intended spelling is
   `%($ROWS 4)`, which unquotes the expression the preprocessor expands.
   This is the compiler-side question: should a bare atom inside `%()`,
   `%[]`, or `%{}` that names a visible object-like `#define` receive a
   diagnostic?

## Proposed diagnostic

Report a warning (not an error; `%(build fast)` style literals are the
common case and a macro named like a data word is legal) when a bare atom
in a literal names an object-like macro defined earlier in the same
translation unit's x2c source:

```text
def.x:4:18: warning: 'ROWS' is a Symbol here; write $ROWS to insert the
  macro's value
```

Facts to rely on:

- `src/parse.x` sees every `#define` line as a `preproc` statement
  (`case %(preproc ?directive)` near line 1883) in source order, so the
  compiler can keep a set of object-like macro names it has passed,
  without expanding anything. Function-like macros (`#define F(x)`) are
  excluded: a bare atom cannot call them.
- Bare atoms in list literals are built by `_list_prefix_atom` in
  `src/literals.x` (line 123), which is the one place to consult the set.
- Macros from included C headers are not in this set. x2c collects raw
  symbols from headers without expansion; a warning for header macros
  would need the `--cpp-symbols` path and is out of scope. Say so in the
  book if the warning ships.

Cost: one Map of names per unit, one lookup per bare atom in a literal.
No new validator on the AST, no origin tracking, no rejection of legal
constructed syntax: a Lisp-constructed `(ROWS 4)` is untouched because
the check runs in the literal parser only.

## Alternatives considered

- Expanding object-like macros inside literals: rejected. `%()` is a data
  grammar; silently substituting values would change the meaning of
  existing literals such as `%(build fast)` whenever a header happens to
  define `build`.
- Making `Var.integer` raise for non-integer tags: rejected. It is the
  documented payload reader; the converting accessors already exist.

## Validation

- Fixture `unittest/compiler-fixtures/literal-define-name.x` with a
  `.diagnostics` sidecar expecting the warning for `%(ROWS 4)` and no
  warning for `%($ROWS 4)` or for a bare atom that names a function-like
  macro.
- The torch package regression (landed): `Tensor.of(%(1 2), %(rows 2),
  XT_INT64)`, `Tensor.zeros(%(3 cols), ...)`, and `t[%(first 1)]` raise
  `<no-convert>` instead of allocating or selecting.

## Plan review

- The literal parser is the producer of Symbols and already knows every
  `preproc` statement it has passed; the check consults established facts
  and adds no second validator downstream.
- Nothing is deleted. The new mechanism is one name set and one lookup,
  justified by a silent 55 GB allocation with no diagnostic at any layer.
- The warning protects against wrong output (a Symbol where a number was
  meant). It is a warning because the same spelling is legal data.
- Consequential choice for Gary: whether a warning on bare macro names in
  literals is wanted at all, and whether it should also cover header
  macros through `--cpp-symbols`.
