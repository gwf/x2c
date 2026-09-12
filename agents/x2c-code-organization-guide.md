# x2c Code Organization Guide

This guide describes the current module boundaries. Mechanical formatting
rules remain in `agents/x2c-coding-style-guide.md`.

## One owner per concern

Put a contract where it can be enforced completely and let downstream code
rely on it. A module should expose a small public surface above
`#pragma private`; its implementation and private dependencies belong below
that boundary. Include collection resolves includes itself and terminates cycles on its own,
so tests, examples, packages, and user programs omit `#pragma once` unless
their own `.x` includes form a cycle. Generated headers receive their own
compiler-owned `#pragma once` automatically.

```c
#pragma once
#include "common.x"

/* public types and functions */

#pragma private
#include <stdlib.h>

/* implementation */
```

Do not create a new helper file solely to shorten an existing coherent module.
Split a module only when the new file has a distinct owner, dependency
direction, and test surface.

Within a coherent module, put state-bearing private helpers on their dominant
implicit-class receiver. Keep stateless helpers free. This makes ownership
visible without creating a wrapper type or another module. Prefer one typed
metadata ledger per existing owner over parallel switches or a cross-module
registry.

Reserve non-static `x2c_*` functions for the intentional C interface used by
generated code, native callers, or process-wide setup. Ordinary public x2c
operations use type methods. Private helpers are `static`; an `x2c_*` spelling
below `#pragma private` still leaks into generated headers.

## Compiler organization

The compiler is consolidated by phase rather than filename prefixes:

- entry and shared state: `main.x`, `cli.x`, `compiler.x`, `diagnostics.x`,
  `collect.x`, `report.x`, `snapshot.x`, `deps.x`, `utils.x`;
- shared runtime tokenization: `lib/tokenizer.x`; compiler parsing:
  `parse.x`, `expressions.x`, `statements.x`, `literals.x`, `macros.x`,
  `ast.x`;
- semantic representation and lowering: `type.x`, `protocol.x`,
  `transform.x`, `lambda.x`;
- output: `cache.x`, `generate.x`, `emit.x`, `format.x`;
- native and project driver: `build.x`, `project.x`, `toolchain.x`,
  `bootstrap.x`.

Runtime modules never depend on compiler modules. Parser modules produce the
annotated AST consumed by transforms; transforms produce the normalized AST
consumed by generation and emission. Cross-phase helpers belong to the phase
that establishes their contract, not the first caller that happens to need
them.

Compiler phase state may use mutable storage internally even when its output
is an immutable List. Compiler scope and brace stacks and initialization
queues use Arrays; Diagnostics stores chronological entries in an Array and
returns a List snapshot; Emitter owns typed cleanup records. Convert at the
phase boundary rather than maintaining two live representations.

When adding compiler behavior:

1. identify the phase that owns its invariant;
2. add the smallest implementation at that owner;
3. prove the phase boundary with an exact compiler fixture when representation
   or diagnostics matter;
4. use runtime unit tests when the behavior belongs to a library owner;
5. update the philosophy ledger if contract status changes.

## Runtime organization

Runtime files are capability owners, not a hierarchy of wrappers:

```text
common, scope, pool           shared representation, lifetime, interning
var, varconvert, varops       tagged values, conversions, operations
dispatch, protocols           dynamic behavior and protocol adoption
string, string-classify,      canonical immutable values, string
string-number, split,         classification, numeric parsing, splitting,
symbol, symbolset, atom, list and closed vocabularies
block, buffer, array, map     mutable storage and builders
iter, match, machine          traversal, pattern matching, and the shared
                              wordcode machine
error, error_init, exception  ambient errors and structured control flow
file, logger                  system boundaries
context, thread, thread-state bounded runtime state, native workers, and
mutex                         their coordination primitive
scan, tokenizer               lexical scanners and the shared tokenizer
func, lisp                    native callable binding and embedded Lisp
lib                           DisjointSet utility
```

Five more modules ship with the runtime but stay out of the implicit prelude,
so a client names one in an explicit include:

```text
typed-array                   packed numeric storage with a native bracket
typed-list                    typed views over canonical List cells
typed-map                     native numeric and canonical String maps
list-selectors                compound List selectors past caddr
match-recursive               readable recursive Match reference
```

`docs/library-manifest.txt` is the owner of that split and of every module's
visibility in the generated library reference; `lib/Makefile` builds the same
five from `OPTIONAL_SOURCES`.

`lib/x2c.x` is generated from the standard modules by `lib/Makefile`. Never
edit it by hand. `.xmacro` files beside the modules own shared macro
definitions (ledgers, adapters, result-flow forms); each is imported by the
modules that consume it and is a module kind of its own, not a header.

Status-bearing operations should own recoverable failure. Convenience
adapters may fail fast, but they should delegate rather than duplicate the
owner's mutation logic. Canonical values should be established once by their
constructor or interning boundary.

The checked compiler symbol snapshot is part of the runtime organization
contract. A private-looking runtime struct field, typedef, or helper can still
be observable there. Representation cleanup that changes that ledger requires
an explicit snapshot transition; do not disguise it as an internal-only edit.

## Dependencies and includes

- Include only the public modules required by the public declarations above
  `#pragma private`.
- Put private standard-library and sibling includes below `#pragma private`.
- Prefer forward declarations when they preserve a clean ownership boundary.
- Avoid compiler-to-runtime callbacks that make a runtime module aware of AST
  or code-generation details.
- Treat generated `.c`, `.h`, dependency files, and `lib/x2c.x` as build
  artifacts, not source.

## Tests, docs, and plans

Runtime suites are in `unittest/test-<feature>.x`. Compiler representation,
diagnostic, and native-output contracts are in
`unittest/compiler-fixtures/`. Curated programs are in
`examples/manifest.txt`.

The generated module catalog is refreshed with `make doc-generate`; do not edit
its API inventory manually. Active plans remain under `plans/` as execution
logs. Create an archive subdirectory there for plans that are complete,
rejected, or superseded.

Before creating a module or compatibility layer, check the philosophy ledger
and current catalog. The usual correction for drift is to strengthen the
existing owner, not add another place that partially enforces the same rule.

## Adding or changing a feature

Change only the boundaries the feature actually crosses:

1. tokenizer, when new lexical structure is required;
2. one parser owner, to build a documented AST shape;
3. type owner, only when a new type fact is required;
4. transform/generate/emit owner, to lower the shape;
5. runtime owner, only when emitted C needs a new primitive;
6. the smallest fixture that proves each changed boundary;
7. unit or checked-example evidence for observable behavior.

These are contract limits, not suggestions. Do not add a downstream workaround
or describe a feature as complete without moving the owning implementation and
its proof together. A parser branch does not prove runtime support, and a
runtime helper does not make syntax supported.
