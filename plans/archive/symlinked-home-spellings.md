# Symlinked home spellings

> Status: done - 2026-09-23, delivered as `610c52f5`. An absolute source
> operand in the home now resolves its directory through symbolic links, so
> it shares the home-relative identity of the prelude's copy. Its file name
> and every other operand spelling are unchanged. The header-cache probe
> runs the reproduction from a symlinked home.

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

The collision also needs a working directory that holds another
`lib/array.x`, such as a repository checkout: protocol location normalization
resolves the prelude's home-relative `lib/array.x` against the working
directory first.

## Decision

Gary decided that the frontend canonicalizes operands through symbolic
links, reusing the include-path canonicalization. `_tokenize_input` resolves
the directory of an absolute operand with `Compiler.canonical_path`, as
collection resolves an includer's directory, and keeps the result only when
it lies in the home.

Canonicalizing every operand's whole path was tried first and rejected.
It printed diagnostics for files outside the home under absolute real
paths. It named outputs after a symlink's target, which broke the package
fixtures. It also changed generated hashes and error-site paths for every
relative operand in the home, touching 92 fixtures and all of `bootstrap/`.

## Validation

The reproduction above translates, and a header-cache probe case runs the
same translation from a symlinked home.
