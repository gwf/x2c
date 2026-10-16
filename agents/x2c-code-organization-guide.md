# x2c Module Maps

[The code standard](x2c-code-standard.md) owns module rules (MO), file
organization (FI), compiler boundaries (AR), and runtime ownership (RT).
These maps list the current owners. The generated
[module catalog](x2c-module-catalog.md) inventories their declarations.

## Compiler organization

Files below are relative to `src/` unless a path is shown.

- entry and shared state: `main.x`, `cli.x`, `frontend.x`, `compiler.x`
  (its members in `compiler/` hold parsing, declarations, generated names,
  lifecycle, binding facts, the literal cache, match patterns, and source
  files and locations), `symbols.x`, `diagnostics.x`, `sourceview.x`,
  `collect.x`, `report.x`, `deps.x`, `utils.x`;
- shared runtime tokenization: `lib/tokenizer.x`; compiler parsing:
  `preprocess.x`, `parse.x`, `expressions.x`, `initializers.x`,
  `statements.x`, `literals.x`, `lambdas.x`, `macros.x`, `grammar.x`,
  `ast-rewrite.x`, `ast.x`;
- compile-time code: `stage.x`, `meta-sdk.x`, `meta-native.x`,
  `builtins.x`, `meta-group.x`, `meta-project.x`, `meta-helper-client.x`;
- semantic representation and lowering: `type.x`, `type-ledger.x`,
  `protocol.x`, `operator-ledger.x`, `transform.x`, which drives
  normalization and dispatches to the shipped components, `callables.x`,
  which lowers only `Func` conversions, `cleanup.x`, `adapter-memo.x`,
  `regions.x`;
- shipped components under `src/components/`, each lowering one language
  feature on the rewrite
  primitives: `component-access.x` (bracket access policy),
  `component-delegate.x` (delegate fields), `component-destructuring.x`
  (flat List destructuring), `component-interpolation.x` (interpolated
  Strings), `component-lambdas.x` (lambda lowering), `component-literals.x`
  (Array and Map literals), `component-match.x` (match statements),
  `component-operators.x` (dynamic operators), `component-printf.x` (Var
  values in printf-family formats), `component-protocols.x` (protocol
  adapters and Var descriptors), `component-raise.x` (raise),
  `component-string-switch.x` (switches on a String), and
  `component-try.x` (try, catch, and finally);
- output: `cache.x`, `generate.x`, `emit.x`, `format.x`;
- native and project driver: `build.x`, `project.x`, `toolchain.x`,
  `script.x`; the editor adapter lives in `commands/editor/`;
- external package management: `commands/package/` owns installation, removal,
  listing, and project dependency lockfiles.

- shared source fields: `fields.x`;
- report wording: static macros in their owner or the shared
  `expressions-reports.x` and `parse-report-macros.x`.

`tools/gen-linked-meta.sh` generates `linked-meta.x`, the shipped `meta`
code compiled into the compiler. Style censuses and these maps exclude it.

## Runtime organization

Files below are relative to `lib/`.

```text
common, scope, pool,          shared representation, lifetime, interning,
static-init, private-keywords static initialization, and the private loop
                              keyword
var, varconvert, varops,      tagged values, conversions, operations, the
var-ledger, var-tags,         tag and C scalar ledgers, pointer converter
var-adapters, integer-ops,    templates, and raw integer arithmetic
native-scalar-types
dispatch, protocols, cleanup  dynamic behavior and protocol adoption
string, string-classify,      canonical immutable values, string
string-number, string-format, classification, numeric parsing, checked
string-escape, split,         formatting, escaped spelling, splitting,
symbol, symbolset, atom,      closed vocabularies, and the optional
list, list-selectors          compound List selectors
block, buffer, array, map,    mutable storage and builders, and the Array
array-generics, map-generics  and Map family generators
typed-array, typed-map,       typed collection families and their
typed-list                    typed views
iter, match, match-plan,      traversal, pattern matching, plan lowering
match-cache, machine,         and caching, and the Match wordcode machine
match-machine
macro-value, system-macros    macros as values that build and recognize
                              code, and convenience macros
error, error_init,            ambient errors, their shared causes and
error-macros, error-private,  transfer layouts, and structured control
func-errors, exception        flow
file, logger, path, process,  system boundaries, argument parsing, and the
args, scripting               modules a script unit includes
json, datum                   values as JSON text and as Lisp reader text
diff, digest, regex           line differences, SHA-256 digests, and
                              regular expressions
context, thread, thread-state bounded runtime state, native workers, and
mutex                         their coordination primitive
scan, tokenizer               lexical scanners and the shared tokenizer
func, lisp, lisp-targets,     native callable binding, embedded Lisp,
lisp-init, meta, type,        its environment, the compile-time SDK,
rewrite                       structural Type operations, and rewrite
                              registration
clibc, cmath                  C prototypes declared for compile-time calls
                              and Var unboxing
lib                           DisjointSet utility
```

`docs/library-manifest.txt` records visibility. `lib/Makefile` records the
prelude and optional sources; it generates `lib/x2c.x`. See RT-6 and AR-9.
