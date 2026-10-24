# Ending an alias with `unalias`

> Status: active, approved by Gary on 2026-10-24.
> Depends on the `with` and `alias` implementation (PR 286,
> [archived plan](archive/with-and-alias.md)). Implementation follows as a
> separate PR that also depends on PR 286.

## Summary

Add `unalias name;`, which removes an alias that the current scope declares.
Its main use is a file-scope alias that an include delivers: today the
including file can neither declare that name nor end the alias, because an
alias follows macro visibility and has no counterpart to `#undef`. Reuse the
alias owner, its scope rules, and its compile-time effects. Add no runtime
mechanism and no hiding state.

## Need

A braced alias already limits a name to a block or a run of declarations,
and `static alias` keeps a file-scope alias out of including files. Neither
helps the file that receives a public alias from a header. After the
declaration-site conflict check in the `with` and `alias` work, a later
declaration of that name in the including file is an error, and the only
remedies are editing the header or renaming. C gives the same situation for
macros the `#undef` directive. `unalias` is that operation for aliases,
limited to lexical scope.

## Language design

```c
#include "settings.x"   // alias config.level as level;

unalias level;
int level = 4;
```

- `unalias name;` removes the alias `name` that the current scope declares:
  an alias declared earlier in the same block, aggregate body, enumerator
  body, or braced wrapper, or at file scope a file-scope alias, including
  one an include delivered. After it, `name` means what it meant before that
  alias, and a later declaration of `name` in the same scope is not a
  conflict.
- It does not reach into an enclosing scope. An inner block cannot remove an
  outer alias; that alias ends with its own scope, and a braced alias ends it
  sooner. Removing an outer alias for the rest of an inner block would need a
  hiding row with no other meaning. Naming no alias of the current scope is
  an error.
- Positions match the semicolon `alias` form: file scope and module members,
  block items, `struct` and `union` bodies, and `enum` bodies, where it needs
  no comma. It cannot be the body of `if` or another statement. It has no
  braced form and no `static` form.
- `unalias` is contextual. It begins the form when an identifier and `;`
  follow and `unalias` is not a visible typedef name; otherwise it is an
  ordinary name. Indentation layout gives an `unalias name` line its `;`, as
  for other statements, except in an enum body.
- In a macro template it removes an alias of the template, which belongs to
  the template as before.

### Includes and modules

A file-scope `unalias` of a public alias is a compile-time effect. An
including file applies it at the include line, after the included file's
earlier effects, so a header that aliases a name and then removes it leaves
nothing visible to its includers. Removing a `static alias` exports nothing.
In a module unit, a member's `unalias` applies to the members and entry text
after it, as an alias does; a member cannot remove another member's
`static alias`, which it cannot see.

## Implementation

- `src/macros/aliases.x` owns the form. Extend its recognizer and its three
  parse entry points (statement, file-scope declaration, aggregate member)
  to accept `unalias`, so the hooks in `src/statements.x`, `src/parse/units.x`,
  and `src/parse/types.x` stay unchanged.
- Decide the target with `Compiler.scope_declares_alias`, the query the
  declaration-site conflict check already uses.
- A Sym-row alias is removed by a new `Sym.undefine_alias`, which drops the
  row, its binding, its `(alias binding)` fact, and its scope and total alias
  counts. A macro-state entry is removed through the existing copy-on-write
  table, so a body still restores its outer entries at its closing brace.
- A file-scope removal of a public entry records
  `(compile-time unalias name)`; `Compiler.install_compile_time_effects`
  applies it by removing the entry.
- Make file-scope conflicts follow source order, so `alias ...; unalias n;
  int n;` is accepted. The alias-site check against file-scope declarations
  runs only during collection, where the symbol map holds the declarations
  before the alias; the declaration-site check covers declarations after it
  in both passes.
- Preserve include-time conflicts while making declaration checks
  source-ordered. An imported alias whose name the including file already
  declares or aliases at file scope remains a conflict. The alias owner
  already rejects an included alias that repeats a file-scope alias.

## Documentation and tools

Add `unalias` to the alias section of `docs/src/reference/language.md` and
its contextual words in `docs/src/reference/syntax/lexical.md`, the alias
rules in `etc/syntax/grammar.x` and `etc/syntax/extensions.x` with their
generated pages, the VS Code grammar and its test file, and REPL completion
keywords.

## Verification and delivery

Add fixtures; add no recurring gate.

- Runnable: removal and redeclaration in a block, at file scope, in a struct
  body, and in an enum body; a header that aliases and removes a name.
- Generated C: an including file that removes an imported alias and declares
  the name itself.
- Negative: no alias of that name in the current scope, an outer alias named
  from an inner block, `unalias` as the body of `if`, and an imported alias
  that conflicts with an earlier declaration of the including file.
- Contextual: a variable or typedef named `unalias`.

Deliver through the shared integrator as one PR. The integrator runs
`tools/gate-state.py ensure agent-pr-check` on the combined tree.

## Plan review

The removal reuses the alias owner's scope query, copy-on-write table, Sym
rows, and compile-time effects. It adds no state: removal deletes existing
rows and entries. Limiting `unalias` to the current scope keeps
removal from needing hiding rows or restoration bookkeeping. Include-time
conflicts remain enforced where the imported entry is installed, reusing
the existing boundary rather than adding a second validator.
