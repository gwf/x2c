# Temporary assignments with `with`; lexical substitution with `alias`

> Status: done, 2026-10-24.
> Implemented as designed and delivered to `dev` in the batch that begins at
> `ab9645f0c`. The built-in `$x2c.with` decorator lowers `with` through
> `with.expand` in `src/builtins.x`; `src/macros/aliases.x` owns both
> `alias` forms. Local aliases are Sym rows; file-scope and body aliases are
> macro-state entries, for the reason its header records. Two interactions
> surfaced during implementation: a substituted plain name read as `(name)`
> destructuring, and a hidden local shared its C spelling with the local
> that hid it. Substitution therefore returns the expression without a
> `parens` node, and `Compiler.reveal_binding` respells the hidden local.

## Summary

Replace `$let` with contextual `with` syntax supporting multiple temporary
assignments. Rename the current expression-alias construct to `alias`, and
add scope-wide alias declarations. Preserve expression substitution and
existing bindings. Reuse ordinary parsing, symbol scopes, assignment typing,
macro templates, and deferred cleanup. Do not extend general macro invocation
syntax. Publication of this plan does not implement the language change.

## Language design

### Temporary assignments

```c
with (object.mode = quiet, object.depth = object.depth + 1) {
  inspect(object);
}
```

Require parentheses, at least one `destination = expression` entry, and a
braced body. Separate entries with commas; parenthesize a comma expression
inside an entry. Accept simple `=` entries, not compound assignments.

Process entries from left to right. Evaluate each destination once, save its
previous value, register restoration, and install its temporary value. Later
entries observe earlier assignments. Restore destinations in reverse order
through ordinary deferred cleanup, including supported early exits and
exception transfer. If a later initializer transfers control, previously
registered restorations still run.

Multiple entries behave like nested single-entry blocks. Repeated destinations
are permitted. The body may change a destination again; exit still restores
its saved value. Restoration affects only the selected locations, not other
side effects of initialization or execution.

Preserve `$let`'s requirements: destinations must be addressable and assignable,
and their storage must outlive the body. Restoration uses the captured address.
Do not add bit-field support or transactional rollback. `with` remains
contextual; `import ... with` keeps its existing meaning.

### Expression aliases

```c
alias object.settings as settings;

alias object.settings as settings {
  inspect(settings);
}

alias object.settings {
  inspect(_);
}
```

Use expression-first syntax, `alias expression as name`. The semicolon form
requires an explicit name. Visibility starts after the declaration and ends
with its enclosing lexical scope. The braced form permits omission of
`as name`, defaulting to `_`.

Substitute a parenthesized expression at each expression-position use. An
unused alias does not evaluate its expression; repeated uses repeat evaluation.
Preserve the parsed expression's declaration-time bindings. Later shadowing
does not retarget them. Do not replace declaration names, field names, labels,
types, or literal atoms.

Follow ordinary declaration conflict rules: inner scopes can shadow outer
names; conflicting declarations in the same scope are rejected. Parse the
source expression before installing the alias, so an outer binding remains
available in that expression.

Permit aliases at file, module, statement, and aggregate declaration scopes,
including enumerator bodies. Semicolon aliases are compile-time declarations:
they contribute no runtime statement, field, or enumerator. At declaration
scope, a braced alias wraps declarations. Its alias name ends at the closing
brace; enclosed declarations retain normal placement in the surrounding file
or aggregate. Inside functions, the braced form retains ordinary block behavior.

File-scope aliases follow source-ordered macro visibility through includes.
`static alias expression as name;` keeps an alias private to its declaring
file. Local and declaration-body aliases do not escape their lexical scope.
`alias` remains contextual.

## Research and implementation

### Existing behavior and owners

- [Built-in macros](../../etc/builtin-macros.x) implement `$let` with a captured
  address, saved value, assignment, and `defer`.
- [Statement parsing](../../src/statements.x) implements current `with` aliases
  with a parsed expression, a lexical binding, and semantic binding facts.
  [Expression parsing](../../src/expressions/syntax.x) substitutes that expression;
  [declarator parsing](../../src/parse/declarators.x) handles template shadowing.
- [Local macro rules](../../docs/src/reference/language.md#local-definitions)
  provide lexical visibility and macro-generated local definitions, but
  require invocation parentheses. Free names resolve where expansion lands.
- [Decorator and keyword rules](../../docs/src/reference/language.md#decorators)
  let `keyword` give a macro an identifier spelling. They retain its argument
  grammar and do not provide `alias expression as name;`.
- [Current alias semantics](../../docs/src/reference/language.md#expression-aliases-with-alias) establish
  repeated expression substitution, not a stored value or captured reference.

Keep aliases on the existing parsed-expression representation rather than
routing them through ordinary local macro expansion. The latter would change
binding behavior and require bare-name invocation support. General macros and
`keyword` are unchanged by this design.

### Connected changes

Generalize the current alias implementation into one owner shared by braced
and semicolon forms. Connect lifetime to existing lexical scopes. Remove
construct-specific name-restoration bookkeeping where scope lookup supplies
the same guarantee; do not discard bindings and reconstruct them by spelling.

Integrate aliases with declaration collection, includes, module visibility,
aggregate parsing, macro templates, and statement parsing. Preserve source
order and definition-time expression bindings across collection and parsing.
Declaration wrappers must not accidentally make their enclosed declarations
private to the wrapper.

Recognize temporary-assignment entries through ordinary expression parsing
and canonical AST structure. Lower them to nested saved-address, saved-value,
assignment, and `defer` code equivalent to `$let`. Reuse existing binding,
typing, assignment, and cleanup operations. Add no runtime mechanism or
general rewriting framework.

### Bootstrap transition and migration

1. Introduce `alias` and assignment-header `with`, temporarily retaining old
   forms for bootstrap development. Distinguish new assignment headers from
   legacy alias syntax during this transition.
2. Rebuild and refresh bootstrap through repository targets before adopting
   syntax the original seed cannot consume.
3. Migrate active compiler, runtime, tooling, package, example, test, and
   documentation sources. Replace `$let(place, value)` with
   `with (place = value)`, adding blocks for formerly unbraced bodies.
   Replace legacy alias `with` forms with `alias`, preserving bindings.
4. Remove `$let` and legacy alias syntax from the final language. Update the
   book, editor syntax support, and source-migration documentation. Leave
   import clauses and unrelated contextual identifier uses unchanged.
5. Regenerate derived artifacts through existing targets. Preserve archived
   plans as historical records. Review and fix the completed authored diff
   before publication validation.

Use syntax-aware, mechanically checked transformations, not unrestricted
textual replacement. Temporary compatibility exists only for the development
transition; the final language replaces both old spellings.

## Verification and delivery

Use existing suites and fixtures; add no recurring gate. Verify:

- Multiple assignments, left-to-right visibility, reverse restoration,
  repeated destinations, and destination evaluation side effects.
- Normal exit, return, loop exits, and existing exception-transfer cleanup,
  including transfer during a later initializer.
- Alias repeated evaluation, unused expressions, l-value use, chaining,
  shadowing, and preserved bindings after later declarations.
- Both alias forms at supported scopes, including declaration wrappers whose
  declarations retain their normal placement.
- Include ordering, exported aliases, static file-private aliases, and modules.
- Macro-generated aliases, template hygiene, contextual identifiers, and
  unchanged `import ... with` behavior.
- Braced and indentation-layout syntax, removal of old forms, and preserved
  generated behavior across the migrated corpus.

Use existing diagnostics for malformed syntax, invalid destinations, and
conflicting declarations. Negative fixtures protect those deliberate public
rules, not merely earlier rejection.

Implementation follows the existing performance checkpoint and publication
requirements. Direct delivery to `dev` is the default unless Gary selects
another destination. Saving this plan and its supporting documentation uses
`tools/gate-state.py ensure doc-check`; implementing the language change uses
`tools/gate-state.py ensure agent-pr-check` on the final integrated tree.

## Plan review

The parser establishes expression and assignment structure. Existing binding
and typing operations establish referenced objects and assignment validity.
Consumers reuse those facts instead of validating them again.

The design reuses current alias substitution and `$let` cleanup behavior,
then removes old spellings and transitional parser paths. Shared alias handling
is necessary because these semantics now apply at multiple scopes. No new
runtime state, cache, or general rewriting framework is required.

Lowering remains ordinary x2c built from expressions, locals, and `defer`.
Validation is limited to the selected grammar and declaration-conflict rules.
Negative fixtures protect those public rules and assignment validity; no
additional defensive validators or diagnostic-only machinery are planned.
