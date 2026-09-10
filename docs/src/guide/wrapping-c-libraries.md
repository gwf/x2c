# Wrapping a C Library

The [previous chapter](packages.md) explains how to build and import a package.
This chapter explains how to design one around a C library.

Provide an x2c API for ordinary use, with strings, collections, indexing,
iteration, `defer`, and `Error` where they simplify the caller's work. Keep the
pinned C API available under its own names for features the wrapper does not
expose. A raw header makes the library callable; the wrapper makes it pleasant
to use without hiding it behind unrelated names.

PCRE2 and yyjson illustrate the choices. Their packages are in
`packages/pcre2/` and `packages/yyjson/`.

## The library we are wrapping

The examples wrap a small fictional C library:

```c
typedef struct feed_parser feed_parser;
typedef int (*feed_visitor)(const char *title, void *user);

feed_parser *feed_open(const char *bytes, unsigned long len);
void         feed_close(feed_parser *parser);
int          feed_next(feed_parser *parser, const char **title,
                       unsigned long *len);
int          feed_scan(feed_parser *parser, feed_visitor visit, void *user);
const char  *feed_strerror(int code);
```

A real package includes a pinned header here. The examples declare these six
names in hidden lines, visible through the eye icon, so each example compiles
on its own.

These six functions leave five things for the caller to manage:

| Concern | Here |
| --- | --- |
| allocation and release | `feed_open` / `feed_close`, and nothing frees it for you |
| pointer plus length | `feed_next` yields `const char *` and a separate length |
| borrowed storage | that pointer is invalidated by the next `feed_next` |
| status versus absence | `feed_next` returns 1, 0 for end, negative for failure |
| callback and its state | `feed_scan` calls back into a C frame with a `void *` |

Identify these obligations before designing types. For each value, decide
whether to copy it, borrow it with a stated lifetime, convert it, or leave it
as a native C value.

Also check for conditions this library does not have: process-global or
thread-local state, callbacks on threads the caller did not start, and bytes
that `String` cannot hold, such as embedded NUL.

## Start with the tasks, not with the header

Start by listing the tasks a developer brings to this kind of library. Then
ask whether the imported x2c API can perform each task without requiring the
raw C header or a hand-written loop over lower-level operations. This gives
you a better measure of usefulness than the fraction of entry points wrapped.

For a regular-expression library such as PCRE2, the list might be:

- Compile a pattern, match, and read named and numbered captures.
- Select case-insensitive, multiline, dotall, or extended matching.
- Find every match in a subject.
- Read capture offsets and distinguish unmatched from empty captures.
- Replace the first match or all matches, with backreferences.
- Match at an anchor or from an offset.
- Match UTF-8 text and Unicode properties.
- Bound backtracking and JIT-compile a frequently used pattern.
- Report PCRE2's code, message, and offset for a bad pattern.
- Split a subject on a pattern.
- Replace each match with a computed value.
- Quote a literal for use inside a pattern.
- List the named groups a pattern declares.

Demonstrate each task with a small program. Reading the wrapper's source can
miss an operation that several existing methods already express together.
Features outside the x2c API must remain reachable through the raw header;
name them in the README. For PCRE2 these include DFA matching, serialization,
callouts, partial matching, and binary subjects.

## Pin the library before you wrap it

A package with a native dependency carries a `dependency.json` naming the
version, the source URL, the archive hash, and the build profile. `make
prepare` fetches and builds it into a cache shared by every worktree of the
clone and leaves a `deps` symlink in the package directory, so ordinary `make
test` needs no network.

```sh
make -C packages/feedparse prepare
make -C packages/feedparse build
```

Document the build you provide: version and URL, archive and public-header
hashes, compile options and disabled features, static or dynamic linkage,
dependencies and platform frameworks, licenses and required notices, and any
x2c limits on foreign declarations. The available raw API depends on these
choices. `packages/FOREIGN-C-QUALIFIERS.md` records where
x2c's observed types drop a `const` that the upstream header declares.

## Keep the raw API reachable

Expose the raw API through a small header in the package's `src/`. It selects
the build profile, rejects the wrong version at compile time, and includes the
upstream header. Do not copy declarations, rename aliases, or add forwarding
functions.

```c
#pragma once

#include <feedparse.h>

#if FEEDPARSE_MINOR != 4
#error "this package pins feedparse 1.4"
#endif
```

Pin it under a versioned name. The generated header for a package unit is named
after that unit, so a package called `feedparse` already produces
`feedparse.h`; a vendored header of the same name beside it would be
unreachable. `pcre2-8.h` and `yyjson-0.12.h` are the two spellings here.

Publish the shim when a public method takes one of the library's own types.
Generated C hoists type definitions above the private include block, so a
private struct over a foreign type will not compile otherwise.

## The entry unit and its two halves

Everything above `#pragma private` is the package's public surface. The wrapper
struct and the native calls are below it.

```x2c
~typedef struct feed_parser feed_parser;
~feed_parser *feed_open(const char *bytes, unsigned long len);
~void feed_close(feed_parser *parser);
typedef struct Feed *Feed;

Feed Feed.open(String text);
Feed Feed.close(Feed feed);
List Feed.titles(Feed feed);

#pragma private

struct Feed {
  feed_parser *native;
  String source;
};
```

`Feed` is opaque to consumers: they hold the pointer and call methods on it,
and only this file knows there is a `feed_parser` inside.

For functions with no receiver, a package can declare a type used only as a
namespace. yyjson does this for `Json.parse`:

```x2c
typedef enum Json {
  JSON_NAMESPACE
} Json;
```

## Ownership and defer

The acquisition function and the release function are one design decision, so
write them together. Release should be idempotent and return `NULL`, which
makes a double close harmless and lets the caller clear their handle in the
same expression.

```x2c
~typedef struct feed_parser feed_parser;
~feed_parser *feed_open(const char *bytes, unsigned long len);
~void feed_close(feed_parser *parser);
~typedef struct Feed *Feed;
~struct Feed { feed_parser *native; String source; };
Feed Feed.open(String text) {
  Feed feed = Scope.calloc(1, sizeof(struct Feed));
  feed.source = text.intern();
  feed.native = feed_open(text, text.len());
  return feed;
}

Feed Feed.close(Feed feed) {
  if (!feed) return NULL;
  if (feed.native) {
    feed_close(feed.native);
    feed.native = NULL;
  }
  return NULL;
}
```

`Regexp.free` and `JsonDocument.free` are both shaped this way.

`Scope` owns the small x2c record. With `Scope.calloc` it releases the
`struct Feed` when its scope ends and knows nothing about `feed_close`, so
the caller must release the native resource. With `Scope.malloc_finalized`
the record carries a finalizer that calls `feed_close` when the scope
reclaims it, so temporaries a library creates faster than a caller can name
them, such as the results of operator expressions, are released with the
region. Keep the explicit `free` method either way: it clears the native
field, so an early release leaves the finalizer nothing to do. See
[attaching a finalizer](memory.md#attaching-a-finalizer).

The caller puts the release on the line after the acquisition:

```x2c
~typedef struct feed_parser feed_parser;
~feed_parser *feed_open(const char *bytes, unsigned long len);
~void feed_close(feed_parser *parser);
~typedef struct Feed *Feed;
~struct Feed { feed_parser *native; String source; };
~Feed Feed.open(String text) { return Scope.calloc(1, sizeof(struct Feed)); }
~Feed Feed.close(Feed feed) { return NULL; }
~List Feed.titles(Feed feed) { return NULL; }
static int count_titles(String document) {
  Feed feed = Feed.open(document);
  defer feed.close();
  return feed.titles().len();
}
```

A `defer` in a function that *returns* the handle closes it before the caller
ever sees it. The release belongs to whoever will finish with it. A handle
whose operations reuse internal state is not reentrant: say so in the README
rather than letting silence imply that concurrent calls are safe. One `Regexp`
cannot be shared across threads for this reason.

## Copy, borrow, convert, or stay raw

Four choices, each selected by a question.

**Will another native call invalidate this result?** Then copy it, or retain a
separate owner for it. `feed_next` hands back a pointer into storage the next
call reuses, so the wrapper copies each title into an immutable `String` as it
goes:

```x2c
~typedef struct feed_parser feed_parser;
~int feed_next(feed_parser *parser, const char **title, unsigned long *len);
~const char *feed_strerror(int code);
~typedef struct Feed *Feed;
~struct Feed { feed_parser *native; };
~static void _feed_error(String operation, int code) { raise %(malformed (code $code)); }
List Feed.titles(Feed feed) {
  List titles = NULL;
  const char *title = NULL;
  unsigned long length = 0;
  int status;

  while ((status = feed_next(feed.native, &title, &length)) > 0)
    titles = cons(String.new_len(title, (int) length), titles);
  if (status < 0) _feed_error("next", status);
  return titles.reverse();
}
```

PCRE2 reuses match data on the next call. The wrapper copies captures into
immutable `List`s so later matches do not change earlier results. The copied
results have the lifetime of their canonical pools.

**Is the native graph large, ordered, duplicated, or lazily walked?** Then own
the document and hand out borrowed views, with an explicit invalidation rule. A
view keeps a reference to its owner and checks it:

```x2c
~typedef struct feed_parser feed_parser;
~typedef struct Feed *Feed;
~struct Feed { feed_parser *native; };
typedef struct FeedEntry {
  Feed owner;
  const char *title;
  int length;
} *FeedEntry;

static void _feed_live(FeedEntry entry) {
  if (!entry || !entry.owner || !entry.owner.native) {
    raise %(bad-state (library "feedparse") (operation "entry")
            (reason "the feed that owned this entry is closed"));
  }
}

String FeedEntry.title(FeedEntry entry) {
  _feed_live(entry);
  return String.new_len(entry.title, entry.length);
}
```

yyjson preserves object order, duplicate names, and the distinction between
signed, unsigned, and real numbers. Its wrapper owns the native document and
returns borrowed views that retain those distinctions. Call `to_x2c`
explicitly when that information is unnecessary.

**Does conversion cover the native value's whole domain?** If not, name the
loss and make conversion opt-in.

**Can x2c represent the bytes at all?** If not, keep that path raw. `String`
excludes embedded NUL, so PCRE2's explicit-length binary matching stays on the
raw header.

Add indexing and iteration when they simplify the caller's code. Inside a
protocol member named `getindex`, a bare `item.getindex(...)` would resolve to
the member itself, hence the cast:

```x2c
typedef List FeedItem;
typedef struct FeedItemIndex *FeedItemIndex;

protocol FeedItemIndex(T) {
  associated Key = Var;
  associated Value = String;

  Value T.getindex(T, Key);
}

protocol FeedItemIndex(FeedItem);

#pragma private

String FeedItem.getindex(FeedItem item, Var key) {
  return key.is_integer()
    ? ((List) item).getindex(key.int()).string() : NULL;
}
```

Do not add a protocol, operator, macro, or wrapper type to display a language
feature. An operator that creates native resources must also give its
intermediate results an automatic lifetime; concise syntax must not hide
manual cleanup.

## Errors keep the library's own codes

A failure raises one structured `Error` carrying the library name, the
operation, the library's own numeric code, its own message, and a location when
it has one. Do not invent a second set of status codes that callers have to
translate back.

```x2c
~typedef struct feed_parser feed_parser;
~const char *feed_strerror(int code);
static void _feed_error(String operation, int code) {
  String message = String.new((char *) feed_strerror(code));
  raise %(malformed (library "feedparse") (operation $operation)
          (code $code) (message $message));
}
```

Pick the cause from the shared codes described in
[Exceptions and Cleanup](exceptions.md): `<malformed>` for bad external input,
`<bad-state>` for a stale or released handle, `<alloc-fail>` for a failed
native allocation.

An error helper shared by several callers must take the operation name as an
argument. Otherwise a failed file write, for example, could be reported as a
failed string conversion.

Expected absence is not a failure. No match, exhausted iteration, a missing
key, and a timeout's "no event yet" all stay on the return value. `feed_next`
returning 0 above ends the loop instead of raising, and `Regexp.match` returns
an empty result instead of an error.

An `Error` must never unwind through a C frame. When the library calls you
back, `catch` at the boundary, record what has to survive, return a status the
library understands, and `raise` once x2c is back in control:

```x2c
~typedef struct feed_parser feed_parser;
~typedef int (*feed_visitor)(const char *title, void *user);
~int feed_scan(feed_parser *parser, feed_visitor visit, void *user);
~const char *feed_strerror(int code);
~typedef struct Feed *Feed;
~struct Feed { feed_parser *native; };
typedef struct FeedScan {
  Array titles;
  int failed;
} *FeedScan;

static int _feed_visit(const char *title, void *user) {
  FeedScan scan = (FeedScan) user;
  try {
    scan.titles.push(String.new((char *) title));
  }
  catch: {
    scan.failed = 1;
    return 0;
  }
  return 1;
}

Array Feed.scan(Feed feed) {
  struct FeedScan scan = { Array.new(), 0 };
  int status = feed_scan(feed.native, _feed_visit, &scan);

  if (scan.failed) {
    raise %(bad-state (library "feedparse") (operation "scan")
            (reason "a title could not be copied"));
  }
  if (status < 0) {
    String message = String.new((char *) feed_strerror(status));
    raise %(malformed (library "feedparse") (operation "scan")
            (code $status) (message $message));
  }
  return scan.titles;
}
```

Check which thread invokes each callback. It must be safe to use the x2c
runtime on that thread before the callback calls into it.

## Two examples decide the design

Sketch two applications before implementing the wrapper: one short and one
more complete. Read the short one first.

One short application should fit on a screen, do one useful thing, and make the
result more prominent than the setup. One broader application should exercise
the library's defining operations, ownership, results, and failure paths while
still performing a task rather than enumerating outcomes.

<!-- ignore: an import needs a registered --package-dir root. -->
```x2c,ignore
import "feedparse" with Feed;

int main(void) {
  Feed feed = Feed.open(File.open("headlines.xml", "r").string_close());
  defer feed.close();

  foreach(String title, feed.titles())
    printf("%s", %"- $title\n");
  return 0;
}
```

If the applications still require the same setup, conversion, and cleanup as
the C API, revise the wrapper around those tasks. Keep exhaustive tests of
malformed input, limits, and cleanup separate from the examples.

The four in this repository are worth reading in this order:
`packages/pcre2/examples/parse-log.x` (35 lines),
`packages/yyjson/examples/service-health.x` (24 lines), then
`packages/pcre2/examples/request-report.x` and
`packages/yyjson/examples/release-catalog.x`.

## Include Lisp bindings in the package

If the library is useful from Lisp, include its bindings in the package behind
one public installer. Bindings defined only in an example are unavailable to
other importing programs.

```x2c
~typedef struct feed_parser feed_parser;
~feed_parser *feed_open(const char *bytes, unsigned long len);
~void feed_close(feed_parser *parser);
~typedef struct Feed *Feed;
~struct Feed { feed_parser *native; };
~Feed Feed.open(String text) { return Scope.calloc(1, sizeof(struct Feed)); }
~Feed Feed.close(Feed feed) { return NULL; }
~List Feed.titles(Feed feed) { return NULL; }
typedef enum FeedLisp {
  FEEDLISP_NAMESPACE
} FeedLisp;

#pragma private

$lisp.binding(feed_lisp, "feed-titles")
static List _lisp_feed_titles(String document) {
  Feed feed = Feed.open(document);
  defer feed.close();
  return feed.titles();
}

void FeedLisp.install(Lisp lisp) {
  $lisp.install(lisp, feed_lisp);
}
```

The group compiles into the archive, so a consumer that only links it gets
every binding from one call:

<!-- ignore: an import needs a registered --package-dir root. -->
```x2c,ignore
import "feedparse" with FeedLisp;

int main(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  FeedLisp.install(lisp);

  printf("%d\n", lisp.eval(%(length (feed-titles "<rss/>"))).int());
  return 0;
}
```

Bindings should take and return values that Lisp can use. Allocate and free
native handles within each call instead of returning opaque objects to the
session. Use x2c when a handle must persist between calls.

Test the results with ordinary Lisp operations. A parsed JSON array is an x2c
`Array`, and an object is a `Map`; Lisp's `car`, `cdr`, and `length` accept
neither. The package supplies `json-len`, `json-keys`, and `json-list` for
those values. A parse-and-serialize test alone would not show whether Lisp
could use them.

## Test both APIs

The x2c tests cover the paths the two applications use, plus ownership and
idempotent release, use after release, absence separately from failure and from
a present `Null`, boundary sizes and embedded NUL where the library allows
them, iteration and indexing including empty and duplicate cases, the native
error detail, and every deliberate conversion loss.

One further test calls representative upstream declarations directly through
the shim. This checks that the raw API is accessible without repeating
upstream's own test suite.

```sh
make -C packages/feedparse test
```

A test must check the effect rather than a round trip. Writing a document with
a pretty-print flag and then re-reading and re-serializing it compactly passes
identically with the flag absent. Assert on the bytes in between.

## How you know you are done

- The imported x2c API supports every task on your list.
- Everything left off it is reachable through the shim and documented as such.
- Both example applications work, and the short one fits on a screen.
- Ownership, invalidation, non-reentrancy, and every conversion loss are
  written down and tested.
- `Error`s carry the library's own code and message; absence is not an error.
- Lisp bindings, if provided, are in the package.
- The source version, build options, hashes, and licenses are recorded.

Reread the short application as a new reader would. Passing tests do not
make an awkward first page acceptable.

See `packages/pcre2/README.md` and `packages/yyjson/README.md` for complete
examples of package documentation.
