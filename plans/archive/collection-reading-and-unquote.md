# Collection reading and parenthesized unquote

> Status: done
> Specification and implementation plan approved in discussion, 2026-10-25.
> Implemented, validated with `agent-pr-check`, and published to `dev` in
> `b9eed26d1` on 2026-10-25.
> Its prerequisite, [Native compiler with runtime Lisp](native-compiler-runtime-lisp.md),
> landed on dev in `ff3aba2aa` with cleanup `735e72f73`. Compiler `$(...)`
> and `@(...)` evaluation is gone; implementation starts from `735e72f73`.

## Result and scope

Give grouped insertion and splicing parenthesized expression boundaries.
Add an evaluated List constructor and an explicitly evaluated Map constructor.
Preserve the natural Array and Map forms, nested quoted data, named holes,
runtime representations, and the `%!` lambda and `$!` quotation prefixes.

Replace braced grouped insertions and splices, including computed holes in
code quotations. Gary selected replacement and source migration, rather than
compatibility aliases. `${...}` becomes the evaluated Map spelling; it must
never silently retain its old expression-insertion meaning.

The compiler-Lisp prerequisite owns removal of its evaluator and syntax.
Do not repeat that work here or change runtime Lisp or its reader punctuation.
`$%`, `%$`, and `$[...]` are outside this plan. No runtime API, ABI, ownership,
macro binding, or general C expression precedence change is selected.

## Specification

### Natural forms and explicit prefixes

In ordinary Ecstasy code, collections have different natural reading rules:

| Source form | Result | Reading rule |
| --- | --- | --- |
| `%(a b)` | List | Quoted data; bare names are Atoms. |
| `$(a, b)` | List | Ecstasy expressions, converted to Var elements. |
| `[a, b]` | Array | Ecstasy expressions, as today. |
| `%[a, b]` | Array | Quoted data with comma separators, as today. |
| `{a: b}` | Map | Bare identifier key is an Atom; value is an expression, as today. |
| `%{a: b}` | Map | Quoted keys and values, as today. |
| `${a: b}` | Map | Both key and value are Ecstasy expressions. |

Ordinary parentheses retain C grouping and call syntax. A destination type
does not turn `(a, b)` into a List. Existing context-sensitive recognition of
bare braces, empty collections, C initializers, and compound literals remains.
An explicit `${}` always constructs an empty Map in an expression position.

An explicitly selected quoted context applies to nested bare delimiters:

```text
%(record (name ada) [red, green] {state: ready})
```

Here the nested List, Array, and Map all contain quoted data. Nested quoted
containers need no repeated percent prefix. Once an insertion enters Ecstasy
expression syntax, ordinary natural forms apply again. For example,
`%(record $([red, green]))` contains an Array of two variable values.
This is not an inherited evaluated mode that changes bare Map keys:
`$({name: value})` in ordinary code constructs a one-element List holding a
natural Map with an Atom key, while `$(${name: value})` evaluates the key.

### Grouped insertion and List splicing

Within quoted Lists, Arrays, Maps, and interpolated Strings:

- `$name` continues to insert one variable value.
- `$(expression)` inserts one complete Ecstasy expression's value.
- In a quoted List, `@name` and `@(expression)` splice a List's elements.
- Arrays, Maps, and Strings acquire no runtime sequence-splice operation.

The grouped form contains one expression. Commas there are C comma operators:
`%(head $(prepare(), value))` inserts only `value`, after calling `prepare`.
Named forms still read one identifier. Inside a quoted String, text after
`$name` remains text; write `%"answer: $(calculate(x))"` for a call.
Existing conversion rules, literal dollar escapes, and left-to-right,
exactly-once insertion evaluation remain unchanged.

The former `${expression}` and `@{expression}` grouped forms are removed.
For quoted data, `${key: value}` instead constructs one evaluated Map value,
including when nested directly in a quoted collection. It is not an unquote.
For a String, use an insertion to obtain any Map's supported String conversion;
there is no direct Map opener inside String text.
An unescaped `${` in interpolated String text reports the retired insertion
spelling. Use `$(${key: value})` to insert an evaluated Map expression there,
subject to the existing conversion rules.

These examples fix the contextual meaning of `$(`. With `x` equal to `7`:

| Source | Value |
| --- | --- |
| `%(head $x)` | `%(head 7)` |
| `%(head $(x))` | `%(head 7)` |
| `%(head ($x))` | `%(head (7))` |
| `%(head $($(x)))` | `%(head (7))` |

In the last row, the outer `$(` enters Ecstasy expression syntax. The inner
`$(x)` is an evaluated List constructor. With `xs` equal to `%(7 8)`,
`%(head $(xs))` contains a nested List, while `%(head @(xs))` is `%(head 7 8)`.
Retain the existing List conversion rules for a splice operand.

### Evaluated List constructor

In an ordinary Ecstasy expression position, the grammar is:

```text
evaluated-list := '$(' [ evaluated-item { ',' evaluated-item } [ ',' ] ] ')'
evaluated-item := assignment-expression | '@' identifier | '@(' expression ')'
```

Each assignment-expression is one element. Use parentheses to make a comma
expression one element: `$((prepare(), value), other)`. Accept an empty List
and an optional trailing comma, consistently with evaluated Array literals.
`$()` produces the existing empty List value, not a new mutable container.

Evaluate elements once each, left to right. Apply existing Var conversion,
List canonicalization, caching, lifetime, and destination-directed typed List
rules. Reject values that existing List construction rejects, including
`void`; do not invent a new validation layer. A List-valued element remains
one element; there is no implicit flattening. An explicit `@name` or
`@(expression)` item splices a List's elements, with the same meaning and
conversion rules as in a quoted List and in a List-rest call. Gary selected
this on 2026-10-25. One public compiler operation, `Compiler.list_expression`,
builds a List from element expressions, splice items included.

### Evaluated Map constructor

In an Ecstasy expression position, or as an explicitly prefixed value in a
quoted collection, the grammar is:

```text
evaluated-map := '${' [ evaluated-entry { ',' evaluated-entry } [ ',' ] ] '}'
evaluated-entry := assignment-expression ':' assignment-expression
```

Retain existing Entry-position macro production and sequence handling.
The only entry-reading difference from a natural Map is that a bare identifier
key is evaluated. For example, with `String key = "answer"; int n = 42;`:

```text
{key: n}        key is Atom key; value is 42
%{key: n}       key is Atom key; value is Atom n
${key: n}      key is String answer; value is 42
${<key>: n}    explicit Symbol key; value is 42
```

Existing parenthesized evaluated keys in natural Maps remain legal. The new
prefix supplies a direct spelling; removing legal ordinary expression keys
would enlarge this change unnecessarily.

Evaluate each key followed by its value, then subsequent entries, once each
in source order. Reuse existing Map conversions, duplicate-key behavior,
destination-directed typed representations, and fresh mutable identity.
`${}` requires no inferred destination type to be recognized as a Map.
Within evaluated expressions, nested bare Maps retain natural key rules;
use another `${...}` to evaluate a nested Map's keys explicitly.

### Code quotations, macros, and pattern positions

Keep `%!(...) => ...`, `$!(...)`, `$!{...}`, typed quotation forms, and
anonymous macro application semantics unchanged. Named `$hole` and `@holes`
also retain their current roles.

In a code quotation, replace computed `${expression}` holes with
`$(expression)` and computed `@{expression}` sequence holes with
`@(expression)`. Each grouped hole computes one expression in the surrounding
quotation-construction environment, once, in source order. Its type and syntax
position determine the hole kind exactly as today. Nested quotations own their
own holes. For example:

```text
meta static List offset(List operand, int amount) =>
  $!( $operand + $(amount + 1) );
```

Here `amount + 1` executes while building the quotation. The resulting addition
involving `operand` belongs to generated code. `${key: value}` inside the
quotation is now an evaluated Map expression in that generated code, not a
computed hole. Its unprefixed names resolve under ordinary template rules.

Distinguish this from an insertion inside a percent literal in the quotation:

```text
$!( %(answer $(calculate())) )
```

Here `calculate()` runs when the generated List expression executes.
`$!( %(answer $($(amount + 1))) )` instead computes `amount + 1` at quotation
construction and inserts that value into the generated List expression.
Preserve this existing two-boundary capability without new stage markers.

In quotation code positions, `$(` denotes a computed hole, so a generated
evaluated List can instead be expressed with a percent List and runtime
insertions: `$!( %( $(a) $(b) ) )` generates a List of the runtime `a` and `b`.
Do not add another escape spelling merely to reproduce the constructor's text.

Named macro templates retain explicit named holes; they do not gain arbitrary
computed-expression holes. Parenthesized runtime insertion inside their quoted
literals remains available. Preserve existing sequence placement rules for
call arguments, declarations, entries, and other supported template positions.

Preserve the distinction between a quoted Map key insertion and an entire
Entry-producing insertion. `%{$(key): value}` inserts a computed key, while
`%{$($handler(arguments))}` inserts the Entry macro's rows. The latter remains
a syntax-position operation, not an expression expected to produce a Var.
Similarly, migrate template wrappers `%[${@items}]` and `%{${@rows}}` to
`%[$(@items)]` and `%{$(@rows)}`. Their sequences fill existing argument and
Entry positions; these wrappers do not introduce runtime Array or Map splicing.
The computed sequence-call form `%{${@rows(arguments)}}` becomes
`%{$(@rows(arguments))}`. In these positions, try the existing Entry/sequence
production before falling back to ordinary expression insertion.

Migrate braced macro-pattern insertions to parenthesized boundaries too:
`case ${$name(...)}` becomes `case $($name(...))`. Apply the same change to
such subpatterns inside quoted patterns. This remains macro-pattern
recognition, not a runtime meta call or evaluated List construction.
Keep `?name`, `*name`, `?(Type name)`, and the Match operator vocabulary intact.

## Current owners and implementation

Planning inspected dev `161eaeb64`. The prerequisite can move or delete the
listed owners; locate their successors after it lands instead of restoring
removed compiler Lisp paths.

| Responsibility | Current owner |
| --- | --- |
| Mode-dependent sigils, nested groups, interpolation, layout | `lib/tokenizer.x`; String segments in `lib/scan.x` |
| Operand dispatch, natural Arrays/Maps, expression precedence | `src/expressions/syntax.x` |
| List construction, grouped insertion/splicing, macro subpatterns | `src/literals/quotation.x` |
| Quoted Arrays/Maps, natural Map entries, Entry macros | `src/literals/collections.x` |
| String interpolation and insertion diagnostics | `src/literals/strings.x`, `src/literals/atoms.x` |
| Code quotation hole discovery and application | `src/macros/definitions/quotations.x`, `slots.x`, `reading.x` |
| Canonical forms and collection lowering | `src/grammar.x`, `src/components/collection-literals.x`, existing literal/binding/transform owners |

1. **Start after the prerequisite.** Verify compiler Lisp syntax removal is
   on current dev and inspect its changed parser, tokenizer, macro-slot, and
   bootstrap owners. Preserve runtime Lisp. Record the actual starting commit.

2. **Add recognition before adopting syntax.** Teach the tokenizer to enter
   ordinary Ecstasy expression parsing for `$(`/`@(` within quoted collections
   where insertion/splicing is supported, and for `$(` within Strings. Keep
   `@` as String text. Recognize evaluated List openers in code. Add evaluated Map
   recognition after the brace-hole migration below. Balance nested
   groups and return to the correct enclosing mode. Share existing group and
   mode-stack operations; do not add a second scanner or raw-text parser.
   Audit Token group traversal, operand-start tests, source spans, recovery,
   and indentation conversion where the prerequisite removed Lisp-form cases.

3. **Reuse canonical construction.** Parse evaluated List elements with the
   existing assignment-expression parser and build the existing typed List
   cells. Reuse grouped insertion/splice parsing for parenthesis boundaries.
   Parse evaluated Maps through the existing entry owner with the smallest
   explicit key-policy distinction. Return the same typed Map AST and use
   current collection lowering. Keep ordinary natural Map behavior unchanged.

4. **Preserve quotation stages.** Update computed-hole discovery, token-group
   skipping, hole lookup, and sequence roles together. A group in a literal
   is a runtime insertion; a code-position group in the quotation is a
   construction-time hole. Reuse existing lexical/parser context and hole
   records, rather than reparsing text or adding AST origin authentication.
   Update macro subpattern recognition at the same boundary.

5. **Stage and migrate the corpus.** The development compiler may temporarily
   accept old brace insertions while current source still needs them. Keep
   `${...}` under its old meaning until that migration is complete; then
   remove brace holes and enable evaluated Maps. This avoids a temporary
   parser that guesses whether a brace is an old hole or a new Map. Build
   the new parser and refresh bootstrap through documented targets before
   migrating compiler/runtime source that the seed must consume. After the
   migration, remove old insertion/splice branches and their diagnostics.
   This temporary transition is not a shipped compatibility promise.

   Use tokenizer/parser-aware transformations, not unrestricted textual
   replacement. Inspect `src/`, `lib/`, `etc/`, commands, tools, tests, examples,
   packages, and authored documentation. Distinguish literal insertions,
   quotation holes, pattern insertions, escaped data, runtime Lisp strings,
   and deliberately invalid fixtures. Preserve each expression's stage and
   precedence. Never hand-edit bootstrap C/H or generated API/book outputs.

6. **Update the book and diagnostics.** Document the context table, natural
   forms, List comma separators, evaluated Map keys, nesting, and stage
   examples. Update the language/lexical/grammar references, collections,
   macros, code generation, examples, and diagnostic hints at their owners.
   Regenerate derived documentation through existing targets. Reconcile the
   local glossary draft separately if it is later selected for publication.

7. **Review and deliver.** Review the completed authored diff and generated
   changes, remove duplicate parser paths and unnecessary checks, and resolve
   any contract conflict before publication validation. Follow the root
   delivery mode and existing performance/publication requirements. No new
   recurring gate, benchmark, or process requirement belongs to this change.

## Verification and acceptance

Extend the existing tokenizer suites and compiler fixtures. Keep expected
artifacts under their current harness; update only intentionally changed
expectations and review their deltas. Use focused cases for:

- Empty/single/multiple evaluated List elements, trailing commas, nested
  constructors, calls, assignment and conditional expressions, and a grouped
  comma expression. Verify Var conversion and existing rejection of `void`.
- Side-effect traces proving each List element, insertion, Map key/value,
  and splice operand runs once in source order. Verify equal canonical Lists
  and distinct fresh Maps without changing lifetime policy.
- The four nested-List examples and insertion versus splicing above, including
  nested calls and a splice with a List-convertible operand.
- Natural, quoted, and evaluated Maps using the same key variable. Include
  `${}`, nested quoted/evaluated containers, duplicate keys, Entry macros,
  computed keys versus whole Entry insertions, template sequence wrappers,
  and supported typed collection destinations.
- String interpolation using grouped calls, literal dollars, nested quotes,
  and balanced parentheses. Preserve bare `$name` behavior.
- Computed code-quotation holes and sequences, typed quotations, nested
  quotations, runtime insertion versus construction-time computation, generated
  Maps and Lists, macro patterns, and ordinary named-template holes.
- Removal of legacy brace insertion/splice meanings, malformed delimiters,
  useful source positions, and brace/indentation spelling parity. A valid
  `${key: value}` must parse as a Map; an old `${expression}` must not be
  guessed into an insertion.
- Existing macro, Match, collection, interpolation, runtime Lisp/REPL, stage,
  and cold-collection checks relevant to preserving these boundaries.

This plan does not claim those new forms have been prototyped or executed.
They are a specification based on source inspection and the agreed examples.
Planning-only publication uses `tools/gate-state.py ensure doc-check`.
Future compiler implementation uses the root's existing `agent-pr-check`
publication gate and applicable performance checkpoint, with bootstrap
regeneration owned by the documented targets.

## Design review

The useful additions are evaluated Lists and explicitly evaluated Map keys.
Parentheses replace existing grouped escape boundaries; they do not add
compatibility spellings. Arrays and natural Maps keep their current behavior.
Reusing List cells, Map entries, conversions, caches, hole records, and normal
binding avoids a new representation, evaluator, registry, or validation pass.

The deliberate cost is contextual `$(`: a constructor in ordinary code, an
insertion in quoted data, and a computed hole in quotation code positions.
The specification states these contexts and fixes their staging with examples.
`$!` and `%!` remain stable. No synchronization or runtime lifetime change is
needed. If implementation requires material machinery beyond these owners,
stop and compare a smaller design with Gary before expanding this plan.
