# The C on-ramp corpus

> Status: active - implemented 2026-09-16 after Gary's yes to both
> decisions. Follows `plans/x2c-c-on-ramp.md` (4a landed as `f94f034` and
> `76b27c0`). The first round of fixes exposed a second and third layer of
> failures behind them; those are recorded under "What the corpus
> established" and "Implementation" as well. Result: 12 of 22 units
> translate and compile, from 3; the ten that remain are listed under
> "Remaining" with their cause.

## The result

A plain C file renamed from `.c` to `.x`, with its headers reached through
`#include`, translates whenever `cc` accepts it, for the shapes that common
C libraries actually use. The measure is a corpus of 22 real units
(`.context/market-opportunities/c-corpus/`, fetched 2026-09-16 from cJSON,
inih, linenoise, termbox2, stb, sds, parson, tinyexpr, jsmn, miniz,
optparse, greatest, utf8.h, uthash, tinycthread, tiny-AES-c, kdtree, log.c,
mongoose, and mattiasgustavsson/ini). Today 3 of 22 translate. After this
plan every unit translates except the two whose source is not valid C for
any compiler (miniz needs a generated header; kdtree carries `return =1;`
in `#if 0`), and the fixture set below keeps it that way.

## What the corpus established

Every failure reproduces in a unit of one to twelve lines. Six root causes
cover all 19 failures:

| Cause | Corpus units | Reproducer |
| --- | --- | --- |
| A. Header collection splits a file into segments at each `#include` and parses each in a fresh shadow compiler, so `extern "C" {` before an include and its `}` after it never meet | cJSON, greatest, inih, linenoise, mongoose, termbox2, tinycthread, parson | `extern "C" {` / `#include <stdio.h>` / `int f(void);` / `}` |
| B. An identifier before the specifiers is taken as the type name | jsmn, optparse, stb_image, stb_sprintf, utf8.h, miniz | `JSMN_API void jsmn_init(int *p);` |
| C. A trailing `__attribute__((...))` or annotation macro after the declarator | sds, stb_sprintf | `int f(int s) __attribute__((noreturn));` |
| D. `__restrict`, `__restrict__`, `__inline`, `__inline__`, and an empty macro after `*` | utf8.h | `int *f(int *__restrict d);` |
| E. `static` or a qualifier before an aggregate definition with a declarator nests the tag one list too deep | log.c | `static struct { int (*fn)(int); } L;` then `L.fn(1)` |
| F. Every `#if` arm is parsed: C++ in `#ifdef __cplusplus`, and one function defined in both arms of one conditional | stb_ds, tinyexpr | `template<class T> T *w(T *a);` under `#ifdef __cplusplus`; `factor` under `#ifdef X` and again under `#else` |

Causes B, C, and D are documented limits (`docs/src/reference/language.md`,
"Unit source still parses unexpanded"; `packages/FOREIGN-C-QUALIFIERS.md:57`).
Cause F is the documented rule that both arms parse
(`docs/src/guide/from-c.md:68-83`). Causes A and E are defects.

## Second and third layers, found during implementation

Fixing the first error in each unit exposed the next. All reproduced in
short units and are part of this change:

| Cause | Corpus units | Fix |
| --- | --- | --- |
| Header collection tokenizes each segment separately, so `extern "C" {` before an `#include` never met its `}` | inih, cJSON, termbox2 and five more | moot once the C++ arm is hidden (F); a stray `}` at file scope no longer ends the tokenizer's scan (`lib/tokenizer.x`) |
| A macro defined to `static STBSP__ASAN`, to `signed int`, or to another prefix macro | stb_sprintf, utf8.h | `_macro_prefix` reads storage, builtin type words, and recorded prefixes; a type-word macro names a type in `_type_specifier` |
| `CJSON_PUBLIC(const char *) f(void);` | cJSON | a function-like macro whose body is its parameter amid prefixes is `<wrapper>`; its parentheses are skipped |
| `typedef char *sds; s[i]` and `T *const p; p[i]` | sds, cJSON | `_postfix_index_expression` resolves pointer typedefs and skips leading qualifiers |
| `tios.c_cc[VMIN]` on a foreign struct field | termbox2, linenoise | an untyped receiver indexes as `(expr () (index ...))` for C to type |
| `static` prototype, definition without `static` | termbox2 | the definition adopts the prototype's linkage in the completion contract |
| A prototype's `__attribute__` was part of the completion contract | sds | attributes are stripped from the contract and carried onto the generated prototype |
| Function bodies move after the declarations and lost their `#if` arm; an `#undef` moved ahead of the bodies that use the macro | aes, kdtree, parson, stb_ds | `_static_prototypes` re-opens each moved body's arms and defers such an `#undef` |
| `typedef enum { A = 1 << 0 } T;` could not be written to the `.xi` interface | jsmn | non-bare symbols are written in their angled spelling |
| `struct b { ... } g;` at public file scope dropped `g` | (probe) | header gets the body and `extern struct b g;`, source defines `g` |
| A public prototype naming a privately defined `struct` | linenoise | the header forward-declares the tag first |
| `in` and `match` used as C identifiers | termbox2, linenoise, utf8.h | contextual retagging at tokenize time |
| MSVC-only arms (`__asm`, `__stdcall`) | stb_image | `_MSC_VER` joins `__cplusplus` as never defined |

## Remaining

| Unit | Cause | Standing |
| --- | --- | --- |
| kdtree, termbox2 | a directive between `else` and its statement (`else` / `#endif` / `stmt`) was dropped from the body | fixed 2026-09-16: `_sub_statement` in `src/statements.x` keeps the directives in a `(group ...)` node that emits without braces; fixture `c-body-directive` |
| cJSON, sds, stb_sprintf | macro invocations that supply grammar (`cJSON_ArrayForEach(a, b) {`, `test_cond(...)` without `;`, `STBSP__UNALIGNED(while ...)`) | documented adjustment |
| tinycthread, mongoose, stb_image | arms for other platforms or libraries (`NTAPI` under `_WIN32`, OpenSSL `STACK_OF`, `__stdcall` under `_WIN32`) that C on this host also skips but x2c parses | documented rule; `_WIN32` is real on MSYS2 and cannot be hidden |
| tinyexpr | `TE_FUN(double)(M(0))`, a type as a macro argument in an expression | documented adjustment |
| miniz | `MINIZ_EXPORT` comes from a generated header the corpus lacks; cc rejects it too | not valid input |

## Decisions

1. **Skip the C++ arm.** x2c output is always compiled as C, so the arm
   under `#ifdef __cplusplus`, `#if defined(__cplusplus)`, and the `#else`
   of `#ifndef __cplusplus` can never be active. The plan skips exactly
   those spellings and keeps parsing every other arm. This changes the
   documented rule and needs Gary's yes. Alternative: leave the rule and
   let stb_ds stay a documented adjustment.
2. **Treat one function defined in two arms of one conditional as one
   definition.** This is also a rule change, narrower than 1: the
   duplicate check learns the conditional group it is in. Alternative:
   document the adjustment; tinyexpr is the only corpus unit that needs it.
3. **`#if 0` and `_MSC_VER` arms are hidden too.** Both are C truths of
   the same kind as `__cplusplus`: x2c output is never compiled by MSVC and
   `#if 0` is never active. Decided during implementation; the spellings
   live in one place, `_never_defined` in `src/compiler.x`.

## Implementation

Six connected changes plus the second-layer fixes above, delivered together
to `main`.

### A. Carry linkage braces across collection segments

Dropped during implementation: once F hides the `__cplusplus` arm, the
guard's braces are never parsed, so no count is needed. What remained was
that a stray `}` at file scope ended the tokenizer's scan; `lib/tokenizer.x`
now keeps the base mode and leaves the brace to the parser. The original
design follows for the record.

`_file` in `src/collect.x:462-495` already threads `private` through
`_flush_segment`/`_parse_segment` (`src/collect.x:363-380`). Thread the
open linkage count the same way: an `int linkage` on `Compiler` beside
`source_private`, handed across segments where `shadow.source_private` is
today. `Compiler.skip_linkage_brace` (`src/parse.x:1618`) increments it on
`extern "C" {` and accepts a file-scope `}` when `c.braces.len() ||
c.linkage`, decrementing. `_shallow_parse_loop` (`src/compiler.x:1191-1268`)
reports unmatched braces only for the entries that are not linkage opens.
The full parse sees one token stream and needs nothing.

### B. Declaration-prefix macros in unit source

`_note_object_macro` (`src/compiler.x:1326`) records `<empty>` or `1`.
Extend it to classify the body: empty, a storage class, `inline` or
`__inline`, or an `__attribute__`/`__declspec` form marks the name as a
declaration prefix, keeping the storage symbol when there is one. Replace
the `compiler.shallow` guard in `_skip_empty_macro` (`src/parse.x:248-257`)
with that classification so `_storage_class` and `_type_qualifiers`
consume the prefix in both passes, contributing `static`/`extern` to the
storage list so `Type.is_static` and header exposure stay right. A name
with conflicting definitions across arms, or an undefined prefix, is kept
as a raw string specifier, the representation `_make_file_init_func`
already uses for `("__attribute__((constructor))")` (`src/generate.x:149`);
`Type.base_type` and the emitter pass such strings through.

### C. Trailing attributes

`_declarator_suffix` (`src/parse.x:766-781`) consumes a trailing
`__attribute__ (( ... ))` or a recorded function-like annotation macro
call with the balanced skipper `_skip_shallow_expression`
(`src/compiler.x:~760`), storing the raw text as a string modifier the
same way as in B, so the emitter reproduces it. `_note_object_macro` then
also records function-like names whose body is empty or an attribute form.
Remove the one-token `else c.next()` fallback in
`_shallow_finish_declaration` (`src/compiler.x:750`); it is what turns
these into `expected ')'` deep inside the following tokens.

### D. GNU qualifier spellings

Accept `__restrict`, `__restrict__`, `__inline`, `__inline__` as the
standard symbols in `Symbol.is_type_qualifier` / `is_inline`
(`src/type.x:194-197`), matching the erasure list the host preprocessor
path already applies (`src/toolchain.x:451-454`). Call `_skip_empty_macro`
from `_pointer` (`src/parse.x:651-660`) so an empty macro after `*` is
skipped as it already is among leading qualifiers.

### E. Flat binding type for qualified aggregate definitions

`_declaration_group` at `src/parse.x:1122-1126` builds
`%( @storage @quals ($tag $name) )`, nesting the tag. Build it the way
`parse_declaration_argument` (`src/parse.x:1404-1408`) already does:
`%( @storage @quals $aggregate $tag_or_body )`. `List.type_from_ast`'s
single-element unwrap (`src/type.x:1035`) was masking this for the
unqualified form; after the fix it is no longer relied on there.

### F. Conditional arms (decisions 1 and 2)

`Compiler.leading_preproc` (`src/compiler.x:1307`) already turns each
directive into a `(preproc "text")` node, and `preproc_conditional_kind`
(`src/ast.x:68`) classifies it. When an `<open>` matches the three
`__cplusplus` spellings, the parser skips tokens to the matching
`<branch>` or `<close>`, counting nested opens with the same classifier;
for `#ifndef __cplusplus` it skips the `#else` arm instead. The directive
nodes stay in the AST so emission is unchanged. For decision 2, the
full-parse loop tracks the conditional group from the same classifier (as
`src/cache.x:445` does for initializers), and
`_record_function_definition` (`src/compiler.x:2696`) accepts a second
definition that sits in a different arm of the same group, anchoring any
real duplicate at the function's own binding token instead of `c.token`.

### Documentation

`docs/src/reference/language.md` (host preprocessing paragraphs near
2660-2685) and `docs/src/guide/from-c.md:68-83`: the C++ arm is skipped;
declaration-prefix macros, trailing attributes, and GNU qualifier
spellings are accepted in units. `packages/FOREIGN-C-QUALIFIERS.md:57`
drops the attribute limit. Update the stale status header in
`plans/x2c-c-on-ramp.md`.

## Validation

Fixtures under `unittest/compiler-fixtures/`, each `h c stdout status`
unless noted:

- `c-linkage-include`: the guard with an `#include` inside it and a
  `#if 0 }` unconfuser, in a unit and in a local header
  (`c-linkage-values-include.h`).
- `c-prefix-macros`: empty, `static`, `extern`, `__inline`, and undefined
  prefixes; a `static`-prefixed function must not appear in the header.
- `c-trailing-attribute`: `__attribute__((format(...)))` on its own line
  and an annotation macro call; the C output carries them.
- `c-gnu-qualifiers`: `__restrict` after `*`, `__inline` functions.
- `c-static-aggregate`: `static`, `const`, anonymous, and pointer
  (`static struct S {...} *P;`) forms with field call and index.
- `c-cplusplus-arm` (`c stdout status`): a template under the guard, an
  MSVC arm, `#if 0`, and one function in two arms.
- `c-tagged-object`: `struct Point {...} origin;` and `enum Mode {...} mode;`
  at public file scope, and a public prototype over a struct defined later.

Corpus proof, not gated: translate all 22 units with
`builds/0/x2c translate u_NAME.x --out-dir DIR` and compile each result
with `cc -c -iquote include/x2c`; 14 of 22 pass on 2026-09-16. The corpus is 5.4 MB of
third-party source and stays under `.context/`, not in the repository.

Focused checks during work: `make x2c` and the fixtures above. Publication
uses `tools/gate-state.py ensure agent-pr-check`; A and B change what a
collected header yields, so expect the two-round bootstrap refresh.

## Plan review

- **Trusted facts.** `preproc_conditional_kind` establishes directive
  kind; `_note_object_macro` establishes what a name expands to; the
  tokenizer establishes token identity. No consumer rechecks them. The
  brace stack remains the single owner of grouping; A adds a count that
  the same operation maintains, not a second scan.
- **Deleted or reused.** C deletes the `else c.next()` fallback. E deletes
  a divergent construction in favor of the one `parse_declaration_argument`
  already uses. B reuses the raw-string specifier representation and the
  existing `_skip_empty_macro`; D reuses the host-cpp erasure list as the
  spelling set; F reuses `leading_preproc` and the classifier. The one new
  lasting state is the linkage count on `Compiler`, needed because
  segments are separate compilers by design.
- **Idiomatic x2c.** Every change is a match or template edit on the
  existing parse operations; no preprocessor, no second parser, no origin
  tracking.
- **Validators and negative fixtures.** None added. The fixtures are
  positive: they protect generated C that must carry attributes and
  storage class correctly, and header exposure of `static` functions.
  Existing parse diagnostics already report a real unbalanced group or
  a real duplicate definition.
