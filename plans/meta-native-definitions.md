# Native `meta` definitions

> Status: active.
> Capability and migration implemented on the worktree branch; see the
> commits that reference this plan. Not yet delivered to `dev`.

## Requested behavior

A runtime function that compile-time code should call natively is declared
twice today: a bodyless `meta` prototype, then the ordinary definition.
`lib/` carries several hundred such pairs. Let the definition itself say
that compile-time code binds the compiler's native copy.

The book change is in `docs/src/guide/meta-functions.md` under "Native
definitions", with matching sentences in `docs/src/reference/language.md`
and `docs/src/guide/packages.md`.

## Spelling

`meta native` before a function definition:

```x2c
/** Returns how many elements compare equal to `value`. */
meta native int Array.count(Array array, Var value) {
  _int_length(array);
  return array._core_count(value);
}
```

It means exactly the bodyless prototype followed by the definition. The
bodyless prototype remains for functions with no x2c body (`meta double
sin(double);`) and is still accepted everywhere it is today. `native` is
contextual: it is a marker only directly after `meta` and before a
declaration, so a type named `native` keeps working.

### Why not a decorator

A decorator cannot express this without new compiler machinery:

- The advertisement must exist during shallow collection. Collection
  records a `native-meta` symbol row from each marked declaration; that row
  feeds the `.xi` interface, the compiler's native target inventory
  (`_x2c.native-meta.targets`), `--kind meta-module` exports, and package
  module detection. Collection does not expand decorators; it collects the
  unchanged target.
- A `Function` decorator replaces only the body. A `Unit` decorator could
  emit a prototype sibling, but a public target "cannot gain new public
  siblings" (reference, Decorators), and collection would still not see it.
- The only other decorator-shaped spelling, a top-level `@`, is rejected
  by the parser.

Making either work means teaching collection to expand one decorator, which
is more machinery than a second contextual word after `meta`.

## Implementation

- `src/parse.x`: `Compiler.take_meta_marker` consumes `meta` and an optional
  `native`, and `meta_form_is_declaration` uses it. `parse_top_level`
  calls the existing `install_native_meta_function` before parsing a native
  definition's body, parses that body as an ordinary function, and rejects
  `native` on a non-function.
- `src/compiler.x`: shallow collection records the existing `native-meta`
  effect for a native definition as it already does for a prototype.
- Everything downstream (target inventory, meta-module exports, `.xi`
  interfaces, package modules) consumes the same row unchanged.

## Delivery

1. Capability, fixtures, book, and bootstrap refresh. The checked-in
   bootstrap cannot parse `meta native`, so callers wait for this commit.
2. Migrate `lib/` pairs whose prototype immediately precedes its definition
   in the same file. Prototypes for functions without an x2c body, and
   prototypes separated from their definition, stay.

Each commit is validated with `tools/gate-state.py ensure agent-pr-check`.

## Plan review

- Trusted facts: the existing native path checks the signature against the
  target and certifies lifetimes; the new form reuses it and adds no check.
- Reuse: no new install path, row kind, or collection pass. The only new
  function is the marker reader shared by the probe and both parsers.
- Validators: one diagnostic, `native` on a non-function, protects public
  behavior: without it `meta native static int x = 1;` would silently
  become a lowered meta value. `comptime-declines-native-meta-definition`
  owns it and the signature mismatch through the definition form.
