# x2c Module Maps

[The code standard](x2c-code-standard.md) owns module rules (MO), file
organization (FI), compiler boundaries (AR), and runtime ownership (RT).
These maps list the current owners. The generated
[module catalog](x2c-module-catalog.md) inventories their declarations.

## Compiler organization

[Module ownership](../docs/src/internals/architecture.md#module-ownership)
in the architecture chapter lists each compiler module and its
responsibility, including the shipped components under `src/components/`.
Report wording lives in static macros in its owner or in the shared
`src/expressions-reports.x` and `src/parse-reports.x`.

`tools/gen-linked-meta.sh` generates `src/linked-meta.x`, the shipped `meta`
code compiled into the compiler. Style censuses exclude it.

## Runtime organization

Paths below are relative to `lib/`.

| Source | Responsibility |
| --- | --- |
| `common.x`, `scope/scope.x`, `pool/pool.x` | Shared representation, allocation lifetimes, and canonical values. |
| `common-types.x` | `Var`, `List`, and `Mutex`, which the compiler prelude declares before its meta prototypes. |
| `static-init.x`, `private-keywords.x` | Static initialization and the private loop keyword. |
| `var/var.x`, `var/conversion.x`, `var/operators.x` | Tagged values, conversions, and operations. |
| `var-ledger.x`, `var-tags.x`, `var-adapters.x`, `integer-ops.x`, `native-scalar-types.x` | Tag and scalar ledgers, pointer converter templates, and raw integer arithmetic. |
| `dispatch.x`, `protocols.x`, `cleanup.x` | Dynamic behavior and protocol adoption. |
| `string/string.x` | Canonical immutable text, classification, numeric parsing, formatting, escaping, splitting, and lazy field cursors. |
| `substring.x`, `substring-map.x` | Borrowed immutable views of String bytes and a scope-owned count table keyed by them. |
| `symbol.x`, `symbolset.x`, `atom.x`, `list/list.x`, `list-selectors.x` | Closed vocabularies, canonical Lists, and optional compound List selectors. |
| `block.x`, `buffer.x`, `array/array.x`, `map/map.x` | Mutable storage and builders. |
| `array/generics.x`, `map/generics.x`, `map/grouped.x`, `typed-array.x`, `typed-map.x`, `typed-list.x` | Collection family generators, grouped Map storage, and typed views. |
| `iter.x`, `match/match.x` | Traversal, pattern matching, plan lowering and caching, and the Match wordcode machine. |
| `macrovalue/macrovalue.x`, `system-macros.x` | Macros as values and convenience macros. |
| `error/error.x`, `error_init.x`, `error-macros.x`, `error-private.x`, `func/errors.x`, `exception.x` | Ambient errors, shared causes, transfer layouts, and structured control flow. |
| `file.x`, `logger.x`, `path.x`, `process.x`, `args.x`, `scripting.x` | System boundaries, argument parsing, and script-unit includes. |
| `net.x`, `http.x` | Blocking TCP sockets backed by File streams, and HTTP/1.1 routing with a worker-pool service. |
| `derive.x`, `test.x` | Record mappings generated from declared fields, and registered tests and assertions for user programs. |
| `json.x`, `datum.x`, `datum-reader.x` | JSON and Lisp reader text. |
| `diff.x`, `digest.x`, `regex.x` | Line differences, SHA-256 digests, and regular expressions. |
| `time.x`, `random.x`, `encoding.x`, `url.x` | Clocks and calendar time, random values and UUIDs, text encodings, and URLs. |
| `context.x`, `thread.x`, `thread-state.x`, `task.x`, `channel.x`, `mutex.x` | Runtime state, native workers, cooperative task batches, communication, and coordination. |
| `scan.x`, `tokenizer.x` | Lexical scanners and the shared tokenizer. |
| `func/func.x`, `lisp/lisp.x`, `lisp-targets/lisp-targets.x`, `lisp-bindings.x` | Native callable binding, runtime Lisp, and its native operations. |
| `meta.x`, `compiler-meta.x`, `type.x`, `rewrite.x` | Public and compiler-private meta operations, structural Type operations, and rewrite registration. |
| `clibc.x`, `cmath.x` | C prototypes for compile-time calls and Var unboxing. |
| `lib.x` | DisjointSet utility. |

`docs/library-manifest.txt` records visibility. `lib/Makefile` records the
prelude and optional sources; it generates `lib/x2c.x`. See RT-6 and AR-9.
