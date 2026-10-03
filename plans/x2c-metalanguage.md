# x2c as its own metalanguage

> Status: active, 2026-10-02. Gary approved the plan and its
> recommendations as one campaign on branch `gwf/macro-metalanguage`,
> started from dev d84f3c26. The branch is pushed freely; the finished
> campaign was submitted as PR #108; the integrator stopped on review
> findings, and Gary handed the integration to the author on 2026-10-02.
> The author merged dev 21b1c3d4, fixed the findings (Integration below),
> and publishes directly after the publication gate.

## Question

Can x2c inspect and rewrite x2c code as directly as Lisp inspects and
rewrites Lisp? If not, which small change to the language, its contracts,
or its syntax would make the compiler's own work much shorter to express?

## The current model

There is no formal grammar. The grammar exists in three places: the
recursive-descent parser (`src/parse.x`, `src/expressions.x`,
`src/statements.x`, `src/initializers.x`), the prose of
`docs/src/reference/language.md`, and the source-form macros of
`src/grammar.xmacro`, which cover part of the grammar. The AST has no
schema either. About 100-130 node heads are implied by the parser and by
the code that matches them.

Compile-time code works at three levels:

| Level | What it is | Lisp analogue |
| --- | --- | --- |
| Macro | A template: x2c source with typed `$hole`s. One definition builds code and, in a `case`, recognizes it. | `defmacro` with automatic fresh names (after M1), but one artifact both builds and matches |
| `meta` function | Ordinary x2c compiled natively and run at compile time. Project meta runs in a helper process and receives compiler facts as `Type` and `Source` parameters; only the compiler's linked meta can query the compiler. | `defmacro` body, phase 1 |
| Compile-time Lisp | `$(...)` and `.xlisp`. Now used mainly for imports (219 of 377 `$(` uses), session setup, native bindings, `x2c.ident`, and the REPL. | Lisp itself |

The two directions between levels are explicit. A template calls meta code
in a slot (`$helper(...)...`). Meta code builds code by applying a `Macro`
value, which returns a pending invocation that the compiler expands where
the result is inserted. Captured syntax is the canonical typed AST:
`(expr TYPE CONTENT)` shells, `(binding ID SPELLING)` identities, and
`(at ID NODE)` source anchors.

Lisp's advantage is that code, templates, and computation are one
language: a macro is a function from code to code, and quasiquote embeds
a template anywhere. x2c has every part of that, but the parts meet at
seams, and the compiler pays for each seam in code.

## Evidence: where the compiler pays

Counts are from `src/` and `lib/` on dev c70a008c.

1. **Recognition falls back to raw AST shapes.** `src/` has 1,048 raw
   `case %(...)` patterns and 190 macro-based cases. The raw ones cluster in
   the lowering files: cleanup 69, regions 63, protocol 54, transform 56,
   cache 36, callables 31. A further layer in `src/grammar.xmacro` splices
   macro-derived patterns into raw ones: `source_content_pattern` (46 uses),
   `source_pattern` (13), `source_pattern_with` (4), `source_call_content`
   (7), and 15 one-line content builders (`source_operator_content`,
   `source_identifier_content`, and others: about 190 uses). Typical:

   ```x2c
   case %(expr ?type (!set ?content
       ${$source_content_pattern($indexed, %(?receiver ?selector))})):
   ```

   Two limits cause this. A macro case accepts only `?binder` in argument
   positions, so a nested form needs a second `match` (about 21 sites) or a
   derived pattern. A macro case cannot see the `(expr TYPE ...)` shell, so
   a case that needs the type spells the shell by hand. Probe: `case
   $add(?a, $neg(?b)):` fails with `parse: expected '?'`.

2. **Nested names are captured.** A `Name` argument is a binding identity
   when its spelling already names a template local, and a bare `String`
   otherwise (`Compiler._name_argument` in `src/macros.x`). A declaration
   made from a bare spelling is public. So a literal name in one macro body,
   declared by a nested macro, captures the caller's variable of the same
   spelling. Both probes reproduce on dev c70a008c:

   ```x2c
   macro Statement $repeat(Name $i, Expr $count, Expr $value, Name $sum) {
     for (int $i = 0; $i < $count; $i++) $sum += $value;
   }
   macro Statement $read(Expr $x) {
     int total = 0;
     $repeat(k, 3, $x, total);
     printf("%d\n", total);
   }
   macro Statement $write(Name $acc) { $repeat(k, 3, 10, $acc); }

   int main(void) {
     int k = 5;
     $read(k);     /* prints 3; should print 15 */
     k = 0;
     $write(k);    /* leaves k at 0; should set it to 30 */
     return 0;
   }
   ```

   The generated C for `$write` is `for(int k = 0; k < 3; k ++) k += 10;`.
   The read fails the same way when `$x` is a `Name` hole.

   Dev 8db7ecc5 addressed a related case by making a `Name` argument keep
   the caller's binding identity, and by giving a caller local a separate C
   spelling so that a macro's free name can reach a native name. Gary ruled
   on 2026-10-02 that this direction is a mistake: macros must not capture
   bindings from the caller or from the definition. PR #103 (named local
   macros resolve literal references where they are invoked) states that
   intent and is parked as incomplete. M1 below replaces both mechanisms.

3. **Five vocabularies name the same syntactic categories.** Hole kinds
   (`author_kinds`, 18 entries), result kinds (`direct_result_kinds` plus
   three special cases), decorator targets (6), slot roles (three
   SymbolSets), and invocation positions (`macro_position_info`, 7) are
   separate lists with different spellings: `Expr`/`Expression`,
   `Statement`/`Block`/`block-item`, `Entry`/`map-entry`. The book's
   "complete" hole-kind table omits `Catch`, `Captures`, and `MatchRow`.
   Meta functions see all syntax as `List`; only `Type` and `Source`
   parameters say what they carry.

4. **Templates cannot loop or branch.** Repetition and choice go into slot
   functions. This costs less than expected: 11 slot functions (127 lines),
   about 22 map-shaped and 10 choice-shaped functions overall, and 138
   `Macro x = $name;` declarations. Template repetition would delete about
   80-100 lines. Most hand-built typed expressions (about 600 `%(expr ...)`)
   are in the resolver, where choosing the type is the real work.

## Proposal

The changes are ordered by payoff and by dependency.

### M1. Macros capture no bindings; names they write stay private

Settled by Gary on 2026-10-02. An expansion means what the same code would
mean if it were written where the expansion lands, except that names the
macro body writes are private to the expansion. A macro stores no binding
identity, from the definition or from the caller. Expansion depends only
on the template, the arguments, and a fresh-name counter.

The rule:

1. Every identifier written literally in a macro body is marked with that
   expansion. The mark travels with the identifier when the body passes it
   to a nested macro, a `meta` helper, or compile-time Lisp.
2. A declaration made from a marked identifier gets a private binding and a
   private C spelling. This includes a declaration a nested macro makes
   from it through a `Name` hole.
3. A marked reference binds to a declaration with the same mark when one is
   in scope. Otherwise the mark is ignored, and the reference resolves like
   any other name.
4. Every other name resolves by spelling where the expansion lands. That
   includes free names in the body and everything the caller passes,
   through `Name`, `Expr`, or any other hole. A `Name` argument is a
   spelling, never a binding identity.
5. One rule covers global macros, named local macros, and `Macro` values.
   A caller's local can therefore supply a free name in a macro body. This
   is the accepted cost of the rule.
6. The one exception is a leading body directive, `using name, other;`
   without `$`, or `using name` after an `Expression` macro's signature. It
   binds each listed spelling to the file-scope function, object, or
   enumerator that it names where the macro is written, or to the native
   name C supplies when no x2c declaration does. Locals are never reached.
   When a caller's local shadows such a name, the compiler gives the
   caller's local a different C spelling, so the generated C still reaches
   the file-scope name. A file-scope name has one identity for the whole
   unit, so this works as a qualified name and does not make the macro a
   closure. Type names are not listed: implemented as identifiers only,
   because type spellings already resolve where the expansion lands and no
   case needed them.

`using $name;` keeps its current meaning, a fresh private name for each
expansion. Rule 1 makes most uses unnecessary, because a literal name in
the body is already private. The six current uses are checked one by one
during implementation.

Results under this rule, by reading the code (not yet implemented):

- The probes above print 15 and set `k` to 30. The loop variable carries
  the outer macro's mark, and the caller's `k` does not.
- `macro-forward-declaration-caller` still prints `5 7000`, and
  `macro-name-reference-capture` still prints `7 7` and `11 11`. The
  behavior those fixtures protect follows from marks, without a stored
  identity.
- PR #103's intent holds: a named local macro's literal `k`, when nothing
  in the expansion declares it, reads the `k` visible at the invocation.
- Decision 11 of the self-expression plan (forward names) becomes a
  consequence of rules 1-3 instead of a separate rule.
- `macro open` has nothing left to select, because closed resolution is
  gone. The keyword is removed from its 64 definitions in the same change.
  Its rule that a free typedef name is emitted as its target type goes
  with it.
- `x2c.ident` produces an unmarked identifier: an exact public spelling
  that resolves where the expansion lands.

Unwound in the same change:

- The 8db7ecc5 book paragraphs: a `Name` argument keeps the caller's
  identity, and a caller local gets a separate C spelling so that an
  untyped free name in call position reaches a native name. The first is
  replaced by rule 4. The second is replaced by rule 6 for names a macro
  declares with `using`.
- The fix-list F10 wording that records "a Name argument referring to an
  existing caller variable keeps that binding".
- The "Local definitions" and "Hygiene and generated names" sections of
  the book: definition-site resolution of parameters and preceding locals,
  shadow renaming to preserve a captured declaration, and the rule that a
  caller's local never captures a free name.
- In source: the String-or-identity branch of `Compiler._name_argument`,
  `_bind_name_arguments`, the stored definition locals that local macros
  and closed templates resolve against, and the implicit caller-local
  renaming. `Expansion.fresh_names` and the private-spelling emission stay
  and carry the marks.

Implementation checks:

- Every macro whose free names resolved at its definition must still find
  them where it lands. A macro in a shipped `.xmacro` or header that calls
  a helper must land in units that declare that helper, or list it with
  `using`. Count these before converting.
- Where a free name in a repository macro could meet a same-spelled caller
  local, decide per site whether `using` is needed. Do not add it by
  default.

Estimated: a medium change in `src/macros.x`, `src/expressions.x`, and
`src/symbols.x`. Net source and book prose should shrink.

M1 results:

- Both capture probes give 15 and 30; a named local macro reads the `k` at
  its invocation (PR #103's five local-macro fixtures pass with their
  checked-in C); a global macro reads a caller's `scale` unless it lists
  it with `using`.
- Fixtures that asserted definition-site resolution were rewritten to the
  new rule or to `using`: `macro-expression-contracts`,
  `macro-forward-name-*`, `macro-import-projection`,
  `macro-construction-regressions`, `macro-native-callee-shadow`,
  `report-named-binding`; `macro-open` became `macro-using-name`.
- `using name;` also keeps a native name C supplies, such as `time`; type
  names are not listed.
- An application compiler code makes has no invocation token; its
  template's authored-origin anchors are stripped, as open templates were,
  so diagnostics point at the source being lowered.
- The compiler's self-translation of `src/` and `lib/` is unchanged except
  in the edited files; all 992 fixtures, 939 unit tests, and 94 book
  samples with outputs pass.
- A free name that resolves at definition to a file-scope declaration keeps
  that identity and its type in the template, marked `template-free`.
  Where the expansion lands sees the same declaration unless a local hides
  it, so the binder skips the subtree as before; a hiding declaration
  rebinds the identifier and its type is recomputed. A `using` name is
  stored as `binding-global` and never rebinds. Macro values carry free
  file-scope names as `binding-free`.
- Translation cost, both compilers built with `make build-safe` from a tree
  whose `src/` matches its bootstrap: the `lib/` batch with `-j 1` retires
  94.1-96.4 G instructions against 94.0-94.8 G on dev d84f3c26 (user time
  6.07 s against 5.92 s). A stage 0 built from `src/` that differs from
  `bootstrap/` preloads meta code cold and is about 0.4 s slower per
  process; compare clean builds only.

### M2. Macro patterns compose and see types

A macro pattern is accepted wherever a pattern is. Its argument positions
accept any pattern, including another macro pattern and a raw `%()`
pattern. Inside a `%()` pattern, `${$macro(?a, ...)}` stands for that
macro's pattern and matches the shelled expression or its bare content, so
the canonical `(expr TYPE CONTENT)` shell captures the type (S5).

```x2c
case $add(?a, $neg(?b)):                          /* nested */
case $indexed(%(!set ?base (expr ?type ?)), ?index):
case %(expr ?type ${$indexed(?receiver, ?selector)}):  /* typed */
```

`source_pattern_with` already does this by hand: it derives the macro's
pattern with simple binders, then replaces each binder with a
sub-pattern. M2 moves that operation into `Macro_pattern`'s binder rows
(`lib/macro-value.x:129-170`) and into the `case` parser. The binder
routing in `MacroPublishing` must publish the nested binders.

Payoff: the derived-pattern layer of `src/grammar.xmacro` goes (about 70
uses of `source_content_pattern`, `source_pattern`, `source_pattern_with`,
and `source_call_content`), the 21 nested `match` statements collapse, and
the raw `%(expr ...)` cases in the lowering files can be written as source
forms. This is the change that makes "the compiler recognizes x2c" read
like x2c.

M2 results:

- `${$m(P, ...)}` is accepted inside `%(...)` patterns and as a whole
  `case` pattern; a named `case $m(...)` with a nested argument pattern
  derives the same way. Derivation happens while the compiler reads the
  `case`, from the macro's stored definition.
- 58 uses converted with byte-identical self-translation;
  `source_pattern` and `source_pattern_with` are deleted. Eleven
  bare-content dispatch arms keep `source_content_pattern` and one keeps
  `source_call_content`: as shelled-or-bare patterns they would lose the
  fixed head that lets the match emitter label the arm.
- Converting the remaining raw `%(expr ...)` cases and collapsing nested
  `match` statements is follow-up adoption; it needs no further language
  change.

### M3. One category vocabulary, usable as types

Define the syntactic categories once: `Expr`, `Statement`, `Type`, `Name`,
`Literal`, `Decl`, `DeclaratorRow`, `Param`, `Function`, `Field`, `Entry`,
`Enumerator`, `Unit`, `NamedType`, `Catch`, `Captures`, `MatchRow`, and an
`Operator` category for operator tokens. Each name is accepted as a hole
kind, a result kind, a decorator target, and a meta parameter or result
type (a `typedef List` alias, as `Type` and `Source` already are). The
`Expression`/`Block`/`Entry` spellings stay accepted as synonyms.

The categories with their source-form macros in `src/grammar.xmacro` then
are the formal grammar: each category lists its productions as templates.
The book gains one table, generated or checked from that file.

Payoff: the five lists become one, the slot binder's position check uses
the declared category, and meta signatures state what they take and
return. An `Operator` category removes the `source_operator_content` and
`source_postfix_content` builders (about 10-15 lines; the gain is
readability).

M3 results:

- One `macro_categories` table in `src/macros.x` replaces the hole-kind,
  result-kind, and decorator-target vocabularies and the spelling
  function; every name is accepted case-insensitively, so `Expr` is now
  also a result kind and `Expression` a hole kind. The book's hole-kind
  table now lists `Catch`, `Captures`, and `MatchRow`.
- Not done, with evidence: category names as `meta` parameter types.
  `Block` is already a runtime type in `lib/`, `Statement` a sqlite package
  type, and `Entry` an example type; and unlike `Type` and `Source`, an
  alias would deliver the same `List`, adding no fact or check.
- Not done, with evidence: an `Operator` hole kind. A template such as
  `$a $op $b * $c` cannot be parsed at definition, because the operator's
  precedence is unknown until expansion; the measured saving was 10-15
  lines.

### M4. Syntax quotation in meta code

Add the quotation `$!( expression )`, `$!{ block items }`, or
`$!Kind{ ... }` inside a meta body (S6). Its `$name` refers to an enclosing meta local of a matching category, and
`$name...` splices a `List`. It is an anonymous macro applied at once:
each `$name` inserts the local's current compile-time value, a piece of
syntax or a scalar, and nothing is retained afterward. The quote captures
no program binding, so it is consistent with M1. A probe confirmed that
today's spelling, an anonymous macro with parameters applied in a loop,
already works in project meta code.

```x2c
/* now: a named template, a Macro value, and a slot function */
List builtin_catch_cases(List selected, List arms) {
  Macro choice = $catch_case;
  Array cases = [];
  int index = 0;
  foreach (List arm, arms)
    cases.push(choice(selected, x2c_literal_int(index++), arm));
  return cases.list_free();
}

/* with M4: the template is written where it is used */
List builtin_catch_cases(List selected, List arms) {
  Array cases = [];
  int index = 0;
  foreach (List arm, arms)
    cases.push($!{ if ($selected == $index) $arm });
  return cases.list_free();
}
```

Measured compiler payoff is modest, about 80-100 lines plus the
single-use template macros. M4 matters more for users: it is the form in
which a meta function reads like a Lisp macro. Rule 2 of
`agents/lowering-with-macros.md` (loops in slot functions) becomes a
choice instead of a requirement.

M4 results:

- `$!( ... )`, `$!{ ... }`, and `$!Kind{ ... }` parse anywhere an
  expression does; the body's `$name` declares a hole for the visible local
  on first use. A quoted hole takes its kind from its position: an
  expression, a name, a `...` sequence, or a statement where it stands
  alone (not followed by `;` or an operator).
- Adopted in the `try` lowering: `builtin_catch_patterns` and
  `builtin_catch_cases` use quotations, and the `$catch_pattern`,
  `$catch_case`, and `$catch_none` templates are deleted (cleanup.x +16/-32).
  The compiler's self-translation is unchanged outside cleanup.c.
- Inside a `%(...)` List, `$` inserts a value, so a quotation there is bound
  to a local first.

### Not proposed

- **Compiler queries from project meta.** The helper-process boundary
  stays. Facts arrive through parameter types (`Type`, `Source`); M3
  extends that rule to every category. Types of constructed code come from
  inserting it and letting the binder type it.
- **Template repetition syntax** (`$for` in templates). M4 covers the same
  cases with ordinary x2c loops instead of a second control language.
- **Parsing code from a `String`.** The current rule that Strings are never
  reparsed keeps source locations and hygiene sound.

## What changes in the compiler

The parser and the resolver produce typed AST; they stay primitive. Their
hand-built typed shells do real type work. The lowering passes (transform,
cleanup, regions, protocol, callables, cache, builtins) recognize typed
source forms and write C-shaped code. They already write most output as
templates; with M2 they also read their input as source forms, and with M1
their generated names need no `using` bookkeeping. `emit.x` matches
lowered C-level forms and is out of scope.

Example, `RuntimeScan._address` in `src/cleanup.x`:

```x2c
/* now */
case $source_pattern_with($indexed, %(?receiver ?selector),
    %((?receiver (!set ?base (expr ?type ?)))
      (?selector ?index))): {

/* with M2 */
case $indexed(%(!set ?base (expr ?type ?)), ?index): {
```

## Decisions

Settled by Gary on 2026-10-02:

- **S1.** Macros capture no bindings, from the definition or from the
  caller. The F10 rule that a `Name` argument keeps the caller's binding was
  a mistake and is unwound.
- **S2.** One resolution rule for every macro: names resolve where the
  expansion lands, and names the body writes are private to the expansion
  (M1 rules 1-5). A caller's local can supply a free name; that cost is
  accepted.
- **S3.** `macro open` is removed, because closed resolution no longer
  exists.
- **S4.** The single exception is the leading body directive
  `using name, other;`, which binds file-scope entities named where the
  macro is written (M1 rule 6). Locals are rejected.

Settled by Gary on 2026-10-02, approving the recommendations:

- **S5.** M2 adds no typed-shell syntax. A macro pattern is accepted
  wherever a pattern is: in a macro pattern's argument positions, and
  inside `%(...)` as `${$macro(?a, ...)}`. The type is captured with the
  canonical shell, `case %(expr ?type ${$indexed(?receiver, ?selector)}):`.
  The first recommendation, `case ?(Type type) $indexed(...)`, was
  withdrawn: after `case` it reads as C's conditional operator and a cast,
  and `?(Type name)` inside `%(...)` already means a `Var` tag test.
- **S6.** M4 spells a quotation `$!( expression )` for an `Expression`
  and `$!{ block items }` for a `Statement`, mirroring `%!` for a runtime
  lambda. Another category names itself before the delimiter, as in
  `$!Unit{ ... }`. Using `$!( ... )` as an anonymous `case` pattern is left
  for later, because `?a` binders inside x2c expression syntax collide
  with the conditional operator.
- **S7.** One campaign in the order M1, M2, M3, M4. M1 replaces PR #103
  rather than building on it.

## Delivery

Work proceeds on `gwf/macro-metalanguage`, with commits pushed to the same
remote branch at any time. When the campaign is complete and reviewed, it
becomes one ready PR to `dev`, submitted through
`tools/integrate-dev.py submit` with focused evidence. The shared
integrator owns the final bootstrap refresh, the publication gate, and
the merge. A milestone that needs a capability in the seed before its
callers compile gets a local bootstrap refresh on the branch.

## Integration

The merge with dev 21b1c3d4 conflicted only in generated files and passed
every fixture and unit test unchanged. The integrator's review of PR #108
found defects in PR #108 itself, fixed on the branch:

- A per-identity `template-free` fact let an unrelated free use of a name
  rebind a `using` occurrence forwarded through another macro. Free names
  are now per-occurrence `binding-name`, and the fast path is gone.
- Names a caller writes in arguments now resolve where the expansion lands:
  a file-scope name hidden by a declaration the active expansion introduced
  (for example from the caller's own `Name`) binds that declaration. Other
  hiding declarations keep the emitted alias, so `using` occurrences and
  code the compiler moves keep their meaning.
- A local macro or anonymous macro inside a template shares the template's
  private names: invocations name a visible local macro instead of quoting
  its definition, and a nested `Macro` value is made where the template
  expands.
- Recognition matches a free name by spelling and a `using` name by its
  file-scope binding; a pending invocation is recognized inside an
  expression shell and by its definition's name and origin.
- Nested patterns substitute binders structurally, keeping operator guards,
  and choose private binders no argument spells; a quotation builds its
  pending invocation with one value per hole.

Fixtures: `macro-binding-landing` (new), `macro-values` (the integrator's
expanded recognition fixture), and additions to `macro-pattern-nested` and
`macro-quotation`.

## Adoption

Follow-up adoption after the campaign landed:

- PR #109 collapses nested `match` statements whose inner match only
  takes apart a captured argument into one macro pattern, in nine files.
  `_op_chain_first` keeps its nested matches: as one pattern it raised the
  translator's peak stack past `var-chain-stack`'s 256 KB limit. The same
  PR fixes a bare `*` argument in a macro pattern, which derivation quoted.
- PR #110 writes 22 single-use templates as quotations. Templates with
  `Type`, `Decl`, `Param`, `Field`, or `Function` holes stay templates,
  because a quotation takes holes only from expression, statement, name,
  and sequence positions. The PR also keeps a macro body's `return` from
  recording the enclosing function's return type, which a retained rebuild
  preserved.
- The remaining raw `%(expr ...)` cases take apart the typed shell or a
  resolved form such as `getindex`; no source-form macro describes them.
- Neither PR changes translation cost: converged trees measure within
  1.3% of dev in instructions retired, with `lib/` output identical.

## Validation

Each change keeps checked-in expectations and adds fixtures beside the
suites that own macros and match. M1: both probes above, the existing
hygiene fixtures (with the 8db7ecc5 fixtures keeping their outputs),
PR #103's local-macro cases, a caller local that shadows a free name, and a
`using name;` that reaches a shadowed file-scope function. M2:
before/after self-translation of the converted lowering files must be
byte-identical. M3: no output change. M4: no output change for converted
slot functions.

## Plan review

- Trusted facts: binding identity is created only by the binder where code
  lands; macros store none. M2 reuses Match and `Macro_pattern` instead of
  a second matcher.
- Deleted or reused: the String/identity `Name` branch, stored definition
  locals, implicit caller-local renaming, `macro open`, the
  derived-pattern layer, four of five kind vocabularies, and single-use
  slot templates.
- New lasting mechanisms: expansion marks on written names, the
  `using name;` directive, nested macro patterns, one category table, and
  the parameterless quote. Each replaces more code
  than it adds, according to the counts above.
- Validators: none added.
