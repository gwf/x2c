# plans/

Active plans live here while their work needs a design or execution record.
Each opens with a `> Status:` block stating its actual state. Durable plans
follow the review below; workspace notes belong in `.context/`.

[HISTORY.md](HISTORY.md) is the single compressed historical record. It keeps
material outcomes, supersession, and evidence limits. Git retains the complete
original plans and research files. Finished plans can be folded into that
record; their instructions do not remain current requirements.

The book owns language/library contracts. Source owners and current repository
guidance own implementation and workflow. A historical rejection does not
forbid a different design or a new workload-supported investigation.

## Public release work

[Public release readiness](public-release-readiness.md) is the authorized
implementation plan based on `68ebfece6`. It records bounded repairs,
performance decisions, packaging work, and deferred items. The small fixes are implemented;
website work belongs to a separate session.

## Current work

Checked against `a7a01924c` on 2026-11-02. These are the remaining items from
the former active plans, verified during consolidation. This cleanup does not
implement them. The public-release plan above records the callable and region
repairs completed on its work branch; remaining rows below are unchanged.
Completed and superseded items are explained in the history.

| Remaining work | Current evidence and owner | Next bounded action |
| --- | --- | --- |
| File-scope diagnostic location | A five-line Iter initializer reports `6:1`; [transform traversal](../src/transform/traversal.x) does not select the recorded definition span. | Anchor that diagnostic through the existing source-location owner. |
| Alias collisions | Member-wrapper and declaration-before-included-alias cases still translate; [aggregate parsing](../src/parse/types.x), [aliases](../src/macros/aliases.x). | Repair these shapes through their existing binding checks. |
| Regex and List rendering recursion | [Regex](../lib/regex.x) checks repeated-group iteration but not all recursive matching; [List rendering](../lib/list/rendering.x) has no recursive floor check. [STATUS](../unittest/STATUS.md) retains prior overflow evidence; large crashes were not rerun. | Bound the respective recursive paths; pair Regex changes with focused hot-path measurements. |
| First hover on an unopened script | First hover returns null, identical second/opened hover finds the value; [LSP requests](../commands/lsp/lsp.x) compute the cursor before [analysis](../commands/lsp/analysis.x) rewrites stored script text. | Preserve original cursor coordinates through the existing mapping. |
| Optional native-module probe | [The probe](../unittest/probes/run-native-modules.sh) submits a REPL meta declaration that the current playground explicitly rejects. | Use source loading for that check while preserving compile-time native coverage. |
| Lint member documentation tier | Entry-only internal manifest classification does not reach its member; [comment checks](../commands/lint/comments.x) use the member path despite an existing entry field. | Reuse the entry's classification and cover the module case. |
| Notes benchmark instructions | [The instructions](../examples/apps/notes/bench/database-thread.md) repeat include and prefix discovery already supplied by package linking. | Remove only those redundant arguments; no database architecture change. |
| Runtime Lisp explanation | [The reference](../docs/src/reference/language.md#runtime-lisp) documents bindings but not explicit condition truthiness or the evaluator's stack/step limits. | Explain those existing semantics using [the evaluator](../lib/lisp/evaluate.x) and current Lisp API. |
| Optional structured lint findings | [Lint](../commands/lint/x2c-lint.x) still prints human text only; [Lint.print](../commands/lint/lint.x) has findings to reuse. | Complete the previously approved List-output option and thin compiler consumer; keep execution optional and lint experimental. |

### Evidence questions

- Included-header attribute macros: the [reference](../docs/src/reference/language.md)
  supports attribute-prefix macros in ordinary mode, but the included-header
  probe fails without `--cpp`. Trace header visibility through
  [type parsing](../src/parse/types.x) before classifying the gap or choosing
  a compatibility change.
- Linux REPL dependency identity: [dependency collection](../commands/repl/repl-program.x)
  treats an entire trace line as a path. Decorated GNU linker output and stale
  reuse have not been reproduced on Linux. Obtain that evidence before repair.
- CPP arithmetic: [conditions](../src/cpp/conditions.x) use native signed
  arithmetic. Settle intermediate-overflow behavior against the reference and
  obtain sanitizer evidence before choosing arithmetic semantics.

Dormant feasibility studies and unselected optimization ideas are historical,
not active work. No broad null audit, public-API deletion, extra gate, or new
benchmark campaign is commissioned by this list.

## Required plan review

Before a plan is presented for approval, end it with a short `## Plan review`
that states:

- which exact facts existing producers or boundaries establish, and whether
  any proposed consumer rechecks those facts;
- what existing code the design deletes or reuses, and why each new helper,
  representation, traversal, cache, or other lasting mechanism is necessary;
- why the resulting source is direct and idiomatic x2c rather than a framework
  imported from another compiler or language; and
- every proposed validator, dedicated diagnostic, and negative fixture, with
  the wrong output, corrupted state, unsafe native crossing, or deliberate
  public behavior it protects. If there are none, say so.

Revise the design before approval when this review finds a duplicated
guarantee or machinery whose only benefit is earlier or more specific failure.
Tests, fixtures, performance work, and green gates may prove a design; they do
not justify keeping the machinery they exercise.

Each planned change also ends implementation with a source review before
the publication proof. That review inspects the completed authored diff for
the same trusted facts, deletion and reuse opportunities, unnecessary
machinery, and idiomatic x2c choices, and fixes what it finds. It is not a new
gate or a report.
