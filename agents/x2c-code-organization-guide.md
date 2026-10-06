# x2c Module Maps

[The code standard](x2c-code-standard.md) owns module rules (MO), file
organization (FI), compiler boundaries (AR), and runtime ownership (RT).
These maps list the current owners. The generated
[module catalog](x2c-module-catalog.md) inventories their declarations.

## Compiler organization

Files below are relative to `src/` unless a path is shown.

- entry and shared state: `main.x`, `cli.x`, `frontend.x`, `compiler.x`,
  `symbols.x`, `diagnostics.x`, `sourceview.x`, `collect.x`, `report.x`,
  `deps.x`, `utils.x`;
- shared runtime tokenization: `lib/tokenizer.x`; compiler parsing:
  `preprocess.x`, `parse.x`, `expressions.x`, `initializers.x`,
  `statements.x`, `literals.x`, `lambdas.x`, `macros.x`, `grammar.x`,
  `ast-rewrite.x`, `ast.x`;
- compile-time code: `stage.x`, `meta-sdk.x`, `meta-native.x`,
  `builtins.x`, `linked-meta.x`, `meta-group.x`, `meta-project.x`,
  `meta-helper-client.x`;
- semantic representation and lowering: `type.x`, `type-ledger.x`,
  `protocol.x`, `operator-ledger.x`, `transform.x`, `callables.x`, `cleanup.x`,
  `adapter-memo.x`, `regions.x`;
- output: `cache.x`, `generate.x`, `emit.x`, `format.x`;
- native and project driver: `build.x`, `project.x`, `toolchain.x`,
  `install.x`, `script.x`, `editor.x`.

- shared source fields: `fields.x`;
- report wording: static macros in their owner or shared `src/*-reports.x`.

## Runtime organization

Files below are relative to `lib/`.

```text
common, scope, pool,          shared representation, lifetime, interning,
static-init                   and static initialization
var, varconvert, varops,      tagged values, conversions, operations
var-ledger
dispatch, protocols           dynamic behavior and protocol adoption
string, string-classify,      canonical immutable values, string
string-number, string-format, classification, numeric parsing, checked
string-escape, split,         formatting, escaped spelling, splitting, and
symbol, symbolset, atom, list closed vocabularies
block, buffer, array, map     mutable storage and builders
typed-array, typed-map,       typed collection families and their
typed-list                    typed views
iter, match, match-plan,      traversal, pattern matching, plan lowering
match-cache, machine,         and caching, and the Match wordcode machine
match-machine
macro-value                   macros as values that build and recognize code
error, error_init, exception  ambient errors and structured control flow
file, logger, path, process   system boundaries
context, thread, thread-state bounded runtime state, native workers, and
mutex                         their coordination primitive
scan, tokenizer               lexical scanners and the shared tokenizer
func, lisp, lisp-targets,     native callable binding, embedded Lisp,
lisp-init, meta               its environment, and compile-time SDK
clibc, cmath                  C prototypes declared for compile-time calls
                              and Var unboxing
lib                           DisjointSet utility
```

`docs/library-manifest.txt` records visibility. `lib/Makefile` records the
prelude and optional sources; it generates `lib/x2c.x`. See RT-6 and AR-9.
