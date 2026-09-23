# Meta follow-ups

> Status: active
> Written 2026-09-22 after [meta recovery](archive/meta-recovery.md) landed
> on `dev` as `db86d4b7`. Tracks A-D are independent implementation work and
> can run in parallel; E-G need design decisions with Gary first. Each track
> is a separate session and worktree based on `dev`.

## Implementation tracks

### A. Readable scalar ledger and layouts

Gary's review of `db86d4b7`:

- `lib/native-scalar-types.xmacro` builds about 130 lines of x2c syntax by
  hand in Lisp. Replace that with an x2c-bodied template, as in
  `$var.tag.unbox` (`lib/var-tags.xmacro`), and turn the chain of
  `List.equal` tests in `native_scalar_access` into a lookup built once from
  the rows. First check whether the row list can drive the template
  directly; if not, list the 14 invocations as `lib/common.x` does.
- Layouts have the fixed shape `(KIND TYPE SIZE ALIGN ...)`. Replace
  one-at-a-time indexing (`layout[2]`, `layout[4]`, `row[3]`) with
  destructuring and `match` in `src/compiler.x` `_meta_type_layout`,
  `src/comptime.x` (`_lower_field_offset`, `_lower_pointer_tag`,
  `_lower_new_object`), and `lib/lisp.x` (`lisp_peek`, `lisp_poke`).
- Split `_meta_type_layout` into one helper per kind (var, scalar, pointer,
  record) and a short dispatcher.

No behavior change; the fixtures and unit suites are the check.

### B. Numeric Func argument cost

`x2c_func_value_argument` (`lib/func.x`) wraps every numeric conversion in a
five-clause `try`/`catch` and prepares those catch plans on every call. It
made compile-time field access 7x slower until the byte operations took
their offsets as `Var`. Every other numeric native call from compile-time
code still pays it. Make the conversion prepare its catch plans once, or
avoid the catch on the common success path; then consider returning the byte
operations in `lib/lisp.x` to `long` offsets. Measure with a
200,000-iteration `$` loop before and after.

### C. Smaller defects from the final review

Each should decline with a plain reason or work as C does:

- `p[0]` on a real pointer lowers to `Array_getindex` and fails at evaluation.
- `NULL` in a meta body reports `file-scope state not declared meta`.
- `foreach (int x, ...)` with a typed non-Var output is refused with
  `unsupported expression`.
- `bool` and enum struct fields have no layout; `bool *` addresses fail.
- `lib/clibc.x` declares `strncmp` with `unsigned long`, which is not
  `size_t` on the LLP64 MSYS2 route. A signature change needs two bootstrap
  rounds, because the running compiler's target must match.
- The Symbol pairing is a named special case in `_meta_type_layout`,
  `lisp_peek` and `lisp_poke`; a generic retag by the layout's TAG would
  remove it.

Status: done on `gwf/meta-c-small-defects`. Pointer indexing, `NULL`,
`true`, `false`, typed `foreach` outputs, `bool` and int-range enum layouts,
C `bool` conversion and `strncmp`'s `size_t` now behave as C does, and
`lisp_peek` and `lisp_poke` retag by the layout's TAG. The layout accepts a
TAG that differs from its bytes' row only when the tag is fixed for the type;
a declared converter's tag may box something other than the bits. Remaining:
the compile-time view of `size_t` is `unsigned long` on every host, which is
32 bits too wide on LLP64, and enum constants still have no compile-time
value.

### D. `--system-headers` cost and packing

`--system-headers` reads every expanded system header, about 3x slower than
`--cpp-symbols` on a small file, and masks `_Atomic(T)` with a `-D`. Structs
under `#pragma pack` are not detected and get natural alignment. Consider
restricting expansion to headers the source includes directly, and detecting
packing so such structs have no compile-time layout.

## Design tracks (decide with Gary first)

### E. Meta-capable protocols

Make protocol conformances the source of compile-time bindings, replacing
hand-listed targets such as the Iter `_into` rows in `lib/lisp.x` and the
`C.iterator` table in `etc/comptime.xlisp`. See
[meta authoring and coverage](meta-authoring-and-coverage.md#meta-capable-protocol-opportunity).

### F. Lifetime certification

Compile-time code follows C semantics, so a pointer to an expired local is
undefined, and nothing checks it. The goal is for compile-time code to
consume the compiler's shared lifetime analysis rather than add its own. The
lifetime-certified tranche of the
[internal adoption campaign](internal-adoption-campaign.md) depends on it.

### G. Native extensions (last stage)

Build a project's native code with generated typed adapters into a loadable
module, then load it for translation, build, or REPL use through the same
binding path as the compiler's linked functions. The command spelling,
registration compatibility, shared runtime state and module lifetime are
open.

## Unblocked elsewhere

The generalized-meta tranche of the
[internal adoption campaign](internal-adoption-campaign.md), starting with
Autodiff, was waiting on this work and can start now.
