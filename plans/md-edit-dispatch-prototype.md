# md-edit focused-component dispatch prototype

> Status: isolated prototype complete, 2026-11-16. Shared CUI and x2cui,
> the installed package, and the original md-edit source remain unchanged.
> Shared API implementation and publication remain held for Gary's review.

## Result

The actual md-edit component now has a component-owned resolver, ordinary
command dispatch, typed host requests, and explicit unhandled-input fallback
in an isolated build. It can replace, block, or decline default bindings.
Committed text can invoke a programmatic command instead of inserting text.
Keyboard commands and toolbar actions share the same command operation.

The prototype implements the bounded contract in
[focused-component input handling](focused-component-input.md). It extends
[the prior focus prototype](md-edit-focus-prototype.md), which remains preserved
as the comparison baseline. The shared worktree starts at
`f082c30be`; both versions use CUI revision
`a5c9ef5efc39b3fc783758362f6b8f9f130f5883` plus their private experimental patches.
The new files are retained under `.context/md-dispatch`.

## Implemented behavior

The private CUI dispatcher maintains key/modifier state, calls the host's
synchronous route callback, and applies unhandled defaults afterward. It
provides repeated-down metadata derived from state before the update.
The host routes to the eligible component first, then its active enclosing
scope and permitted application commands. CUI does not store component
callbacks or acquire a Markdown command vocabulary.

The existing Tab traversal was extracted and reused. The dispatcher preserves
the previous submitted Tab owner, so built-in code editors can still insert
Tab. An unhandled paragraph Tab traverses exactly once after component refusal.
The legacy input path retains its existing frame-start traversal and modifier
sampling. No CUI event queue or mandatory extra submission was added.

MdEditor resolves an input into a local command, explicit consumption, or
fallback. The default map handles exact modifier combinations and lets each
command choose whether repeated downs invoke it. Unknown keys and releases
are no longer unconditionally swallowed. A caller-supplied resolver can
replace the defaults without editing CUI.

| Input | Executed behavior |
| --- | --- |
| Primary+B | Format command shared with Bold toolbar and direct command calls |
| Override Primary+B | Italic command, explicit consumption, or explicit decline |
| Primary+K | Typed OpenLinkEditor request containing editor and selection |
| Primary+S, declined by editor | Host Save dialog; blocked from background use in a modal |
| `*` then committed space | Bullet conversion within the insertion transaction |
| Paste `* ` | Literal insertion without typing-prefix conversion |
| Committed text through a custom resolver | Programmatic movement without text insertion |
| Tab / Shift+Tab in a list | Indent / Outdent |
| Tab in a code block | Insert indentation |
| Tab / Shift+Tab in a paragraph | CUI focus traversal |
| Escape with editor-owned suggestion state | Dismiss local state before host Escape |
| Read-only mutation command | Consume without changing the document |

The existing prefix-recognition helper is now called inside the document's
insertion transaction, before its single commit. Conversion ends the typing
merge group. Undo after typing `*` and space restores the literal `*`; Redo
restores the bullet. Serialization, selection, and document revision follow
the same transaction. Paste uses a separate insertion mode.

Ownership notifications run after every completed submission, including empty
frames and reconciliation passes. They cancel local keyboard state on focus
loss. A repeated down in a new owner cannot arm a release-bound command whose
initial press belonged elsewhere. A genuinely owned press/release can execute
such a binding.

The existing dialog reconciliation rule is unchanged: Apply/Remove require one
extra pass after draw-time closure; pre-draw Escape requires none. A cold
Link-open through Apply-to-text sequence needs one extra pass after Apply.

## Physical state versus default actions

This experiment establishes a necessary refinement to the proposed contract.
Updating physical state while skipping `kpressed` is not sufficient: hold
buttons and node panning also inspect held keys.

The prototype retains physical held state and records whether a down was
consumed or arrived while inactive. Such a key cannot drive default held
behavior until release. Component-owned repeating commands can still interpret
the ordered input themselves. Modifier and release bookkeeping always runs.

In the private implementation, `cui_key_down` reports actionable held state
for opt-in dispatch, while `cui_probe_physical_down` exposes physical state.
Applications that never opt in retain the prior behavior. This naming and
semantic distinction must be explicit before a shared API is chosen; do not
silently present both as the same query.

A final probe reproduced three failures before the inactive fix: an inactive
key-down could activate a hold button, appeared actionable, and remained
armed upon reactivation. The fixed version preserves physical state but blocks
the action until release. The failed probe output is retained. The final
positive control confirms that a fresh press after release activates normally.

## Validation

The final isolated build passes:

- 52 dispatch checks covering command reuse, override replacement/consumption/
  decline, typed requests, host fallback, exact modifiers, prefix conversion,
  Undo/Redo, paste, Unicode and multi-codepoint commits, read-only copy and
  navigation, repeat policies, and inactive-window behavior.
- Those checks also cover Tab/Shift+Tab, modal containment, built-in code-editor
  Tab, local Escape before host Escape, ownership loss during empty frames,
  repeated downs after transfer, release bindings, and physical/actionable
  held state. Actual hold-button controls cover normal, consumed, inactive,
  reactivation, release, and fresh-press behavior.
- All 16 previous focus checks, including built-in inline-editor forward focus.
- The original 4,261 model checks and 73 component checks.
- Hidden native Cocoa checks for ordered text/key delivery, navigation,
  scrolling, rendering, and save success/failure.

The prior transition matrix still contains 120 cases across four policies and
two submission orders: 114 pass and six intentionally fail. All failures are
in the no-extra-pass control: Apply-to-text, Remove-to-text, and cold-open
through Apply-to-text in each order. All 30 cases under the selected conditional
policy pass. These controls were preserved rather than removed to claim an
all-green matrix.

The independent reconstruction builds the private package and application
from the preserved focus baseline plus the recorded patch. Its checks and case
outputs match the primary build. Original md-edit source fingerprints remain
unchanged. No shared package file was edited.

## Cost comparison

The final run compares the complete previous focus prototype with the complete
new dispatch prototype. Both use optimized application/CUI builds, the same
compiler, a 1040 by 820 viewport, reduced motion, and zero pass delta on the
same Mac16,5 host. The shared harness uses identical documents and event batches.
Candidate and baseline execution order alternates by trial and dialog order.
No builds or other agent benchmarks overlap the final timing run.

There are four document sizes, seven trials, and 20 batches per trial.
Typing/navigation, Bold-click-to-text, and idle submissions run in normal
order. Apply, Remove, and Escape transitions run in both declaration orders.
Across both versions there are 504 trial records, 10,080 batches, and 33,600
input events. Every editing batch checks its expected document result.
Pass counts are identical between versions.

Values below are medians of seven trial means, in milliseconds of process CPU
per batch. They are not input-to-screen latency or isolated dispatcher cost.

| Markdown bytes | Batch | Passes | Previous focus prototype | New dispatch prototype |
| ---: | --- | ---: | ---: | ---: |
| 1,104 | Typing/navigation, six events | 6 | 0.619 | 0.625 |
| 8,832 | Typing/navigation, six events | 6 | 2.745 | 2.801 |
| 35,328 | Typing/navigation, six events | 6 | 8.126 | 8.242 |
| 61,824 | Typing/navigation, six events | 6 | 13.446 | 13.775 |
| 35,328 | Bold click then text | 4 | 5.378 | 5.517 |
| 61,824 | Bold click then text | 4 | 8.915 | 9.103 |
| 35,328 | Selection setup and idle UI | 1 | 0.158 | 0.158 |
| 61,824 | Selection setup and idle UI | 1 | 0.159 | 0.161 |
| 35,328 | Apply then text, editor first | 5 | 5.663 | 5.610 |
| 61,824 | Apply then text, editor first | 5 | 9.335 | 9.165 |
| 35,328 | Escape-down then text, editor first | 2 | 2.796 | 2.729 |
| 61,824 | Escape-down then text, editor first | 2 | 4.587 | 4.584 |

The displayed editing medians increased modestly; idle and transition results
are close and vary by workload. For the 35,328-byte typing batch, paired trial
differences range from -0.108 to +0.337 ms. For 61,824 bytes, they range from
-0.581 to +0.602 ms. These measurements do not support a universal speedup,
a zero-cost claim, or a precise attribution of the difference to the dispatcher.

The comparison includes resolver/command work, lifecycle notifications, prefix
checks, and private command counters, as well as full UI layout and draw-data
generation. The typing/Bold harness includes selection setup and input capture;
transition setup and dialog opening occur outside its timed interval. Both
exclude fixture/font creation, rasterization, native presentation, and OS input
collection. Raw wall times, each trial, and both dialog orders are retained.

The earlier full comparison before the inactive fix is retained separately and
excluded from the final table. The final build was remeasured after that fix.

## Contract recommendation before shared changes

The prototype supports adopting the component-first contract, with these
explicit boundaries:

1. CUI owns focus and physical input bookkeeping. The component owns bindings,
   commands, and typed host requests. The host owns scope fallback and queueing.
2. Handled input stops actions, not state maintenance. A command that makes no
   change can still be handled. An unhandled input reaches permitted fallback.
3. CUI defaults run after refusal in the opt-in path. Tab cannot depend solely
   on an earlier frame-start phase. Built-in Tab ownership must be retained.
4. Physical held state and default-action state are distinct. Consumed and
   inactive downs remain blocked from default held actions until release.
5. Ownership notifications must occur at every completed submission, even with
   no input. Repeats after transfer do not create initial-press ownership for
   release bindings.
6. Typing transforms run within document commands and transactions. They are
   not CUI key events. Paste and committed typing can have different rules.
7. The measured conditional reconciliation remains application-owned. This
   dispatch contract adds no extra per-event UI pass.

The patch is a private experiment, not a ready generic API. Exported names,
physical-versus-actionable query naming, and the participating-target restriction
from the prior focus proposal still need a shared API decision. No shared change
is made by this report.

## Limits

The suggestion case tests editor-owned suggestion state and Escape ordering;
it is not a complete suggestions interface. Built-ins retain their existing
path; universal post-widget bubbling is not implemented. Raw printable-key
consumption does not suppress separately delivered committed text. IME
composition, hardware input-to-visible latency, browser execution of this new
patch, nested overlay combinations, and same-frame focus visuals remain outside
the demonstrated result. Focused compatibility probes are not whole-library
proof, including all existing disabled/overlay hold-button paths.

## Retained artifacts

Paths are relative to this worktree:

- `.context/md-dispatch/run.sh`: actual md-edit with conditional reconciliation.
- `.context/md-dispatch/dispatch.patch`: private delta against `.context/md-focus`.
- `.context/md-dispatch/dispatch-probe.x`: executable command, fallback,
  lifecycle, and default-action cases.
- `.context/md-dispatch/dispatch-results.csv`, `focus-results.txt`, `check.log`,
  and `native.log`: final verification outputs.
- `.context/md-dispatch/cases.csv`, `cases-reversed.csv`: full transition matrix.
- `.context/md-dispatch/dispatch-before-inactive-fix.csv`: retained reproduction.
- `.context/md-dispatch/compare-probe.x`, `baseline-comparison`, and
  `candidate-comparison`: common scenarios and separately built comparison apps.
- `.context/md-dispatch/run-comparison.py`, `comparison-raw.json`, and
  `comparison-progress.log`: final alternating comparison and full measurements.
- `.context/md-dispatch/summarize.py`, `results.json`: count, correctness-control,
  pass-count, trial-structure, and measurement validation.
- `.context/md-dispatch/reproduce.py NEW_DIRECTORY`: reconstruct the private
  prototype from the preserved focus baseline, verify source hashes, build,
  and run checks. Existing destinations are refused; nothing is installed.
- `.context/md-dispatch/reproduced`: successful independent reconstruction.

## Plan review

CUI establishes focus, layers, and physical state. MdEditor consumes that
ownership rather than maintaining an independent focus authority. The host's
current source/disabled/read-only options are new information before submission,
not redundant focus validators. Document transactions remain the owner of
history and revisions.

The dispatcher reuses key-state updates and traversal. Its per-key action mask
is needed because default held behavior otherwise bypasses consumption. The
host's completion callback is needed because ownership can change without an
input event. The resolver reuses document/editor commands and removes the
unconditional unknown-key consumption. No callback registry, generic command
bus, new queue, configuration language, or recurring gate was added.

Focused negative probes protect specific behavior: no stale release commands,
no background shortcuts through a modal, no duplicate traversal, no invalid
Undo state, and no default held action from consumed or inactive input. The
no-extra control intentionally preserves its failures. No new diagnostic or
validator framework is proposed. All implementation and evidence remain private.
