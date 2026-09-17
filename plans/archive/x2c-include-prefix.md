# The `x2c/` include prefix

> Status: done - 2026-09-16. First of four plans from the 2026-09-15
> capabilities and market spike; it landed before the others because every new
> runtime module is another chance to collide with a system header, and the
> planned `lib/time.x` would collide on every platform.
> Notes: the include directory the C compiler actually sees is owned by
> `src/toolchain.x:95,100,109`, not `src/utils.x`; `x2c run` fails until all
> three change. Thirteen places outside the six planned edits compile
> generated C with the old flag, including `unittest/compiler-fixtures/run.sh`,
> whose omission failed 285 of 667 fixtures. `include/.gitignore` keeps
> `*.[xh]` beside `x2c/` so a stale flat layout stays ignored after a pull.
> Bootstrap delta was four string literals in four files.

## The result

Runtime sources and generated headers live under `<home>/include/x2c/` instead
of `<home>/include/`. A C program that calls x2c code compiles with
`-I <prefix>/include` and writes `#include <x2c/x2c.h>`, and every system
header still resolves to the C library.

Before this change, `-I <prefix>/include` put x2c's `string.h` ahead of libc's,
so an ordinary `#include <string.h>` failed with `unknown type name 'Symbol'`.
The correct flag was `-iquote`, which the driver already passed and nothing
told a user about.

## Why a prefix and not renames

The collisions were not confined to one obvious name:

| Header | Collides with |
| --- | --- |
| `string.h` | C standard, every platform |
| `block.h` | the macOS SDK |
| `error.h` | glibc, so Linux |
| `process.h` | MinGW, so the MSYS2 Windows path |

Renaming those four fixes today and leaves the next module to be caught by a
user on a platform we do not test. A directory prefix is categorical.

## Why layout only

Sources and generated C keep their bare sibling includes. A quoted include is
searched first in the directory of the file doing the including, so once
`include/x2c/string.h` and `include/x2c/error.h` sit together, `string.h`'s own
`#include "error.h"` resolves with no flag at all.

The alternative, prefixing what the emitter writes, was measured and rejected:
586 quoted include lines across 97,167 generated lines in `bootstrap/` would
regenerate, requiring the two-round bootstrap refresh, and the benefit amounted
to self-documenting generated C. This change touches no emitted include and no
generated file.

Two facts make layout-only sufficient:

- The driver already passes `-iquote` (`src/toolchain.x:147-151`), so pointing
  it one level deeper is a constant change.
- x2c's own `.x` include resolution never goes through `include/` for a repo
  build. `_resolve_include_dirs` (`src/collect.x:139-160`) searches the
  includer's directory, cwd, `src/`, and `lib/` directly.

`_is_home` (`src/utils.x:146-152`) still tests that `<path>/include` is a
directory, which remains true, so home discovery is unchanged.

## What changed

| Edit | Where |
| --- | --- |
| symlink under `x2c/` | `include/Makefile`, `include/.gitignore` |
| toolchain include dir, all three layouts | `src/toolchain.x:95`, `:100`, `:109` |
| repo default include dir | `src/utils.x:210` |
| APE bootstrap request | `src/bootstrap.x:337` |
| runtime-vs-user include classification | `src/collect.x:125` |
| benchmark builds | `Makefile:292`, `:330`, `:334` |
| unit-test builds | `etc/x2c.mk:13` |
| install destination | `etc/x2c-payload.py:32-33` |
| example builds | `examples/check.sh:107` |
| shootout builds | `examples/shootout/tools/shootout.py:257` |
| probes that compile generated C | eight scripts under `unittest/probes/` |
| prefix layout and a compile recipe | `docs/src/guide/installation.md` |

## Validation

`make build`, `make verify`, then `tools/gate-state.py ensure agent-pr-check`.
No bootstrap refresh: nothing about emission changes.

The end-to-end check is the reason the plan exists. Hand-written C compiled
with `-I include` and no `-iquote`:

```c
#include <string.h>        /* must reach libc */
#include <x2c/x2c.h>       /* the x2c runtime */
```

This now builds and runs. Before the change the same command failed in
`include/string.h`.

## Plan review

- **Facts already established.** Quoted-include resolution against the
  including file's own directory is a preprocessor guarantee; the design
  relies on it rather than reimplementing it, which is why the 436 quoted `.x`
  includes across `lib/` and `src/` needed no edit. `_is_home` already
  establishes that `include/` exists, and nothing rechecks it.
- **Reuse and deletion.** Nothing is added to the compiler. Path constants move
  in the places that already own path constants. The alternative that changed
  emission was measured and rejected.
- **Why idiomatic.** One directory level, expressed where the layout is already
  expressed.
- **Validators and fixtures.** None added. The hand-built mixed program is a
  one-time check, not a gate.
