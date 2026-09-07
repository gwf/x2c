# X2C Debugging Guide

Practical techniques for diagnosing compiler issues, understanding AST shape,
and validating runtime behaviour.

---

## 1. Core Concepts

### 1.1 Var, Symbol, List Basics

```c
// WRONG: car() returns a Var, so direct symbol comparison fails
if (node.car() == <declare>)
  ...;

// CORRECT
if (node.car().symbol() == <declare>)
  ...;
```

Use list helpers from `lib/list.x`:
- `list.car()`, `list.cdr()`
- `list.cadr()`, `list.caddr()`, `list.cadddr()`
- No `second()`, `third()`, etc.

### 1.2 Symbol Limits

`Symbol.new` selects an encoding from the payload and truncates to that
encoding's limit: 10 characters when every character is in the restricted
5-bit alphabet, otherwise 7 characters in 7-bit encoding. Plan abbreviations
accordingly instead of relying on runtime errors.

### 1.3 Pointer Access

Use `.` for both struct and pointer member access. C pointer member access
with `->` is also accepted. The universal dot notation also
covers method calls, so avoid naming struct fields the same as type
methods to prevent ambiguity.

---

## 2. CLI Diagnostics

`src/cli.x` owns the option table; these switches short-circuit the
pipeline:

- `--dump-tokens` / `--dump-cpp-tokens` — inspect lexer output
- `--dump-ast` / `--dump-transforms` — observe initial and transformed ASTs
- `--dump-cache` — view literal cache entries emitted by `src/cache.x`
- `--dump-code` — print the unformatted C token stream
- `--dump-symbols` / `--dump-cpp-symbols` — inspect compiler symbol tables
- `--dump-cpp` / `--dump-cpp-text` — show preprocessor output
- `--debug` — mirror compiler debug logging to standard error
- `--no-cpp` — skip the host preprocessor

Use a dedicated output directory when iterating:

```sh
mkdir -p /tmp/x2c-debug
./builds/0/x2c translate --out-dir /tmp/x2c-debug /tmp/test.x
```

Compiler diagnostics report one-based lines and columns and underline the
offending token's first-line width. The CLI records one ordinary error by
default, followed by its limit notice. The exact location fields and generic
Diagnostics API are documented in `agents/logger-and-diagnostics-guide.md`.

For a preprocessing failure, read the host `cc` stderr first, then the x2c
driver diagnostic. The driver entry records the preprocess status and points
at the first source directive. Because x2c invokes `cc` without a shell, a
source or `-I` path containing spaces or metacharacters should be investigated
as an ordinary filesystem/include problem, not escaped as command text.

---

## 3. Working with ASTs

1. Dump the AST for a minimal reproducer:
   ```bash
   echo 'static int x = 42;' > /tmp/test.x
   ./builds/0/x2c translate --dump-ast /tmp/test.x
   ```
2. Use source `match` to name a static AST shape instead of walking it with
   `car`/`cdr` or constructing a binding List only to search it with `assoc`:

   ```x2c
   match (decl)
     case %(declare ?type
            (bindings (op = (bind ?name ?mods) ?init) *rest)): {
       // Inspect type, name, mods, init, and rest here.
     }
   ```

   [Replacing manual AST walks with `match`](replacing-manual-ast-walks-with-match.md)
   explains how structural captures, semantic probes, traversal, and output
   templates compose in compiler code.
3. Use `--dump-transforms` after editing `src/transform.x` or a related
   lowering module to confirm the expected rewrite occurred. The
   match/loop-control fixture checks exact transformed output as well as
   emission and native behavior.

---

## 4. Common Pitfalls

- "expected atomic expression": test for a declaration and call
  `Compiler.parse_simple_declaration` at that parser boundary.
- Missing field lookup: inspect pointer/aggregate classification in
  `src/type.x` and field resolution in `src/compiler.x`.
- Iterator returning nothing: inspect the adapter in `lib/dispatch.x` and the
  protocol in `lib/iter.x`.
- Literal emitted twice: inspect `src/cache.x` and the lowering that emits the
  `cache` node.
- Directive missing from generated C: compare `--dump-ast` and `--dump-code`.
  Directives at top level and inside compound statements should remain AST
  nodes in source order; `--dump-cpp-text` is only the discovery stream.

---

## 5. Progressive Testing Pattern

1. Start from the simplest expression or statement in `/tmp/test.x`.
2. Create `/tmp/x2c-debug`, translate with
   `translate --out-dir /tmp/x2c-debug`, and inspect the
   generated file matching the input basename.
3. Add one feature at a time (operators, decorators, foreach) until failure.
4. Redirect complete stdout and stderr from failing invocations into `debug/`
   (`debug/dump-ast.log`, `debug/build-x2c.log`).
5. When compiler behaviour changes, finish with `make verify` and
   `make stage-3`.

---

## 6. Helpful References

- Language semantics: `docs/src/reference/language.md`
- Runtime APIs: `docs/src/library/overview.md`
- Module inventory: `agents/x2c-module-catalog.md`
- Logger and diagnostic contracts: `agents/logger-and-diagnostics-guide.md`

Keep this guide aligned with actual debugging surfaces. Update the CLI flag
list and troubleshooting notes whenever the compiler changes them.
