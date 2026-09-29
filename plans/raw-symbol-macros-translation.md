# Raw-symbol translation of macros.x

> Status: both repairs verified; the standalone sweep passed on the
> integrated pre-publication tree after the import correction.
> The explicit raw-symbol sweep remains optional; this record adds no gate.

## Observed behavior

The explicit `make proof-raw-symbols` sweep finished in 111.96 seconds with
648 required sources, 409 classified exclusions, 647 successful comparisons,
and one failure: `src/macros.x` translated in CPP mode but failed in raw mode.
The complete Make command exited 2. Compiler and fixture source were unchanged
from the named dev revision during this investigation.

Raw translation reports that Compiler has no methods `parse_expression`,
`resolve_expression`, `parse_assignment`, and `parse_variable`. Both relative
and absolute source-path invocations reproduce the error, exiting 1. The
relative CPP-mode invocation exits 0. These checks used the same stage-0
compiler, source tree, and working directory.

## Reproduction

At the named revision, prepare the compiler with `make build-safe`, then run
from the repository root:

```sh
out=$(mktemp -d)
builds/0/x2c translate --out-dir "$out" src/macros.x
builds/0/x2c translate --cpp-symbols --out-dir "$out" src/macros.x
```

The first command should translate successfully, and both modes should
produce the same C/H under the existing sweep contract. Currently only the
second succeeds. The full sweep remains available through its existing
explicit target; do not exclude macros.x or rewrite expectations to hide
this failure.

## Cause and repair

The same sweep failed on macros.x before publication of the workflow change.
A relative-path raw translation subsequently succeeded in 717 ms with the
post-gate compiler at `813a897d`. That was an isolated pass, not a green full
sweep. At dev `89da87d0`, a fresh stage-0 compiler failed the cold raw
translation while CPP mode succeeded. In the earlier `f6606dbf` diagnosis,
a self-hosted stage-1 compiler passed with an interface but failed with
`--no-interfaces`, so an interface can hide the cold collection defect.

`src/expressions.x` defines `$func_call` before the slot function
`x2c_func_call_arguments` is declared. Its only earlier prototype was in
`src/builtins.x`, which `src/macros.x` includes after `expressions.x`.
Shallow collection therefore cannot parse the template at that point.
`Compiler.collect_compile_time_definition` suppresses the malformed macro
and advances to end of file, dropping the later `Compiler` method rows from
the included contribution. Full CPP collection or a complete interface
provides those rows by another path.

The repair moves that existing prototype from `builtins.x` to immediately
before `$func_call` in `expressions.x`. The definition and builtin
registration remain where they were; no parser validation or second
declaration mechanism is added. A two-file inert `/tmp` reproduction has a
template using a slot declared later in its included file, followed by a
method the including file calls. Raw translation reports the method missing
before a slot prototype is placed ahead of the template and succeeds after.
On dev `f6606dbf`, a temporary full-source copy with the prototype ahead of
the template made cold raw `macros.x` translation succeed with stage-0 and
stage-1; removing its later duplicate also passed stage-0 raw translation of
`macros.x`, `builtins.x`, and `expressions.x`. On the authored tree from
`89da87d0`, `make build` and cold raw/CPP translation of `src/macros.x`
succeed, with byte-identical generated C/H.

The optional `make proof-raw-symbols` compared 651 of 652 required sources.
Its one failure was `unittest/test-diagnostics.x`: the CPP invocation cannot
open `grammar.xmacro` because it looks under `unittest/`; the raw invocation
succeeds. Running that source alone reproduces the same CPP/raw result. The
source and import owner are outside this prototype move, so the sweep was
still red at that checkpoint. No exclusions or sweep flags changed.

That failure also reproduces on an unmodified `89da87d0` archive built with
`make build-safe`: focused CPP translation exits 1 with path
`unittest/grammar.xmacro`, while raw translation exits 0. The import is in
`src/literals.x`, reached through the included compiler source.
`_canonical_path` resolves a relative macro import against the
current compiler filename or import stack. The CPP-flattened input therefore
uses the `unittest/` unit directory. Changing that one import to the canonical
`../src/grammar.xmacro` spelling already used by the other compiler clients
fixes the focused CPP translation. In the disposable baseline archive, raw
and CPP then produced byte-identical C/H, and the raw C/H did not change from
before the path correction. On the authored tree, the same focused parity
check passes after `make build`.

Logs in `/Users/gary/.codex/worktrees/d40d/x2c/debug/`:
`raw-symbol-followup.log`, `raw-symbol-relative.log`,
`raw-symbol-absolute.log`, and `raw-symbol-cpp.log`.

The complete optional `make proof-raw-symbols` sweep passed after integration:
652 required sources compared, 414 classified exclusions, and zero failures.
Its expected contract and exclusions did not change. The ordinary final-tree
publication gate remains to be run on this batch.

## Plan review

The repair preserves the slot's definition, registration, signature, and
generated C/H. It reuses the existing sweep and ordinary declaration
collection. It adds no helper, validator, representation, language diagnostic,
recurring fixture, or gate.
