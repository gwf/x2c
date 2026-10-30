# Contextual x2c keywords

> Status: blocked, 2026-10-30.
> Gary authorized implementation after approving the plan. The lexical
> feasibility step reproduced a conflict requiring the architecture decision
> described below. No compiler or runtime source has been changed.
> Selected policy remains visible ordinary bindings winning ambiguous syntax,
> reserved `defer` and C words, and full-syntax recognition for `with`.

## Result and scope

Make nine currently hard-reserved x2c words contextual:

```
associated catch delegate finally import protocol raise threaded try
```

Keep the tenth addition, `defer`, reserved. Keep C keyword reservations and
alternate C spellings unchanged. In particular, `thread_local` and
`_Thread_local` keep their storage-specifier meaning even though x2c's
`threaded` spelling becomes contextual.

Improve the already contextual `with`: recognize temporary assignment only
as `with (...) { ... }`. Ordinary `with(args);` calls and other identifier
uses must work directly. Preserve `import ... with` and temporary assignment's
entry grammar, evaluation order, restoration, and required braced body.

Do not change `in`, `match`, other contextual words, general macro precedence,
keyword alias replacement restrictions, or C keyword behavior. Existing
`match` collisions are evidence for this design, not additional implementation
scope. Keep runtime ABI, exception behavior, and canonical AST forms unchanged.

## Expected simplification

Gary expects this change to tighten the implementation as well as improve
identifier compatibility. The current behavior reflects many individual,
ad hoc decisions. Replace those decisions with the selected rules and delete
the special cases they supersede. The resulting code must be cleaner,
more direct, and simpler to understand.

Do not satisfy the behavior by layering exceptions, fallback paths, or a
general recognition framework over the current decisions. Share recognition
where the same rule applies; keep genuinely different grammar positions
explicit. Fewer lines alone do not establish a simpler design.

During the completed source review, identify which ad hoc decisions and code
were removed. Explain any remaining exceptions and why they are necessary.
If the proposed implementation instead adds complexity, revise the approach
before treating it as complete. Passing tests do not replace this requirement.

## Selected language rules

### Recognition and ordinary bindings

Recognize each word only at its owning grammar position. Outside that
position, accept it as an identifier in declarations, expressions, member
names, labels, and other ordinary name positions.

Where both interpretations overlap, a visible ordinary binding wins. Use
normal source-ordered scope lookup, including included declarations and inner
shadowing. Functions, objects, parameters, enumerators, and typedefs count;
expression aliases follow their existing ordinary-name lookup. A struct tag,
a field of another object, or a declaration appearing later does not reserve
an ordinary identifier in the current scope. Follow the actual namespace at
member and label positions rather than consulting unrelated ordinary names.

An ordinary binding selects ordinary parsing even if that use then fails
normal typing. Do not retry the keyword interpretation after an ordinary
call has the wrong arguments or a non-callable object is called. Recognition
must not depend on which interpretation happens to compile successfully.

Use syntax alone when the alternatives do not overlap. A binding with the
same spelling does not disable every use of the keyword. For example,
`with (mode = quiet) { body(); }` remains a temporary assignment even if a
function named `with` is visible: a C call statement cannot have that body.

Preserve existing macro/local-macro and alias behavior. This plan does not
let a function silently override a visible user macro or permit replacement
of a protected built-in alias. For newly softened words, ordinary name
positions receive identifiers; macro definition/invocation owners continue
to enforce their own existing contracts.

### Recognition by word

| Word | Keyword position and boundary |
| --- | --- |
| `import` | Unit-scope import head followed by a quoted package name; preserve optional `as` and `with` clauses. |
| `raise` | Statement head with the required `%()` payload and terminating semicolon. Account for the lexical overlap with modulo described below. |
| `try` | Statement head governing a body with the required catch/finally continuation. Preserve braced and unbraced bodies; consult ordinary bindings where a prefix can also start an expression or declaration. |
| `catch` | Catch introducer while parsing a pending try/handler continuation, followed by a filter or default colon. A catch body may itself call a function named `catch`. |
| `finally` | Finalizer introducer in a pending try/handler continuation. Distinguish that continuation from an ordinary same-named statement when both fit the surrounding grammar. |
| `delegate` | Delegate modifier at a field declaration head. A visible typedef named `delegate` wins when it can instead begin the ordinary field declaration. |
| `associated` | Associated-type introducer inside a protocol body. Preserve ordinary member declarations whose return/type spelling is a visible typedef named `associated`. |
| `protocol` | Unit-scope protocol definition/adoption head, including current `meta` and `static` markers. Preserve ordinary typedef-based declarations and function declarators. |
| `threaded` | Storage specifier in a declaration prefix. A visible typedef named `threaded` wins in an overlapping ordinary declaration. |
| `with` | Statement head followed by a parenthesized header and braced body. Other uses proceed through ordinary declaration/expression parsing. |
| `defer` | Remains reserved with its current statement grammar and cleanup meaning. |

A completed governed body establishes its continuation position. Do not
interpret the first statement inside that body as an outer handler merely
because its identifier spells `catch` or `finally`. Preserve normal nesting
and association of handlers, finalizers, control statements, and directives.

### Why `defer` stays reserved

These meanings have identical source:

```c
defer(f());
```

One calls a function named `defer` now. The other schedules the parenthesized
call to `f` for block exit. Binding precedence could select the first, but
Gary chose to retain the existing reservation and cleanup meaning instead.
Do not narrow defer to braced bodies or introduce another spelling.

### Compatibility consequences

Previously rejected C identifier uses become valid. Existing ambiguous
keyword uses can change interpretation when an ordinary binding is visible;
that is the selected policy. Unambiguous constructs keep their meaning.

`with(args);` changes from an attempted temporary assignment to an ordinary
call. `(with)(args);` remains valid. Malformed keyword-shaped forms still use
the existing parser's diagnostics once the recognizer claims the construct;
ordinary typing owns errors after ordinary parsing wins.

## Evidence and lexical feasibility

Investigation baseline: `a208671ba`. `make build-safe` passed. A temporary
harness demoted one keyword spelling to `<ident>` after tokenization and
used the real parser and binder. All 80 cases passed: eight identifier forms
for each of the ten original additions. This includes `defer` feasibility;
its exclusion is a language decision, not a failed parser experiment.

The forms covered globals, locals, parameters, function definitions and
expression calls, statement calls, fields, typedefs, and labels/gotos.
The harness did not implement recognition, check all emitted native programs,
or establish scanner and collection equivalence. Baseline accepted some
keyword-spelled declarators; baseline `defer(1);` produced a defer node,
not a call to the declared function.

An ordinary `match` typedef compiled and ran. A valid C definition beginning
`match (f(void)) { ... }` failed in x2c because lexical lookahead retained
`<match>`. This demonstrates why scope-sensitive decisions belong to parsing.

Temporary evidence is currently under `/tmp/x2c-keyword-spike/`; it is not a
required dependency for a future implementing session. The research narrative
is also in `.context/keyword-research.md` in the originating worktree.
Reproduce relevant cases from this plan if those temporary files are absent.

The scanner already uses keyword types to choose `%()` literals, `%!` lambdas,
angle-symbol literals, and block/operand boundaries. Demoting tokens after
scanning does not prove those decisions correct for ordinary identifier uses.
For example, with a visible integer named `raise`, `raise %(n)` must select
ordinary modulo, while an unbound statement `raise %(code);` retains payload
syntax. Both keyword and ordinary uses must work in the same source unit.

Before committing to a lexical implementation, prove this distinction using
existing scanner/parser operations. Also cover `%` before a parenthesized
operand, `<` comparisons, percent literals after governed statements, CPP
expansion, and indentation rewriting. Do not declare success from identifier
positions alone, require whitespace workarounds, or silently exclude valid
ordinary C expressions.

If the distinction requires a new token representation, speculative semantic
transactions, a second source parser, or material repeated tokenization, stop
and present the concrete conflict and smaller alternatives to Gary. Those
architectural changes are outside the selected plan. This is a bounded
feasibility condition, not authorization to add that machinery.

## Implementation feasibility result, 2026-10-30

The first implementation step reproduced the lexical conflict. With the real
parser harness, these results are:

| Source | Result |
| --- | --- |
| `int f(int value, int a, int b) { return value %(a+b); }` | Parses as modulo of `value` by `a+b`. |
| Same source using `raise`, demoted to identifier after scanning | Fails at `%(` with `expected ';'`. |
| `int f(void) { raise %(bad-arg); }` | Parses as the existing raise construct. |

The scanner emits `%(` and one `lit-atom` token `a+b` after raw `<raise>`.
After an ordinary identifier it emits `%`, `(`, `a`, `+`, `b`, `)`.
`lib/tokenizer.x` selects the mode before parser bindings exist;
`src/compiler/parsing/tokens.x` completes scanning and CPP before retagging.

Changing which mode wins globally breaks the other interpretation. Joining or
splitting tokens only in the parser does not solve the general case:
`scan_atom_status` accepts escaped bytes and atom punctuation that C scanning
can reject, and `src/cpp/expand.x` expands identifiers before parsing.
`src/literals/atoms.x` explicitly keeps literal atoms out of CPP expansion.
Angle-Symbol literals and ordinary comparisons have the same timing issue.
No existing operation was found that preserves both lexical and CPP semantics
by consulting normal source-ordered bindings at the current boundary.

This rejects post-scan retagging as a complete implementation. It does not
establish that the requested behavior is impossible. Full behavior requires
revising when lexical mode and preprocessing are selected. Such a design must
also preserve stable Token pointers, source positions, CPP state, collection,
and repeated parses. That is the consequential boundary change for which the
feasibility section requires a stop and discussion.

The smaller alternative is explicit lexical priority: keep keyword-oriented
percent/angle scanning after these spellings while softening ordinary
identifier positions, calls, assignments, and other expressions. For example,
`raise(args);` could call a function, but a bound `raise %(a+b)` would not
acquire normal modulo meaning. Parenthesizing the name or separating `%` from
`(` would remain necessary. This alternative violates the current no-workaround
requirement and is not selected or implemented.

Decision needed: retain exact binding precedence and design the lexical/CPP
boundary change, or explicitly narrow precedence to preserve lexical priority
for these forms. Do not implement either policy by inference. Temporary
reproducer outputs are in `/tmp/x2c-keyword-spike/lexical-feasibility.json`;
the sources and token distinction above preserve the essential evidence.

## Implementation

1. Establish the lexical behavior above with focused temporary probes. Select
   the smallest implementation that preserves ordinary expression tokens and
   existing literal readers. Keep C tokens and `defer` reserved. Prefer
   ordinary identifier tokens for the nine softened words; retained raw tags
   are acceptable only if they do not make scope-dependent lexical choices
   irreversible or leak reservation into identifier uses.
2. Update the owning recognizers and source consumers together. Statements
   live in `src/statements.x` and `src/parse/binding.x`; unit forms in
   `src/parse/units.x`; fields and storage in `src/parse/types.x` and
   `src/parse/declarations.x`; protocols in `src/protocol/declarations.x`.
   Use current symbol lookup for ambiguity. Do not add a separate binding
   registry or scan ahead through semantically parsed bodies to discover
   handlers. Preserve the parser's current clause/binder ordering.
3. Pass the recognized keyword kind explicitly where source dispatch currently
   reads `c.peek(0)`, then construct the same canonical AST as before. Reuse
   existing binding, typing, lowering, and cleanup. Do not mutate shared
   token types based on one scope's interpretation. Reuse a recognition query
   only where consumers need the identical decision; avoid forwarding layers.
4. Make `with` recognition check its complete header/body boundary before
   claiming the statement. Reuse `_with_statement`, the built-in decorator,
   and existing entry validation. Ensure generic macro recognition does not
   reclaim an ordinary `with(args);` call through the built-in alias. Keep
   user replacement restrictions and `import ... with` unchanged.
5. Apply the same rules in shallow collection, full parsing, source templates,
   headers/CPP, interactive submissions, completion, and indentation syntax.
   Source templates use ordinary source grammar; canonical constructed AST
   forms remain structural and need no keyword-origin authentication.
   Read current scanner-name consumers before changing `scan_keyword_type`;
   preserve C/GNU normalization and macro dotted-name support.
6. Update the language reference and relevant scanner/tokenizer documentation.
   Explain reservation, grammar position, ordinary-binding precedence, defer's
   exception, and direct `with` calls. Keep the public scanner API description
   accurate for the chosen implementation; no runtime signature change.
7. Add focused coverage below within existing suites/fixtures. Keep bootstrap
   transitions usable through documented targets. Review and fix the complete
   authored diff for duplicated recognition, changed precedence outside scope,
   unnecessary machinery, and missed callers before publication validation.

## Validation and delivery

Use existing checks; add no recurring gate or process requirement.

- Exercise all nine softened words as globals, locals, parameters, functions,
  direct statement calls, fields, typedefs, labels, and ordinary expressions.
  Compile and run representative outputs, verifying effects and native names.
- Exercise each keyword construct without a competing binding, and mixed
  keyword/name uses in one file. Verify AST meaning where both interpretations
  can parse; successful compilation alone is insufficient.
- Verify binding precedence with declaration order, includes, parameters,
  inner shadowing, typedefs, and same-named fields/tags that must not count.
  An ordinary but ill-typed interpretation must report its ordinary error
  instead of falling back to keyword syntax.
- Verify nested try/catch/finally, unbraced bodies, same-named calls in governed
  bodies, directive placement, and existing exception/cleanup behavior.
- Verify direct `with(args);`, existing `(with)(args);`, assignment-list bodies,
  and a braced with statement in scope with an ordinary `with` function.
- Verify modulo/literal and comparison/angle-token choices, CPP-produced words,
  collected headers, macro templates, canonical constructed syntax, interactive
  submissions, and indentation sources through their existing owners.
- Retain coverage for C keyword reservations, C/GNU alternate spellings,
  `thread_local`/`_Thread_local`, and reserved `defer`. Reuse existing negative
  coverage; add only missing cases needed to establish the selected contract.

Planning ends with this file. Do not implement, regenerate bootstrap, or
publish as part of the plan-writing request. Future authorized implementation
uses the root delivery workflow, publication gate, and applicable compiler
performance checkpoint. Review generated deltas and preserve stage usability;
this plan adds no independent validation sequence.

## Plan review

The scanner owns token boundaries and literal modes. Normal scope lookup owns
visibility, namespaces, and declaration order. Existing parsers own valid
constructs, types, and errors. Consumers rely on those facts; recognition does
not duplicate semantic validation or retry a failed interpretation.

Reuse statement/clause binders, declaration and protocol parsers, the built-in
with decorator, and canonical AST/lowering. Replace hard-token dispatch for
nine words and the unconditional statement-start with claim. Keep defer's
existing owner. No cache, binding registry, provenance state, general parser
framework, or runtime machinery is proposed. Lexical feasibility must be proved
before accepting a more expensive representation.

The completed change must demonstrate the simplification described above:
superseded decisions are removed, common rules have one owner, and remaining
grammar differences are easy to follow. Added machinery requires revising the
design if it defeats that result, even when the behavior checks pass.

Small grammar-position queries and normal `Sym` lookup fit the current
recursive-descent x2c implementation. They do not require new caller obligations
or defensive validation of constructed AST forms.

No new validator or dedicated diagnostic is proposed. Reuse existing rejection
coverage for reserved C words and defer, invalid with entries, and malformed
exception constructs. Any missing negative fixture must protect one deliberate
public behavior: reservation, ordinary-binding precedence without fallback, or
the existing construct grammar. Do not add fixtures solely to obtain earlier
or more specific diagnostics.
