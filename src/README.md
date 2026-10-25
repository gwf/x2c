# Reading the compiler

This directory contains the x2c compiler and its native build driver. The
compiler reads x2c source, resolves its meaning, lowers the added language
features, and writes C. The driver can then compile and link that C.

If you are new to the implementation, start with [main.x](main.x), then
[frontend.x](frontend.x). Follow a small source program through collection,
parsing, transformation, and generation. You do not need to read every module
before following one feature.

## How the files fit together

A self-contained unit is one `.x` file at this level. A split module keeps its
entry and members together, for example:

```text
compiler/
  README.md
  compiler.x
  lifecycle.x
  parsing/
    README.md
    parsing.x
    tokens.x
    ...
```

Callers include the entry explicitly: `#include "compiler/compiler.x"`.
The entry's `module { ... }` block lists members relative to that entry.
Members share one translation unit; nested entries remain part of that same
unit. The [module-block reference](../docs/src/reference/language.md#module-blocks)
explains visibility and member paths.

The compiler build discovers split modules by the path `src/name/name.x`.
This is a repository build convention; include directives still name files
explicitly. Nested members are compiled through their parent entry, not as
separate units.

The [components directory](components/README.md) is different. Its files are
independent units that implement shipped syntax rules and enter the compiler's
prelude. They are not members of one `components.x` file.

## Follow a compilation

1. [main.x](main.x) dispatches a [CLI request](cli/README.md). A
   [project manifest](project/README.md) can produce the same request type.
2. [translation.x](translation.x) coordinates source translation and workers.
   [frontend.x](frontend.x) opens configured source units.
3. [Collect](collect/README.md) reads the prelude, includes, packages, and module
   members. It collects declarations or replays valid cached interfaces.
4. [Compiler parsing](compiler/parsing/README.md) drives the full parse.
   [Parse](parse/README.md), [statements.x](statements.x), and
   [expressions](expressions/README.md) bind and type individual forms.
5. [Transform](transform/README.md) lowers typed forms through the shipped
   [components](components/README.md). [Cleanup](cleanup/README.md) inserts
   cleanup on control transfers; [regions](regions/README.md) analyzes lifetimes.
6. [Generate](generate/README.md) separates headers and sources.
   [Emit](emit/README.md) produces C tokens and [format.x](format.x) prints them.
7. The [build command](../commands/build/build.x) uses [toolchain.x](toolchain.x)
   to compile and link native output.

Compile-time execution crosses these phases. [Macros](macros/README.md)
construct syntax that returns through ordinary binding. [meta-project.x](meta-project.x)
builds a helper for a project's meta functions; compiler-owned meta code is
linked into the compiler itself.

## Driver and source access

| File or module | Responsibility |
| --- | --- |
| [main.x](main.x) | Command dispatch and process entry. |
| [cli/](cli/README.md) | Arguments, response files, typed requests, and help. |
| [project/](project/README.md) | Manifest parsing, target selection, source expansion, and ordered build plans. |
| [translation.x](translation.x) | Translation requests, workers, and generated output coordination. |
| [frontend.x](frontend.x) | Configured compiler sessions, source units, collection, and parsing. |
| [toolchain.x](toolchain.x) | Host preprocessing, compilation, archiving, and linking. |
| [utils.x](utils.x) | Compiler/home/package discovery, identities, file locks, and worker utilities. |
| [sourceview.x](sourceview.x) | Request-owned source access and unsaved editor overlays. |
| [report.x](report.x) | Command progress and completion receipts on stderr. |
| [diagnostics.x](diagnostics.x) | Diagnostic storage, source rendering, and report output. |
| [deps.x](deps.x) | Make dependency files for translated units. |

## Parsing and meaning

| File or module | Responsibility |
| --- | --- |
| [compiler/](compiler/README.md) | Translation state, parsing orchestration, declaration production, names, origins, and cached literals. |
| [collect/](collect/README.md) | Source/include walks, module splicing, packages, and declaration/interface caches. |
| [preprocess.x](preprocess.x) | The directives and conditional arms x2c interprets without running the host preprocessor. |
| [parse/](parse/README.md) | Declaration/type/function grammar and binding of constructed syntax. |
| [parse-reports.x](parse-reports.x) | Package, binding, and alias diagnostics. |
| [statements.x](statements.x) | Statement grammar and return checking. |
| [expressions/](expressions/README.md) | Expression grammar, name/member/call resolution, operators, and conversions. |
| [expressions-reports.x](expressions-reports.x) | Expression typing diagnostics. |
| [initializers/](initializers/README.md) | Brace initializer destinations and value conversion. |
| [literals/](literals/README.md) | Scalar, quoted List, interpolated String, collection, and exception-payload syntax. |
| [lambdas.x](lambdas.x) | Lambda parsing and capture resolution. |
| [symtab/symtab.x](symtab/symtab.x) | Scoped semantic symbol tables and binding identities. |
| [type.x](type.x) | Semantic types and per-unit Var registrations; structural operations live in lib/type.x. |
| [type-ledger.x](type-ledger.x) | Compiler tables projected from the runtime's Var tag ledger. |
| [protocol/](protocol/README.md) | Protocol declarations, conformance resolution, and preparation for adapter generation. |
| [operator-ledger.x](operator-ledger.x) | Operator precedence, compound assignments, and protocol-member mappings. |

## Macros and compile-time execution

| File or module | Responsibility |
| --- | --- |
| [macros/](macros/README.md) | Definitions, invocation captures, expansion, quotations, compile-time call slots, and rewrites. |
| [meta-sdk/](meta-sdk/README.md) | Compiler operations exposed to compile-time code through lib/meta.x. |
| [meta-native/](meta-native/README.md) | The unit's native meta binding table, calls, loaded modules, and compiler-linked definitions. |
| [meta-group/](meta-group/README.md) | Selection, emission, staging, and loading of a unit's compile-time code. |
| [meta-project.x](meta-project.x) | Builds and caches a project's native meta helper. |
| [meta-helper-client.x](meta-helper-client.x) | Starts that helper, exchanges calls and queries, and handles failures. |
| [stage.x](stage.x) | Converts arguments and results across the compile-time/runtime boundary. |
| [builtins.x](builtins.x) | Native algorithms used by built-in macros. |
| [linked-meta.x](linked-meta.x) | Generated copies of shipped meta definitions; regenerated by tools/gen-linked-meta.sh. |

## Lowering and C output

| File or module | Responsibility |
| --- | --- |
| [components/](components/README.md) | Shipped rules for language features such as matching, lambdas, exceptions, and dynamic operators. |
| [transform/](transform/README.md) | Normalizes typed forms and applies lowering rules. |
| [regions/](regions/README.md) | Analyzes storage lifetimes before lowering. |
| [cleanup/](cleanup/README.md) | Places cleanup on exits and preserves storage across exception landings. |
| [callables/](callables/README.md) | Function values, Func adapters, and native callback conversions. |
| [adapter-memo.x](adapter-memo.x) | Reuses generated callable adapters. |
| [cache.x](cache.x) | Materializes cached literals and deferred static initialization. |
| [generate/](generate/README.md) | Header/source partitioning, declaration order, initialization, and file publication. |
| [emit/](emit/README.md) | Emits C tokens from normalized AST forms. |
| [format.x](format.x) | Formats token lists as readable or compact C. |
| [ast.x](ast.x) | Shared operations on AST nodes represented by Lists. |
| [ast-rewrite.x](ast-rewrite.x) | Traverses and rewrites immediate AST children. |
| [grammar.x](grammar.x) | Source-form templates and accessors used by lowering rules. |
| [fields.x](fields.x) | Helpers that construct statements to copy or set named fields. |

## Working examples and further reading

The [language tour](../examples/tours/language.x) is a smaller introduction to
the language used here. The [implementation map](../docs/src/internals/implementation-map.md)
connects language features to their owners. The [architecture chapter](../docs/src/internals/architecture.md)
explains the phases in more detail.

Compiler behavior is exercised by [phase fixtures](../unittest/compiler-fixtures/)
and [focused probes](../unittest/probes/). The [build guide](../docs/src/internals/building.md)
explains bootstrap and self-hosted stages. Generated bootstrap C belongs in
`bootstrap/`; edit these `.x` sources and regenerate it through the build.
