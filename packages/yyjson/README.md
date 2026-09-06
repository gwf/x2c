# yyjson client

This package provides an x2c interface to yyjson 0.12.0. It is an importable
package: `src/yyjson.x` is its entry unit, every public name compiles to
`yyjson__*`, and a program reaches it through an alias. The short application
and Lisp bindings use ordinary x2c `Map` and `Array` values. The parallel
`JsonDocument` path keeps yyjson's data model intact: its `JsonValue`,
`JsonArray`, `JsonObject`, and `JsonMember` views preserve object order,
duplicate keys, and signed, unsigned, or real numeric intent.

```x2c
import "yyjson" as json;

int main(void) {
  Scope.retain();
  defer Scope.release();

  json.JsonDocument document =
    json.JsonDocument.read_file(%"releases.json");
  defer document.free();
  json.JsonObject root = document.root().object();

  foreach(json.JsonValue item, root[%"releases"].array()) {
    json.JsonObject release = item.object();
    printf("%s\n", release[%"version"].string());
  }

  foreach(json.JsonMember member, root[%"labels"].object())
    printf("%s=%s\n", member.key(), member.value().string());
  return 0;
}
```

Build the package once with `make build`, then compile a consumer with
`--package-dir <packages>` and `--c-system-dir <prefix>/include`; the driver
adds the package's `builds` and `src` directories and links
`builds/libyyjson.a`. `src/yyjson-0.12.h` stays public because the options
methods take yyjson's own flag types, so a caller that wants the raw API can
include it directly.

`object[key]` returns the first matching member. `object.all(key)` returns all
matching values in document order, and object iteration yields every
`JsonMember`, including duplicate names. Array indexing supports negative
indices, and array iteration yields borrowed `JsonValue` views. Missing
members return NULL; `object.require(key)` instead raises `<bad-arg>` carrying
the missing key when the member is required.

The document owns every view. `JsonDocument.free` releases yyjson's native
storage and is idempotent; using an older view afterwards raises
`<bad-state>`. The small x2c view records belong to the active `Scope` and do
not need individual cleanup. `JsonDocument.patch` applies RFC 6902 to a copy
and returns another owned document. Document and value writers return
canonical x2c `String` values without caller-managed buffers.

## Explicit x2c-value conversion

`document.to_x2c()` and `value.to_x2c()` deliberately cross into ordinary
x2c values: objects become `Map`, arrays become `Array`, strings become
`String`, and integers retain yyjson's signed or unsigned representation.
This conversion loses duplicate object keys and insertion order because
`Map` owns different semantics.

`Json.parse` remains the concise conversion-first spelling for callers that
want those x2c collection semantics immediately. `Var` values use
`value.json()`, `value.pretty_json()`, `value.json_pointer()`,
`value.json_patch()`, and `value.json_merge_patch()`. `Json.stringify_opts`
retains the explicit write-flags path. JSON booleans use
`<yyjson--bo>` so they stay distinct from the numbers 1 and 0.

A document can preserve and re-emit a JSON string containing NUL. Converting
that string to x2c `String`, directly or through `to_x2c`, raises `<bad-enc>`
because x2c Strings exclude embedded NUL. In-situ parsing remains a raw-only
operation because it would mutate a canonical x2c String.

## Files

Both paths read and write files, and the choice between them is the same one
as for text. `JsonDocument.read_file` and `JsonDocument.write_file` keep
object order, duplicate names, and numeric intent, and they hand the bytes
straight to yyjson, so content an x2c `String` could not hold still parses.
`Json.read_file` and `Json.write_file` are the converting pair: they return
and accept ordinary x2c values and lose exactly what `to_x2c` loses.

Each has an `_opts` form taking yyjson's own read or write flags, so the
indented form is `write_file_opts(path, YYJSON_WRITE_PRETTY_TWO_SPACES)`
rather than a separate method. A missing file, an unreadable file, and
malformed content all arrive as `<malformed>` carrying yyjson's code,
message, and byte offset.

## Lisp

`JsonLisp.install(lisp)` adds `json-parse`, `json-stringify`, `json-pretty`,
`json-read-file`, `json-write-file`, `json-pointer`, `json-null?`, `json-len`,
`json-keys`, and `json-list` to a ready Lisp session. The bindings ship with
the package, so importing it is enough.

The Lisp surface uses the converting path rather than `JsonDocument`, so no
borrowed view can outlive the document behind it. The cost is the documented
one: object order, duplicate names, and the signed/unsigned/real distinction
do not survive.

JSON false crosses as Lisp nil, so it behaves correctly in `if` and `cond`.
JSON null is a distinct package value recognized by `json-null?`, and a
missing JSON Pointer returns Lisp nil. The write bindings reverse those
conversions, so parsed false and null values round-trip. Because Lisp nil is
also the empty List, `json-stringify` treats nil as false; keep an empty JSON
array in its parsed `Array` form when it must round-trip as `[]`.

Those values are `Map` and `Array`, which Lisp's own `car`, `cdr`, and
`length` do not accept. `json-len` and `json-keys` read them in place, and
`json-list` crosses an array into the `List` that Lisp does operate on, so
reshaping happens in Lisp and `json-stringify` takes the result back.

`examples/inline-lisp.x` (`make lisp-example`) drives that surface.

## Examples

`examples/service-health.x` is the short application (`make short-example`).
In 24 lines it reads `examples/services.json`, walks the services, prints
which are down, and writes the list of failures back out as JSON. It is the
shape most first uses of a JSON library take.

`examples/release-catalog.x` (`make example`) parses one release catalog,
indexes and iterates borrowed views, aggregates exact
unsigned values, observes duplicate ordered labels, applies a JSON Patch,
and writes the resulting document. It contains no native allocation, byte
pointers, manual buffers, yyjson callbacks, or status handling.

## Native API

`src/yyjson-0.12.h` includes the real upstream header and rejects a different
yyjson release. It exposes the complete pinned surface directly, with no
copied declarations, forwarding bodies, renamed aliases, or generated method
walls. Use it for custom allocators, incremental reading, in-situ parsing,
mutable native documents, file and stream I/O, and other advanced yyjson
facilities.

`document.native()` returns the borrowed `yyjson_doc *`, and
`value.native()` returns the borrowed `yyjson_val *`. Both expire when the
owning `JsonDocument` is freed; the value pointer remains owned by that
document and must not be freed separately.

x2c preserves imported C qualifiers and rejects conversions that silently
drop them. Raw callers must retain the upstream header's `const` qualifiers.
[Foreign C qualifiers](../FOREIGN-C-QUALIFIERS.md) describes the compiler
behavior and its earlier limitation.

## Build and test

`make prepare` downloads, verifies, and builds yyjson 0.12.0 in the shared
dependency cache. `make run` and `make test` prepare it automatically when
absent and reuse it when present. Set `X2C_DEPS_DIR` to move the shared cache,
or set `YYJSON_PREFIX` to diagnose another compatible installation.

```sh
make verify-headers
make run
make test
```

The client, tests, and example are licensed under
[Apache-2.0](../../LICENSE).
yyjson retains the MIT terms reproduced under `LICENSES/`. The dependency is
admitted under the policy in `../LICENSE-POLICY.md`.
