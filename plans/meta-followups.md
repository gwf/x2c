# Meta follow-ups

> Status: active
> Written 2026-09-22 after [meta recovery](archive/meta-recovery.md) landed
> on `dev` as `db86d4b7`. Tracks A-D are independent implementation work and
> can run in parallel; E and G need design decisions with Gary first, and F
> has an approved design. Each track is a separate session and worktree
> based on `dev`.

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

Outcome, 2026-09-22:

- Cost. `builds/0/x2c translate`, best of 3 over 5 runs on an M4 Max,
  default / `--cpp-symbols` / `--system-headers`: a trivial `main`
  0.03 / 0.08 / 0.05 s; `meta-system-header-record.x` 0.06 / 0.15 / 0.11 s;
  a file including `stdio.h`, `stdlib.h`, `string.h`, `time.h` and
  `pthread.h` 0.03 / 0.08 / 0.08 s. `--system-headers` is not slower than
  `--cpp-symbols`, so the 3x premise does not reproduce. Expansion stays
  unrestricted: restricting it to direct includes would lose
  `struct timespec`, which macOS declares in `sys/_types/_timespec.h`
  through `_time.h` and glibc in `bits/types/struct_timespec.h`.
- Packing. Tokenizing records where `#pragma pack` turns packing on or off,
  outside unreachable conditional arms. It follows the directives along one
  reading per arm position: reading `k` takes each group's reachable arm
  `k`, or its last reachable arm when the group has fewer. No reading skips
  a group without an `#else`, so include guards are always read. Packing is
  on where any reading has it on, which handles alternative pushes in
  `#if`/`#elif`/`#else`, a push and pop under the same guard, and packing
  inside an include guard. Tokenizing also marks each `packed`,
  `aligned`, `mode` or `vector_size` attribute. Collection reads a header's
  attributes directly; a preprocessing mode turns each attribute into a
  marked string rather than erasing it, and tokenizing erases the string. A
  struct defined under packing or around such a mark has no compile-time
  layout, and meta code that uses it declines with `a compile-time struct
  with no host layout`.
- Remaining:
  - Default collection reads each file separately, so it misses packing that
    one header starts and another ends (Windows `pshpack1.h` and
    `poppack.h`). `--cpp-symbols` and `--system-headers` read the
    preprocessed unit and decline such a struct. Closing the gap needs each
    collected header's net packing effect carried into its includer's scan,
    including through header caches and `.xi` interfaces.
  - In default collection, a push and a pop under unrelated conditions,
    such as a push under `A` and a pop under `B`, balance in every reading,
    so a later struct gets natural layout where C packs it when only `A`
    holds. A pop in a group without `#else` counts as taken, with the same
    effect when C skips it. Guarded pushes whose conditions C rejects can
    decline a struct that C lays out naturally. `--cpp-symbols` and
    `--system-headers` see the preprocessor's own choice of arms.
  - A layout attribute on a typedef, such as
    `typedef long aligned_long __attribute__((aligned(16)))`, and a field
    declared `_Alignas`, leave a struct its natural layout; neither mark
    lies in the struct's own definition.
  - `-D_Atomic(T)=T` stays: `_Atomic` scalars have the size and alignment of
    their plain type on the supported hosts, so a struct with such a field
    keeps a correct layout. An `_Atomic` struct type could differ and is not
    handled.

## Design tracks (decide with Gary first)

### E. Meta-capable protocols

Make protocol conformances the source of compile-time bindings, replacing
hand-listed targets such as the Iter `_into` rows in `lib/lisp.x` and the
`C.iterator` table in `etc/comptime.xlisp`. See
[meta authoring and coverage](meta-authoring-and-coverage.md#meta-capable-protocol-opportunity).

### F. Lifetime certification

Compile-time code followed C semantics, so a pointer to an expired local was
undefined, and nothing checked it. A compile-time call frees its locals when
it returns (`lib/lisp.x` `_call_lambda_slots`), so `return &local` or
`&local` stored into a `meta static` read freed memory. The goal is for
compile-time code to consume the compiler's shared lifetime analysis rather
than add its own. The lifetime-certified tranche of the
[internal adoption campaign](internal-adoption-campaign.md) depends on it.

Gary approved the design on 2026-09-22; the first delivery implements it.

- **Function-storage region.** `src/regions.x` treats a function's own
  locals, parameters, and compound literals as one more region, `frame`. An
  address taken with `&` belongs to the storage it names; an address reached
  through a pointer belongs to what that pointer holds, so `&param->field`
  counts as the parameter in the summary and a callee that returns it hands
  the caller's borrow back. Returning a frame address, or storing it into a
  static, a static local, a parameter's object, an unknown pointer, or fresh
  storage that outlives the call, is an escape. Regions the function opens
  end first, so storing into them or into another local is not.
- **Enforcement in meta bodies.** `Compiler.install_meta_function` runs the
  pass on each definition through `Compiler.check_meta_regions`, seeded with
  `meta_regions`, the summaries of the `meta` functions installed before
  it. A finding is an error at the escaping statement. The process lowering
  cache stores the summary with the lowered forms, so a reused lowering
  carries its check result and seeds later callers.
- **Ordinary code** gets the same findings as warnings. Always on; the
  per-unit cost is within noise.
- Each arm of `?:` flows separately, and a local C array at a flow site is
  a frame borrow of its first element.
- Refinements that keep the rule from reporting safe code: a reference
  capture (`using &name`) moves the local into a cell, so a closure holds
  the cell rather than the frame; a store into a place that an earlier
  `defer` in the same block writes back is restored, as `$let` already was;
  a statement expression's declarations are locals rather than stores
  through an unknown pointer; and an argument a canonical parameter converts
  by copying, such as an `Array` given to `cons`'s `List` parameter, is not
  stored. The last one removed the `src/statements.x` false positive, and
  `lib/lisp.x` `_call_lambda_slots` now places its restoring `defer` before
  the store it restores.

Result against `dev` `440c0461`: a full build prints no `region:` warning
and no other translation warning, and there is no new finding in
`unittest/`, `examples/`, or `tools/`. Fixtures: `region-local-escapes`
(ordinary warnings), additions to `region-safe`, and
`comptime-declines-local-address-{return,static,callee,conditional,array}`.
Self-translation of `src/` measured 3.97 s user before and 3.99 s after
(medians of ten alternating runs before the review fixes; noise is about
1.4%).

Not covered, as the book's meta and region chapters list: an address kept
in a field of a local struct that is returned by value or assigned to a
`meta static` struct, pointer arithmetic, and native calls that retain an
argument. Phase 8 remains: opt-in whole-project certification that treats
unknown calls as unproved, the effect inventory, and File and Job
finalizers.

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
