# Foreign C qualifiers

x2c keeps the `const`, `volatile`, and `restrict` qualifiers that a C header
declares on a function result, a global object, or a record field. It
rejects a conversion that would silently drop one. Given

```c
const char *GetMonitorName(int monitor);
```

the call `GetMonitorName(0)` has type `(* const char)`, and assigning it to
a `char *` stops translation with
`cannot convert (* const char) to (* char)`. The note that follows names the
two repairs.

Keep the qualifier, as in `const char *name = GetMonitorName(0);`, or copy
the value when the program needs to own it, as in
`String name = GetMonitorName(0);`. Conversions to `void *` follow the same
rule, and qualified typedefs such as `typedef const char *(*fn)(int);` keep
their qualifiers.

A package author treats the upstream header as authoritative. Spell each
upstream qualifier exactly as the header does in client source. Do not add
renamed pointer types, copied records, casts, or forwarding functions to work
around a qualifier; they obscure the upstream API.

x2c checks the declarations it reads: those in headers found on an `-I` or
`--x-include-dir` path. A package's native headers usually reach only the C
compiler, through `--c-include-dir`. x2c does not check a call into such a
header; the C compiler does, and it warns when an initialization or
assignment discards a qualifier.

x2c reads C headers without expanding macros. A macro among a declaration's
specifiers is read through its definition when that definition is empty, a
storage class, an attribute, builtin type words, or a type-wrapping
function-like macro. A header whose declarations depend on other macro
expansion, such as a macro that supplies grammar, is not read correctly.
A package's `PROFILE.md` lists the upstream declarations whose qualifiers x2c
does not record.
