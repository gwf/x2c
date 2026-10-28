> Status: done
> Implemented and validated on 2026-10-27 in 2816c20e1.
> Both spellings, the 43 conversions, and the 19 compact raises are complete.

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

## Validation

The final `tools/gate-state.py ensure agent-pr-check` passed: 1,308 compiler
fixtures, 1,051 unit tests with 27,534 assertions, documentation examples,
command checks, cold collection, bootstrap recovery, and self-host comparison.
Integration with the independent lint-command update retained compiler proof
and passed the changed consumer checks. Existing fixture outputs were retained.

The JSON, process, regex, string, and Var generated C match the baseline after
normalizing diagnostic source line numbers. The tokenizer and alias parser
contain the intended syntax changes; generated linked-meta hashes were refreshed.

A fixed seven-file translation corpus used the baseline unit sources for
String, JSON, Regex, Tokenizer, Array, Map, and Var. Both compilers had current
prelude interfaces and no missing prelude units. Five alternating measured
runs followed warmups, using `/usr/bin/time -l` instruction counts. The baseline
c74ee597a median was 14,655,899,860 instructions; candidate 2816c20e1 used
14,713,367,856 instructions, an observed increase of 0.39%. The sample ranges
over five runs were 14,615,360,143-14,687,917,639 and
14,677,477,867-14,766,419,820 respectively. This covers translation of those
seven inputs, not full-build or runtime performance.

## Plan review

The prefix establishes the new form; the ordinary expression parser supplies
its value. Existing alias owners establish binding, visibility, and scope;
no consumer rechecks those facts. The change reuses `AliasHead` and removes
43 macro definitions without adding a representation, cache, or framework.
No new validator, dedicated diagnostic, or negative fixture is planned.
Existing fixtures exercise the deliberate new syntax and unchanged semantics.
