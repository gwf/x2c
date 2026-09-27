# Real parser and native-meta prototype

Isolated managed worktree: `/Users/gary/.codex/worktrees/dual-parser/x2c`.
Exact base: `1b23aaa7e103461c3b219b9e10546aeb35384b60`.
`make build-safe` and focused `make build` succeeded. No fetch, rebase, commit,
publication gate, push or production worktree source edits. Compiler is
`builds/0/x2c` in that worktree. Full source-only patch is `parser3.patch` in
this directory; reverse earlier parser patches before applying this full one.

## What the real source forms establish

`Macro` is a List typedef in the prototype, with complete existing `macrodef`
Lists including body, parameter descriptors, fresh rows and capture IDs. The
parser exposes bare `$sum` as a cached data expression. Descriptor bodies are
not opaque, and helper functions inspect/pass/return them normally.

| Form | Behavior demonstrated |
| --- | --- |
| `$sum` | snapshotted global named descriptor; passes ordinary meta parameters |
| `$sum(a,b)` | existing named syntax expansion; preserved inside program and meta computation |
| `sum` for `Macro sum` | ordinary variable value and ordinary passing/selection |
| `sum(a,b)` for `Macro sum` | data construction via shared descriptor body |
| `case sum(?a,?b)` | runtime descriptor-valued pattern from same body; source capture layout is explicit |
| `macro Expression(Expr $a, Expr $b) => $a + $b` | actual anonymous expression producer, one enclosing semicolon |

A same-spelled ordinary function, local macro and global macro retain their
existing precedence. Executed collision output: `103 23 3 103 103`, including
bare ordinary function pointer under a local macro and `(sum)(args)` escape.
A runtime `choose(argc == 1, plus, times)` selects genuinely different bodies;
dynamic Match returns `1 0` for plus and product against the same addition.
Literal `*` initially behaved as a wildcard in an inadequately role-aware
helper; quoted operator roles fixed that false positive. Literal payload nodes
are preserved with `!quote` and never traversed for template invocations.

Anonymous factory/pass/return is compiled through the actual project helper.
`meta static Macro lexical_wrap(Macro inner) =>
 macro Expression(Expr $left, Expr $right) => (inner($left,$right));`
retains a structural `tpl-call` in the shared body. Its parser-owned capture
map is copied into inspectable `(env CAPTURE-ROWS)` data at closure creation.
The helper consumes a captured Macro callee by identity-record content; no
native closure pointer crosses the wire. Construction and recognition both
inline that structural child body. Actual output `lexical composed 1 7`
proves matching plus ordinary program insertion/evaluation. Multiple immutable
Lists pass/return between helper functions; this is no preprocessing stunt.

`parser-complete3.x` and `parser-lexical.log` reproduce the successful basic,
collision, dynamic and anonymous/lexical tests. Root independently ran them.

## Real typed and repeated/sequence probes

`parser-categories2.x` executed successfully; `parser-categories2.log` shows:

```
repeated 1 0
sequence 0 3 rebuild 0 3
source Type 1
Type 1 1
Name 1 1
Statement 1 1
```

Repeated Expr holes reuse one logical parameter and enforce existing Match
identity equality; the mismatch changes a binding identity. Alpha-equivalence
for declaration-bearing repeats belongs to the separately integrated contextual
Match prototype, not this source helper.

Sequences cover empty and nonempty final argument tails, ordered reconstruction
and actual Macro-variable application. Runtime dynamic sequence cases use
`*items` explicitly, so the compiler knows the capture is List-valued even when
it cannot know the runtime descriptor's grammar interface.

The Type example is `sizeof($type)` with a real source capture `sizeof(int)`.
It preserves explicit canonical type structure and ignores derived expr types.
An earlier hand-authored guessed `(sizeof (int))` shape did not match because
actual syntax is `(sizeof (parens (decl (int) ...)))`; that disproved the guessed
shape only. Construction and recognition of the actual producer shape pass.

Name covers expression receiver/member label projection and reconstruction.
It does not prove every declaration-name/member correlation. Statement covers
recognizing a direct return and rebuilding its syntax; result macro bodies use
`seq`, so the explicit category adapter extracts the sole statement before
matching it. A raw result `seq` against a direct return pattern correctly failed
before that adapter. These are stage/category choices, not a new validator.

## Compatibility and implementation owners

The existing `meta-template-calls.x` fixture executes under the prototype and
prints its checked-in values `14 8 11`, `91 2 91`, `42 42 3 2`. An exploratory
patch made every named Expression call in a meta body construct data; this
would change existing meta computations. It was removed from `parser3.patch`.
Macro-valued calls provide the explicit data-construction route; named Expr
calls preserve existing semantics. Existing Unit/Statement deferred calls are
unchanged.

Authoritative prototype owners:

- `src/macros.x`: named getter; common definition parser accepts anonymous
  expression; captures are attached as ordinary data; source pattern arguments
  expose explicit layout before runtime matching.
- `src/expressions.x`: anonymous producer expression; Macro-valued invocation
  lowers to data construction; nested Macro callees retain structural tpl-call.
- `src/compiler.x`: long Atom cache literals (previously blank generated C);
  dynamic `Macro_pattern` capture layout uses existing MatchCaptureLayout and
  existing dynamic emitter. No second Match engine.
- `src/stage.x`: explicit Macro returned-data caching. A production change
  should generalize existing valid alias-to-List result handling where possible,
  not turn this narrow prototype branch into a parallel result validator.
- `lib/meta.x`: Macro typedef available to generated helper headers.
- Source helper: pure shared-body construction/pattern projections, child
  inlining, environment data. It is prototype code, not a finished library ABI.

## Specific limits, not conclusions against the architecture

- Construction helper does not process `fresh` rows. Introduced declarations
  remain symbolic; ordinary expansion still owns their allocation. It does not
  prove macro-variable construction with introduced local declarations.
- Source pattern helper lacks automatic declaration ownership/injectivity,
  boundary maps and alpha comparison for arbitrary binder-bearing captures.
  The contextual Match prototype establishes runtime feasibility separately.
- Lexical value closure supports captured Macro values used as structural
  callees. Ordinary scalar/runtime capture values and noncallee Macro reference
  occurrences are not implemented. Prototype capture type recovery uses
  spelling lookup; production should query the captured identity's facts.
- Multiple nested templates with overlapping internal slot names have not been
  tested; proper composition must rename interfaces, not rely on this arithmetic
  example's compatible names. Free binding rebasing/fresh cloning remain shared
  compiler-owner work.
- Dynamic case argument arity/category mismatch diagnostics are not complete;
  the explicit capture arguments establish layout, not descriptor authenticity.
- Recognition eagerly inlines the captured structural child tpl-call. Retained
  call-vs-expanded child recognition needs an explicit stage selection; no
  universal reverse evaluator exists.
- Pure helpers need same-unit availability in this bounded fixture. A separate
  `.x` helper function caused native unresolved targets; moving it into the
  fixture fixed that implementation issue. An unnecessary bodyless meta forward
  declaration caused `no binding for Macro_inline`; using an ordinary pure
  helper declaration avoided expanding compiler native-meta registry work.
- An attempted deferred Statement splice insertion remains a failed prototype
  (`parser-deferred-insertion-fails.x/.log`), with exact `syntax cannot be
  constructed at this position`. This does not reject deferred construction:
  existing checked-in meta-template fixtures still execute correctly.
- No corpus, performance, bootstrap refresh/publication or platform-wide test
  was run. No production implementation has been delivered.

### Typed surface qualifications

The corrected PASS fixture is also saved as `parser-categories3.x/.log`; the
original failed `parser-categories.x` remains separate evidence. A Type hole is
logically singular, but its current canonical representation is a List splice.
The prototype's `case pattern(*type)` exposes that representation. Production
must derive the internal span capture and publish the logical Type value for
`case pattern(?type)`; do not require users to change logical hole multiplicity
because its AST occupies multiple cells. Statement rebuilding is recognized
only after the fixture explicitly extracts the sole result `seq` element. This
proves projection feasibility, not complete automatic category integration.
A root-category alternative matching both direct statement and `(seq SAME)` is
viable for singleton block-item results without erasing arbitrary scopes.

### Additional experiments, deliberately separated

`complete14.log` in the isolated worktree still fails after adding deferred
Statement inspection/insertion experiments: `syntax cannot be constructed at
this position` reported at the source root. Do not replace the previously
validated `parser-complete3.x` with that combined failing experiment. The
multi-step increment transform was included there but consequently has not
executed; root is running it independently from the working fixture. Explicit
pending-invocation matching against expanded syntax is not established by this
worker. Construction through existing named Unit/Statement templates remains
proven by the unchanged checked-in `meta-template-calls` compatibility fixture.
