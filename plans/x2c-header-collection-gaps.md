# Header collection gaps

> Status: needs author scoping - 2026-09-16.
> Found while repairing raylib collection in PR #62, which made collection
> skip an object-like macro defined to nothing (`#define RLAPI`). The forms
> below are still mis-collected or rejected. No package build hits them
> today, because only raylib passes `-I` for its upstream headers; each one
> blocks another package from collecting its real headers.

## Result

Collecting a C header reads its unexpanded source (see "Host preprocessing"
in `docs/src/reference/language.md`). Headers commonly decorate declarations
with macros and compiler attributes. Collection should record the same
declarations and types a C compiler sees for these forms, without changing
how unit source parses.

## Reproduced gaps

Reproductions from the PR #62 investigation, with the current `main`
compiler (`x2c translate` of a unit that includes the header):

| Header form | Result today |
| --- | --- |
| `void API f(int a);`, where `API` is defined to nothing, after the type | parse error |
| `void f(API int a);` inside a parameter list | "expected ')'" |
| `void f(int a) API;` trailing | accepted, token dropped |
| `ATTR(1) void f(int a);` function-like macro expanding to nothing or an attribute, as libcurl's `CURL_DEPRECATED(...)` at `curl.h:157` | parse error |
| `__attribute__((visibility("default"))) void f(int a);` | parse error |
| `_Noreturn void f(int a);` | parse error |
| `#define E extern` then `E void f(int a);` | parse error |
| `E void f(int);`, `E int v;`, `E struct S {}` with `E` an unknown non-empty macro | records wrong symbol keys such as `( int )` |
| `extern "C" {` opened before an `#include` and closed after it | "missing '}'": each include-delimited segment checks braces separately (`_shallow_parse_loop` clears `c.braces`) |

The last row blocks libuv (`uv.h:27`) and blis (`blis.h:45`) once their
builds pass `-I`; sqlite (`SQLITE_API`) is covered by PR #62.

## Decisions needed

- Whether collection should evaluate simple macro definitions beyond empty
  object-like ones (for example `#define E extern`), or only skip
  attribute-like decorations.
- Whether function-like attribute macros are skipped by name when every
  definition expands to nothing or to `__attribute__((...))`, or through
  host preprocessing for collection only.
- Whether `__attribute__`, `_Noreturn`, and `[[...]]` are accepted in unit
  source too, which would change emitted C.

## Implementation outline

- Extend the `<empty>` macro facts recorded in `_note_object_macro`
  (`src/compiler.x`) to function-like macros whose definitions expand to
  nothing or to an attribute, and skip an invocation with its balanced
  argument list where `_skip_empty_macro` (`src/parse.x`) already skips a
  name.
- Accept `__attribute__((...))` and `_Noreturn` among collected declaration
  specifiers and after a declarator, carrying the spelling in the type the
  way `("_Noreturn")` is carried for emission.
- Carry linkage-group brace depth across segments of one collected file
  instead of checking each segment alone.

## Validation

- A compiler fixture per form, in the style of `c-annotation-macro`, whose
  header uses the form before an `#include` and whose unit calls the
  declarations.
- `make -C packages/libcurl test run run-lisp`, `make -C packages/libuv test
  run`, and `make -C packages/blis test run` with `-I` added for their
  upstream headers.

## Plan review

- Facts: `_note_object_macro` already records each definition from the
  source; the new skips consume only names and invocations whose recorded
  definitions contribute no declaration syntax, and nothing rechecks them.
- Reuse: extends the existing macro map, `_skip_empty_macro`, and the
  segment state handoff; no new traversal or cache.
- Idiom: a direct parser skip over recorded facts, not a preprocessor.
- Validators and diagnostics: none proposed.
