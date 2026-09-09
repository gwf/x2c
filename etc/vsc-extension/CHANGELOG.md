# Change Log

All notable changes to the x2c syntax extension are recorded here, newest
first.

## 0.3.0

- Use `x2c editor` from an installed compiler for diagnostics, definitions, and
  hover, with trusted workspace and PATH discovery.
- Preserve explicit legacy worker settings and report missing tools once.

## 0.2.1 - Repository preview

- Highlight `?(Type name)` typed Match captures using ordinary x2c type
  syntax. Keep spaced `? (pattern)` contents as literal sublist patterns.

## 0.2.0 - Repository preview

- Add compiler diagnostics, definition navigation, and type hover through an
  optional repository-built semantic worker.
- Analyze unsaved source and include snapshots in fresh processes, with
  revision cancellation and UTF-8 to UTF-16 source-position conversion.
- Keep semantic execution restricted to trusted local workspaces; retain
  syntax highlighting when the worker or configuration is unavailable.
- Reuse ordinary project and compiler options. Completion, rename, and a
  workspace index remain outside this preview.

## 0.1.23 - 2026-09-06 (Preview)

### Added

- Braced `${expression}` insertion in Lists and Strings and `@{expression}`
  splicing in Lists.
- Current x2c control and error keywords, protocol declarations, associated
  types, macros, decorators, and macro holes.
- Current percent literals: Lists, Arrays, Maps, Strings, SymbolSets, and
  lambdas, including recursive List contents and runtime unquote and splice.
- Embedded compile-time Lisp with quote, quasiquote, unquote, and
  unquote-splicing.
- `.xmacro` registration for x2c and a standalone x2c Lisp grammar for
  `.xlisp` files.
- Automated TextMate scope tests and pinned development and packaging tools.
- A tracked packaged VSIX for inclusion in future x2c distributions and
  releases.
- Apache License 2.0 terms for the standalone VSIX package.
- Public package metadata, preview status, capabilities, keywords, and
  repository links.
- Explicit support and first-publication guidance.
- Current `with` blocks, flat List destructuring, import aliases, protocol
  representation aliases, delegate fields, thread-local storage, `Self`
  method types, and source keyword aliases.
- Specific scopes for x2c syntax, the 28 prelude types, and the existing macro
  result and hole kinds, with copy-ready dark and light palettes.

### Changed

- Arrays and Maps now highlight quoted data, recursively nested collections,
  and `$name` or `${expression}` insertion according to the data-first literal
  grammar.
- Capitalized macro result and hole types while retaining highlighting for
  compatible lowercase spellings.
- Removed parenthesized runtime insertion and List-splice highlighting;
  ordinary `$()` remains compile-time Lisp.
- Bumped the extension version to 0.1.23.
- Gave x2c-specific forms precedence over inherited C operator, call, string,
  and angle-bracket rules.

### Fixed

- Nested x2c statements and lambdas retain their specific scopes inside
  function bodies and call arguments.
- Lowercase `void` receives a value scope in unambiguous expression
  positions without recoloring C declarations or casts.
- Runtime interpolation braces no longer break bracket-pair coloring.
- Same-type destructuring declarations are no longer misclassified as
  function definitions.
- Inline and multiline `with` statements receive the same scopes as the
  single-line form.
- Braces, brackets, parentheses, and quotes use their actual opening
  characters in the editor auto-closing configuration.

## [0.1.15] - 2025-08-15

### Added

- Pattern variable highlighting for `?name` and `*name`.
- Optional pattern prefixes in simple symbol literals.

### Fixed

- C strings and function-call arguments retain their standard scopes.
- Function-call capture groups and string punctuation scopes are consistent.
- X2C literals keep precedence without coloring an entire function call.

## [0.1.4] - 2025-08-14

### Changed

- Lowered the VS Code engine requirement for broader compatibility.
- Prioritized x2c literals in function and call contexts.
- Made nested list content and ordinary list content use the same scopes.
- Added standard numbers, strings, types, and `=` handling inside lists.

## [0.1.1] - 2024-12-19

### Fixed

- Prevented C primitive-type rules from leaking into x2c literals.
- Applied explicit, recursive symbol captures to lists, arrays, and maps.

## [0.1.0] - 2024-12-19

### Added

- Initial x2c grammar.
- List, array, map, string, symbol, interpolation, and nested literal scopes.
