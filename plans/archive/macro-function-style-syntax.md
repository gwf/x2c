> Status: done - 2026-09-21.
>
> Implemented from execution base `67cf4be5` with additive compatibility.
> Body-local `using $name;` is the generated-name directive, while lambdas
> retain `using &name`. The commit adding this archived plan delivers the
> compiler, corpus, tooling, documentation, fixtures, and generated artifacts.

# Function-style macro definitions

## Result

Make macro bodies follow the two function body forms while preserving macro
result kinds, holes, hygiene, expansion, and canonical AST:

```x2c
macro Statement $guard(Expr $condition) {
  if (!$condition) return 0;
}

macro Expression $twice(Expr $value) => $value + $value;
```

The semicolon on an expression body is required. Newlines are tokenizer
trivia, and without a delimiter a following postfix-looking statement can be
consumed as part of a local macro's expression. This is the same rule already
used by expression-bodied functions.

The change is feasible without a new AST, transform, emitter, runtime path,
or macro validator. `Compiler.parse_macro_definition` already lowers both
body families into the canonical `macrodef` template consumed by the existing
Match replacement and `Compiler.bind_syntax` path.

## Generated names

Do not mechanically move every header `using` clause. Ordinary names declared
inside a macro template are already hygienic and receive one private binding
per expansion. For example, the canonical swap needs no explicit generated
name declaration:

```x2c
macro Statement $swap(Expr $left, Expr $right) {
  $(x2c.syntax.type $left) temporary = $left;
  $left = $right;
  $right = temporary;
}
```

The tracked corpus has 30 macro definitions with 55 `using` binders. Of those,
42 are immediately owned by ordinary declarations and should become literal
hygienic names. Eleven genuinely need an explicit `Name` hole: the five names
passed to `foreach.expand`, all five autodiff locals passed to its compile-time
reverse transformation, and the `converted` binding passed into compile-time
Lisp by `native.update`. The final two are a duplicate-hole negative fixture
and an unused editor-grammar sample.

For the 11 real cases, use a compiler-only directive as a contiguous prefix
inside a braced body:

```x2c
macro Decorator $x2c.foreach(Block $body, Decl $declaration,
                             Expr $collection) {
  using $iterator, $item, $pair, $object, $cursor;
  $(foreach.expand
    $declaration $collection $body
    $iterator $item $pair $object $cursor)...
}
```

`using` remains contextual. In a lambda, `using &identifier` selects an
existing runtime binding for reference capture. In a macro body,
`using $identifier;` declares a new expansion-private `Name` hole. The sigils
make the two meanings explicit without adding another reserved word. A macro
generated-name directive creates syntax identity, not runtime storage, so it
works for static helper functions and labels as well as automatic variables.

Keep the directive prefix-only. Allowing it after emitted items or inside
nested braces would require hooks in every result-specific parser and would
suggest lexical scope that the definition-wide macro-hole map does not have.

## Compatibility

Ship the syntax additively:

- Direct `{ ... }` is the canonical braced form; continue accepting legacy
  `=> { ... }`.
- `=> expression;` is the canonical expression form; continue accepting the
  legacy complete `=> (expression)` body without a semicolon.
- A parenthesized new expression such as `=> (a) + b;` is not the legacy form.
  The parser must treat the initial group as legacy only when that group is the
  complete body.
- Retain signature `using` as compatibility syntax. The current public grammar
  permits it on expression-result macros even though the tracked corpus has no
  production use, and an expression body has no braced position for body-local
  `using $name;`. Do not add a speculative expression-directive envelope until
  a real use requires it.
- Keep lambda capture `using &name` unchanged. Its `&` aliases an existing
  runtime binding; macro `using $name` creates an expansion-private syntax
  name.

This policy lets installed and external `.xmacro` files continue to load.
Removing the old spellings can be considered only as an explicitly scoped
breaking change after a published migration interval.

## Evidence and scope

- `src/macros.x:2426-2700` owns the definition grammar, result/body checks,
  canonical `macrodef`, and existing `fresh` rows.
- `_parse_body` in `src/macros.x:2339-2368` already delegates braced templates
  to the ordinary block, field, enumerator, map-entry, and unit parsers.
- `src/macros.x:2953-3040` allocates the stored generated names per expansion;
  this remains unchanged.
- `src/parse.x:988-1028` and `src/macros.x:1838-1885` establish hygienic
  identities for literal declarations in a template. A focused probe confirmed
  distinct private bindings for literal local variables and static helper
  functions, including repeated expansion and caller collisions.
- Shallow collection calls the same parser through `src/compiler.x:891-903`;
  there is no second compiler grammar.
- The current tracked `.x`/`.xmacro` corpus contains 572 macro definitions in
  257 files, including 30 definitions with header `using`. Most definitions
  are compiler fixtures; 113 are outside `unittest/`.
- The current compiler rejects direct braced bodies with `expected '='` and
  unwrapped arrow expressions with `expected parenthesized or braced macro
  body`, confirming that neither proposed form is already accepted.

## Implementation

### 1. Add parser capability before migrating source

Refactor `Compiler.parse_macro_definition` in `src/macros.x`:

1. Parse the signature and result kind as today.
2. For expression results and expression-target decorators, accept the new
   arrow expression through the existing expression parser, require `;`, and
   retain the exact legacy balanced-parenthesis branch.
3. For all braced result kinds, accept `{` directly and retain `=> {` as a
   compatibility alias. Preserve the existing result-kind diagnostics.
4. Let `_parse_body` consume zero or more leading
   `using $first, $other;` directives. Reuse
   `_parse_signature_hole(c, 1)` so argument conflicts, duplicates, singular
   `Name` kind, and existing diagnostic behavior remain owned in one place.
5. Feed those binders into the existing `fresh` rows, invocation Match pattern,
   and expansion allocator. Do not change `macrodef`, template, source-origin,
   freeze/thaw, binding, or emission representations.

No tokenizer change is required: `using` is already contextual, and the `$`
and `&` punctuation tokens already distinguish the two forms.

### 2. Update duplicated source readers

Update `tools/x2c_source.py`:

- teach `_statement_spans` direct braced macro bodies and new
  semicolon-terminated expression bodies while retaining both legacy forms;
- teach `_unit_macro_definitions` direct `{`, compatibility `=> {`, and the
  body-prefix `using` directive;
- add focused scanner tests for adjacent definitions, nested delimiters,
  expression bodies beginning with parentheses, and Unit macros whose prefix
  contains generated names.

Update editor and site syntax consumers:

- `etc/vsc-extension/syntaxes/x2c.tmLanguage.json` and
  `etc/vsc-extension/test/current-grammar.test.x`;
- in-memory macro definitions in `tools/x2c-editor/tests/worker.test.js`;
- `site/shiki-x2c-theme.mjs` and `site/tests/highlight-book.test.mjs` if
  the generated-name scope changes;
- rebuild the checked-in VS Code extension package through its documented
  command rather than editing it as an archive.

### 3. Migrate the corpus by syntax, not text

Use a balanced/token-aware transformation or reviewed manual edits. Do not use
an unrestricted textual replacement.

- Remove `=>` before canonical braced bodies.
- Remove the expression body's delimiter-only outer parentheses, retain any
  semantically meaningful grouping, and add `;`.
- For header `using`, first prove which name owns the binding. Convert an
  ordinary body declaration and its references to one literal hygienic name.
  Add a leading body `using` directive only when Lisp or another generated
  form needs the `Name` hole before such a declaration.
- Keep focused old-syntax fixtures so compatibility remains tested.
- Cover authored sources under `src/`, `lib/`, `etc/`, `examples/`,
  `tools/`, `packages/`, `unittest/`, inline shell-probe sources, and editor
  test strings.

Update the owning prose and examples in:

- `docs/src/reference/language.md`;
- `docs/src/guide/macros.md`, `from-c.md`, `idioms.md`, and
  `meta-functions.md`;
- macro examples and the site's macro/decorator/keyword slides.

Regenerate compiler API pages, the module/documentation outputs,
`site/public/llms-full.txt`, `lib/x2c.x`, and other owned artifacts with their
repository commands. Do not hand-edit generated output.

### 4. Stage the self-hosting transition

The checked-in bootstrap cannot consume migrated new syntax.

1. Add the compatibility parser while the compiler and embedded macro sources
   still use old syntax.
2. Build an intermediate stage-0 compiler and run paired old/new probes.
3. Migrate the authored corpus with that capable compiler.
4. Regenerate `etc/*.xlisp`, documentation output, and `bootstrap/` from the
   migrated final source.
5. Review generated changes. The canonical templates and Lisp algorithms
   should be unchanged; unexpected semantic deltas are a stop condition.

`bootstrap/src/macros.c` will change for the parser and embedded shipped macro
text. Generated callers or headers change only if the implementation exposes a
new helper. `lib/x2c.x` should change only if its generated include inventory
changes, not because of syntax alone.

## Validation

Add paired old/new probes that compare source AST, expanded AST, generated C/H,
and runtime behavior for:

- every braced result kind and relevant decorator target;
- expression macros, expression-target decorators, multiline expressions, and
  a new body beginning with parentheses;
- global, local, imported, macro-generated, and shallow-expanded Unit macros;
- literal hygienic variables, helper functions, and labels;
- a genuine body-local `using $name;` passed into compile-time Lisp before its
  declaration;
- repeated expansion and collisions with caller spellings;
- argument/generated-name duplicates, duplicate directives, unused directives,
  and a
  use before the directive;
- a local expression macro followed by a postfix-looking statement, proving
  the semicolon terminates its body;
- both legacy body forms and legacy signature `using`.

Update intentional fixture expectations only through
`make verify-fixtures-update` and review every delta. Source migration will
move diagnostic line origins, so paired feature probes, not whole-tree C byte
identity, establish semantic parity. Run the relevant example, documentation,
editor, site-highlighting, and prepared package checks. Finish on the exact
final tree with:

```sh
tools/gate-state.py ensure agent-pr-check
```

## Plan review

The parser already establishes the result kind, hole kinds, body grammar, and
canonical template; expansion already establishes fresh binding identity and
ordinary binding owns declaration scope and type. The design does not recheck
those facts. It reuses `_parse_signature_hole`, `_parse_body`, the existing
`fresh` rows, Match pattern, and `bind_syntax` path.

The migration deletes wrapper punctuation and 42 unnecessary production
generated-name declarations. The only new lasting generated-name syntax is a
thin body-prefix placement of `using` for the 11 names that generated syntax
must receive explicitly. Prefix placement avoids new
traversals, scoped-hole machinery, or result-specific parser hooks and keeps
the implementation direct x2c.

No new AST, validator, cache, transform, emitter path, or runtime mechanism is
proposed. The only negative fixtures protect deliberate public behavior:
semicolon termination prevents the wrong expression from being captured;
duplicate and use-before-declaration checks prevent a misspelled or ambiguous
template binding; result-kind checks prevent syntax from entering the wrong
source position. Existing diagnostics own all other rejection behavior.
