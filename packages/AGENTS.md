# Packages (`packages/`)

Use the [agent directory](../agents/README.md) for task routing and the
[root instructions](../AGENTS.md) for publication. The book in `docs/`
describes x2c syntax and semantics; verify relevant behavior in source,
tests, or a focused probe.

## Start from applications

`pcre2/` and `yyjson/` are accepted packages. Start with
[parse-log.x](pcre2/examples/parse-log.x) for copied captures, indexing, and
native cleanup beside acquisition, and
[service-health.x](yyjson/examples/service-health.x) for JSON through ordinary
Map/Array values. Their broader applications, clients, tests, and READMEs
show how the same integration handles substantial work while keeping native
allocation, buffer growth, status dispatch, and cleanup out of common tasks.

`libcurl/`, `termbox2/`, `blis/`, `libuv/`, and `raylib/` are importable and
included in `make packages-check`, but await Gary's application review.
They are reasonable designs to extend; acceptance and package status changes
require Gary's review of the developer experience.

A package supplies both an ordinary x2c surface and the complete pinned raw C
API for its admitted build profile. Preserve upstream types, constants,
callbacks, options, statuses, and operations under their real names. Keep one
obvious ordinary starting path, with coherent advanced operations accessible
without recreating native handles.

For a new package or a completeness review, identify the ordinary tasks a
developer brings to that kind of library before inspecting the client.
Choose tasks for the library kind rather than copying another library's
list. Gary approves or edits the list. Run a probe for each row through the
imported x2c surface; a task requiring the raw API or a hand-written lower-level
loop remains a gap in the ordinary surface. Describe the raw escape hatch for
work outside that list.

Write the intended applications before implementing a new client:

- A screen-sized application does one useful task and makes its result more
  prominent than setup. It can rely on documented caller obligations.
- A broader application, where useful, exercises coherent operations over
  real data, including ownership, absence, errors, and cleanup. Exhaustive
  malformed-input and failure combinations belong in tests.

Compile proposed constructs or reduce them to focused probes. Improve the
short application before expanding the surface, using values, iteration,
indexing, protocols, and operators where they remove work without changing
meaning. New macros and wrapper types should make the application clearer.
Keep native concepts visible instead of introducing an unrelated framework.
Public methods serve ordinary or recognizable advanced use, rather than
exposing bookkeeping solely for tests. Migrate an unaccepted example instead
of retaining competing compatibility APIs for it.

Present the short running application first and the broader application next.
Gary accepts the developer experience before a new package claims completion
or publication readiness. For an already accepted package, preserve public
compatibility unless the requested change authorizes otherwise.

## Imports and public headers

A package's entry unit is `src/<name>.x`. Tests and examples are ordinary
consumers: `import "<name>"` reaches public names as `<name>__*` and links the
built archive.

Adopt a protocol only when the package defines the protocol or a participant.
An ordinary `protocol Var(T)` adoption registers the tag derived from `T`.
If a package alias defines `T.var(T)` but boxes as `List` or `Map`, declare
`protocol Var(T) as List` or `protocol Var(T) as Map` so native `Func` checks
expect the actual tag. That shared-tag form registers no descriptor for `T`.
An alias inheriting `List.var` or `Map.var` needs no adoption.

Publish raw headers in the package's `src/`; consumers receive both `src/`
and `builds/` on their C include path. A public signature using upstream types
requires a public include: generated type definitions precede private
includes. Keep raw header names distinct from the generated unit header,
for example `yyjson-0.12.h` and `pcre2-8.h`. Package directories use `-iquote`,
so the shim's `<...>` include still reaches the real upstream header.

Use a small checked shim including the real pinned upstream header, with
build-time version/profile checks. Preserve the declarations rather than
copying them or creating forwarding functions to expose names. A wrapper over
a foreign handle publishes `object.native()` for raw operations on that same
handle; this requirement applies to package wrappers, not x2c objects in
general.

## Representations and lifetimes

Identify native pointer/length pairs, growing buffers, allocation/release,
borrowed storage and invalidation, reused handles, status/absence, callbacks
and their threads, global or thread-local state, binary data, and distinctions
an x2c collection would erase. For each, state whether the x2c path copies,
borrows, retains an owner, exposes raw access, or rejects conversion.

Choose existing x2c facilities according to their documented meaning:

- `String` for canonical NUL-terminated text; `Bytes` or a native span for
  binary data.
- `List` for immutable sequences and small fixed records; `Array` for mutable
  indexed values; `Map` when unique keys and unordered lookup fit the data.
- Indexing for real keyed or positional access, and iteration with a stable
  lifetime and exhaustion behavior.
- `defer` beside native acquisition; Scope for x2c allocations, with the
  native release function still responsible for native resources.
- Error for failures; ordinary results for expected absence, kept distinct
  from a present Null value where both are possible.

The existing packages illustrate two different lifetime choices:

- PCRE2 reuses match data. `Regexp` owns compiled code, match data, and match
  context; `defer regexp.free()` releases native storage. Results copy capture
  text, names, and offsets into immutable x2c values, so a later match cannot
  alter them. The client supports named/numbered indexing and iteration,
  advances zero-length global matches, grows replacement output internally,
  and preserves native error codes and messages. Binary subjects and other
  advanced native operations remain available on the raw API.
- yyjson's `JsonDocument` owns the native graph; `JsonValue`, `JsonArray`,
  `JsonObject`, and `JsonMember` borrow it. Document iteration preserves order,
  duplicate names, and signed/unsigned/real distinctions. Freeing the document
  invalidates views; stale access raises `<bad-state>`. `to_x2c` and
  `Json.parse` explicitly accept ordinary Map/Array semantics. Embedded NUL
  survives in a native document and serialization, while conversion to String
  raises `<bad-enc>`.

Copy or retain a separate native owner when a later call would invalidate a
result. Prefer owned documents and borrowed views when copying would lose
semantics or impose the wrong cost. Make lossy conversion explicit, keep a
binary/native path for values outside String's domain, and document handle
non-reentrancy instead of implying concurrent safety.

Trust documented caller obligations. A borrowed `Bytes`, view, or pointer
needs an owner and invalidation rule, not an extra copy solely because its
type can mutate or free storage. Validate external values and representation
changes where they enter; subsequent code can rely on that result until a
later operation invalidates it. Operators creating native resources must give
intermediate results automatic cleanup as well as concise syntax.

## Errors, callbacks, and Lisp

Errors preserve the native operation, code, message, and useful location or
offset. A shared raising helper takes its caller's operation name. Expected
no-match, exhaustion, missing-key, and "no event yet" results remain ordinary
outcomes where the upstream API defines them that way.

Catch x2c Errors inside C callbacks, copy or snapshot what must survive, and
report them after control returns safely to x2c. Errors must not unwind
through C library callbacks. Verify which thread invokes each callback;
entering x2c from an arbitrary worker thread requires a specifically proven
runtime guarantee. Copy borrowed callback data that must escape, and make
callback-only objects invalid or unavailable outside the callback.

When useful value-oriented Lisp operations exist, ship them inside the
package behind one public installer. `RegexpLisp.install(Lisp)` and
`JsonLisp.install(Lisp)` demonstrate `$lisp.binding` and `$lisp.install` groups
that survive archive linking and work for an import-only consumer. Bindings
use values Lisp can consume; keep opaque native objects on the x2c/raw path.
Probe actual inspection and traversal of returned collections, not just a
parse/stringify round trip. Supply readers when Lisp cannot walk the returned
collection directly.

## Tests and supported releases

Cover the applications' paths, ownership, promised idempotent release and
stale access, absence versus Error versus Null, boundary sizes/growth,
embedded NUL/binary data, empty/duplicate iteration and indexing, native error
details, and deliberate conversion loss as applicable. Tests need not defend
against explicitly forbidden caller actions; keep test-only helpers private.

Assert the observable effect before another operation can erase it; for
example inspect pretty-printed file bytes before reparsing. The raw test calls
representative declarations directly through the real header, without
repeating upstream's test suite.

Run package builds, tests, applications, and profile/header verification.
`make packages-check` combines these for the current packages. It needs a
prepared dependency cache and stays optional, outside `check`, `precommit`,
and `agent-pr-check`. It is useful after compiler/runtime changes reaching
package clients. Follow the root instructions for repository-wide validation.

The package `test` target builds only `tests/test-*.x`, so each package also
has `run` for applications. Packages with Lisp installers add `run-lisp`;
those without them do not. The current combined check runs all three for
pcre2, yyjson, and libcurl, `test run` for termbox2, blis, and libuv, and
raylib's `verify` target for headers, application, tests, and rendered PNGs.

A supported release additionally supplies the small public interface,
complete pinned raw header, importable archive and generated header, link
flags, reproducible native profile, installation/use instructions, license
notices, README, book coverage, root package index, and checked consumer
commands. Demonstrate ownership, borrowed views, callback/thread entry,
cleanup, errors, text/numbers, and conversion behavior in the applications.
Ship a Lisp installer where useful, otherwise explain why native objects
remain on the x2c/raw path. Record the upstream version/URL, source archive
and public-header hashes, compile-time options/disabled features, linkage,
dependencies/frameworks, licenses/notices, and foreign-declaration limitations.

Accepted packages currently claim macOS; `make packages-check` on macOS
supplies that platform evidence. Additional platforms and the packages chosen
for a release are separate decisions.

## Dependencies and generated files

Keep client source, examples/tests, a small header shim, the dependency
manifest/build recipe, required licenses/notices, and reviewed source fixtures
in Git. Keep upstream trees/archives, installed prefixes, object files,
static libraries, and generated research inventories in the dependency cache.
A compact reviewed research summary belongs in Git only when useful.

`packages/tools/deps.py` owns the shared cache. `X2C_DEPS_DIR` selects it
explicitly; the default is
`$(git rev-parse --path-format=absolute --git-common-dir)/x2c-integrations`.
A user-level cache may share builds between clones.

Cache entries are keyed by version, admitted profile, host/target, compiler
identity, and manifest hash. Prepare in a temporary directory, verify source
and license hashes, atomically rename the completed prefix, and write a
completion stamp. Concurrent worktrees use a per-key lock or reuse an already
completed identical entry.

Each package sets `PACKAGE` and includes `package.mk`, which uses
`dependency.mk` when applicable. `prepare` refreshes the ignored `deps`
symlink; ordinary `test` and `run` reuse the matching entry without network or
rebuilding dependencies. `make -C packages prepare-checked` prepares the
packages named by `make packages-check`.

Generated C, headers, executables, and application outputs stay in ignored
`builds/`. `clean` removes local products and `deps`, leaving the cache intact.
`build` translates `src/*.x` in package mode into unit headers and objects,
compiles any package-authored `src/*.c`, and creates `builds/lib<package>.a`.
`builds/<package>.link` holds the additional consumer link flags (empty without
native dependencies). Tests/examples import and link the archive.

Reuse this machinery; change `dependency.json` for pin/profile changes. Use a
package-specific prefix override only for narrow diagnosis.
