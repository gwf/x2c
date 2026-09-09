> Status: reference
> T3 source-package verification completed on 2026-09-09. The distributed
> support builds packages without their producer checkout. This does not
> establish a relocatable binary package or test the optional APE installer.

# Source-package production and isolated use

The shipped production and consumption recipe is in
[the package guide](../docs/src/guide/packages.md). It uses ordinary `tar`,
keeps package sources and support together, and delegates native compilation
and archiving to the existing driver. It adds no packaging service or command.

## Compiler installation boundary

`make install` aliases `build-install`: it builds the compiler and copies it
into the compiler checkout's `bin/`. There is no `PREFIX` or `DESTDIR` option
on this owner. Normal development retains the full compiler support tree.
The only prefix installer is the optional APE command
`x2c.com bootstrap --prefix`, whose owner in `src/bootstrap.x` reads the
embedded `/zip/x2c` source payload. A normal native compiler has no such
payload. No APE executable was available for this verification, and building
that optional release is outside T3's source-package scope.

The isolated proof therefore copied an already built native compiler and its
support files into a temporary fixture. It did not claim to exercise the
installer. Both the original package/compiler worktree and the main checkout
were inaccessible to every process performing the package build and use.

## Reproduce the isolation proof on macOS

From a built checkout, the commands below prepare the same kind of compiler
fixture and use the package guide's source bundle. They do not change host
settings or install anything in a user or system prefix. The empty `src/`
directory is the fixture's compiler-root marker; the actual support files
come from the matching native build. This is a verification fixture, not a
new compiler distribution contract.

```sh
repo=$(pwd -P)
main=$(git rev-parse --path-format=absolute --git-common-dir)
main=${main%/.git}
work=$(mktemp -d /tmp/x2c-package-proof.XXXXXX)
mkdir -p "$work/compiler/bin" "$work/compiler/src" "$work/unpacked"
cp builds/0/x2c "$work/compiler/bin/x2c"
cp -R lib "$work/compiler/lib"
cp -R -L include "$work/compiler/include"
cp -R etc "$work/compiler/etc"
cp builds/0/libx2c.a "$work/compiler/lib/libx2c.a"
package=yyjson
tar --exclude="packages/$package/deps" \
  --exclude="packages/$package/builds" \
  -czf "$work/$package-source.tar.gz" \
  "packages/$package" packages/package.mk packages/dependency.mk \
  packages/tools/deps.py
tar -xzf "$work/$package-source.tar.gz" -C "$work/unpacked"
python3 - "$repo" "$main" "$work/no-checkout.sb" <<'PY'
import json
import pathlib
import sys
paths = ' '.join('(subpath ' + json.dumps(p) + ')' for p in sys.argv[1:3])
pathlib.Path(sys.argv[3]).write_text(
    '(version 1)\n(allow default)\n(deny file-read* ' + paths + ')\n')
PY
cd "$work/unpacked"
export X2C_DEPS_DIR="$work/cache"
# These controls must fail with Operation not permitted.
/usr/bin/sandbox-exec -f "$work/no-checkout.sb" /bin/cat "$repo/AGENTS.md"
/usr/bin/sandbox-exec -f "$work/no-checkout.sb" /bin/cat "$main/AGENTS.md"
/usr/bin/sandbox-exec -f "$work/no-checkout.sb" \
  make -C packages/yyjson prepare build short-example \
  X2C="$work/compiler/bin/x2c"
cd packages/yyjson
/usr/bin/sandbox-exec -f "$work/no-checkout.sb" builds/service-health
```

Use the project's supported GNU Make on `PATH`. The sandbox controls are
expected failures; run the example commands interactively rather than under
`set -e`. `sandbox-exec` is used only for this macOS proof and is not a package
build dependency. Keep the temporary directory to inspect generated files.

## Recorded results

`debug/t3-source-bundle-isolated.log` records both denied-read controls and
successful package builds under that same restriction. It covers a pure
multi-unit x2c package, a mixed C/x2c package with colliding source basenames,
and yyjson with its checksum-verified native dependency. The two synthetic
consumers print `42`; yyjson's service-health example runs successfully.
The tar archive was unpacked after deleting its synthetic producer directory;
its package `Makefile` and all three shared support files were present, and
`deps`/`builds` were absent. Current worktree and main-checkout reads were denied
throughout preparation, translation, native compilation, linking, and use.

Earlier focused evidence remains applicable: `debug/t3-deps-after.log` records
11 dependency tests passing outside Git, `debug/t3-warm-package.log` records
warm archive/consumer retention, and `debug/t3-header-reuse.log` records native
header invalidation rebuilding the affected object and archive. These remain
optional focused proofs, not new publication gates.

## Plan review

The package guide reuses `tar`, existing compiler selection, shared Make
support, and the driver's native actions. The verification fixture adds no
shipped installer, cache, parser, validator, diagnostic, or recurring test
requirement. The sandbox only demonstrates the promised absence of checkout
reads; it is not product machinery. Binary installation and native dependency
bundling remain separate distribution decisions.
