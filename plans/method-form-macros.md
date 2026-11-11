# Method-form macros

> Status: Gary accepted decisions 1 to 5 with the postfix-dot recognition
> design on 2026-11-11. Decisions 1 to 4, the compiler semantics, are
> implemented on branch `gwf/method-form-compiler`, based on `dev` at
> `069ad6363`, with compiler fixtures and a book section. On 2026-11-11
> Gary also directed "Make method forms work inside templates too. Fix
> Entry @options too." and then "Fix the foreach and computed macro name
> limits too."; all four are implemented on the same branch. Decision
> 5 and the x2cui macros are package work on the x2cui branch.
> The prototype that preceded the implementation is on the local branch
> `gwf/scratch-x2cui-method-ui` on top of `x2cui` at `b393dd58c`.
> Every "verified" statement below was compiled and run on macOS arm64 with
> the implementation's compiler unless it names the prototype. Statements
> marked "not verified" were not.

## Result

A type can give its methods block and expression forms that are macros. With
x2cui, a screen reads like this:

```x2c
ui.column (width: fill, max_width: 560, pad: 24, gap: 16) {
  ui.row (gap: 8, align: center) {
    ui.segmented("filter", %("All" "Open" "Done"), todo.filter);
    ui.spacer();
    if (ui.button("Clear done", variant: ghost, disabled: done == 0))
      todo.confirm_clear = true;
  }
}
```

Written with today's x2cui forms, the same screen is:

```x2c
$cui.column(ui, { .width = CUI_FILL, .max_width = 560, .pad = 24, .gap = 16 }) {
  $cui.row(ui, { .gap = 8, .align = CUI_ALIGN_CENTER }) {
    ui.segmented("filter", %("All" "Open" "Done"), todo.filter, {});
    ui.spacer();
    if (ui.button("Clear done", { .variant = CUI_BUTTON_GHOST,
                                  .disabled = done == 0 }))
      todo.confirm_clear = true;
  }
}
```

The compiler adds two invocation positions for macros that already exist.
Everything else is library code in the x2cui package.

## Decisions

1. **Method-form decorators.** `receiver.name(args) TARGET` invokes the
   decorator `$Type.name`, where `Type` is the receiver's named type and the
   receiver is the decorator's first explicit argument.
2. **Method-form Expression macros.** `receiver.name(args)` in an expression
   invokes the Expression macro `$Type.name` the same way.
3. **The self-call rule.** Inside the expansion of `$Type.name`,
   `receiver.name(...)` is the ordinary method. A macro can therefore wrap
   the method of the same name.
4. **Macros shadow methods.** When `$Type.name` exists, it takes every
   method-form call of that name, even where a method `Type.name` exists.
5. **Option lowering stays in the library.** `name: value` arguments become
   C designated initializers through an `Entry @rows` hole and a `meta`
   function. The compiler needs no keyword-argument feature.

Decisions 1 to 4 change public language semantics. Decision 5 is a package
design choice.

## Semantics

### Method-form decorators

A statement of the form

```text
RECEIVER . NAME ( ARGUMENTS ) TARGET
```

is a decorator application when:

- `RECEIVER` is an expression whose type is a named type `T`;
- a decorator `$T.NAME` is visible; and
- the token after `)` is `{`, `$`, or a word (an identifier or a keyword)
  other than `is` and `in`.

The receiver becomes the decorator's first explicit argument; the
parenthesized arguments follow. `TARGET` is the decorator's target, as for a
`$name(...)` application. Decorators stack:

```x2c
ui.column (width: fill, align: center)
ui.column (max_width: 560) {
  ...
}
```

The rule is unambiguous: none of `{`, `$`, or another word can follow the
closing parenthesis of a call inside an expression statement. `is` and `in`
are excluded because they are x2c operators that can follow a call, as in
`ui.get(1) is <int>`. A call followed by `(`, as in `ui.pick(0)(21)`, stays
an ordinary call. Verified.

The receiver is captured like any other argument, so the expansion decides
how often it is evaluated; a macro that binds `$ui` once evaluates it once.
Verified with call, field, `->` field, index, and parenthesized receivers:
`ui_of(app).row (...)`, `app.ui.row (...)`, `app->ui.row (...)`,
`uis[1].row (...)`, `(ui_of(app)).row (...)`.

### Method-form Expression macros

In an expression, `RECEIVER.NAME(ARGUMENTS)` invokes the Expression macro
`$T.NAME` when one is visible for the receiver's named type `T`. The receiver
is the first explicit argument. Verified.

### The self-call rule

While `$T.NAME` is being expanded, a method-form call of `NAME` inside its
expansion is the ordinary method:

```x2c
macro Expression $Ui.button(Expr $ui, Expr $label, Entry @options) =>
  $ui.button($label, (cui_button_opts){ @_cui_fields($options) });
```

Without the rule, a wrapper must call the method as `Ui.button($ui, ...)`.
That free name resolves where the expansion lands. In an importing file it
emitted a C call to `Ui_text` without the package prefix, which failed to
link. Verified with the prototype.

Method forms work in templates too. A receiver that is a hole has its type
only where the template expands, so the form is recognized when the
template's syntax is bound there; a receiver whose type the template
already knows, such as a typed local, is recognized when the template is
parsed.

The self-call rule is lexical: only a `receiver.NAME(...)` call written in
`$T.NAME`'s own template is the method. It is decided where the template is
defined, because the definition being parsed is known then. Its name is
recorded in the template's hole map under `(definition)`. A call whose
member matches it becomes `(expr () (method-call DEFINITION CALL))`, and a
statement form whose member matches it is not deferred. Where the template
expands, the marked call resolves as the method of `DEFINITION`. A target or
argument passed into `$T.NAME`, and other macros' templates expanded within
it, still get method forms, so `$ui.row (...) { $ui.row (...) $body }`
nests. Verified in `macro-method-form-templates`. An earlier version of
this change checked the whole `c.macro_stack` instead, and that rejected
exactly this nesting. Two macros whose templates use each other's method
forms recurse until the ordinary limit reports "macro expansion depth
exceeds 64". Verified in `macro-method-form-mutual`. Decision 4 holds in
templates as in source.

### Entry rows forwarded into a call

An `Entry @options` hole spliced into a call's argument list forwards its
`key: value` rows as the call's entries. The rows reach a `Map @rest`
function or method, or another macro's `Entry` hole; no rows forward no
entries. Verified in `macro-entry-forwarding`. Before this change the
template was rejected where it was defined, with "macro hole 'options' has
ambiguous kind", for an ordinary function call as well as a method form.

### Decl holes in a foreach header

A `Decl` hole can stand where a template reads a declaration argument, as
in `foreach ($element in $items) $body`. `parse_declaration_argument`, the
owner of that position, now first accepts a `Decl` hole in the `decl` role,
which that hole kind already accepts. Before, the declaration parser read
the hole as the declaration's type and reported "macro hole 'element' has
ambiguous kind; first: Decl also: Type". The declared variable is typed and
visible in the body, including through a method form such as
`ui.each(int n in [1, 2, 3])`. Verified in `macro-decl-foreach`.

### Computed macro names

A `macro` definition inside a template may take a component of its name
from an enclosing `Name` hole: `$W.$m`, or `$$m` for a one-component name.
Neither spelling parsed before; there was no existing computed-name
spelling to stay consistent with. The definition's name is then
`(macro-name PART ...)`. The enclosing expansion fills it, and
`publish_macro_definition_node` joins it as `W.add` through
`Compiler.macro_definition_name`. The self-call mark compares a computed
name's last part with the call's member, so `$w.$m(...)` in the generated
template is the method. Verified in `macro-computed-name`, which generates
Expression macros and a decorator.

With this, x2cui's `$cui.named` decorator and `cui_named` meta function can
be removed: each template can be named `$Ui.$method` directly. The
per-arity templates (`$cui.widget0` to `$cui.widget8`, `$cui.block0` and
the rest) do not exist only because of the name limit. Each one has a
different parameter list, `Expr $a, Expr $b, ...` before `Entry @options`,
and a template cannot compute a definition's parameter list. That is a
separate limit and is not built here.

### Package types

Inside a package, a type such as `Ui` is `x2cui__Ui` in generated code, while
its macros keep the spelling `$Ui.row`. Lookup tries the type's generated
name and then its source name. `Compiler.package_source_name`, in
`src/symtab/namespaces.x` beside `package_spelling`, which adds the prefix,
removes it only when it names this unit's package or an imported package
(`c.package` or a key of `c.package_roots`). `reverse_converter_spelling`
already made the same split inline and now calls it. Verified with the toy
package `panels`, in the package itself and in an importing file.

## Option values in x2cui

These are package decisions, not language changes.

- `name: value` arguments arrive in an `Entry @options` hole. A public
  `meta` function rewrites each row as a designated initializer of the
  options record. A call builds no `Map`; the generated C contains only the
  initializer. Verified by reading a probe's generated C.
- A value that is a name with no declaration of its own is a short name for a
  CUI constant. The option decides the constant: `align: center` is
  `CUI_ALIGN_CENTER`, `variant: primary` is `CUI_BUTTON_PRIMARY`, `icon: plus`
  is `CUI_ICON_PLUS`. A declared name keeps its own value. Verified: a local
  `int primary` stays itself.
- A misspelled option is a C error that names the field and suggests the
  correct one: "field designator 'padd' does not refer to any field ... did
  you mean 'pad'?". It points into generated C, not at the x2c call site.

## Implementation

The implementation adds 132 lines and removes 27 in seven compiler files.
The x2cui package changes are not part of it.

| File | Change |
| --- | --- |
| `src/macros/invocations/expressions.x` | `try_parse_method_macro`, `parse_method_decorator`, the macro lookup, and the target test |
| `src/expressions/syntax.x` | The postfix tail receives where its expression began; the hook in `_parse_postfix_dot` |
| `src/statements.x` | `_expression_statement` also begins a statement that starts with `(`, and catches `<method-dec>` |
| `src/macros/invocations/captures.x` | The receiver as the first captured argument |
| `src/compiler/compiler.x` | Two fields: the pending decorator and the receiver |
| `src/symtab/namespaces.x` | `Compiler.package_source_name` |
| `src/protocol/registry.x` | `reverse_converter_spelling` calls `package_source_name` |

The template and Entry changes add 180 lines and remove 28 in eight files:

| File | Change |
| --- | --- |
| `src/macros/invocations/expressions.x` | `bind_method_macro`, `bind_method_decorator`, `mark_method_call`, the deferred statement form, and the capture rows of a template's call arguments |
| `src/expressions/calls.x` | `_method` offers a call in an expansion to `bind_method_macro`, with the macro whose own template wrote it; a forwarded Entry row becomes a `key: value` argument |
| `src/expressions/resolution.x` | `(method-call DEFINITION CALL)` resolves `CALL` as a method of that macro |
| `src/expressions/expressions.x` | `Resolve` carries that macro |
| `src/expressions/syntax.x` | `Compiler.parse_call`; a template's call in its own macro's name is marked; an Entry hole in a call's arguments parses in the Map-entry role |
| `src/macros/definitions/reading.x` | A template's hole map records its definition's name |
| `src/parse/binding.x` | The `(method-decorator CALL TARGET)` statement |
| `src/macros/templates.x` | `_template_arguments` becomes a module operation |

### Recognition

Both forms are recognized in `_parse_postfix_dot`, which already has the
typed receiver and the member name before the argument list. The receiver is
parsed once, by the ordinary parse.

- **Expression macro.** `Compiler.try_parse_method_macro` captures the
  arguments with the receiver first and returns the expansion.
- **Decorator.** It is accepted only when the postfix expression began at the
  start of its statement and the token after the arguments' `)` begins a
  target. The postfix tail receives the token where its expression began,
  so the test is `start == c.meta_statement`. The parser keeps the
  definition and the receiver in two compiler fields and raises
  `<method-dec>`. `_expression_statement` catches it and calls the existing
  decorator path, `_decorate`, from the call's `(`.

A statement that begins with `(` now begins in `_expression_statement`,
which sets `c.meta_statement` for it and holds the one catch. The
prototype's second catch, in `parse_parenthesized_statement`, is gone.

The raise unwinds the expression parser, so no operator loop can read the
next statement. A statement after a block that begins with `*` or `(`, as in
`ui.row (3) { } *p = 0;`, parses correctly. Verified. A decorator inside a
larger expression, as in `k = ui.row (1) { }`, `-ui.row (1) { }`, or
`printf("%d", ui.row (1) { })`, is not recognized and gets the ordinary
error, "type Ui has no method row". Verified.

In a template, a statement form whose receiver has no type yet raises
`<method-dec>` with no definition. `parse_method_decorator` then parses the
arguments with the ordinary call parser and the target as a statement, and
returns `(method-decorator CALL TARGET)`. Binding resolves the receiver,
finds the decorator `$T.NAME`, and builds the same `macro-invoke` node a
source application builds. A missing decorator is the existing error
"unknown or forward-referenced macro '$T.NAME'". An Expression form in a
template is an ordinary call until `_method` in `src/expressions/calls.x`
binds it inside an expansion; `bind_method_macro` then takes it. Both build
their capture rows with `_template_arguments`, the owner that meta template
calls already use, so a template's arguments are read as a call's:
expressions, `key: value` entries, and splices, with a sequence hole taking
the rest.

For Entry forwarding, `_parse_postfix_apply` parses an `Entry` hole in a
call's arguments in the Map-entry role, which that hole kind already
accepts, instead of the argument role, which rejected it. A forwarded row
arrives as a bare `(map-entry KEY VALUE)`, and `_resolve_call_arguments`
gives it the `(expr ("Map") ...)` spelling that `parse_call_entry` gives a
source entry.

The definition travels in a field, not in the raised details, because a
raised value is copied, and expansion keys its state by the definition's
identity. In the prototype, passing it in the details made every free name
in the expansion fail with "identifier has an unknown binding identity".

### The forward-scan design it replaces

The first prototype scanned each statement ahead to its first top-level
`{`, `;`, or `}`, parsed the receiver once to find its type inside a rolled-
back transaction with held diagnostics, then parsed it again as the first
argument. It needed 122 more lines in `recognition.x`, a check that some
`$<type>.NAME` exists before the trial parse, and a fallback for a receiver
that failed to parse. Its scan also miscounted nesting at `%(` and `$(`
until that was fixed. The postfix design deletes all of that.

## Compatibility

- Code without a `$T.NAME` macro is unaffected. Every existing compiler
  fixture keeps its exact checked artifacts, and the compiler builds itself
  through stage 2. Verified. Whether the compiler's own generated C is
  byte-identical is not verified.
- A statement that begins with `(` now has `c.meta_statement` set to its
  `(`. That field decides when a meta call ends its statement: a meta call
  whose origin is `c.meta_statement` and that `;` follows is left for the
  statement to evaluate. A meta call's origin is its `$` token, never a
  `(`, so nothing changes. Five statements that begin with `(` and contain
  meta calls, and a meta call returning a statement inside parentheses,
  produce the same C, header, and diagnostics with the `dev` compiler and
  this one. Verified.
- Existing `$cui.row(ui, { ... })` decorators keep working beside the method
  forms. Verified with the prototype in the to-do example.
- Decision 4 is a deliberate change for types that define such macros: the
  macro replaces the method at method-form call sites.
- A method with a `Map @rest` parameter can have a macro of the same name
  that forwards its `Entry @options` rows to it, as
  `$ui.caption($text, @options)`. Verified.
- An `Entry` hole spliced anywhere other than a call's arguments is
  unchanged: `$ui.label($text, @({@options}))` is still rejected with
  "macro hole 'options' has ambiguous kind".

## Performance

Cold `make stage-3`, alternating baseline (`b393dd58c`) and prototype:

| Measurement | Baseline | Prototype |
| --- | --- | --- |
| User CPU, two runs each | 169 s, 178 s | 169 s, 176 s |
| Translating the compiler, stages 2 and 3 | 2.60 s, 2.64 s; 2.75 s, 2.79 s | 3.07 s, 3.18 s; 2.74 s, 2.71 s |

The two sets overlap. Later wall-time runs reached 40 s and 72 s against
26 s, with equal user CPU, while the machine's load average was about 27.
The slow steps then were the ones the unchanged bootstrap compiler runs. Two
runs per side cannot rule out an effect below about 0.3 s per stage.

These measurements are of the forward-scan design; the implementation was
not measured. The postfix design does
less work: it adds one macro-table lookup per method call and one group scan
per method call that names a decorator. One cold `make stage-3` of it took
26.4 s and 156 s of user CPU, inside the baseline's range.

## Limits and shortcuts

The prototype's compiler shortcuts are settled:

- **Source names** (prototype limit 2) come from the package records through
  `Compiler.package_source_name`, not from the last `__` in the name.
- **`<method-dec>`** (limit 8) stays a raise. A returned marker would have to
  stop the postfix loop and every binary, conditional, assignment, and comma
  tail that `parse_expression` and `_finish_paren_statement` run, and each
  of those callers would have to know that a statement ended inside an
  expression. The raise needs one catch, in `_expression_statement`, and
  `with` restores the parser fields it unwinds.
- **`c.meta_statement`** (limit 9) changes no meta-call behavior; see
  Compatibility. `_expression_statement` sets it for every expression
  statement, including one that begins with `(`.
- **The self-call check.** The prototype skipped a definition already on
  `c.macro_stack`. That check is replaced by the lexical mark described
  under the self-call rule, which owns decision 3.
- **Method forms in templates** and **Entry forwarding** are implemented.
- **Fixtures and book** (limit 10) are written.

What remains:

- A template cannot compute a nested definition's parameter list, so a
  generator needs one template for each arity. A `$private`-style fresh
  name is not accepted as a name component.

- Method forms work in statement and expression positions only, not at file
  scope (prototype limit 7), and only with `.`.
- In a template, a statement form whose receiver has no type yet takes a
  statement target, so such a form cannot apply an `Expr`-target decorator.
- In a template, a form recognized where the template expands reads its
  arguments as a call's arguments, not by its holes' kinds. A `Type`,
  `Stmt`, or other non-expression hole cannot take such an argument.
- Package work for x2cui, outside the compiler, keeps the prototype's
  numbers:
  1. Keys are read by position, `row[1][2][2]`, instead of through a syntax
     helper.
  3. Short names are keyed by option name across all widgets. `variant`
     always means a button variant, which is wrong for other records with a
     `variant` field. The prefix should come from the field's C type.
  4. The literals behind `fill`, `fit`, and the color tokens copy two details
     of CUI's macros (`CUI_SIZE_GROW, 1` and the token marker `0xC5, 0x1D`).
  5. The meta helper `_cui_fields` must be public, because an importing file
     cannot call a `meta static` function. A package needs a way to keep such
     a helper private.
  6. Only the to-do example's widgets have macros. The other components need
     `x2cui-generate.x` to produce them.

## Validation for an implementation

- Compiler fixtures: stacked decorators; each receiver form; a call followed
  by `(`; a statement with no matching decorator; a decorator inside a larger
  expression; a statement beginning with `*` or `(` after a block; the
  self-call rule; a macro shadowing a method. Done:
  `macro-method-form-decorators`, `macro-method-form-expression`, and
  `macro-method-form-in-expression`, and, for package source names,
  `package-method-form` and `import-method-form` over the toy package
  `unittest/compiler-fixtures/packages/panels`. Templates and forwarding:
  `macro-method-form-templates`, `macro-method-form-mutual`,
  `macro-entry-forwarding`, and a hole receiver in `import-method-form`.
  Decl holes and computed names: `macro-decl-foreach` and
  `macro-computed-name`.
- The x2cui to-do `--shot` image stays byte-identical to the one drawn with
  `$cui.row`; it is, for every prototype commit.
- `make stage-3`, `make verify-fixtures`, and `precommit`.

## Plan review

- **Established facts.** The ordinary parse establishes the receiver's type,
  and the macro table establishes which macros exist. Recognition uses both
  once and rechecks neither. The statement-start test reuses
  `c.meta_statement`, which `_expression_statement` already sets.
- **Reuse and new mechanism.** Invocation, argument capture, hygiene,
  `_decorate`, expansion, `Token.after_group`, and the package-prefix owner
  are reused. New mechanism: two `Compiler` fields, the `<method-dec>`
  signal and its one catch, the start token passed along the postfix
  tail, the `(method-decorator CALL TARGET)` statement that defers a
  template's statement form to binding, and the `(method-call DEFINITION
  CALL)` mark that carries the self-call decision from the definition to
  its expansion. The forward scan, trial parse, and existence check of the first
  design are deleted, and so are the prototype's group scanner, its `__`
  split, its `postfix_start` field, and its self-call check.
- **Idiomatic x2c.** Both forms are new invocation positions for existing
  macro kinds. Option lowering is an ordinary `meta` function over
  `Entry @rows`. Nothing is imported from another language's framework.
- **Validators and diagnostics.** No diagnostic is added. Errors come from
  the ordinary parse, ordinary typing, or the C compiler. Existing
  diagnostics gain callers: a template's statement form with no decorator
  reports "unknown or forward-referenced macro", and a form recognized
  where its template expands reports too few or too many arguments as a
  `$T.NAME(...)` call does. A `$T.NAME` with no parameters has no place
  for the receiver, so `receiver.NAME()` reports "macro invocation has too
  many arguments" instead of dropping the receiver unevaluated. Mutual
  method-form recursion is reported by the existing expansion depth limit;
  `macro-method-form-mutual` records that. The fixtures listed above
  protect deliberate public behavior.
