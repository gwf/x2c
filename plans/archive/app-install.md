# x2c application development installs

> Status: done 2026-09-15. Both phases merged to main in PR #42 (merge
> commit "merge x2c home and package installs"); release assets and the
> package index uploaded to v0.12.0; site deployed; live install.sh and
> `x2c install pcre2` verified from a machine with no checkout. Deviations
> from the design: the index is line-oriented text, not JSON; examples
> install to `<home>/examples/`; `install.sh` reads the current version
> from the site. Follow-ups: v0.12.0 tag predates the merge; torch and
> raylib have no bundles; linux-aarch64 has no release; binding numbers
> remain unique only per symbol table (reachability keyed by spelling).

## Context

`make install PREFIX=...` already produces a working native prefix
(`etc/x2c-payload.py`), and `--package-dir` already lets a program import a
built package. What is missing is the developer-facing system around those
pieces: a defined "x2c home" the compiler resolves the same way in a checkout
and an install, an application install that ships what an app needs and
nothing else, a way to see what the compiler resolved, an uninstall, a place
for installed modules that the compiler searches by default, and a command
that fetches, verifies, and installs a module into that place.

Three facts from current source shape the design:

- Root discovery (`src/utils.x:157-166`) requires `src/`, `include/`, and
  `lib/` under one directory, so an installed prefix today works only because
  the installer copies `src/` in. The installed-prefix branch of
  `_toolchain_layout` (`src/toolchain.x:102-105`) is effectively dead.
- Package lookup (`src/collect.x:590-602`) already accepts the bundle layout
  `<root>/<name>/src/<name>.x` + `builds/lib<name>.a` + `builds/<name>.native.rsp`
  that `packages/tools/bundle.py` produces, and the repository's own
  `packages/` directory has that layout too.
- The installer keeps an ownership manifest (`.x2c-install-manifest`) that
  nothing consumes for removal.

## Result

One layout, called the x2c home, with two provenances:

```
<home>/
  bin/x2c
  include/        lib/*.x + generated lib/*.h   (translate and C compile)
  lib/libx2c.a    lib/x2c/toolchain             (link, CC/AR defaults)
  etc/            symbols.xlisp, init.xlisp, compiler-sdk.xlisp, *.xmacro
  packages/       one directory per installed module, bundle layout
  examples/       (app install only) runnable examples; mirrors the checkout
  licenses/
  .x2c-install-manifest
  src/            checkout only
```

A checkout is a home (it already has every top-level entry). The dev story is `git clone`, `make build-safe`, and either
`export PATH=<checkout>/bin:$PATH` (`make build-install` already places
`bin/x2c`) or `export X2C_HOME=<checkout>`.

Developer-visible surface after this work:

| Command | Meaning |
|---|---|
| `curl -fsSL https://x2c-lang.dev/install.sh \| sh` | fetch a release tarball into `~/.local/x2c` |
| `make install PREFIX=<dir>` | the same layout from a checkout, minus `src/` |
| `make uninstall PREFIX=<dir>` | remove owned files using the manifest |
| `x2c env` | print home, include dir, runtime archive, package dirs, cc, ar |
| `x2c install <spec>` | install a module into `<home>/packages/<name>` |
| `x2c remove <name>` / `x2c list` | remove / list installed modules |
| `X2C_HOME` | explicit home override; wins over discovery |

`<spec>` is one of: a local bundle directory or `.tar.gz`, a URL to a bundle
or source tarball with `--sha256 <hex>`, or a bare module name resolved
through an index file (`https://x2c-lang.dev/packages/index.json`, also
overridable with `--index <url-or-path>`). A bundle installs as is. A source
tarball of a pure-x2c package (a `src/<name>.x` tree with no
`dependency*.json`) is built in place by the compiler itself with the two
commands `packages/package.mk:85-94` already use: `translate --out-dir builds`
per unit, then `build --kind static-library`. Packages with native C
dependencies are only installable as bundles; the index carries per-platform
bundle entries built by CI.

## Settled choices

- **Home discovery.** Replace the `src/`+`include/`+`lib/` probe with: a
  directory containing `etc/symbols.xlisp` and `include/`. Order: `X2C_HOME`,
  then walk up from the executable, then from cwd. The existing stage
  branch of `_toolchain_layout` (`builds/<n>/x2c`) stays; the "repo" and
  "installed prefix" branches collapse into one `<home>/include` +
  `<home>/lib/libx2c.a` (bootstrap fallback retained for a checkout with no
  `builds/0`). `x2c_repo_cpp_include_dirs` includes `<home>/src` only when it
  exists.
- **Default package dirs.** After explicit `--package-dir` and manifest
  `package-dirs`, append `<home>/packages` when it exists. This gives the
  repository checkout its own `packages/` for free and keeps explicit dirs
  ahead in precedence. `x2c.toml` needs no new field.
- **App install drops `src/`.** `copy_support` keeps its `src` row only for
  the APE `support` payload (the APE bootstrap rebuilds the compiler). Add
  `packages/` (empty, with a `.keep`) and `examples/` (the checkout's
  `examples/` tree minus `build/`, `check.sh`, `packages/*/builds`), and
  nothing else. `etc/x2c.mk` is not installed; installed apps use
  `x2c build` / `x2c.toml`.
- **Uninstall** is `x2c-payload.py uninstall --prefix`: unlink every owned
  file, remove `<home>/packages` only if empty, then remove empty
  directories. Installed modules are not owned by the compiler manifest and
  survive a compiler upgrade; `x2c install` refuses a bundle whose
  `BUNDLE.json` `x2c_version` differs from `x2c --version` unless `--force`.
- **Module identity.** `<home>/packages/<name>/` with the bundle's
  `BUNDLE.json`, or a `SOURCE.json` written by `x2c install` for a source
  build (name, version, url, sha256, x2c version). `x2c remove` refuses a
  directory without either file (same rule `bundle.py` applies).
- **Fetching** runs `curl -fsSL -o` as a child process through the existing
  `process_run` in `src/utils.x`; sha256 verification also shells out
  (`shasum -a 256` / `sha256sum`, whichever is on PATH). No HTTP or hashing
  code enters the runtime. A missing `--sha256` for a URL spec is an error;
  index entries carry their digests.
- **Index format** is a line-oriented text file, `index.txt`, one row
  `name version kind platform url sha256` per entry, written by
  `tools/gen-package-index.py` from a directory of source packages and the
  bundle archives named on its command line. The runtime has no JSON reader,
  so the plan's JSON shape was dropped rather than adding a parser; the one
  `BUNDLE.json` field the compiler needs is found by a marker scan.
  Platform key is `sys.platform`-`machine` as `BUNDLE.json` records.
- **Release artifacts.** A `make dist PREFIX=/opt/x2c` target runs the
  existing installer with `DESTDIR` into `dist/` and tars
  `x2c-<version>-<platform>.tar.gz`. `release-validation.yml` gains an
  upload of that tarball and each `make -C packages/<p> bundle` output as
  workflow artifacts; publishing them as a GitHub release and refreshing the
  site index remain a manual `gh release` step (site deploys are manual
  today). `_print_version` (`src/cli.x:419`) stays the single version
  source; `tools/gen-package-index.py` reads it from `x2c --version`.

## Implementation

Phase 1 - home, env, app install, uninstall (compiler + installer + docs)

1. `src/utils.x`: `_is_repo_root` -> `_is_home` (probe `etc/symbols.xlisp`
   and `include/`); honor `X2C_HOME` first in `x2c_initialize_environment`;
   `_prepare_repo_defaults` adds `src` to cpp dirs only when present. Add
   `x2c_home_packages()` returning `<home>/packages` or NULL.
2. `src/toolchain.x`: collapse `_toolchain_layout` branches two and three;
   `_installed_tool` reads `<home>/lib/x2c/toolchain` via `x2c_get_root`
   instead of walking up from the executable.
3. `src/frontend.x:215`: append `x2c_home_packages()` to
   `compiler.package_dirs` after request dirs. `src/build.x:402` reads
   `state.request.package_dirs`; route both through one accessor so link
   and collect see the same list.
4. `src/cli.x`: add `env` (prints one `key = value` line per resolved
   path; `x2c env cc` prints one value) to the command table at
   `src/cli.x:64-71`; dispatch in `src/main.x`.
5. `etc/x2c-payload.py`: `install` skips `src/`, adds `packages/.keep` and
   `examples/`; new `uninstall` subcommand; `Makefile:503-510`
   gains `uninstall` and `dist`.
6. Probe: install into a scratch prefix, unset PATH to the checkout, build
   `<prefix>/examples/foreach.x` and one `x2c.toml` project, and an
   `import "greet"` program with `examples/packages/greet` copied under
   `<prefix>/packages`. Confirms no `src/` dependency and default package
   dir resolution.
7. Docs: `docs/src/guide/installation.md` (home, `X2C_HOME`, `x2c env`,
   uninstall, dev = checkout, and a "Developer workflow" section: the
   global prefix is installed only from a release, a checkout is its own
   home selected per shell with `PATH` or `X2C_HOME`, release candidates
   are validated in a scratch prefix), `docs/src/reference/cli.md` (`env`,
   default package dir), README install section.

Phase 2 - module install (compiler + tools + CI + docs)

1. `src/install.x` (new module, following `src/bootstrap.x` for staging and
   rename-into-place and `src/project.x` for manifest reading): `install`,
   `remove`, `list`; spec classification; fetch + verify via child
   processes; bundle extraction with `tar -xzf` into a sibling temp dir
   then rename; source build via the two existing commands; `SOURCE.json`.
2. `src/cli.x` / `src/main.x`: three commands and flags `--sha256`,
   `--index`, `--force`.
3. `tools/gen-package-index.py`, `make dist`, workflow artifact upload in
   `.github/workflows/release-validation.yml`, `site/` install section
   pointing at the index and tarballs (`site/src/pages/index.astro:164-205`
   currently hard-codes a v0.12.0 APE link).
4. `site/public/install.sh`: POSIX shell installer run as
   `curl -fsSL https://x2c-lang.dev/install.sh | sh`. Detects `uname -s`/
   `uname -m`, downloads the matching release tarball and its `.sha256`,
   verifies, unpacks into `$HOME/.local/x2c` (`X2C_PREFIX` overrides),
   accepts `--version` to pin, refuses to run without `cc` on PATH and
   prints the platform hint `configure:45-47` already prints, and ends by
   printing the `export PATH` line. Re-running it is the upgrade path.
   `tools/check-install-script.sh` runs it against a local `dist/` tarball
   in `release-validation.yml`. Homebrew/apt packaging and a self-update
   command are deliberately out of scope.
5. Probes: install `examples/packages/greet` from a local source tarball
   and from a `file://` index; install a `make -C packages/yyjson bundle`
   output as a local bundle; refuse a wrong sha256 and a mismatched
   `x2c_version`; `remove`; `list`.
6. Docs: `docs/src/guide/packages.md` "Installing modules" replacing the
   manual `tar -xzf` recipe at `packages.md:316-345`; CLI reference.

## Compatibility

- `--package-dir`, `x2c.toml`, bundle layout, `.native.rsp`, and `.link`
  files are unchanged; explicit dirs keep precedence over `<home>/packages`.
- A checkout still resolves as before; the only discovery change is that a
  directory without `src/` can now be a home, and `X2C_HOME` is new.
- Existing prefixes installed with `src/` keep working; the next
  `make install` removes `src/` through the manifest's obsolete-file rule.
- The APE `bootstrap` payload keeps `src/`.

## Validation

- Phase 1: `make x2c`, then the scratch-prefix probe above, plus
  `unittest/probes/run-cli-boundary.sh` (it links `builds/0/libx2c.a`
  directly and exercises the layout branches). Final tree:
  `tools/gate-state.py ensure agent-pr-check`.
- Phase 2: the four probes above, run from a scratch prefix with the
  checkout removed from PATH; a compiler fixture for each new CLI error
  (bad sha256, unknown spec, unowned remove target); same gate.

## Plan review

- Established facts: the package layout and `.native.rsp` contract are
  established by `bundle.py` and consumed unchanged by `collect.x` and
  `build.x`; the installer manifest already establishes ownership; sha256
  is verified once at fetch and not rechecked at build. `x2c install`
  checks `x2c_version` because a bundle carries no ABI promise across
  releases (documented in `packages.md`), and that check protects against
  linking an archive built by a different runtime.
- Deleted or reused: the dead installed-prefix branch and the
  `src/`-requiring root probe go; `_installed_tool`'s second path walk goes;
  the manual bundle extraction recipe in the docs goes. Reused: installer
  staging/ownership, `bundle.py` and `BUNDLE.json`, `process_run`, the two
  package build commands, `x2c.toml` parsing style. New lasting mechanisms:
  `src/install.x`, `x2c env`, `uninstall`, `gen-package-index.py`,
  `make dist`. Each exists because no current code fetches, verifies,
  places, or lists modules, prints resolved paths, or removes an install.
- Idiomatic x2c: the new module is a CLI command over child processes and
  file moves, like `src/bootstrap.x`; no in-process HTTP, hashing, or
  archive library.
- Validators and diagnostics: unknown spec form; URL without `--sha256`;
  digest mismatch (wrong bytes would be linked into user programs); bundle
  `x2c_version` mismatch (unsafe archive/runtime pairing, overridable);
  `remove` of an unowned directory (would delete user data). No other
  negative fixtures.

## Open for Gary

None blocking. Two defaults chosen here that could be changed later:
the index URL lives under the site, and source-package builds on install
are limited to pure-x2c packages.
