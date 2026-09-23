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
- **Shared runtime.** A module links without `libx2c.a` and binds to the
  loading compiler's runtime: `-bundle -bundle_loader <compiler>` on macOS,
  so a runtime function the compiler lacks fails the module's link and names
  the symbol, and `-fPIC -shared -Wl,-Bsymbolic-functions` on Linux, where
  such a function fails at load instead. The compiler links with
  `-rdynamic` on Linux (`builds/stage.mk`, `bootstrap/src/Makefile`, and the
  `x2c bootstrap` compiler request). The build writes a generated entry unit
  that includes the module's x2c sources and defines `x2c_module_targets`,
  the name-to-`Func` Map that `lisp.native.targets` generates from the
  prototypes those sources declare (`_x2c.native-meta.declared`), and
  `x2c_module_stamp`, the content hash of the building compiler. The loader
  rejects any other hash.
- **Runtime coverage.** Gary chose on 2026-09-22 to link whole every runtime
  object that reserves no Var class row. `etc/runtime-objects.sh` derives the
  set from the objects' symbol tables at each compiler link: an object the
  compiler's own code does not reach is left out when it calls a
  row-reserving registration function, or needs a function only a left-out
  object defines. Today it adds `args`, `diff` and `lib` (`DisjointSet`),
  and leaves out `autodiff`, `regex`, `typed-array`, `typed-map`, `mutex`,
  `thread`, `scripting`, `list-selectors` and `match-recursive`. It runs one
  `nm` over all objects, about 50 ms per compiler link, and a failing `nm`
  fails the link. The Makefile links run it on macOS and Linux; the APE
  seed and MSYS2 link the runtime as before. The APE payload records the
  selection as `etc/runtime-objects.txt`, by object stem, and a compiler
  that `x2c bootstrap` installs links those runtime objects too, without
  running `nm` on the installing machine.
- **Lifetime and trust.** `Frontend.load_support` checks the stamp in the
  module file's bytes before `dlopen`, so a stale module's code never runs,
  then loads each requested module once per process and never closes it.
  Each module's name-to-`Func` Map is kept by path in a process-lifetime
  Scope, and each request selects the modules it names, in order.
  `_bind_native_meta` falls back to the selected modules when the compiler
  links no function of the name; the first selected module that defines a
  name supplies it, and the existing signature check validates each
  binding. The prototype reports a warning when a compiler-linked function
  hides a module's, or when more than one selected module defines the
  name. Nothing is discovered through includes, interfaces or package
  roots.
- **Entry.** The entry includes each module source by its absolute path,
  through an `x2c-root` link to `/` beside the entry rather than an include
  directory, so same-named sources stay
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
`unittest/probes/run-native-modules.sh`, which the optional
`make check-native-modules` runs outside every gate, covers a module built
and called from a meta body, a manifest target and the REPL; rejection of a
stale or twice-stamped module before its code runs, of a non-module file,
of a signature mismatch and of a module with no `meta` prototype;
same-named and `..`-spelled sources; the duplicate-name warning; a runtime
function from a linked object, and on macOS the build failure for one left
out; no binding without the option or in a target that does not name the
module; and reuse of an unchanged module and its consumer, with
retranslation after a module edit.

Measured on macOS arm64 (optimize build), 60 interleaved runs each:

| Compiler | Size | `--version` min | One-line `translate` min | Var tag rows |
|---|---|---|---|---|
| Before track G | 2,404,880 B | 3.84 ms | 37.5 ms | 5 |
| Loader, current link | 2,424,432 B | 3.22 ms | 35.16 ms | 5 |
| Selected objects linked whole | 2,442,688 B | 3.21 ms | 35.16 ms | 5 |
| Whole runtime (measured, rejected) | 2,625,512 B | 3.12 ms | 34.50 ms | 18 |

The first row was measured in an earlier session, so compare its times
only with each other; the last three rows are one interleaved series.
Startup does not change beyond noise. Linking the whole runtime would spend
13 more of the 32 rows at startup, which is why it was not chosen. On Linux
`-rdynamic` adds the roughly 1,500 exported names to the dynamic symbol
table, an estimated 70 KB; nothing was measured on Linux.

Follow-ups:

- **Lazy class registration.** Registering a class's Var row when a value of
  it is first boxed, rather than in its file initializer, would make linking
  the whole runtime free of rows, so a module could call all of it.
- **Extensions linked into the compiler.** A later route may compile a
  project's extension into the compiler at compile and link time instead of
  loading a module. Registration already allows it: targets are Maps keyed
  by their source, `Compiler.add_native_module` records one, and
  `_bind_native_meta` binds only through the selected Maps, so a statically
  linked extension could register its Map at startup the same way. Nothing
  in the fallback assumes `dlopen` supplied the Map.

## Unblocked elsewhere

The generalized-meta tranche of the
[internal adoption campaign](internal-adoption-campaign.md), starting with
Autodiff, was waiting on this work and can start now.
