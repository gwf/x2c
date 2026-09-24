# Indentation dogfooding

> Status: done 2026-09-24, delivered on `dev` by the commit that archived
> this plan. All eight files converted and passed the token proof; none was
> rejected. The conversion found three layout gaps, fixed in the same
> change and recorded under "Results". It follows the delivered
> [indentation syntax](indentation-syntax.md).

## Goal

Convert the repository's x2c script tools to the indentation syntax with
`#pragma indent`. They keep their extensionless names. The conversion tests
the syntax on real programs that nobody wrote for it. A converter does the
work, and each converted file is proved equivalent to its original before
its behavior is checked.

## Scope

Convert these files:

| File | Lines | Run by |
| --- | --- | --- |
| `tools/check-docs` | 479 | `make doc-check` |
| `tools/gen-llms-txt` | 266 | `make doc-generate`, `make doc-check` |
| `tools/check-doc-examples` | 210 | `make doc-examples`, `make doc-outputs` |
| `tools/check-gallery-examples` | 134 | by hand |
| `tools/gen-package-index` | 133 | `tools/release-candidate.py` |
| `tools/check-release` | 75 | by hand, against the live site |
| `tools/check-conformance-coherence` | 65 | `make` gate target |
| `tools/doc-samples.x` | module | included by the two example checkers |

`etc/x2c-payload.x`, which is on the release path, and the scripts under
`examples/` stay in brace form.

## Converter

Add `tools/indent-convert`, an x2c script in brace form. It converts one
file at a time in place, or with `--check` it reports without writing. It
is the converter the indentation syntax plan listed as a follow-up, and the
lint-and-format work can build on it later.

The converter tokenizes the brace source with `Tokenizer`, then rewrites
the source text line by line. It relies on the file's existing indentation,
which the style guide keeps at two spaces per level:

- adds `#pragma indent` after the shebang line;
- turns a `{` that ends a line into `:`, and deletes a line that holds only
  `}` or `};`;
- turns `} else {` and `} else if (...) {` into an `else:` or
  `else if ...:` line at the outer indentation;
- turns `do {` ... `} while (cond);` into `do:` with a `while (cond)`
  trailer line;
- drops a `;` that ends a line, and the parentheses around a control
  condition;
- keeps a braced one-line body such as `if (x) { a; }` as a one-line
  `if x: a` when it holds one statement;
- adds `@` to a decorator line, which is a `$name(...)` line with no `;`
  followed by the statement it wraps.

The converter leaves a file unchanged and reports the line when it finds a
form it cannot convert, such as two statements on one line, a `{` that
does not end its line, or indentation that disagrees with the braces.

### Equivalence proof

After converting, the converter scans its output with `layout` set and
compares that token stream with the original file's significant tokens.
Only two differences are allowed:

- a `case` or `default` body gains a `{` `}` pair, because the indented
  form opens a block there;
- a lone `;` empty statement may disappear.

Any other difference is a converter defect. The converter then reports it
and writes nothing. A file that passes has the same program by
construction, so its gate run confirms behavior and does not need to find
conversion mistakes.

## Forms that do not convert

When the converter rejects a construct, the file stays in brace form. The
case is recorded here with the file and line, and Gary decides on a
syntax change, a converter change, or leaving it. No file is edited by hand
to make it convert.

Recorded cases: none. Every file in scope converted.

## Results

`tools/indent-convert --check` reported all eight files as converting, and
the conversion wrote them. Line counts fell by 147 in total, almost all
closing braces; `tools/x2c-script-ports.md` records the new counts.

The first proof run failed on three files. Each failure was a layout pass
gap, not a converter defect, and each is fixed in `lib/tokenizer.x` with
coverage in the `indent-syntax` fixture:

- a line ending in the `:` of a `?:` expression was read as a block
  header; a colon that closes a pending `?` now continues the line
  (`tools/check-doc-examples`, `tools/gen-llms-txt`);
- in an unbraced `foreach (...)` whose body is a braced `if (...) {`, the
  converted `if x:` continues the `foreach` line, and only the first
  keyword of a line got parentheses; the condition now belongs to the last
  control keyword before the colon (`tools/check-docs`);
- `catch pattern: {` and `match (x) case pattern: {` lost their label
  colon; a `case`, `default`, or `catch` anywhere in a header now keeps it.

Behavior: the gated tools ran in `agent-pr-check`.
`tools/check-gallery-examples` printed the same output and status before
and after. `tools/gen-package-index`, run on a temporary one-package
directory, wrote the same index row and archive members; the archive hash
differs, as expected. `tools/check-release` relies on the proof alone.

Follow-up, same day: Gary asked for bodies without braces in colon form
too. The converter now gives each such header a colon, which adds a
one-statement block, so the token proof became an AST proof: the
compiler's `--dump-ast` output for the result must equal the original's
after dropping statement numbers, reading a one-statement block as its
statement, and splicing a block that follows a `case` label. It rejects a
dangling `else` or an unbraced body whose indentation misstates its
extent. All eight files reconverted from their brace form and passed; no
C-style header remains. Gary then decided that `foreach` takes `in` in
place of its comma in both forms, with the comma still accepted, and that
a `for` header keeps its parentheses and takes the colon after them. The
macro argument parser accepts `in` after a `Decl` argument, the layout
pass stops adding parentheses to `for`, the converter writes both forms,
and the tools were converted again. The tools keep their extensionless names, so they
run by name from a shell when executable.

## Validation

- Run `tools/indent-convert --check` over every file in scope and record
  the results in this plan, including rejected cases.
- Gated tools run in `tools/gate-state.py ensure agent-pr-check`.
- Run `tools/check-gallery-examples` by hand before and after conversion
  and compare stdout and status.
- Run `tools/gen-package-index` on one source package before and after
  conversion, and compare the index apart from archive hashes, as the
  script's port record did.
- For `tools/check-release`, the equivalence proof is the check, because
  it downloads from the live site.
- The converter gets no fixture of its own. Its token comparison checks
  every conversion it performs.

## Delivery

Deliver the converter together with the converted tools, directly to `dev`
under the root `AGENTS.md`. Update the tool table in
`tools/x2c-script-ports.md` to note the indented form. Add a short
`tools/indent-convert` entry to the Indentation Syntax guide page.

## Plan review

- **Trusted facts.** The layout pass and the parser are proven by the
  delivered fixtures. The converter trusts them and adds no checks of its
  own on the output beyond the token comparison.
- **Reuse and new machinery.** The converter reuses `Tokenizer` for both
  the input scan and the proof. It is the only new mechanism, and the
  earlier plan already called for it.
- **Idiom.** The converter is a line-oriented rewrite driven by tokens,
  written as an ordinary x2c script like the tools it converts.
- **Diagnostics.** The converter reports unconvertible forms and token
  mismatches. Both protect against wrong output: a converted tool that
  means a different program. There are no other validators.
