# plans/

Internal design and execution records for maintainers; not user documentation.

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
performance decisions, packaging work, and deferred items. Candidate staging
has passed on four platforms; the separate twenty installed-package cases
remain outstanding. Official publication remains held.

## x2cui package

[x2cui](x2cui-package.md) is the plan, specification, and running record of
the package over the CUI user-interface library. Gary accepted its
decisions on 2026-11-10. The package is implemented on macOS and in a
browser; on Linux arm64 and x86_64 it builds and passes its off-screen
checks.

[x2cui lists and tables](x2cui-lists-and-tables.md) records `ui.each`,
`ui.item`, `ui.table` with a Map of columns, `ui.table_row`, and `ui.cell`,
with the package's generated method forms and their option values. Gary
accepted its decisions on 2026-11-11. It is implemented in the package.

## Method-form macros

[Method-form macros](method-form-macros.md) gives decorators and Expression
macros method forms, as `ui.row (...) { }` and `ui.button(...)`. Gary
accepted its decisions on 2026-11-11. The compiler semantics, decisions 1 to
4, method forms inside templates, forwarding of `Entry` rows into calls,
`Decl` holes in `foreach` headers, computed macro names in templates, and
sequence holes before final `Entry` rows are implemented with fixtures and
a book section; the x2cui option lowering, decision 5, is package work.
File-scope and type-name method forms (`T.name(...)`) are merged into `dev`.

## Live UI and runtime loading

Three linked plans from 2026-11-24, the first two approved by Gary that
day. [x2cui Lisp surface](x2cui-lisp-surface.md) draws a UI held as a List
and lets a Lisp session change it; it is implemented in the package.
[x2cui builder](x2cui-builder.md) edits that List by pointing at it, with
CUI's layout; its first version is implemented as an example, without
dragging or free placement.
[x2cui builder redesign](x2cui-builder-redesign.md) is a proposal from
2026-11-25, not approved, to rebuild the builder's interaction around six
tasks after Gary judged the first version far from usable.
[Runtime native modules](runtime-native-modules.md) compiles and loads x2c
in a running program; it is a proposal, not approved or started, and adds
`dlopen` to the runtime.

## Current work

Reevaluated on 2026-11-15 against `955dfde73`. The repair batch below
resolves the first-hover, alias-member collision, native-module probe, lint
classification, Lisp explanation, and Notes command items. The earlier
included-alias collision already rejects correctly. Remaining work below
retains its prior scope; completed and superseded work is recorded in history.

| Remaining work | Current evidence and owner | Next bounded action |
| --- | --- | --- |
| List rendering recursion | [List rendering](../lib/list/rendering.x) has no recursive floor check. Regex matching was repaired in PR #650 after focused measurements; see the [release plan](public-release-readiness.md). | List rendering remains deferred; do not expand the accepted Regex repair. |
| Optional structured lint findings | [Lint](../commands/lint/x2c-lint.x) still prints human text only; [Lint.print](../commands/lint/lint.x) has findings to reuse. | Complete the previously approved List-output option and thin compiler consumer; keep execution optional and lint experimental. |

### Evidence questions

- Included-header attribute macros: the [reference](../docs/src/reference/language.md)
  supports attribute-prefix macros in ordinary mode, but the included-header
  probe fails without `--cpp`. Trace header visibility through
  [type parsing](../src/parse/types.x) before classifying the gap or choosing
  a compatibility change.

The CPP overflow and Linux weak-provider findings are now selected repairs,
not deferrals. CPP arithmetic leaves unsupported intermediate results undecided.
Linux REPL linking retains selected shared-library providers while preserving
weak declarations and missing-provider inspection. The release plan records
focused evidence and candidate validation requirements.

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
