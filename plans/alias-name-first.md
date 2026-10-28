> Status: active
> Implementation authorized on 2026-10-27; direct delivery to dev.

# Name-first expression aliases

Support `alias name to expression;` and `alias name to expression { ... }`
alongside the existing expression-first and unnamed forms. Both spellings
have the same declaration-time bindings, scope, visibility, repeated
evaluation, shadowing, and removal behavior. `to` is contextual only after
the name in a name-first alias. Preserve ordinary identifiers and typedefs
named `alias`, `as`, and `to` outside the recognized declaration head.

Recognize the `identifier to` prefix in `src/macros/aliases.x` and parse
both spellings into the existing `AliasHead`. Reuse all alias installation,
binding, scope, and include operations. No new AST form or runtime state.
Recognize the exact `alias name to` token prefix before percent and Symbol
literals. Reuse the tokenizer's operand-tail classifier after braced aliases
whose expression ends in a literal, preserving its special handling of casts.

Extend the existing alias fixtures to cover the new spelling in lexical,
declaration, module, template, and indentation positions. Retain old-form
coverage and compare observable output. Document both spellings in the book.

Build and refresh the bootstrap with this capability before adopting it.
Convert the 43 audited diagnostic expressions to compact name-first aliases.
Move the native-module diagnostic to its sole consuming module member.
Keep the 19 audited raise macros and put each definition on one line with
braces. Preserve every message, error payload, and invocation's behavior.

Review and fix the completed authored diff, integrate current origin/dev,
run the applicable performance checkpoint and publication gate, review all
generated artifacts, and publish the validated tree to dev.

## Plan review

The prefix establishes the new form; the ordinary expression parser supplies
its value. Existing alias owners establish binding, visibility, and scope;
no consumer rechecks those facts. The change reuses `AliasHead` and removes
43 macro definitions without adding a representation, cache, or framework.
No new validator, dedicated diagnostic, or negative fixture is planned.
Existing fixtures exercise the deliberate new syntax and unchanged semantics.
