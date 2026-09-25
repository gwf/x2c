# Packages with compile-time parts

> Status: done - delivery 1 landed on `dev` 2026-09-24 as `b51c3642`;
> delivery 2 (extensions linked into the compiler) as `7a371fa6`.

## Result

- A package whose sources define `meta` functions has a compile-time part.
  Building or installing the package also builds its native meta module.
- `import "pkg"` loads that module, so the package's `meta` functions are
  callable from compile-time code with no `--native-module` option and no
  `native-modules` entry.
- A package without `meta` functions behaves as today: it is linked, not
  loaded.
- The compiler links the whole runtime, so a module may call any runtime
  function.
- A later delivery links extensions into the compiler itself, the only
  route on hosts without `dlopen`.

## Current behavior

Facts from source on `dev` at `8dd290af`:

- `import "name"` resolves through `Compiler.collect_package`
  (`src/collect.x:740`), merges the package's prefixed declarations, and
  `Build._link_packages` (`src/build.x:381`) links `builds/lib<name>.a`
  plus the package's `.native.rsp`. The package's Makefile decides static
  or dynamic linking of its native dependency through `PACKAGE_LINK`.
- A package's bodyless `meta` prototype already crosses the import as a
  `native-meta` row (`src/macros.x:1643`). It binds only if the compiler
  links the function or a selected module defines it.
- Modules load only from `--native-module` or a target's `native-modules`,
  once per command in `Frontend.load_support` (`src/frontend.x:130`),
  before any unit. `Compiler.add_native_module` and the selection can be
  extended at any time; `_bind_native_meta` reads the selection when it
  binds (`src/macros.x:1797`).
- No package ships a module. cstar's compile-time part is Lisp in a
  `.xmacro` imported by relative path.
- The compiler links only runtime objects that reserve no class row
  (`etc/runtime-objects.sh`, `etc/runtime-objects.txt` in the APE payload).
  Nine objects are left out, among them `regex`, `thread`, `typed-map` and
  `autodiff`.

## Design

### A package's compile-time part

A package has a compile-time part when its sources define a function
declared `meta`. No manifest field is added: the `meta` declarations are
the declaration, as they already are for a `meta-module` target
(`_x2c.native-meta.declared`).

`packages/package.mk` and the source build in `src/install.x` build the
module beside the archive, as `builds/<name>.module`, from the package's
entry unit through the existing `Build.module_entry`. A package whose
sources declare no `meta` function builds no module, which the module
build already reports as an error, so the package build checks for the
declarations first.

### Loading on import

The parent process loads package modules once, before it forks
translation workers, so each worker inherits them. It finds the packages a
build imports from two sources: a token scan of each unit's top-level
`import "name"` statements, and the depfiles of the previous build, which
also name packages imported through included headers. Loading goes through
the same `_load_native_module` the command line uses: the stamp check,
`dlopen`, and `Compiler.add_native_module`.

`Compiler.collect_package` then selects the package's module for the unit,
on both the cold walk and the `.xi` replay path, after the command-line
modules, so an explicit `--native-module` still wins. If the parent missed
a package (a first build that reaches it only through a header), the
worker loads the module itself; the result is the same, only slower, and
the next build's depfiles let the parent preload it.

A stale module (its stamp names another compiler) is an error at the
import that tells the user to rebuild the package, exactly as a missing
archive is today ("package is not built"). The import never builds.

Caching: the module path goes into the unit's depfile, so its bytes enter
the translation state and a rebuilt module retranslates its consumers.
Header caches keyed on the package record it the same way.

The REPL loads a package's module when an `import` is submitted, through
the same hook.

### Whole runtime in the compiler

With class rows spent only on first box, linking a runtime object costs
nothing at startup. The compiler links `libx2c.a` whole (`-force_load` on
macOS, `--whole-archive` on Linux). `etc/runtime-objects.sh`, its `nm`
pass, and `etc/runtime-objects.txt` are deleted; `x2c bootstrap` links the
whole archive the same way. Measure compiler size, `--version` and a
one-line `translate` against the current link, as track G did.

### Extensions linked into the compiler (second delivery)

A static extension registers its targets from a file constructor under
its own key instead of defining `x2c_module_targets`, so several can link
into one compiler, and `select_native_modules` includes every registered
extension after `<compiler>`. `x2c bootstrap` takes a list of packages to
link in and generates their registration unit. No stamp is needed. This is
the only route for the APE seed, MSYS2 and Windows, where `dlopen` is
refused (`src/frontend.x:110`).

## Decisions taken

- The parent loads modules before forking workers (Gary, 2026-09-24).
- The import loads and never builds. Building inside a forked worker would
  race its siblings, and a package's archive already follows the same
  rule.
- The compile-time role is inferred from `meta` declarations rather than a
  manifest field, because those declarations already select the module's
  targets.
- Static or dynamic linking of a package's native dependency stays the
  package author's `PACKAGE_LINK` choice; x2c still builds no shared
  library targets. Nothing in this step needs that to change.

## Compatibility

- `--native-module` and `native-modules` keep working and are selected
  first.
- Book: `docs/src/guide/packages.md` (compile-time parts, `builds/` layout,
  rebuild after a compiler change), `docs/src/guide/meta-functions.md`
  native modules, and `reference/language.md` packages and import.
- Packages with bundles: a bundle carries its module, stamped for the
  compiler that built the bundle; a different compiler gets the stale
  error. Bundle builds in the release workflow add the module.
- Not supported on the APE seed, MSYS2 and Windows until the second
  delivery; there the import reports that native modules are not
  supported, as the option does today, only when the package has a module.

## Implementation

Delivery 1:

1. Whole-runtime link in `builds/stage.mk`, `bootstrap/src/Makefile` via
   its generator, and `src/bootstrap.x`; delete `etc/runtime-objects.*`.
   Measure and record.
2. `packages/package.mk` and `src/install.x` build `builds/<name>.module`
   when the package declares `meta` functions.
3. Parent preload before forking (import scan plus previous depfiles);
   `Compiler.collect_package` (cold and replay) selects the module and
   loads it only when the parent missed it; depfile entry; REPL import
   hook.
4. A test package under `unittest/` with one `meta` function and one
   record class: a consumer calls it at compile time through `import`
   alone; a rebuilt module retranslates the consumer; a stale stamp
   reports the rebuild error; `--native-module` still takes precedence.
   Extend `unittest/probes/run-native-modules.sh`.
5. Book pages above.
6. Review the completed authored diff and fix what it finds, then
   `tools/gate-state.py ensure agent-pr-check`.

## Delivery 1 result

- The compiler, the bootstrap compiler, the compiler `x2c bootstrap`
  installs, and the external commands link the whole runtime archive
  (`-Wl,-force_load` on macOS, `--whole-archive` with `--export-dynamic`
  on Linux). `etc/runtime-objects.sh` and the payload's
  `etc/runtime-objects.txt` are gone. The commands link it whole too,
  because the REPL loads modules into its own process.
- The loader moved from `src/frontend.x` to `src/macros.x`, beside the
  module registry: `Compiler.load_native_module` for options,
  `Compiler.preload_native_module` for the parent, and
  `Compiler.select_package_module`, which `Compiler.collect_package` calls
  on both its cold and replay paths. `build_module_stamp` moved to
  `src/utils.x` so the loader can reach it.
- The package build decides whether a package has a compile-time part
  from the interfaces translation wrote: a `native-meta "<name>__` row
  names one of the package's own prototypes. `packages/package.mk` and
  `x2c install` build `builds/<name>.module` only then, and
  `packages/tools/bundle` copies it.
- A module build from a package's own sources links no archive of that
  package: `Build._link_packages` now skips a package when any request
  input is one of its sources, not only the unit being linked.
- A package's module joins the process's selection after the request's
  modules and stays selected for later units in the same process. Its
  targets are the package's prefixed names, which only that package's
  prototypes declare.
- Not covered by a test: the REPL import. REPL imports resolve only
  `<home>/packages`, and the REPL has no `--package-dir`, so the probe
  cannot place a package there. The import runs the same
  `Compiler.collect_package`.

Rows after startup (lldb, `row_count` at `exit`): `--version` 1 and a
one-line `translate` 2, the same for the current `dev` compiler and the
whole-runtime compiler, so linking the whole runtime spends no row.

Measured on macOS arm64 (optimize build), 60 interleaved runs each, both
compilers copied outside `builds/` so neither replays the prelude
interface. The host load average was about 60 during the runs, so the
times carry more noise than track G's table.

| Compiler | Size | `--version` min | One-line `translate` min |
|---|---|---|---|
| `dev` at 7fd8c5dd (selected objects) | 2,496,768 B | 6.58 ms | 343.8 ms |
| Whole runtime | 2,678,816 B | 6.66 ms | 353.0 ms |

Delivery 2: static extensions, with `x2c bootstrap` building a compiler
that links a named package's compile-time part, and a probe that calls it
without `dlopen`.

## Delivery 2 result

- `--extension <package-dir>` repeats on `x2c build` and `x2c bootstrap`;
  bootstrap passes it to its compiler request. The option is on `build`
  too because the APE is the only way to run `bootstrap`, so a checkout
  on macOS or Linux can build and test a linked compiler only through
  `build`.
- `CliRequest.prepare` adds the package's `src/*.x` and `src/*.c` to the
  inputs and its parent directory to the package roots, so the sources
  translate in package mode. `Build.extension_entries` writes one
  registration unit per package through the entry writer
  `Build.module_entry` now shares: a file constructor calls
  `x2c_register_extension("<name>", targets)`. No stamp, no shared symbol.
- `src/macros.x` keeps the registrations in a plain C list, because the
  constructors run before the runtime starts. `select_native_modules`
  adds each one as the native module `<name>` after the request's
  modules, so `--native-module` still comes first.
  `Compiler.links_extension` makes `select_package_module` and the
  parent's preload skip a linked package, so its import loads no module.
- A package with a native dependency cannot be linked this way: its
  dependency's flags are not passed.
- `unittest/probes/run-native-modules.sh` builds a compiler from `src/*.x`
  with `tally` linked in, then translates the consumer with a stale
  `tally.module` present (the stock compiler rejects it) and with none.
  The compiler build adds about 20 s to the optional probe.

## Design review

- Reuse: the module build, stamp check, loader, selection and binding are
  track G's, unchanged. The import hook calls the existing loader.
- Deleted: the runtime-object selection script, its payload file and its
  per-link `nm` pass.
- No new validator: the stamp check and "not built" error already exist.
- Risk: the parent's scan can miss a package imported only through a
  header on a first build. The worker fallback keeps that correct; the
  test package covers it.
