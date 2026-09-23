# Symlinked home spellings

> Status: needs author scoping - 2026-09-23, reproduced on macOS arm64 at
> the unit-interface compiler-identity branch. The home root is resolved
> through symbolic links, but a source operand named through a symlinked
> spelling is not, so one runtime file can be collected under two paths.
> Installs avoid it by translating from inside the home with relative
> operands (`etc/x2c-payload.x`, `bootstrap_write_interfaces`).

## Reproduction

On macOS `/tmp` is a symbolic link to `/private/tmp`. With an installed home
at `/tmp/h`:

```sh
X2C_HOME=/tmp/h /tmp/h/bin/x2c translate --out-dir /tmp/out \
  /tmp/h/lib/array.x /tmp/h/lib/x2c.x
```

The translation fails with `protocol: conflicting adoption declarations for
Cleanup(Array)`, noting `first: lib/array.x:37:1 second:
/tmp/h/lib/array.x:37:1`. The same command succeeds with relative operands
from inside the home, or with every spelling under `/private/tmp`.

## Result

A source operand should name the same file however it is spelled, so the
prelude's `lib/array.x` and the operand `/tmp/h/lib/array.x` are one unit.

## Decisions needed

Whether the frontend canonicalizes operands through symbolic links, as
collection already canonicalizes include paths, or whether the home keeps
the spelling it was given.

## Validation

The reproduction above translates, and a header-cache probe case runs the
same translation from a symlinked home.
