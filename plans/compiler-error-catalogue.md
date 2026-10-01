> Status: active
> The complete compiler rewrite is being prepared on a branch from `dev`.
> Gary will review the draft PR before it is merged; other work may advance
> `dev` while this branch is under review.

# Compiler error catalogue

Replace owned compiler diagnostic details with `$report(compiler, key, ...)`.
The native meta function selects an anonymous Statement macro from a Map;
the selected macro expands to the existing `report_error` operation. Keys
are compile-time String literals and do not enter the generated program.

Use at most three short dot-separated components. Prefer familiar words and
abbreviations such as `ref`, `expr`, `decl`, `sig`, `param`, `init`, and `ctor`.
Use hyphens sparingly: `type.optional-ref.unchecked` is the agreed example.
Share a key when message, category, and note structure describe the same
diagnosis. A catalogue key identifies a template; the existing broad category
remains the diagnostic code and recovery category.

The catalogue owns fixed wording, interpolation, fixed hints, and local
diagnostic construction. Caller operands are explicit expression captures;
receiver, token, origin fallback, evaluation, messages, and notes retain their
existing behavior. Arbitrary messages forwarded from other owners remain on
`report_error` at those boundaries. No public diagnostic codes or language
semantics change.

The starting inventory contains 280 calls in 23 source units: 268 owned
diagnoses and 12 forwarding calls. All owned calls are in scope. The central
catalogue and dispatcher use current Macro, Map, and native meta facilities.
An unknown key or incorrect operand count fails at the macro invocation.

Build the complete catalogue into linked native meta targets before adopting
the rewritten callers. Catalogue edits change the linked closure hash, so a
compiler with an older table cannot expand a newer table's invocations.
Regenerate linked targets and bootstrap through their documented tools.

Compare generated code across all migrated units, review every replacement
against its original template, and probe unknown keys, operand count, runtime
evaluation, source locations, categories, and notes. Use the existing
diagnostic, macro, and publication checks; add no recurring gate. Review the
authored diff, integrate current `origin/dev`, and validate the final tree
with `tools/gate-state.py ensure agent-pr-check`.

Deliver an unmerged draft PR with `dev` as its base. Do not advance `dev` from
this task. Record validation and any remaining limitation in the PR so Gary
can review the entire rewrite together.
