# Foreign C qualifier boundary

## First-release decision

The compiler change landed before the first public release, so this file no
longer describes a live limitation. x2c stores imported `const`, `volatile`,
and `restrict` on the outer function-result, global-object, and record-field
type path, and rejects a conversion that would silently drop one.

The example that opened this file:

```c
const char *GetMonitorName(int monitor);
```

now annotates the call expression `(* const char)`. Assigning it to a mutable
pointer stops the translation instead of reaching a C compiler that only
warns.

## What changed in the compiler

`Sym.declare` stores `Type.declared()` rather than
`Type.canonicalize()`. Both drop storage classes and `inline`, which describe
where a declaration lives; only `canonicalize` drops the qualifiers, which
describe the value. The same distinction now applies to the function return
type a `return` statement is converted against (`src/parse.x`, `src/emit.x`),
to the identity bindings in `Sym.bind_identity`, and to the
`_Generic` signature a foreign alias asserts against.

`Compiler.convert_expression` reports
`cannot convert (* const char) to (* char)` when the source and target are
the same type apart from qualifiers the target does not offer. That is the
case where C hands the same address on without a call; a conversion that
reaches a converter function copies the value, so `String owned = name;`
still works through `String_new`.

Everything that uses a type as a *lookup key* keeps the unqualified form,
because a `const` receiver names the same aggregate, the same fields, the
same methods, the same protocol conformance, and the same `Var` tag as the
unqualified type: the declared-typetag rows in `src/type.x`, the `Var` tag
resolution and interpolation paths, `Compiler.resolve_postfix_member`,
`_resolve_protocol_member`, `Compiler.protocol_rejects_direct_member`, and
the foreach collection type in `src/transform.x`. The func-landing thunk in
`src/emit.x` also keeps the unqualified result type, because it declares a
result variable and assigns to it afterwards.

`src/snapshot.x` needed no change. It serializes whatever the symbol Map
holds and already carried qualifiers, which is exactly why the snapshot and
the live table used to disagree.

Two adjacent defects were repaired because the fixtures could not otherwise
spell an upstream header:

- a qualified typedef did not parse at all. `typedef const char *(*fn)(int);`
  and even `typedef const int cint;` stopped with `expected scalar type`,
  because `_parse_typedef` never read the leading qualifiers.
- a foreign alias to a `const`-returning function failed its own static
  assert, because the emitted `_Generic` type had been canonicalized.

## Measured result

The before-and-after probe copied the macOS SDK `sqlite3.h` beside a small
client and translated it with `--cpp-symbols`, once with the checked-in
`bin/x2c` and once with the rebuilt compiler. That header is a real upstream
header carrying all three shapes: the `sqlite3_libversion()` result, the
`sqlite3_version[]` global, and the `struct sqlite3_vfs` `zName` field.

| Symbol | Before | After |
|---|---|---|
| `sqlite3_libversion` | `((func ((void))) * char)` | `((func ((void))) * const char)` |
| `sqlite3_version` | `((dim) char)` | `((dim) const char)` |
| `struct sqlite3_vfs zName` | `(* char)` | `(* const char)` |

Before, the client that assigned all three to `char *` translated without a
diagnostic and its generated C compiled with three
`-Wincompatible-pointer-types-discards-qualifiers` warnings. After, each
assignment stops the translation. A client that spells the qualifiers
faithfully compiles `-Wall` clean, links `-lsqlite3`, and runs.

Snapshot and live symbols agree. `etc/symbols.xlisp` used to record
`((struct "LispCanonicalName") (struct ((int) (* const char) (* "Var"))))`
and, three lines below it,
`((struct "LispCanonicalName" "spelling") (* char))` -- the aggregate body
kept the qualifier the field row dropped. Refreshing the artifact changed 37
rows: 14 record fields, five function results, and 18 globals. `make
sym-check` passes on the refreshed artifact and `make proof-conformance`
agrees across 67 units.

The changed compiler translates the whole of `lib/` and `src/` with no new
diagnostic and emits the same C, byte for byte, as the pre-change bootstrap
compiler emits for every unit. The only accepted output change anywhere is in
`unittest/compiler-fixtures/foreach-lowering`, where a `const char *p` local
now indexes to `const char` instead of `char`.

`unittest/compiler-fixtures/foreign-qualifier*` pins the behavior against a
vendored header, `foreign-qualifier-upstream.h`, covering the call, the
global, the field, a callback typedef with a `const char *` result, two
foreign aliases, the checked symbol table, and the generated C. Three
companion fixtures pin the exact rejection for the result, global, and field.

## Two adjacent shapes, now checked

Both are pinned by `unittest/compiler-fixtures/qualifier-void-pointer` and
`foreign-alias-pointer-result`:

- A conversion to `void *` is checked. It was the one target whose base type
  differs from the source's by construction, so the same-canonical-type test
  could not see it, and it silently laundered `const`.
- `$x2c.foreign.alias` accepts a pointer-returning target. The validator
  required exactly one declarator modifier, and a function returning a pointer
  carries its pointer modifiers after the `fnmod`.

A header that spells its declarations with macros needs `--cpp-symbols`,
because x2c does not expand macros.

## Integration policy

Packages keep the upstream header and raw function name authoritative and
spell upstream qualifiers faithfully in client source. The compiler now
enforces that instead of asking clients to honor it by convention. Do not
introduce renamed pointer types, copied records, casts, or forwarding
functions to work around a qualifier; they create a second API and hide what
the type system now states.

## Recorded measurement

The tracked [delta inventory](foreign-qualifier-deltas.json) records the rows
measured during the 2026-07-31 campaign under the old behavior: 92
function-result and 49 direct-field deltas, plus eight BLIS global-object
deltas, with none in the measured OpenBLAS scope. Those rows have not been
re-measured, because each needs its pinned dependency fetched from the
network. They describe what the old semantic table lost; they are not a gate
and not a claim about current package coverage.

| Client | Result deltas | Field deltas | Global deltas |
|---|---:|---:|---:|
| PCRE2 | 2 | 6 | 0 |
| yyjson | 8 | 5 | 0 |
| termbox2 | 2 | 0 | 0 |
| raylib | 15 | 0 | 0 |
| libcurl | 8 | 22 | 0 |
| libuv | 7 | 7 | 0 |
| BLIS | 50 | 9 | 8 |
| OpenBLAS | 0 | 0 | 0 |

A client that crossed one of those rows and compiled before will now stop if
it assigned an imported `const` result, global, or field to a mutable
pointer. That is the intended change; repair it by spelling the qualifier.
