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

Compile-time code follows C semantics, so a pointer to an expired local is
undefined, and nothing checks it. The goal is for compile-time code to
consume the compiler's shared lifetime analysis rather than add its own. The
lifetime-certified tranche of the
[internal adoption campaign](internal-adoption-campaign.md) depends on it.

### G. Native extensions (last stage)

Build a project's native code with generated typed adapters into a loadable
module, then load it for translation, build, or REPL use through the same
binding path as the compiler's linked functions.

Gary decided the four open questions on 2026-09-22, and the first delivery
implements them; the book documents it under
[native modules](../docs/src/guide/meta-functions.md#native-modules).

- **Spelling.** `x2c build --kind meta-module` and `kind = "meta-module"`
  build a module; `--native-module <file>` on `translate`, `build`, `run` and
  `repl`, or a target's `native-modules` list of module targets, loads one.
  Module targets build before the targets that load them.
- **Shared runtime.** A module links without `libx2c.a` (`-bundle -undefined
  dynamic_lookup` on macOS, `-fPIC -shared` elsewhere) and binds to the
  loading compiler's runtime. The compiler links with `-rdynamic` on Linux
  (`builds/stage.mk`, `bootstrap/src/Makefile`, and the `x2c bootstrap`
  compiler request). The build writes a generated entry unit that includes
  the module's x2c sources and defines `x2c_module_targets`, the
  name-to-`Func` Map that `lisp.native.targets` generates from the
  prototypes those sources declare (`_x2c.native-meta.declared`), and
  `x2c_module_stamp`, the content hash of the building compiler. The loader
  rejects any other hash.
- **Lifetime and trust.** `Frontend.load_support` checks the stamp in the
  module file's bytes before `dlopen`, so a stale module's code never runs,
  then loads each requested module once per process and never closes it.
  Each module's name-to-`Func` Map is kept by path in a process-lifetime
  Scope, and each request selects the modules it names, in order.
  `_bind_native_meta` falls back to the selected modules when the compiler
  links no function of the name; the first selected module that defines a
  name supplies it, and the existing signature check validates each
  binding. A module function that a compiler-linked name shadows, and a name
  two selected modules define, are reported as warnings. Nothing is
  discovered through includes, interfaces or package roots.
- **Entry.** The entry includes each module source by its absolute path,
  found through the root include directory, so same-named sources stay
  distinct and generated headers stay in the build directory. A module
  whose sources declare no `meta` prototype fails to build. On Linux the
  module links with `-Wl,-Bsymbolic-functions`, so its own functions are not
  interposed by same-named compiler exports.
- **Platforms.** macOS, Linux and WSL. The APE seed, MSYS2 and native Windows
  compile the loader but report that native modules are not supported.

Consumer translations fingerprint each loaded module's contents. A module
link is cached like a static archive, because macOS signs each link with
its pid-suffixed staging name, so an unconditional relink would change the
module's bytes and retranslate every consumer. The REPL accepts a bodyless
`meta` prototype, so a module function is callable there too.
`unittest/probes/run-native-modules.sh` covers a module built and called
from a meta body, a direct build, a manifest target and the REPL; rejection
of a stamp mismatch and a signature mismatch; no binding without the
option; and reuse of an unchanged module and its consumer.

Measured on macOS arm64 (debug build): the compiler grew from 2,404,880 to
2,423,184 bytes (+0.8%, the loader, entry generation and REPL change), and
startup is unchanged within noise (`--version` 3.84 ms vs 3.74 ms minimum,
a one-line `translate` 37.5 ms vs 36.4 ms minimum, 60 interleaved runs).
`-rdynamic` does not apply there. On Linux it adds the roughly 1,500
exported names to the dynamic symbol table, an estimated 70 KB; it was not
measured on Linux.

Remaining: the compiler links only the runtime members it uses, so a
module that calls another runtime function fails to load and names the
missing symbol (467 runtime symbols today, such as autodiff and `Args`).
Linking the whole runtime into the compiler would remove that limit for
about 200 KB (+8.4%) on macOS; that is a separate decision.

## Unblocked elsewhere

The generalized-meta tranche of the
[internal adoption campaign](internal-adoption-campaign.md), starting with
Autodiff, was waiting on this work and can start now.
