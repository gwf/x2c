# Ordinary dispatch examples

`components.x` registers typed addition and Choice switch translation through
`$rewrite`. Macro patterns recognize syntax and quotations construct results.
The compiler selects candidates by operation; full matching decides eligibility.

An ordinary method lookup runs first. Member rewrites run only after a miss.
Binary rewriting follows operand typing. Switch rewriting uses the existing
statement transformation boundary. These are explicit compiler operations, not
an authored hook language.

Only the active registration is suppressed while its replacement binds.
`composition.x` verifies independent rules can compose. `bindings.x` distinguishes
global, shadowed, and restored-global bindings. `constraints.x` and
`recognition.x` exercise typed patterns and registration selectivity.

Decorator support retains compile-time-only function definitions and rolls back
speculative meta-group rows with symbol transactions. The internal code-value
carrier preserves captured binding identity. Component bodies do not construct
raw AST lists.

Run `python3 experiments/language-components/run.py` for the complete optional
corpus. Passing these bounded examples establishes behavior, not a compiler
throughput improvement or a complete delegation replacement.
