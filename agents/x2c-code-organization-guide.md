# x2c Module Maps

[The code standard](x2c-code-standard.md) owns module rules (MO), file
organization (FI), compiler boundaries (AR), and runtime ownership (RT).
These maps list the current owners. The generated
[module catalog](x2c-module-catalog.md) inventories their declarations.

## Compiler organization

Files below are relative to `src/` unless a path is shown.

- entry and shared state: `main.x`, `cli.x`, `translation.x`, `frontend.x`, `compiler.x`
  (its members in `compiler/` hold parsing, declarations, generated names,
  lifecycle, binding facts, the literal cache, match patterns, and source
  files and locations), `symtab/symtab.x`, `diagnostics.x`, `sourceview.x`,
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
  primitives: `bracket-access.x` (bracket access policy),
  `delegate-members.x` (delegate fields), `destructuring.x`
  (flat List destructuring), `interpolation.x` (interpolated
  Strings), `lambda-functions.x` (lambda lowering), `collection-literals.x`
  (Array and Map literals), `pattern-match.x` (match statements),
  `dynamic-operators.x` (dynamic operators), `printf-format.x` (Var
  values in printf-family formats), `protocol-adapters.x` (protocol
  adapters and Var descriptors), `raise.x` (raise),
  `string-switch.x` (switches on a String), and
  `try-catch.x` (try, catch, and finally);
- output: `cache.x`, `generate.x`, `emit.x`, `format.x`;
- project planning and native primitives: `project.x`, `toolchain.x`;
  build/run/script workflows live in `commands/build/`, and the editor
  adapter lives in `commands/editor/`;
- external package management: `commands/package/` owns installation, removal,
  listing, and project dependency lockfiles.

- shared source fields: `fields.x`;
- report wording: static macros in their owner or the shared
  `expressions-reports.x` and `parse-reports.x`.

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
string/string                canonical immutable values, classification,
                              numeric parsing, formatting, escaping,
                              splitting, and lazy field cursors
symbol, symbolset, atom,      closed vocabularies, and the optional
list, list-selectors          compound List selectors
block, buffer, array, map,    mutable storage and builders, and the Array
array-generics, map-generics  and Map family generators
typed-array, typed-map,       typed collection families and their
typed-list                    typed views
iter, match/match            traversal, pattern matching, plan lowering
                              and caching, and the Match wordcode machine
macrovalue, system-macros    macros as values that build and recognize
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
func, lisp, lisp-targets,     native callable binding, runtime Lisp and
lisp-bindings                 the native operations its sessions bind
meta, compiler-meta, type,    the meta function surface, compiler-private
rewrite                       meta operations, structural Type
                              operations, and rewrite registration
clibc, cmath                  C prototypes declared for compile-time calls
                              and Var unboxing
lib                           DisjointSet utility
```

`docs/library-manifest.txt` records visibility. `lib/Makefile` records the
prelude and optional sources; it generates `lib/x2c.x`. See RT-6 and AR-9.
