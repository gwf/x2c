# Pattern conditions

> Status: done
> Implemented 2026-10-26 in 94942111d, with subsequent integration fixes.
> Behavioral fixtures and generated C verified. Publication uses the
> delivering tree's standard gate and performance evidence.

`subject ~= pattern` tests once and returns an int. It has equality
precedence. The right operand uses the existing match pattern grammar,
including typed captures. Captures are visible on the right of `&&` and
in the true arm of `if`; parentheses preserve this visibility. Negation,
`||`, and other operators do not export captures. Else and following
statements retain their ordinary scope.

Reuse pattern analysis, binding identities, typed capture declarations,
and match lowering, including its fallback for complex patterns. Keep the
user's branch outside any generated switch so break and continue retain
ordinary if behavior. Lower positive conjunctions as nested conditions;
a match condition uses the existing match tests without a switch. Plain
predicate expressions use a statement expression returning success.

Verify success/failure, typed and tail captures, subject evaluation count,
short circuit, else, shadowing, break/continue, complex patterns, and macro
constructed syntax. Inspect generated C for the simple pattern's direct
tests. Review the authored diff, then follow the repository performance
checkpoint and publication gate before direct delivery to dev.

## Plan review

The pattern owner establishes definite captures and types; consumers reuse
those facts. Existing symbol binding identities provide conditional scope.
The new condition node carries the pattern's declarations and visible
bindings because the expression must expose names without declaring them
in its caller's scope. Existing matching operations remain authoritative.
Nested conditions preserve lexical lifetimes without a capture-storage
framework or new runtime API. Existing diagnostics protect invalid patterns
and unavailable names; focused negative cases cover capture scope. No new
recurring checks or gates are added.
