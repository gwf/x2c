# md-edit isolated focus prototype

> Status: private prototype and measurements complete, 2026-11-16.
> The contract below is proposed for Gary's review. Shared CUI, shared x2cui,
> the installed package, and the original md-edit source remain unchanged.

## Result

Completed UI submission is a workable boundary for custom-editor focus.
Apply and Remove need one empty UI pass before the next queued text event.
Escape closes the dialog before submission and needs no extra pass. These
results hold with the editor before dialogs and with dialogs before the editor.
No unconditional release pass or CUI-owned replay scheduler is necessary for
these tested sequences.

This refines the unresolved timing question in
[the preceding investigation](md-edit-cui-reconciliation.md). It does not prove
that every CUI application or overlay transition has the same pass requirements.

The experiment starts from worktree revision
`2435d7eb009c75714c1098415ab6dbea94c9bd23`, with CUI pinned to
`a5c9ef5efc39b3fc783758362f6b8f9f130f5883`. The previous isolated integration
is preserved in `.context/md-edit`; this experiment is in `.context/md-focus`.

## What the prototype changes

The actual Markdown editor submits its canvas as focusable text input.
Keyboard routing queries CUI's single focus owner rather than trusting the
editor's private focus boolean. Selection remains editor state. Host routing
also checks current visibility, disabled, and read-only options.

A private request records a custom target ID. At `end_frame`, the last request
is resolved against the complete focus-order array, then expires. An absent or
disabled target does not acquire focus. A late request can therefore target an
editor that was submitted before the dialog action. The query checks the last
complete focus membership, window activation, modal layer, and popup exclusion.
It is called before component submission, not halfway through constructing UI.

The host marks reconciliation only when a dialog closes during drawing.
After that event's pass completes, policy 3 builds the changed UI once before
routing the next queued event. Escape is handled before drawing, so it does not
set this flag. Queueing, event ownership, and scheduling remain in MdInput.

The comparison uses four policies over the same focus implementation:

| Policy | Extra passes |
| --- | --- |
| 0 | After each mouse release, as in the previous application |
| 1 | None; deliberately retained as a failing control |
| 2 | After every event; cost control |
| 3 | After a dialog closes during drawing |

## Input and focus evidence

Fifteen actual-editor sequences run under four policies and two submission
orders: 120 cases. There are 114 passes and six expected failures. All six
failures are policy 1: Apply-to-text, Remove-to-text, and cold Link-open through
Apply-to-text, in each order. The document remains unchanged when that next
text is rejected by the still-recorded modal boundary.

All 30 cases using conditional reconciliation pass. These include ordered
text and modifiers, toolbar formatting, Apply, Remove, Escape, cold dialog
opening, source visibility, disabled/read-only transitions, window blur, and
repeated key-downs. Escape-down followed immediately by text also passes,
without a key-release event to hide a timing dependency.

| Sequence | Event passes | Required extra passes under policy 3 |
| --- | ---: | ---: |
| Mouse move/down/up on Apply, then text | 4 | 1 |
| Mouse move/down/up on Remove, then text | 4 | 1 |
| Escape-down, then text | 2 | 0 |
| Cold Link click, select URL, type URL, Apply click, text | 10 | 1 |
| Bold click, then text | 4 | 0 |

The trace explains the Apply result. At the release pass's completion, focus
already belongs to the editor, but the modal layer remains registered. The
empty pass removes that modal from the completed submission. The next text
then reaches the editor. Querying current and previous modal layers with an
OR would incorrectly continue blocking it.

Sixteen additional checks pass:

- Two editors share one input owner; the last focus request wins.
- A focus request after the target's submission takes effect for the next event.
- An open popover receives text instead of the underlying editor.
- Closing a popover and submitting the focus request restores editor input.
- Disabled and absent targets do not acquire focus; absent requests expire.
- Hiding and reintroducing a focused custom editor does not resurrect focus.
- Editor Space/Enter insertion and window-blur exclusion work.
- At canvas level, Tab shows focus; Space/Enter click a button canvas but do
  not click a text canvas. These keys reach CUI directly in this control test.
- The built-in inline editor preserves its forward-focus activation path.

The existing application also passes 4,261 model checks and 73 component checks
with policy 3. Hidden native Cocoa checks pass for text/key ordering, navigation,
scrolling, rendering, and save success/failure. These use responder methods;
physical keyboard delivery, IME composition, and browser execution were not
newly tested in this prototype.

## Measured pass costs

Same Mac16,5 host and optimized build configuration as the previous experiment.
Viewport is 1040 by 820, reduced motion is enabled, and pass delta is zero.
Four document sizes, three transitions, three passing policies, seven rotated
trials, and 20 batches per trial run in each submission order. The final run
contains 504 trial records, 10,080 batches, and 33,600 input events. No builds
or other agent benchmarks overlapped this run.

Fixture preparation, selection, dialog opening, and link setup are outside the
timed interval. Apply starts with an unlinked selected character; Remove starts
with an existing link. Each batch verifies resulting text length, first
character, link state where relevant, and dialog closure. Timing covers queue
dispatch, full UI submission/layout/draw-data generation, and nested extra-pass
timing. It excludes rasterization, native presentation, and OS event delivery.

Values are median trial means in milliseconds of process CPU per batch. The
extra-pass column is a nested measurement, not an inferred difference.

| Markdown bytes | Transition | Editor first: total | Editor first: extra pass | Dialogs first: total | Dialogs first: extra pass |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1,104 | Apply then text | 0.486 | 0.139 | 0.503 | 0.066 |
| 8,832 | Apply then text | 1.994 | 0.755 | 2.057 | 0.160 |
| 35,328 | Apply then text | 5.649 | 2.561 | 5.777 | 0.163 |
| 61,824 | Apply then text | 9.256 | 4.339 | 9.407 | 0.164 |
| 35,328 | Remove then text | 5.605 | 2.549 | 5.782 | 0.163 |
| 61,824 | Remove then text | 9.316 | 4.395 | 9.478 | 0.164 |
| 35,328 | Escape-down then text | 2.706 | 0 | 2.822 | 0 |
| 61,824 | Escape-down then text | 4.613 | 0 | 4.701 | 0 |

The extra pass is not all scheduling overhead. With the editor first, the link
command occurs after editor submission, and edit-dependent work falls into the
extra pass. Source inspection confirms that the new document revision triggers
Markdown serialization in `MdEditor.sync` and a layout rebuild in
`MdEditor.layout`. With dialogs first, that work occurs in the event pass. The similar
total times and different nested times support this interpretation; they do not
establish a net speed advantage for either declaration order. The two order
runs were sequential, so small total differences are not treated as causal.

For the 35,328-byte Apply batch with editor first, release-only policy 0 takes
5.619 ms in five passes, conditional policy 3 takes 5.649 ms in five, and
policy 2 takes 6.132 ms in eight. For Escape, conditional policy 3 takes
2.706 ms in two passes versus policy 2's 3.064 ms in four. Policy 1 loses input
in the Apply/Remove cases and is not a valid performance baseline for them.

An earlier timing run used Remove on an unlinked selection. It is retained as
`transitions-preliminary.csv` and excluded from these results. Raw final CPU
and wall timings and all policies are retained in `results.json` and the CSVs.

## Proposed contract for review

1. **Opt-in custom text focus.** A participating canvas registers in CUI's
   existing focus order and layer bookkeeping. Pointer and Tab use the same
   focus owner as built-ins. Text participation suppresses Space/Enter button
   activation. Selection and document state remain with the editor.
2. **Deferred custom focus request.** The target must be a participating custom
   control, identified by its stable ID. The last request before a completed
   submission wins. Resolve it against that submission, expire it there, and
   leave the current owner unchanged if the target is absent or disabled.
   Requests made between frames need a completed submission before input is
   routed under the new owner; there is no immediate-transfer promise.
3. **Completed-state keyboard eligibility.** Query only after a completed
   submission or before components in the next submission. Membership, focus,
   window activation, and modal/popup exclusion must all permit delivery.
   Unsubmitted host visibility or read-only changes remain host decisions.
4. **Scoped removal revocation.** Removing or disabling a participating custom
   owner revokes its eligibility and prevents automatic focus on reappearance.
   Keep metadata on the single owner; do not add a parallel editor registry.
5. **Host-owned reconciliation.** If an action closes an already-submitted
   dialog, submit the changed UI before dispatching the next queued event.
   One extra pass suffices in the tested transitions. Do not put an event queue,
   global dirty-state protocol, or mandatory release pass inside CUI.
6. **Visual timing.** The prototype commits requests after painting and requests
   redraw. It guarantees ownership for the next event, not same-frame caret or
   border updates. The production API must document deferred visual feedback
   or settle a stronger guarantee explicitly; these tests do not prove one.

The existing optional ordered-capture proposal remains separate. This experiment
does not change clipboard, wheel, italic drawing, or composition contracts.

### Compatibility boundary discovered during review

Do not globally clear every focus ID missing from a submission. Built-in inline
editing and scrub editing intentionally assign focus to a field before its next
submission. A global cleanup would erase that assignment. The prototype instead
records one opt-in custom-owner ID and only revokes that matching owner.
Built-in takeover clears the marker. The inline-edit regression test verifies
one concrete forward-focus path; this is not whole-library compatibility proof.

The prototype request function currently accepts any submitted ID and marks it
custom. It is an experimental helper, not a generic API ready for promotion.
The production surface must restrict its target to a participating custom
control. Its end-frame scan should also be guarded by custom owner/request
presence so applications that do not opt in avoid that work.

## Reproduction and retained artifacts

All paths below are local to this worktree:

- `.context/md-focus/run.sh`: run the actual app with conditional reconciliation.
- `.context/md-focus/focus.patch`: private CUI and app delta against the previous
  isolated integration; no shared package file is part of this patch.
- `.context/md-focus/focus-probe.x`, `replay-probe.x`: ownership, transition,
  failing-control, and timing probes.
- `.context/md-focus/cases.csv`, `cases-reversed.csv`, `focus-results.txt`:
  exact correctness results, including intentional policy-1 failures.
- `.context/md-focus/transitions.csv`, `transitions-reversed.csv`: final timings.
- `.context/md-focus/trace.log`, `trace-cases.csv`: completed focus/modal state
  around Apply under each policy.
- `.context/md-focus/summarize.py`: validates counts, exact failure cases,
  pass counts, and trial structure; writes `results.json`.
- `.context/md-focus/reproduce.py NEW_DIRECTORY`: copies the previous isolated
  baseline, applies the private patch, verifies authored-source hashes, builds
  the package/app/probes, and runs the correctness checks. Existing destinations
  are refused. It does not install files.
- `.context/md-focus/reproduced`: successful independent reconstruction, with
  identical case matrices and ownership checks and passing existing checks.

Original md-edit source fingerprints were verified unchanged. No shared CUI
change, PR submission, installation, or deployment occurred.

## Design review and remaining limits

The prototype reuses CUI's owner, focus arrays, layers, and input entry points.
The extra state is a pending custom request and metadata identifying the opt-in
owner. The application owns its one reconciliation flag and existing queue.
The failed no-extra control establishes the need for reconciliation in these
transitions, not the impossibility of a different immediate/modal-close design.

Nested modal/popover combinations, accessibility, IME composition, physical
input-to-visible latency, and browser behavior remain unverified. The request's
visual timing and target-kind restriction must remain explicit in any proposed
public API. The recommended next step is review of this bounded contract before
implementing shared CUI changes.
