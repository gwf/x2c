# Release Notes

Each section summarizes what changed for a user of the compiler, runtime,
commands, and packages since the previous release. The
[installation chapter](../guide/installation.md) carries the upgrade steps.

## 0.15.1 (2026-10-17)

A patch release of 0.15.0. Existing installations upgrade in place; no
packages need rebuilding.

- An uncaught error prints one line naming the error, the raising function
  and location, and its details, then aborts with the same status. The
  full logger event remains available with `X2C_DEBUG` or a `<log>` policy.
  See [Handlers and policy](../guide/exceptions.md#handlers-and-policy).
- `$auto` on a local that is already managed is a compile-time error
  instead of a crash at scope exit.
- The REPL continues a list literal across lines.
- The book gains this release notes page, and the repository gains a
  security policy, a pull request template, and a bug report template.

## 0.15.0 (2026-10-17)

Releases ship for macOS arm64 and x86_64 and Linux aarch64 and x86_64, with
the book as a PDF beside the archives. Read
[Upgrading from 0.14.0](../guide/installation.md#upgrading-from-0140)
before replacing an existing prefix.

### Language

- `meta` functions run ordinary x2c during translation. A macro body calls
  one with `$helper(...)`, passes constants or captured syntax, and inserts
  the code it returns. `meta.x` supplies the `Code` and `Type` operations
  for inspecting and building code. See
  [Meta Functions](../guide/meta-functions.md) and
  [Generating Code](../guide/generating-code.md).
- Macro values: a macro can select, apply, and collect cases as values,
  and typed quotations with expression holes build code with its type.
- `Stmt` macros accept an expression body, and a macro call may begin with
  a dotted name.
- Module blocks split one translation unit across a directory. The new
  `module` storage class is visible in every member file; `static` stays
  private to its file.
- Indentation syntax: a `.xp` file, or `#pragma indent` in a `.x` file,
  groups statements by indentation without braces or semicolons. See
  [Indentation Syntax](../guide/indentation.md).
- `raise` is a statement head, `catch` accepts patterns as codes, and a
  variable may supply a `raise` code.
- Optional reference parameters, GNU statement expressions, `threaded`
  thread-local storage, and the contextual `in` membership operator.
- `class` types gain `alloc` and a refusing `init`, and `init` takes
  constructor arguments.
- Twelve language features moved out of the compiler kernel into
  components under `src/components/`; their behavior is unchanged.

### Library

- `lib/regex.x` adds regular expressions over the bytes of a String, and
  every `x2c script` can use them.
- `lib/diff.x` computes line differences between two texts.
- The runtime's canonical pool operations moved from `List` to `Pool`.
- `Var.truth` replaces `Var.truthy`; `List.reduce`, `Array.reduce`, and
  `Iter.reduce` are removed in favor of `Iter.foldl`.
- Compile-time Lisp gains tail calls and a bounded call depth.

### Commands and packages

- `x2c new` creates a starter project that builds and runs.
- `x2c repl` is a shipped command with line editing, grammar-aware and
  semantic completion, and named inspection of session values. It
  evaluates a supported subset of the language. See
  [Experimental REPL](../guide/repl.md).
- Package management, the editor adapter, and project creation are
  external commands under `libexec/x2c/`. `x2c lint` and `x2c graph` are
  shipped as experimental.
- Packages record native arguments in `<name>.native.rsp` instead of
  `<name>.link`. Rebuild source packages and replace native bundles.
- Automatic differentiation moved from the runtime to the optional
  `autodiff` package; `import "autodiff"` supplies its types and macros.
- The SQLite package renames `Statement` to `Prepared` and
  `Var.statement` to `Var.prepared`.
- Every package manages its handles with `$auto`, so connections, loops,
  images, documents, and terminals release at scope exit.
- The C* verification package is removed.

### Documentation

- The book adds the [x2c Syntax Map](../guide/x2c-syntax-map.md) for C
  readers, the [syntax specifications](syntax/index.md) with a source
  grammar and lexical rules, [The Region Model](../guide/regions.md), and
  chapters for meta functions, generating code, the REPL, and indentation.
- The language reference was corrected against the implementation and
  its repeated rules removed.
- The public site at [x2c-lang.dev](https://x2c-lang.dev/) carries the
  book under `/docs/`.

### Fixed defects

- A `return` inside a `defer` or `finally` body leaves its exception frame
  before transferring, so a later `raise` in the caller is caught.
- Macro bindings retained across package builds, nested empty unit
  macros, quotation members and splices, and template members in
  anonymous aggregates expand correctly.
- Parameter redeclaration inside callable bodies and the author-binding
  `extern` regression are fixed.
- Constructed raw string segments, nested string literals inside list
  literals, and negative percent literals in every radix are read as
  written.
- Pointer arithmetic over pointer typedefs and casts to template typedefs
  type correctly.
- Project meta payloads, include handling, the failure cache, and host
  flags are repaired for package builds.
