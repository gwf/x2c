> Status: active
> Planned 2026-10-28 against `origin/dev` `25c91608e` from reproduced
> probes (`builds/0/x2c translate` on the reproducers listed under
> "Evidence"). Gary funded the work on 2026-10-28 and delegated it to one
> implementing session with shared-integrator delivery. The three
> decisions below were made by the planner; Gary can overrule any of them
> before the implementation settles on them.

# An x2c-owned C preprocessor

x2c parses a unit before any macro is expanded, so a C macro that supplies
grammar does not parse, and a macro body is never translated. This change
expands the macros x2c can see before the parser runs, evaluates the
conditionals it can decide, and keeps generated C configuration-neutral for
the conditionals it cannot. No language syntax changes.

## Evidence

Reproduced with `builds/0/x2c translate --out-dir SCRATCH FILE.x`:

| Source | Result today |
| --- | --- |
| `#define FIELDS(X) X(alpha) X(beta)` / `#define DECL(n) int n;` / `FIELDS(DECL)` | `parse: unexpected end of file` or `expected ';', '{', or '=>'` |
| `#ifdef __GNUC__` / `int main(void) {` / `#else` / `int main() {` / `#endif` | same parse error at the `#else` line |
| `#define NAME(n) fn_##n` / `int NAME(a)(void) { ... }` | same |
| `#define FOR_N(i, n) for (int i = 0; i < n; i++)` / `FOR_N(k, 3) body;` | `parse: expected ';'` |
| `#define GET(c) c.get()` with an x2c receiver | the body reaches `cc` untranslated: `no member named 'get'` |
| `#define N 10` / `Var v = N;` | `type: cannot convert an unresolved expression to Var` |
| `#define SWAP(a,b) do { ... } while (0)` / `SWAP(x, y);` | passes; the use parses as a call |
| `#define INT int` / `INT x;` | passes through the prefix heuristics |

`--cpp-symbols` and `--live-symbols` do not change the parse results: the
host output only fills the global symbol table
(`src/frontend.x` `_preprocess_input`, `docs/src/reference/language.md`
"Host preprocessing", lines 4611-4614).

The three failure classes are: macros that supply grammar, macro bodies
that use x2c syntax, and untyped expansions.

How directives flow today:

- The tokenizer turns each directive line, with its continuations, into one
  `<preproc>` token (`lib/scan.x` `scan_preprocessor`; `lib/tokenizer.x`
  `_preprocessor`). The parser keeps each as a `(preproc "text")` node at
  file scope or inside a block (`src/parse/binding.x:254`), and generation
  and emission place them back where they were written
  (`src/generate/projection.x` `_add_preproc`, `src/emit/dispatch.x`
  `_preproc`).
- `src/preprocess.x` (449 lines) hides arms C never takes (`#if 0`,
  `__cplusplus`, `_MSC_VER`, the Windows names off Windows), classifies
  `#define` bodies as declaration prefixes, wrappers, annotations, or
  strings, ranks conflicting definitions across arms (`_prefix_rank`), and
  tracks layout attributes. `src/literals/atoms.x:75` warns when a bare
  atom inside a literal spells an object macro.
- Collection (`src/collect/walk.x` `_split`, `_include_file`) follows
  `#include` itself through the includer's directory, the working
  directory, `lib/`, `src/`, and `-I` directories, never the system
  directories. A header it cannot resolve stays in the emitted C for the C
  compiler.
- The compiler's own sources use the preprocessor sparingly: 4 `#define`
  lines in `src/`, 51 in `lib/` (the `VAR_*` bit constants, `JSON_MAX_DEPTH`,
  `LISP_READ_DEPTH_MAX`), and nine conditionals, all on host facts
  (`__APPLE__`, `__GLIBC__`, `__BYTE_ORDER__`, `_WIN32`).

The retired on-ramp corpus (`plans/archive/x2c-c-on-ramp-corpus.md`,
"Remaining") left cJSON, sds, and stb_sprintf failing on grammar-supplying
macros and tinyexpr on a type as a macro argument. Gary declined a rule for
object-like definitions in untaken arms on 2026-09-24 because it "would
begin a preprocessor" (`plans/archive/x2c-header-collection-gaps.md:44-45`).
This plan begins one deliberately.

## Decisions

1. **Expansion precedes parsing, and generated C carries the expansion.**
   The parser reads expanded tokens, so a macro body is translated like
   any other source, including x2c syntax inside it. The emitted C contains
   the expanded tokens at the invocation site; the `#define`, `#undef`,
   conditional, and `#include` directives stay where they were written.
   The alternative, keeping the invocation text in the output, is
   impossible once a body carries x2c syntax that lowers to different C,
   so it is not pursued.
2. **x2c expands only the macros it can see.** A macro is visible when it
   is defined in the unit, in a `.x` file or project header that x2c reads
   through its own include search, or on the command line with `-D`.
   Macros from headers x2c does not resolve, which are the system headers,
   stay unexpanded and reach the C compiler as today. `__FILE__`,
   `__LINE__`, `__COUNTER__`, and the other predefined names stay for C.
3. **Conditionals are evaluated when decidable and parsed both ways when
   not.** A condition is decidable when every name it tests is visible
   under decision 2, is in the never-defined set (`__cplusplus`,
   `_MSC_VER`, and off Windows `_WIN32`, `_WIN64`, `__CYGWIN__`), or is a
   literal. A decidably false arm is hidden as today. An undecidable
   condition, such as `__APPLE__` or a name a system header may define,
   parses every arm as today. A macro defined or undefined inside an
   undecidable arm is visible only to the rest of that arm; after the
   group closes, the name is conditionally defined, its uses stay
   unexpanded for the C compiler, and the existing prefix heuristics in
   `src/preprocess.x` classify it. This keeps the emitted C neutral for
   platform conditionals and makes yyjson's `#define bool unsigned char`
   in an untaken `#elif` arm harmless without a special rule.

Routine choices, settled here:

- Full C99 expansion semantics: object-like and function-like macros,
  `#` stringification, `##` pasting, `__VA_ARGS__`, hide sets with rescan,
  nested invocations, and redefinition rules. `__VA_OPT__` follows if the
  tokenizer already accepts it; otherwise it is reported as unsupported at
  the definition.
- No expansion inside `%(...)` literals, `<sym>` atoms, string and
  character literals, or `$name` holes; the warning at
  `src/literals/atoms.x:75` stays. Everywhere else an identifier token that
  names a visible macro expands as C would, including inside an x2c
  `macro` body at its definition site.
- `#if` expression evaluation covers integer constants, `defined`,
  arithmetic, shifts, comparisons, bitwise and logical operators, and
  `?:`, over `long`. An identifier that is not a visible macro makes the
  condition undecidable rather than zero.
- `#include` inside a macro body, computed includes, `#pragma` other than
  `indent` and `once`, `#line`, and `#error` keep today's handling:
  directives stay in the stream and C reads them.
- An expanded token keeps the invocation's `line`, `col`, and `pos`, so
  source mapping, located diagnostics, and the text slicing in collection
  behave as for an x2c macro expansion: the location is the use. The
  tokenizer records each token's expansion origin in a side table, not in
  `struct Token`, because that struct is shared with every command.
- A diagnostic on an expanded token names the invocation and adds one
  note naming the macro and its definition site, in the form
  `src/macros/diagnostics.x` already uses for x2c macros.
- `--dump-tokens` prints the parser's input, which is now the expanded
  stream, and marks expanded tokens. The host modes `--cpp-symbols`,
  `--live-symbols`, and the `--dump-cpp*` dumps are unchanged by this work.
- `-D NAME` and `-D NAME=VALUE` on `translate`, `build`, and `run` define
  the macro for x2c expansion as well as for the C compile step. A project
  profile's defines reach translation the same way.

## Implementation

One coherent change, in this order, so each step is probe-able with
`builds/0`:

1. **Macro table and expander** in a new module `src/cpp/` (`cpp.x` entry;
   members `macros.x` for parsing `#define` and `#undef` lines and the
   path-scoped table, `expand.x` for invocation collection, substitution,
   `#` and `##`, hide sets, and rescan, `conditions.x` for the tri-state
   `#if` evaluator). The expander runs over `Tokenizer.tokens` after
   `scan` and before any consumer, rewriting the token array in place and
   recording the origin side table on the `Tokenizer`. Reuse
   `Compiler.preproc_directive`, `preproc_conditional_kind`, and the
   directive scanning in `src/preprocess.x` (`_macro_directive`) rather
   than writing a second directive reader.
2. **Conditional evaluation** replaces `preproc_open_state` and
   `_never_defined` in `src/preprocess.x`: `scan_conditionals` asks the
   evaluator for each group's state (hidden, taken, undecidable) and keeps
   its layout and arm-stack bookkeeping. The never-defined set moves into
   the evaluator as known-false names.
3. **Visibility across files.** A cold walk of an included file
   (`src/collect/walk.x` `_walk_cold`) exports the file's visible macro
   definitions in its collection entry, and the `.xi` interface records
   them, so a replayed include supplies the same table as a cold walk.
   `_split` threads the macro table across include segments the way it
   threads privacy today. The includer's expander starts from the tables
   of everything it included, in include order, before expanding its own
   tokens that follow each include. Verify that a public `#define` in an
   included `.x` file reaches the includer's generated C the same way the
   C compiler would see it through the generated header.
4. **Prefix heuristics narrow to conditionally defined names.** In
   `src/preprocess.x`, `note_object_macro`, `_note_function_macro`, and
   `_note_prefix_macro` run only for names the evaluator marks
   conditionally defined; an unconditionally defined name is expanded and
   never reaches them. `_prefix_rank` and the layout tracking stay.
5. **Command line.** `-D` reaches `CliRequest` for translation (today
   `src/cli/parsing.x:189` routes it to the C compiler only) and the
   expander's initial table. `--dump-tokens` marks expanded tokens.
6. **Diagnostics.** Parse and type errors on expanded tokens add the
   macro note. Expansion errors (unterminated invocation, bad `##`
   result, wrong argument count) report at the invocation with the same
   note.
7. **Documentation.** `docs/src/reference/language.md`: rename "Host
   preprocessing" to "Preprocessing", state decisions 1-3 as rules,
   delete the "does not fully preprocess" and "macro expansion that
   supplies grammar" limitations, keep the host-mode paragraphs, and
   revise the `#define` paragraph under "C foundation" (lines 471-475) and
   the `->` rule for macro bodies (line 481). `docs/src/guide/from-c.md`
   "Before bringing over a C source file": replace the parse-before-
   preprocess warning. `docs/src/reference/cli.md`: `--dump-tokens` and
   `-D`. `docs/src/internals/architecture.md`: add the expansion step to
   the pipeline and correct the `cc -E -P` drift at line 286.
8. **Review the completed diff** before handing off: look for a second
   directive reader, checks that repeat what the evaluator established,
   and heuristics that step 4 made unreachable; delete them.

## Compatibility

- Generated C changes wherever a unit uses a visible macro: the expansion
  replaces the invocation. The runtime's `VAR_*` constants expand into the
  generated runtime C, so the bootstrap changes at integration. The
  integrator owns that refresh; the implementing session performs a local
  rebootstrap only if the seed cannot consume the change, which this plan
  does not expect, and must pass `make stage-2`.
- A program whose macro use parsed before continues to parse; the
  expansion is what C would have produced. A program that relied on x2c
  reading an unexpanded prefix macro keeps working, because an
  unconditional prefix macro now expands to the same words.
- Behavior preserved on purpose: platform arms parse both ways, system
  macros pass through, directives stay in the output, `.` reaches members
  inside a macro body only when the body is now parsed (so `->` is no
  longer required there; the rule text changes, the old spelling still
  works).
- Public runtime signatures are unchanged. `struct Token` is unchanged.
  `Tokenizer` gains the origin side table; the tokenizer's public
  operations keep their signatures.

## Validation

- Compiler fixtures under `unittest/compiler-fixtures/` for each row of
  the evidence table, plus: nested invocation with hide set, `#`
  stringification, `##` producing an x2c identifier, variadic macro,
  `#undef` followed by reuse of the name as an identifier, a macro
  defined inside an undecidable arm and used after it (stays unexpanded),
  a macro defined in an included `.x` file and used by the includer with
  and without a replayed interface, `-D` on the command line, and a
  diagnostic inside an expansion showing the note.
- `make verify-fixtures` with reviewed expectation deltas: existing
  fixtures whose generated C now shows expansions change; accept only
  those deltas.
- The reproducers under "Evidence" translate, compile, and run with the
  expected output.
- `unittest/probes/run-header-cache.sh` for interface replay parity.
- `make verify`, `make examples`, `make doc-check` after the book edits,
  and `make stage-2` on the final tree.
- Optional: the corpus units cJSON, sds, and stb_sprintf from the retired
  on-ramp corpus translate, if their sources are at hand; this is
  evidence, not a gate.

## Design review

- Facts and their owners: the tokenizer owns directive tokens; the new
  evaluator owns which arm is hidden; the macro table owns visibility.
  Downstream parsing relies on them; no second check of hidden arms or of
  visibility remains in `preprocess.x` after step 4.
- Reuse: directive classification, arm tracking for emission, layout
  marks, and the prefix heuristics for conditionally defined names stay as
  they are. No second tokenizer, no text-level substitution, no origin
  field on `struct Token`.
- Not pursued: expanding system-header macros (needs host facts from `cc`
  and a sysroot for a wasm compiler; a later change can add it behind the
  same table), rewriting output to the invocation text, and retiring the
  host modes.
- Size: about 1.2 to 1.8 thousand lines for `src/cpp/`, about 150 lines
  removed from `src/preprocess.x`, about 200 lines in collection and
  interfaces, plus fixtures and book text.
