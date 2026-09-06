# Package Guidelines

These instructions apply to everything under `packages/`. Read the root
`AGENTS.md` first. The language contract belongs in `docs/`; do not invent x2c
syntax or infer it from generated C.

## Current status

Two packages are accepted:

- `pcre2/`
- `yyjson/`

Five more are importable packages that have been through the whole method in
`plans/archive/package-completion.md` — an ordinary-task list with every row
answered by probe, their applications, and an entry in `make packages-check` —
and are waiting on Gary's review of their applications:

- `libcurl/`, `termbox2/`, `blis/`, `libuv/`, `raylib/`

Those five are reasonable designs to read and to extend. They are not
accepted, and only Gary's review of the developer-facing application makes
them so; compilation, symbol counts, a raw-header test, or an agent-authored
plan status cannot. Do not change a package's status here yourself.

## Read before designing

Follow the root `AGENTS.md` task routing, then read only the book chapters for
the language and runtime crossings the package actually uses. Verify each
relevant behavior in current source, tests, or a focused probe.

Read the accepted PCRE2 and yyjson applications first, then their client
source, tests, READMEs, and archived reference-client plans. Compare the
application against its equivalent raw C responsibilities. The five packages
awaiting review are reasonable designs to read and extend, but they are not
accepted examples. The rejected libevent client is preserved only as history
in `plans/archive/libevent-reference-client.md`; do not inherit its API shape.

## What a package is

A good x2c package has two surfaces at the same time:

1. The pinned upstream C API remains available under its real names as the
   raw API. Advanced callers can still use its types, constants,
   callbacks, options, status values, and operations.
2. Ordinary use crosses into the parts of x2c that make the application
   shorter and clearer: `String`, `List`, `Array`, `Map`, typed methods,
   indexing, iteration, protocols, `defer`, Scope, and structured Error where
   each fits.

Neither surface substitutes for the other. A raw header proves callability,
not usability. One large wrapper that hides the native library behind an
unrelated object is also not a package. Preserve the library's concepts
and semantics while removing pointer, buffer, callback, status, and cleanup
boilerplate from its common path.

The application decides whether this worked. A normal application should not
need native allocation, pointer-and-length pairs, output-buffer growth,
callback casts, repeated numeric status dispatch, or cleanup detached from
the acquisition it releases.

## Write the ordinary-task list first

Before reading a line of the client, write down ten to fifteen tasks a working
developer brings to this kind of library. Then check each one: can it be done
through the imported surface, using x2c values, without including the vendored
header and without hand-rolling a loop over a lower operation. A task fails
when the honest answer is "call the raw API" or "write it yourself".

Completeness is not API coverage. PCRE2 has hundreds of entry points and four
new methods closed its list; yyjson needed two. What matters is that the list
is answered and that everything not on it is reachable through the raw escape
hatch and said to be.

The rows are per library kind, not per package. PCRE2's thirteen and yyjson's
eleven share no entry. What transfers to the next library is the method, not
the rows; `plans/archive/package-completeness.md` keeps both lists as worked
examples.
The list is the deliverable Gary approves or edits, and it is what makes a
completeness claim checkable a year later.

## Prove each row by probe

Answer every row by running code, never by reading the client. An audit of
PCRE2 read the source and reported caseless, multiline, and anchored matching
as unreachable. A twelve-line probe showed all three already work:
`Regexp.compile` and `Regexp.match_from` take a raw options word, and
`import "pcre2"` brings the `PCRE2_*` constants with it. Four redundant
methods were nearly written to close a gap that did not exist.

A probe must exercise the value the way its destination will, not merely hand
it back. The yyjson Lisp design passed a `json-parse` into `json-stringify`
round trip and looked proved, yet a Lisp program still could not touch the
value in between: a parsed array arrives as an x2c `Array` and an object as a
`Map`, and Lisp's `car`, `cdr`, and `length` accept neither. `json-len`,
`json-keys`, and `json-list` had to be added after the design was settled.
Round-tripping a value through the path that produced it proves that the path
is symmetric and nothing else.

## Package boundary

A package is imported, not included. Its entry unit is `src/<name>.x`, so
`import "<name>"` reaches every public name as `<name>__*`, and its own tests
and examples are ordinary consumers of that surface. Three rules follow.

Adopt a protocol only for a protocol or a participant the package defines.
Two packages adopting the same foreign pair for one program is a conflict
nobody owns, and the compiler cannot always see it. An ordinary
`protocol Var(T)` adoption registers a descriptor under the tag derived from
`T`. If a package-defined alias has its own `T.var(T)` converter but actually
boxes as `List` or `Map`, declare `protocol Var(T) as List` or
`protocol Var(T) as Map` so native `Func` checks expect the tag the converter
writes. This shared-tag form registers no descriptor for `T`. An alias that
relies on inherited `List.var` or `Map.var` already boxes under the inherited
tag and needs no adoption.

A package may publish the vendored header as its raw API, and that
header must be in the package's `src/`. A consumer build puts both
`builds/` and `src/` on its C include path, so a published header resolves
with no extra flag. Publishing is required when a public method takes one of
the library's own types: generated C hoists type definitions above the
private include block, so a private struct over a foreign type does not
compile with that include below `#pragma private` at all.

The generated header for a unit is named after the unit. A package named
`json` produces `json.h` and therefore must not also publish a vendored
`json.h`. Keep the pinned versioned spelling (`yyjson-0.12.h`, `pcre2-8.h`).
The vendored header's own `<...>` include of the real upstream name still
resolves, because consumers receive package directories with `-iquote`.

## Begin with the examples

The examples must show both halves of the x2c claim: simple things stay
simple, and the same integration continues into substantial work. A package
that aspires to a broad ordinary API normally has both:

- one short application that fits comfortably on one screen, does one useful
  thing, and makes x2c look lightweight; and
- one broader application that exercises more of the library's operations,
  ownership, results, and failure behavior.

The short application is not an API inventory or a walk through test fixtures.
It may rely on documented caller obligations and leave exhaustive malformed,
limit, cleanup, and native-failure cases to the tests. Its source should make
the useful result more prominent than setup or integration machinery.

The broader application may try a large coherent part of the ordinary
surface. It must still perform a task rather than merely enumerate success,
absence, and error outcomes. Breadth is welcome when the small path does not
pay for it.

Write the intended applications before implementing the client. Together
they must do enough real work to expose a shallow design:

- process a collection rather than make one trivial call;
- exercise the library's defining operations;
- use x2c iteration, indexing, values, lifetime, or errors where they remove
  real boilerplate;
- include absence, failure, and cleanup paths; and
- remain recognizably an application of the upstream library.

Compile every proposed x2c construct or reduce it to a focused probe. The
application is not pseudocode, and unsupported syntax is not a design.

Implement the smallest clear path first. Inspect the short application before
expanding the ordinary surface, then add coherent breadth without making that
path more complicated. If either application still reads like C with an `.x`
filename, revise the boundary first. Do not generate broad declarations while
the ordinary path is still wrong.

One ordinary starting path must be obvious. Multiple layers are useful when
they serve different needs, but two builders or spellings that compete for
the same operation leave the package unfinished. Do not preserve a
second compatibility API merely to keep an unaccepted example compiling;
migrate the example or leave that rejected path out of the checkpoint.

The public surface is not limited to methods used by the short application.
Every public method must nevertheless belong to a coherent ordinary layer, a
broader application, or a recognizable advanced operation. Tests do not
justify public queries that only expose wrapper bookkeeping; use private
helpers or the raw upstream API for those checks.

Present the short running application first, followed by the broader
application. Gary accepts or rejects the developer experience before the
package claims completion or publication readiness.

## Find the real crossings

Before designing types, make a concrete inventory of what a native caller
must manage:

- pointer plus length pairs;
- caller-sized or growing buffers;
- allocation and release functions;
- borrowed pointers and their invalidation points;
- handles whose operations reuse internal storage;
- status codes, expected absence, and actual failures;
- callbacks, callback state, and callback thread;
- process-global or thread-local state;
- strings or byte sequences outside x2c String's domain; and
- native data distinctions that an x2c collection would erase.

For each item, decide who owns it in the x2c path. State whether the client
copies it, borrows it, retains an owner for it, exposes it raw, or rejects the
crossing. Avoid vague claims such as "managed safely."

Once a public contract states the owner, lifetime, and permitted operations,
callers are expected to honor it. A borrowed `Bytes`, native view, or
pointer-shaped value does not need a defensive copy or restricted wrapper
solely because its underlying type can also mutate or free storage. Validate
external values and representation changes at the boundary that owns the
invariant; downstream code may rely on that result until another crossing
invalidates it.

Use x2c facilities only when their existing contracts match:

- `String` for canonical NUL-terminated text, never arbitrary binary data;
- `Bytes` or an explicit native span for binary data;
- `List` for immutable sequence results and small fixed records;
- `Array` for mutable indexed values;
- `Map` for keyed mutation only when key uniqueness and unordered lookup are
  the data's real semantics;
- indexing when the upstream value genuinely has keyed or positional access;
- iteration when traversal has a stable lifetime and exhaustion contract;
- `defer` beside explicit native-resource acquisition;
- Scope for groups of x2c allocations, not as a replacement for native
  release functions; and
- Error for actual failures, while expected absence remains on the ordinary
  return channel.

Protocols, indexing, iteration, and operators are positive integration tools
when they make the short application materially shorter while retaining the
upstream operation's meaning. An operator that creates native resources must
also give intermediate results an honest automatic lifetime; concise syntax
must not conceal manual cleanup. Do not add a protocol, operator, macro,
decorator, or wrapper type merely to display a language feature. A macro that
is longer or more Lisp-heavy than the code it replaces has failed.

## What PCRE2 taught us

PCRE2's native execution path reuses match data. Returning borrowed capture
pointers would make an earlier result change or dangle after the next match.
The accepted client therefore:

- owns compiled code, reusable match data, and match context in `Regexp`;
- puts `defer regexp.free()` beside compilation;
- copies capture text, names, and offsets into immutable x2c values;
- supports numbered and named indexing and capture/match iteration;
- returns no match as an ordinary empty result but raises real PCRE2 errors
  with the native code and message;
- handles zero-length global matches without getting stuck;
- grows replacement output internally and returns `String`; and
- leaves binary subjects, custom allocation, DFA, serialization, and callback
  machinery on the complete raw API when no accepted x2c path improves them.

The important decision was not to create a `Regexp` object. It was to copy a
result that otherwise borrowed reusable native storage, while retaining PCRE2
names, options, behavior, and advanced access.

## What yyjson taught us

The first yyjson path converted every object to `Map`. That was convenient but
silently discarded object order, duplicate names, and the distinction among
signed, unsigned, and real numbers. The accepted revision therefore has two
explicit paths:

- `JsonDocument` owns the native document, and `JsonValue`, `JsonArray`,
  `JsonObject`, and `JsonMember` are borrowed views that retain yyjson's data
  model; and
- `to_x2c` and the concise `Json.parse` path deliberately convert to ordinary
  x2c values when the caller accepts Map and Array semantics.

Object iteration yields every member in document order, including duplicate
names. The document invalidates all views when freed, and stale access raises
`<bad-state>`. JSON containing an embedded NUL can remain in the document and
be serialized again, but conversion to x2c `String` raises `<bad-enc>`.

The important correction was not to wrap more yyjson functions. It was to
notice that the obvious x2c collection conversion lost information and make
that loss an explicit opt-in operation.

## Copy, borrow, convert, or stay raw

PCRE2 and yyjson deliberately make different choices. Use these questions for
the next library:

- Will another native call invalidate this result? Copy it or retain a
  separate native owner.
- Is the native graph large, ordered, duplicated, or lazily traversed? Prefer
  owned-document plus borrowed views when eager copying would lose semantics
  or impose the wrong cost.
- Does conversion fit the complete native value domain? If not, name the loss
  and make conversion explicit.
- Can x2c represent the bytes? If not, keep a binary/native path rather than
  truncating through `String`.
- Is a pointer borrowed only during a callback? Copy what must escape and make
  the callback-only object impossible or invalid outside that call.
- Does the upstream API reuse one handle internally? State non-reentrancy and
  do not imply concurrent safety.

There is no universal wrapper shape. The consistent part is that every
lifetime and semantic loss is visible and tested.

## Errors and callbacks

Keep upstream outcomes recognizable. Include the native operation, code,
message, and useful location or offset in an x2c Error. Do not invent a second
status vocabulary that callers must translate back to the library.

A private helper that raises for several callers must take the caller's
operation name. `_json_write_error` hardcoded `(operation "stringify")`, so a
failed `write_file` on either path reported a stringify failure and a caller
reading `%(format *detail)` could not tell the two apart. A shared raise site
that names one caller's operation produces a detail that lies.

Expected outcomes such as no regex match, iterator exhaustion, a missing key,
or a timeout API's "no event yet" result are not automatically Errors.
Separate absence from a present Null value whenever both are possible.

Never let an x2c Error unwind through a C library callback. Catch it at the
callback boundary, copy or snapshot what must survive, and report it when
control is safely back in x2c. Verify which thread invokes every callback.
Do not enter the x2c runtime from an arbitrary worker thread without a
specific proven runtime contract.

## Raw API

Prefer a small checked shim that includes the real pinned upstream header.
Reject the wrong version or profile at build time. Do not copy thousands of
declarations, rename the API, or generate forwarding functions merely to make
the symbols visible.

A wrapper over a foreign handle publishes that handle as `object.native()`.
A raw API that cannot be reached *from* the ordinary object is not a
raw API: libcurl's `CurlEasy` kept its `CURL *` private, so a caller who
needed any verb but GET had to build a second handle from scratch, and
libuv's loop could only be reached by casting the wrapper and trusting that
`uv_loop_t` stays its first member. Both are now accessors, and the caller
who needs one unwrapped option keeps everything else the package gives it.

This is a rule about package wrappers over foreign handles and it stops
there. It is not a requirement on x2c objects generally, and no existing type
changes to adopt it.

The raw API is complete only for the admitted build profile. Record:

- upstream version and source URL;
- archive and public-header hashes;
- compile-time options and disabled features;
- static or dynamic linkage;
- linked dependencies and platform frameworks;
- licenses and required notices; and
- known x2c foreign-declaration limitations.

A function count or API inventory supports review, but it never proves the
x2c client complete.

## The Lisp surface belongs in the package

When a library has a useful value-oriented Lisp surface, that surface ships
inside the package behind one public installer, not in an example. PCRE2
exposes `RegexpLisp.install(Lisp)` and yyjson `JsonLisp.install(Lisp)`; a
consumer that only links the archive gets every binding by calling one
function. Wrappers defined in an example reach nobody who imports the package.

This survives the archive boundary, and it was proved before it was written: a
`$lisp.binding` group and the `$lisp.install` call that publishes it compile
inside the package unit, and the group reaches a consumer whose only mention
of the package is `import`.

Bindings take and return values Lisp already operates on, and keep opaque
package objects on the x2c side. yyjson's bindings work on the `Var` value
path; `JsonDocument` handles never enter the interpreter. When a binding
returns a collection Lisp cannot walk, the package owes the readers that make
it usable, and the probe that finds this out is the one that consumes the
returned value rather than handing it straight back.

## Tests and acceptance

Each accepted package needs focused proof for both surfaces.

The x2c tests should cover:

- the same paths used by the short and broader applications;
- ownership, idempotent release where promised, and use-after-release checks;
- absence separately from error and from present Null;
- boundary sizes, growth, embedded NUL, and binary behavior where relevant;
- iteration and indexing, including empty and duplicate cases;
- native error details; and
- every deliberate conversion loss.

Tests verify the promises made by the public contract. They need not defend
against an explicitly forbidden caller action, and they must not force
test-only inspection methods into the ordinary API. Exhaustive failure
combinations belong here rather than in the short application.

A test must check the effect, not the round trip. The assertion for pretty
printing wrote a document with the flag set, read the file back, and
re-serialized it compactly; it passed identically with the flag absent, so the
only write path that used the option was never covered. It now reads the
file's bytes. Whenever a test's second call can undo what its first call did,
assert on the artifact between them.

The raw test should call representative upstream declarations directly from
the real header. It does not need to repeat upstream's test suite.

Run the package's build, tests, application, and profile/header verification.
Run repository-wide gates only when the changed files require them under the
root `AGENTS.md`. Show the short application first, then the broader
application and exact results at the API checkpoint. Do not change a
package's status to accepted until Gary accepts the developer experience.

## Keep the package inside a gate

A package outside every gate breaks without anyone noticing. Between the day
PCRE2's and yyjson's clients were written and the day they were audited,
fifteen commits changed `src/` or `lib/` without either package noticing,
because nothing built
them. Both still passed. That was chance, not evidence.

`make packages-check` is the gate, and it is the check to run after a compiler
or runtime change that could reach a package client. It stays optional and out
of `check` and `precommit` by Gary's decision, because it needs a prepared
dependency cache; the root `AGENTS.md` "Process Ceiling" governs any move to
make it mandatory.

A gate that runs only `make -C packages/<name> test` is a weak gate.
`package.mk` builds test programs from `tests/test-*.x` alone, so such a target
compiles none of the examples, which are the code a reader of the package
actually sees. Every package therefore carries `run` beside `test`, and
`packages-check` names both; a package with a Lisp installer carries
`run-lisp` too, and the gate names that as well. pcre2, yyjson, and libcurl
run all three; termbox2, blis, and libuv publish no Lisp surface and run
`test run`; raylib is named once as `verify`, which is `verify-headers run
test` plus its rendered-PNG checks. Do not add a `run-lisp` target to a
package that has no Lisp surface.

## Shipping a package as supported

Acceptance makes a package good. Shipping it as supported in a public release
is a larger claim with its own list. For every package chosen to ship as
supported, complete one focused campaign containing all applicable parts
below:

1. one useful application accepted by Gary before the wrapper is accepted;
2. one screen-sized example and, where useful, a broader application;
3. a small public `.x` interface that keeps the upstream library's concepts;
4. the complete pinned upstream C header as the raw API;
5. an importable archive, generated public header, link flags, dependency pin,
   reproducible native profile, and install/use instructions;
6. a Lisp installer inside the package when the library has a useful
   value-oriented Lisp surface; otherwise an explicit statement that opaque
   native objects remain inside x2c wrappers or on the raw path;
7. ownership, borrowed-view, callback, thread-entry, cleanup, error, string,
   numeric, and conversion rules demonstrated by the application;
8. focused x2c tests and representative direct calls through the real raw
   header;
9. exact license, notice, source, header, and linkage evidence;
10. package README, book coverage, root package index, and checked consumer
    commands.

macOS is the only platform an accepted package claims, and `make
packages-check` on macOS is the whole platform proof. Adding Linux or Windows
is a separate decision nobody needs to anticipate; do not make a package
carry per-platform evidence for a platform it does not claim.

Which packages ship in a given release is a launch decision, and it is recorded
in `plans/go-to-market.md`.

## Dependency storage

Keep package work in Git; keep fetched and built upstream dependencies
outside each worktree.

The checked-in package should contain:

- hand-written x2c client source;
- examples and focused tests;
- a small real-header shim;
- a compact dependency manifest with version, URL, hashes, profile, and build
  recipe;
- license texts and notices required for review or redistribution; and
- small reviewed fixtures that are genuinely project source.

Do not check in upstream source trees, archives, installed prefixes, object
files, static libraries, or generated API inventories. Inventories used only
for research should be reproducible outputs in the dependency cache. Keep a
compact reviewed summary in Git only when it informs an actual boundary.

`tools/deps.py` owns one shared cache outside the worktree. `X2C_DEPS_DIR`
selects it explicitly. Otherwise the helper uses
`$(git rev-parse --path-format=absolute --git-common-dir)/x2c-integrations`,
which every worktree for the clone shares. A user-level cache such as
`~/Library/Caches/x2c/integrations` is reasonable when several clones should
share builds.

Key each installed prefix by library version, admitted profile, host/target,
C compiler identity, and the hash of its dependency manifest. Prepare into a
temporary directory, verify source and license hashes, then rename the
finished prefix atomically and write a completion stamp. Concurrent worktrees
must either take a per-key lock or accept the already completed identical
entry.

Each package Makefile sets `PACKAGE` and includes `package.mk`, which includes
`dependency.mk` and provides `prepare`, `build`, `test`, and `clean`.
`make prepare` also refreshes an ignored `deps` symlink in the package
directory pointing at that cache entry's prefix. Ordinary `make test` and
`make run` reuse the matching entry without network access or rebuilding.
`make -C packages prepare-checked` prepares every package the root
`make packages-check` builds.
Generated x2c C, test executables, and application output remain under the
worktree's ignored `builds/` directory. `make clean` removes only those local
products and the `deps` symlink; it never removes the shared cache.

`make build` translates every `src/*.x` in package mode and compiles it into
`builds/<unit>.h`, `builds/<unit>.o`, and one `builds/lib<package>.a`. Tests
and examples import the package and link that archive instead of recompiling
the client. `builds/<package>.link` holds the one line of link flags a
consumer needs besides the archive, empty for a package with no native
dependency.

Do not bypass or reimplement this mechanism in a package. Change the package's
`dependency.json` when its pinned source or build profile changes. Use the
package-specific prefix variable only as a narrow diagnostic override.

## Review the developer experience

Read the short example before the client or tests. A review should answer:

- What useful result does the short example produce?
- Which C allocation, pointer, buffer, callback, status, or cleanup work
  disappeared?
- Which upstream names and operations remain visible?
- Why is each x2c value or collection the right representation?
- Is there one obvious starting path, with broader layers that do not burden
  it?
- Which caller obligations are documented and intentionally trusted?
- Do operator-created or callback-created values have honest lifetimes?
- Did tests cause wrapper bookkeeping to enter the public API?

Then inspect the broader example, client, tests, raw header, profile, and
package diff. Passing tests cannot rescue an awkward short example, and a
short example cannot substitute for the broader boundary proof.

## Failure patterns

Reject a package that does any of the following:

- places the whole C library behind one unrelated x2c object;
- exposes only a raw header or a list of aliases and calls that the client;
- translates a C example mechanically into `.x`;
- offers no screen-sized path because every example is an API or failure list;
- measures completion by declarations, symbols, or compiled calls;
- converts native data into Map or Array while hiding lost semantics;
- returns borrowed storage without an owner or invalidation rule;
- makes applications grow native buffers or dispatch native statuses;
- lets exceptions cross a C callback or enters x2c on an unproven thread;
- creates an ORM, framework, scene graph, status hierarchy, or other second
  vocabulary unrelated to the upstream library;
- adds macros, protocols, decorators, operators, or objects that do not make
  an application shorter and clearer;
- gives concise operator syntax to native results whose intermediate cleanup
  remains manual; or
- claims advanced support merely because the raw function is callable.

Delete and redesign a failed ordinary surface rather than preserving several
competing APIs. Retain exact provenance or ABI research separately when it is
still useful.
