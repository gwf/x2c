# Foreign C qualifiers

x2c stores imported `const`, `volatile`, and `restrict` on the outer
function-result, global-object, and record-field type path. It rejects a
conversion that would silently drop one. For example:

```c
const char *GetMonitorName(int monitor);
```

The call expression has type `(* const char)`. Assigning it to a mutable
pointer stops translation with `cannot convert (* const char) to (* char)`.
A conversion through a converter function copies the value, so
`String owned = name;` works through `String_new`.

## Declared types and lookup types

`Sym.declare` stores `Type.declared()`. Both `declared` and `canonicalize`
drop storage classes and `inline`, which describe where a declaration lives;
only `canonicalize` drops qualifiers. Function return conversion, identity
bindings in `Sym.bind_identity`, and the `_Generic` signature asserted by a
foreign alias preserve declared qualifiers.

Type lookup uses the unqualified form: a `const` receiver names the same
aggregate, fields, methods, protocol conformance, and `Var` tag as its
unqualified type. The func-landing thunk in `src/emit.x` also uses an
unqualified result type because it declares a result variable and assigns to
it afterwards. `src/snapshot.x` serializes the qualifiers in the symbol Map,
so snapshot and live symbol collection expose the same declared types.

Qualified typedefs, including `typedef const char *(*fn)(int);` and
`typedef const int cint;`, preserve their qualifiers. Conversions to `void *`
are checked for qualifier loss, and `$x2c.foreign.alias` accepts
pointer-returning targets while checking their declared signatures.

## Examples and tests

Imported declarations retain these types:

| Symbol | Type |
|---|---|
| `sqlite3_libversion` | `((func ((void))) * const char)` |
| `sqlite3_version` | `((dim) const char)` |
| `struct sqlite3_vfs zName` | `(* const char)` |

`unittest/compiler-fixtures/foreign-qualifier*` covers calls, globals,
fields, a callback typedef with a `const char *` result, foreign aliases,
the symbol table, and generated C against `foreign-qualifier-upstream.h`.
Companion fixtures check rejection of qualifier-dropping assignments from
results, globals, and fields. `qualifier-void-pointer` and
`foreign-alias-pointer-result` cover the corresponding pointer conversions
and aliases.

A header that spells its declarations with macros needs `--cpp-symbols`,
because x2c does not expand macros.

## Package source

Packages keep upstream headers and raw function names authoritative and
spell upstream qualifiers faithfully in client source. Do not introduce
renamed pointer types, copied records, casts, or forwarding functions to work
around a qualifier: they obscure the upstream API. Assign an imported
`const` result, global, or field to a pointer that preserves its qualifier,
or use a converter that copies the value when ownership is needed.
