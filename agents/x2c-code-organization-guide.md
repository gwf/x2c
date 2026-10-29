# x2c Module Maps

[The code standard](x2c-code-standard.md) owns module rules (MO), file
organization (FI), compiler boundaries (AR), and runtime ownership (RT).
These maps list the current owners. The generated
[module catalog](x2c-module-catalog.md) inventories their declarations.

## Compiler organization

Compiler paths below are relative to `src/`. Paths beginning with `lib/` or
`commands/` are relative to the repository root.

- entry and shared state: `main.x`, `cli/cli.x`, `translation.x`,
  `frontend.x`, `compiler/compiler.x`
  (its members in `compiler/` hold parsing, declarations, generated names,
  lifecycle, binding facts, the literal cache, match patterns, and source
  files and locations), `symtab/symtab.x`, `diagnostics.x`, `sourceview.x`,
  `collect/collect.x`, `report.x`, `deps.x`, `utils.x`;
- shared runtime tokenization: `lib/tokenizer.x`; compiler parsing:
  `cpp/cpp.x`, `preprocess.x`, `parse/parse.x`, `expressions/expressions.x`,
  `initializers/initializers.x`, `statements.x`, `literals/literals.x`,
  `lambdas.x`, `macros/macros.x`, `grammar.x`,
  `ast-rewrite.x`, `ast.x`;
- compile-time code: `stage.x`, `meta-sdk/meta-sdk.x`,
  `meta-native/meta-native.x`, `builtins.x`, `meta-group/meta-group.x`,
  `meta-project.x`, `meta-helper-client.x`;
- semantic representation and lowering: `type.x`, `type-ledger.x`,
  `protocol/protocol.x`, `operator-ledger.x`, `transform/transform.x`, which
  drives normalization and dispatches to the shipped components,
  `callables/callables.x`, which lowers only `Func` conversions,
  `cleanup/cleanup.x`, `adapter-memo.x`, `regions/regions.x`;
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
- output: `cache.x`, `generate/generate.x`, `emit/emit.x`, `format.x`;
- project planning and native primitives: `project/project.x`, `toolchain.x`;
  build/run/script workflows live in `commands/build/`, and the language
  server lives in `commands/lsp/`;
- external package management: `commands/package/` owns installation, removal,
  listing, and project dependency lockfiles.

- shared source fields: `fields.x`;
- report wording: static macros in their owner or the shared
  `expressions-reports.x` and `parse-reports.x`.

`tools/gen-linked-meta.sh` generates `linked-meta.x`, the shipped `meta`
code compiled into the compiler. Style censuses and these maps exclude it.

## Runtime organization

Paths below are relative to `lib/`.

| Source | Responsibility |
| --- | --- |
| `common.x`, `scope/scope.x`, `pool/pool.x` | Shared representation, allocation lifetimes, and canonical values. |
| `static-init.x`, `private-keywords.x` | Static initialization and the private loop keyword. |
| `var/var.x`, `var/conversion.x`, `var/operators.x` | Tagged values, conversions, and operations. |
| `var-ledger.x`, `var-tags.x`, `var-adapters.x`, `integer-ops.x`, `native-scalar-types.x` | Tag and scalar ledgers, pointer converter templates, and raw integer arithmetic. |
| `dispatch.x`, `protocols.x`, `cleanup.x` | Dynamic behavior and protocol adoption. |
| `string/string.x` | Canonical immutable text, classification, numeric parsing, formatting, escaping, splitting, and lazy field cursors. |
| `symbol.x`, `symbolset.x`, `atom.x`, `list/list.x`, `list-selectors.x` | Closed vocabularies, canonical Lists, and optional compound List selectors. |
| `block.x`, `buffer.x`, `array/array.x`, `map/map.x` | Mutable storage and builders. |
| `array/generics.x`, `map/generics.x`, `typed-array.x`, `typed-map.x`, `typed-list.x` | Collection family generators and typed views. |
| `iter.x`, `match/match.x` | Traversal, pattern matching, plan lowering and caching, and the Match wordcode machine. |
| `macrovalue/macrovalue.x`, `system-macros.x` | Macros as values and convenience macros. |
| `error/error.x`, `error_init.x`, `error-macros.x`, `error-private.x`, `func/errors.x`, `exception.x` | Ambient errors, shared causes, transfer layouts, and structured control flow. |
| `file.x`, `logger.x`, `path.x`, `process.x`, `args.x`, `scripting.x` | System boundaries, argument parsing, and script-unit includes. |
| `json.x`, `datum.x`, `datum-reader.x` | JSON and Lisp reader text. |
| `diff.x`, `digest.x`, `regex.x` | Line differences, SHA-256 digests, and regular expressions. |
| `context.x`, `thread.x`, `thread-state.x`, `channel.x`, `mutex.x` | Runtime state, native workers, communication, and coordination. |
| `scan.x`, `tokenizer.x` | Lexical scanners and the shared tokenizer. |
| `func/func.x`, `lisp/lisp.x`, `lisp-targets/lisp-targets.x`, `lisp-bindings.x` | Native callable binding, runtime Lisp, and its native operations. |
| `meta.x`, `compiler-meta.x`, `type.x`, `rewrite.x` | Public and compiler-private meta operations, structural Type operations, and rewrite registration. |
| `clibc.x`, `cmath.x` | C prototypes for compile-time calls and Var unboxing. |
| `lib.x` | DisjointSet utility. |

`docs/library-manifest.txt` records visibility. `lib/Makefile` records the
prelude and optional sources; it generates `lib/x2c.x`. See RT-6 and AR-9.
