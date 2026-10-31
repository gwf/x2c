# Unchanged C through x2c

- Run: `20261031T024127.534963Z`
- x2c: `/Users/gary/.codex/worktrees/f2bc/x2c/builds/0/x2c`
- Compiler SHA-256: `9558fc95dcc1eccbe56e0415437a782e2cfeee0309afefc0ff53b24741e30d9e`
- Profile comparison: `local`

The native-driver path builds the original `.c` with `x2c build`.
The parser path translates a byte-identical `.x` copy with `--cpp`,
then compiles the emitted C. Both paths check the official fixtures.
Successful parser builds also compare profile output with the
fixture-verified native-driver program. No source is rewritten.

| Problem | Native driver | x2c parser | Parser result |
| --- | --- | --- | --- |
| nbody | pass | pass | official fixtures and profile output match |
| spectralnorm | pass | pass | official fixtures and profile output match |
| fannkuchredux | pass | pass | official fixtures and profile output match |
| mandelbrot | pass | pass | official fixtures and profile output match |
| fasta | pass | fail | examples/build/shootout-c/20261031T024127.534963Z/fasta/reference.x:135:49: parse: invalid token |
| knucleotide | pass | fail | examples/build/shootout-c/20261031T024127.534963Z/knucleotide/reference.x:23:49: parse: expected identifier in destructuring declaration |
| revcomp | pass | fail | examples/build/shootout-c/20261031T024127.534963Z/revcomp/reference.x:68:10: parse: empty parameter list; use (void) |
| binarytrees | pass | pass | official fixtures and profile output match |
| regexredux | pass | pass | official fixtures and profile output match |
| pidigits | pass | pass | official fixtures and profile output match |

Commands, source hashes, stdout, stderr, and comparison details
are retained beside `report.json`. This optional check is separate
from timing results and publication gates.

Observed parser limits on these exact contributions:

- FASTA contains a backslash-newline continuation after a string literal.
  The x2c parser rejects that token.
- k-nucleotide invokes the `KHASH_INIT` macro supplied by a native C header.
  The x2c parser does not expand that invocation in this translation path.
- Reverse-complement declares `int main()`. The x2c parser requires an
  explicit parameter list, such as `(void)`, for this source form.

The native build-driver path accepts all three original sources because the
configured C compiler handles their C syntax. No compiler behavior was changed
and no adopted contribution was patched as part of this observation.
