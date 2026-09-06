# PCRE2 client

This package provides an x2c interface to the pinned PCRE2-8 10.48 profile.
It is an importable package whose entry point is `src/pcre2.x`; it compiles
`String` patterns, returns immutable capture values, supports named and
numbered indexing and iteration, and returns replacement results as `String`.

```x2c
import "pcre2" with Regexp, RegexpMatch;

int main(void) {
  Regexp request = Regexp.compile(
    %"^(?<method>[A-Z]+) (?<path>[^ ]+)$$",
    PCRE2_UTF | PCRE2_UCP
  );
  defer request.free();

  RegexpMatch found = request.match(%"GET /docs");
  if (found)
    printf("%s %s\n", found[<method>], found[<path>]);
  return 0;
}
```

## Splitting, computed replacement, quoting, and names

`Regexp.split` returns the text between matches, keeping an empty field where
two matches touch or a match is at either end.

`Regexp.replace_fn` replaces each match with whatever its callback returns.
The callback receives the whole `RegexpMatch`, so it can read captures and
offsets. PCRE2 never inspects the result, so a `$1` inside it stays literal;
use `Regexp.replace_all(subject, "$2:$1")` when PCRE2 should expand
backreferences instead. Use a plain C string literal for replacement text
containing `$`, because `%"..."` reserves `$` for x2c interpolation.

`Regexp.escape` quotes a literal for inclusion in a pattern. It escapes every
ASCII byte that is not a letter, digit, or underscore and passes bytes above
ASCII through, so a UTF-8 literal survives.

`Regexp.capture_names` lists the names a pattern declares, in capture-group
order. A name declared several times under `(?J)` is listed once per group.

`examples/parse-log.x` is the short application (`make short-example`). In 35
lines it summarizes a syslog batch: one expression with named captures pulls
the time, program, and message out of each line, a second splits the message
into fields, and unmatched lines are skipped. It is the shortest complete path
through the package.

`examples/request-report.x` (`make example`) processes a List of request
lines with four expressions, named and numbered captures, capture and match
iteration, aggregation, and token redaction. Its ordinary path contains no
native allocation, output buffer, or PCRE2 status handling.

## Lisp

`RegexpLisp.install(lisp)` adds `regex-match`, `regex-find-all`,
`regex-split`, `regex-replace`, and `regex-escape` to a ready Lisp session.
The bindings are part of the package, so importing it is enough; nothing has
to be written per program.

The surface is value-oriented on purpose. Every binding takes and returns
`String` and `List`, and each compiles and frees its own `Regexp` inside the
call, so no native handle and no borrowed storage ever enters a session. A
program that needs a compiled pattern to persist across calls stays in x2c. A
bad pattern raises out of the binding as the same `<malformed>` an x2c caller
would see.

`examples/inline-lisp.x` (`make lisp-example`) drives that surface.

## Native API

`src/pcre2-8.h` selects the width-8 API, rejects another PCRE2 minor version,
and includes the real upstream header. It exposes the complete pinned core
surface directly, including the upstream types, constants, callbacks, and
generic function macros. No copied declarations, forwarders, or renamed
aliases sit between x2c and PCRE2.

`src/pcre2-posix.h` adds the real POSIX header with its four functions, three
types, errors, flags, and compatibility macros. Raw programs link both
`pcre2-posix` and `pcre2-8`. The raw path is also the way to reach binary
patterns or subjects containing NUL, custom allocation, DFA workspace,
serialization, conversion contexts, JIT stacks, and callbacks.

`regexp.native()` returns the borrowed `pcre2_code *`;
`native_match_data()` and `native_match_context()` return the two reusable
execution records. All three expire at `Regexp.free`, and an ordinary match
replaces the same match-data ovector. `Regexp.compile_context(pattern,
options, context)` supplies an upstream compile context for extra compile
options, maximum pattern length, or custom character tables. The caller
retains and releases that context.

`dependency.json` pins the source archive and static width-8/POSIX build with
JIT enabled. JIT compiles PCRE2's bundled SLJIT component into
`libpcre2-8.a`; `PROFILE.md` records the complete build and license closure.
`make verify-headers` checks the prepared upstream headers against their
reviewed SHA-256 values.

## Ownership and execution

`Regexp` owns one compiled `pcre2_code`, one reusable match-data block, and one
match context. `Regexp.free` releases those native resources and is safe to
call more than once while the wrapper itself remains in scope. Every other
method, including `pattern()` and `capture_count()`, raises `<bad-state>` after
release. Use `defer` at the acquisition site.

Matches copy their capture text and offsets into immutable x2c Lists, so a
match remains valid after the next call. Reusing the native execution state
makes one `Regexp` non-reentrant and unsuitable for concurrent calls. Use a
separate `Regexp` or the raw PCRE2 path when execution state must be isolated.
Callouts remain raw until their re-entry and callback lifetimes have a tested
x2c interface.

`found[key]` is the concise text view. It returns NULL when a capture matched
the empty string, did not participate, or the requested name was never
declared. Use `found.capture(key)` when those three outcomes must be
distinguished; its `matched()`, offsets, and presence retain the difference.

The high-level interface accepts `String`, whose x2c contract excludes
embedded NUL bytes. PCRE2's explicit-length binary capability remains fully
available through `pcre2-8.h`.

## Build and test

`make prepare` downloads, verifies, and builds the pinned static profile in the
shared integration cache. `make build` produces `builds/libpcre2.a` and the
generated package headers. `make run` and `make test` prepare it automatically
when absent and reuse it when present. Set `X2C_DEPS_DIR` to move the shared
cache, or set `PCRE2_PREFIX` to diagnose another compatible installation.

```sh
make verify-headers
make run
make test
```

The client and its tests are licensed under
[Apache-2.0](../../LICENSE). PCRE2 and
SLJIT retain the terms reproduced under `LICENSES/`. See
`../LICENSE-POLICY.md` for the project intake policy.
