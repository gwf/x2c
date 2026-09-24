# Indentation syntax

> Status: active.
> A spike on 2026-09-24 showed the design works without parser changes.
> Gary chose both triggers, a pragma and the `.xp` and `.xpmacro`
> extensions, on 2026-09-24. Nothing is implemented.

## Goal

Let an x2c file group statements by indentation instead of braces and end
statements at line breaks instead of semicolons, as Python does. A line
that opens a block ends with `:`. The indented lines after it are the
block. The block ends when a line returns to an outer indentation level.

The indented form is only a different spelling. Each indented file has
exactly one brace-form equivalent, and every later compiler stage sees the
same tokens it sees today. Semantics, the AST, macros, match, meta
functions, and emitted C do not change.

```x2c
#pragma indent

int sum_positive(int *xs, int n):
  int total = 0
  for int i = 0; i < n; i++:
    if xs[i] > 0: total += xs[i]
    else if xs[i] == -99:
      break
  return total
```

## Triggers

A file uses the indented form when either trigger is present.

- **Pragma.** `#pragma indent` as the first line of the file. A shebang
  line may come before it, and so may comments. It works with any file
  name, including `.x`, `.xmacro`, and extensionless scripts. The layout
  pass removes the pragma token, so no pragma reaches the emitted C.
- **Extension.** `.xp` marks a source unit and `.xpmacro` a macro file.
  A file with one of these extensions needs no pragma. `.xp` units follow the same rules as `.x` units: `#include
  "foo.xp"` emits `#include "foo.h"`, and builds, projects, packages, and
  `x2c script` accept them wherever they accept `.x`.

The pragma lets a single file in an existing project switch forms without
renaming. The extension lets a whole project use the form, and it lets
tools and editors choose highlighting from the name.

## Layout rules

The spike validated every rule below except the four marked *new*. All of
them are decided unless Gary changes them.

1. **Logical lines.** A logical line runs until a newline at bracket depth
   zero. Tokens that end in an opening bracket count as openers, such as
   `%(`, `${`, and `%[`.
2. **Continuation.** A line continues the previous logical line when it is
   more indented and the previous line does not end in `:`. This is
   Haskell's offside rule. It covers `=>` bodies on the next line and
   expressions split after an operator. A line that starts with `.` also
   continues the previous line, so method chains can be split.
3. **Blocks.** A line ending in `:` and followed by a deeper line opens a
   block, and the `:` becomes `{`. `case X:` and `default:` keep their
   colon and add `{`. Each dedent closes one block. A block whose header
   contains `struct`, `union`, or `enum` closes with `};`, unless the
   header starts with `typedef`.
4. **Conditions.** `if`, `else if`, `while`, `for`, `foreach`, `switch`,
   and `match` get parentheses around their condition when the source has
   none.
5. **One-line bodies.** `if cond: stmt` uses the first `:` at depth zero
   that does not close a `?` (*new*: the spike took the first colon, so it
   split a ternary).
6. **Semicolons.** Every other statement line gets `;`, except:
   - lines that already end in `;`;
   - enum bodies;
   - preprocessor lines;
   - a line that is one whole `$(...)` form;
   - decorator lines;
   - a line that ends in a Block hole (*new*: the spike produced a
     harmless `$body;`).
7. **Decorators.** A decorator is written `@$time("loop")` on the line
   before the statement it wraps. The pass removes the `@` and adds no `;`.
   The marker is needed because `$name(...)` alone looks the same as a
   statement macro call, and only the parser knows which one it is.
8. **Bare scope blocks** (*new*). `do:` followed by a block with no `while`
   trailer at the same indentation is a bare block `{ ... }`. With a
   trailer line such as `while (i < 3)`, `do:` stays a do-while loop. The
   spike used `if 1:` as a stand-in. Macros such as `$time` and
   `$error.fallback` need this form.
9. **Indentation errors** (*new* location fix). A dedent that matches no
   open block is an error reported at the dedented line. A tab in leading
   indentation is an error, because the pass could group the lines wrongly.
10. **Brace-form escape.** Braces and semicolons written explicitly still
    work inside an indented file, because the parser accepts them as
    usual. Braces used as values, such as map literals and initializers,
    are bracketed and never treated as blocks.

## Implementation

Put the pass in `lib/tokenizer.x` as `Tokenizer.layout`. `Tokenizer.scan`
runs it after scanning when the Tokenizer's `layout` flag is set, or when
the first significant token is `#pragma indent`. The pass rebuilds the
contiguous token array with synthetic tokens inserted. Each synthetic
token has zero length and takes the line, column, and byte position of the
token it follows. Diagnostics and source spans therefore point at the
indented source, and later stages never see the inserted tokens as source
text. Scanning and token storage are otherwise unchanged. Files without a
trigger pay one flag test.

Callers that read a file by path set the flag from its extension:

- `Compiler.tokenize` in `src/compiler.x` for units;
- raw symbol collection in `src/collect.x`, which scans units to find
  includes and declarations;
- `.xmacro` imports in `src/macros.x`, which also accept `.xpmacro`.

The extension also has to be recognized at these other sites:

- `x2c_source_file` in `src/utils.x`;
- include rewriting in `src/emit.x` (`.xp` maps to `.h`);
- package unit discovery in `src/install.x`;
- the bootstrap source classification in `src/bootstrap.x`, only if
  compiler or runtime sources ever adopt the form.

The editor adapter and the REPL tokenize through the same code. The editor
gets the form for free. The REPL stays in brace form, because it reads one
submission at a time.

The spike's `xp2x.x` in the spike workspace is the reference for the rules.
It is about 150 lines, and the tokenizer pass should be about the same
size.

## Validation

- Compiler fixtures under `unittest/`, following `unittest/AGENTS.md`. Each
  fixture is an indented source whose expected output is its brace-form
  translation or its program output. Cover each rule above, each trigger,
  and the four indentation errors.
- Convert the spike's test programs into fixtures. They are the demo
  program, `examples/power/match.x`, `examples/magic/range-and-swap.x`, a
  prefix of `examples/scripts/line-counts.x`, and an `.xpmacro` import
  covering `lib/error-macros.xmacro` and `$dedent`/`$time` from
  `lib/system-macros.xmacro`.
- Add one executable example written in the indented form to
  `examples/manifest.txt`.
- Delivery follows the root `AGENTS.md` with
  `tools/gate-state.py ensure agent-pr-check`. No compiler or runtime source
  adopts the form, so no bootstrap sequencing is needed.

## Documentation

Add an "Indentation syntax" section to `docs/src/reference/language.md`
with the triggers and the rules above. Add a short guide page under
`docs/src/guide/` that shows the demo program in both forms and explains
decorators, bare blocks, and continuation.

## Follow-ups outside this plan

- A converter between the two forms, as a mode of the formatter in
  [lint and format](x2c-lint-and-format.md).
- REPL input in the indented form.

## Plan review

- **Trusted facts.** The tokenizer already records each token's line,
  column, and bracket-opening text. The parser already accepts the brace
  form. The pass trusts both and adds no parser checks.
- **Reuse and new machinery.** The design reuses the tokenizer, parser,
  and all later stages unchanged. The only new mechanism is the layout
  pass, which is required because no current stage knows about
  indentation. The extension checks extend existing `.x` and `.xmacro`
  tests and add no new dispatch.
- **Idiom.** The pass is a single loop over the token array with a small
  indentation stack. It rewrites tokens and builds no second grammar or
  AST.
- **Diagnostics.** The pass adds two. The unmatched-dedent error protects
  against wrong grouping, which would otherwise compile into different
  code. The tab-in-indentation error protects against the same wrong
  output. There are no other validators. Negative fixtures cover exactly
  these two errors, plus a ternary inside a one-line `if` and a
  continuation line, because the old rule gave wrong output for both.
