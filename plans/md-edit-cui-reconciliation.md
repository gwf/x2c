# md-edit against experimental CUI

> Status: investigation and private integration complete, 2026-11-16.
> Proposed shared input/focus changes await Gary's decision. No shared CUI
> input contract or production package source was changed by this experiment.

## Result and scope

The actual md-edit application runs against experimental x2cui at
`eb6b01614d5d653f2a4e2a5d4ecbbf0c1d6bd879`, whose CUI pin is
`a5c9ef5efc39b3fc783758362f6b8f9f130f5883`.

The experiment copies `/Users/gary/Git/x2c-ux/md-edit` into
`.context/md-edit/app`. It uses this worktree's built compiler/runtime and
an isolated copy of this branch's x2cui package. Gary explicitly authorized
this experimental dependency instead of the source application's usual
installed-only build. The original application source and installed package
are not edited. Original source fingerprints were checked after the work.

Two private CUI additions remain: ordered input capture and slanted text
drawing. The existing input-hook patch was adapted around upstream's new
pending-click handling, preserving that handling. The old private clipboard
functions were removed; the editor calls the public clipboard functions.
The existing built-in scroll container remains responsible for wheel input.
Adding a canvas wheel region would intercept that container's input without
solving a demonstrated requirement.

The private input scheduler has a probe-only policy selector:

- 0: current behavior, one input pass per event plus a pass after mouse release;
- 1: one input pass per event, no extra pass;
- 2: one input pass and one extra pass for every event, as a cost control.

The default remains policy 0. This selector is not in the shared package.
The demo host's only additional instrumentation records target rectangles.
No eligibility or focus repair was made to hide the observed failures.

## Executable evidence

The application passes 4,261 model checks and 73 existing component checks.
These pass under policies 0 and 1. A hidden native Cocoa window also passes
ordered text/key delivery, navigation, scrolling, screenshot, and save
success/failure checks under both policies. The native check calls responder
methods; it does not validate physical hardware input, OS clipboard contents,
or IME composition. The off-screen sample was visually inspected.

A new harness uses the actual MdApp, MdEditor, document, and MdInput units.
All events in each case are queued before dispatch. Buttons use measured
rectangles and actual mouse move/down/up events. A separate sacrificial
fixture measures the Apply rectangle for the cold-open case; the tested
fixture has never opened its dialog. Assertions inspect document text,
selection, marks or link state, and focus as appropriate. They do not merely
check that a handler ran.

Ten cases pass under all three policies:

1. A, Left, B in one batch produces BA.
2. Text and modifier-only changes around Bold preserve mark order.
3. Bold click then text replaces the selection with bold text.
4. Text then Bold preserves the resulting text, caret, and focus.
5. URL text, Apply, then document text routes to the correct fields.
6. Remove link then text clears the link and restores document input.
7. Escape then text closes the dialog and restores document input.
8. Cold Link open, URL text, Apply, then document text works in one batch.
9. The actual source-view toggle click followed by text does not edit the
   hidden document; its pointer path clears the editor's private focus.
10. Repeated key-down events move the caret twice before insertion.

Four desired eligibility cases fail under all three policies:

| Transition | Observed result |
| --- | --- |
| Host switches to source view, completes a draw, then receives text | Hidden editor retains private focus and changes `abcd` to `aXd` |
| Host sets disabled immediately before queued text | Text changes to `aXd` before draw updates the editor's disabled flag |
| Host sets read-only immediately before queued text | Text changes to `aXd` before draw updates the editor's read-only flag |
| Window blur followed by queued text | Editor retains private focus and changes text to `aXd` |

The transition cases deliberately change host state before routing, unlike
existing settled-disabled tests. They establish a missing eligibility boundary;
CUI cannot discover a host option that has not been submitted to it.
The blur case injects the ordered focus/text sequence, not a claim that the OS
normally sends text to an inactive window.

Thus the 42-case matrix has 30 passes and 12 reproduced failures, not an
all-green result. The failure rows are retained and independently checked.

A separate two-editor host demonstrates:

- Selecting the first editor, then the second, leaves both private focus flags
  true. Text goes to the first editor because it is routed first.
- Clicking the second editor gives it exclusive input as expected.
- With a real CUI popover and autofocus input open, the custom editor consumes
  `Z` and the popover field remains empty. The custom dispatch bypasses CUI's
  built-in keyboard ownership rules.

These are actual editor probes, not built-in-code-editor stand-ins. They
support unifying focus ownership, rather than adding more unconditional draw
passes to compensate for independent focus flags.

## Replay cost

Host: Mac16,5, 16 physical cores, macOS 15.7.9, arm64. Probe application and
private CUI compile with `-O2`; the x2cui package uses its normal recipe.
Viewport is 1040 by 820 logical points at scale 1. Reduced motion is enabled;
pass delta is zero. The full demo toolbar, editor, and status bar are drawn.
Documents contain repeated paragraphs with bold, italic, code, and links.

Seven trials per size/scenario/policy; 20 batches per trial. Policy order
rotates by trial. There are 252 trial records, 5,040 batches, and 16,800 input
events. Each row below is the median of seven trial means in milliseconds of
process CPU per batch. Wall time is retained in the raw data and is close to
CPU time. The final controlled run did not overlap our builds.

Timing includes selection setup, input capture, queue draining, actual editor
commands, full UI construction, layout, draw-data generation, and the small
per-batch correctness check. It excludes fixture creation, initial font load,
software rasterization, native presentation, and OS event collection. Every
batch verifies text length and the expected edit/mark result.

| Markdown bytes | Visible-text bytes | Bold click + text, current 5 passes | No extra, 4 passes | Extra after every event, 8 passes |
| ---: | ---: | ---: | ---: | ---: |
| 1,104 | 839 | 0.484 | 0.417 | 0.674 |
| 8,832 | 6,719 | 1.996 | 1.829 | 2.461 |
| 35,328 | 26,879 | 5.905 | 5.593 | 6.445 |
| 61,824 | 47,039 | 9.647 | 9.527 | 10.178 |

The typing/navigation batch replaces one character with A, moves Left, inserts
B, then Backspaces. Key releases are distinct events: six events in total.
The policies with and without release reconciliation both use six passes.

| Markdown bytes | Current 6 passes | No extra, 6 passes | Extra after every event, 12 passes | One idle UI pass, no-extra policy |
| ---: | ---: | ---: | ---: | ---: |
| 1,104 | 0.631 | 0.625 | 1.008 | 0.065 |
| 8,832 | 2.765 | 2.755 | 3.688 | 0.157 |
| 35,328 | 8.381 | 8.339 | 9.433 | 0.165 |
| 61,824 | 14.209 | 14.212 | 15.170 | 0.163 |

Removing the release pass helps the tested toolbar batch. It does not affect
keyboard-only batches and does not account for most large-document editing
cost. The idle comparison suggests edit-dependent work deserves profiling
before changing shared scheduling; it does not identify the specific costly
function. These are batch costs, not FPS or end-to-end keystroke latency.

An initial 66,240-byte source fixture exceeded the model's admission limit and
loaded no document. That run is explicitly excluded, retained as
`replay-bench-invalid-capacity.csv`, and replaced with a valid 61,824-byte
fixture. The final harness rejects empty/refused benchmark documents.
A preliminary measurement overlapping a build is retained separately and is
not the table's source.

## Proposed CUI changes for review

### 1. Optional ordered input capture

Expose the existing private hook as an opt-in synchronous hook before legacy
aggregation, retaining the prototype's contract:

- event order includes repeated downs, key releases, and modifier-only changes;
- event/text storage is borrowed only during the callback; retain text by copy;
- returning true consumes the event; returning false preserves existing input;
- no UI construction, recursive injection, or hook mutation inside the callback;
- queue allocation, limits, error handling, lifetime, and replay stay with the app;
- unregister before replay through existing input calls, and before user cleanup;
- no behavior change for applications that do not install the hook.

The first version covers pointer, scroll, keyboard, committed text, and window
focus, as the existing private implementation does. File drops are outside its
scope. IME composition is not equivalent to committed text and is not added by
this proposal. No CUI-owned event queue or shared replay scheduler is proposed.

### 2. Unified custom-editor focus, first as an isolated prototype

Reuse CUI's existing interaction and focus bookkeeping. Provisional surface:

- a text-input flag on the custom/focusable canvas;
- interaction results for focused, keyboard-eligible, and visible-focus-ring;
- a programmatic focus request for a stable component ID;
- a query for whether that component currently owns keyboard input.

A text canvas must not synthesize button clicks from Space/Enter. One CUI focus
owner must serve built-in and custom controls. Popup exclusion and window
activation belong in the eligibility query, not in copied downstream rules.
Removal/disablement after submission must revoke keyboard eligibility without
a second custom-editor registry. Read-only controls may retain selection/copy.

**Request timing is not yet settled.** The current editor draws before dialogs.
Apply requests focus after the editor was submitted. If a new request applies
only on the next submission, the next event is routed before it takes effect.
A modal's current-pass registration can also survive after its application bool
was cleared during Apply. Therefore today's no-extra-pass success with private
focus does not prove that a CUI-owned-focus version can omit every reconciliation
pass. An isolated focus prototype must compare immediate eligibility for an
already-submitted target with pending requests and any narrowly required
host reconciliation. It must pass Apply/Remove/Escape/cold-open-to-text without
weakening popup ownership, and report the actual pass cost before this contract
is promoted. Do not impose a mandatory second pass based on inference alone.

The query can describe submitted component state plus live CUI window/layer
state. It cannot know an unsent host visibility/disabled/read-only change.
MdApp must gate routing against those current host decisions before forwarding
the event. This belongs in the host, not in a speculative global scheduler.

### 3. Italic drawing, separately from input

Expose styled/slanted text drawing through a public rendering operation so the
editor no longer alters CUI draw-list vertices through a private extension.
Keep this independent of input ordering and focus. The exact API should reuse
upstream's existing text renderer; this experiment retains the original private
slant function solely to run the real editor.

### No additional clipboard or wheel API

The new public clipboard functions suffice. The editor's current built-in
scroll container already passes native scrolling checks. Keep both paths.
Native IME composition, custom caret placement, accessibility, and grapheme
editing remain separate requirements; none is claimed solved here.

## Recommended next decision

Approve an isolated focus-participation prototype plus MdApp eligibility fixes,
using the private hook and the same exact CUI revision. Preserve selection as
editor state while replacing the private focus flag as input authority. Run the
real-editor matrix and measure any required focus/layer reconciliation. Return
the resolved focus timing and final small CUI patch for review before changing
the shared contract. Keep global queueing and replay scheduling out of that
patch.

This recommendation is deliberately narrower than adopting the current
MdInput scheduler in shared CUI. The evidence supports ordered capture and one
focus owner, but it neither proves a universal no-extra-pass schedule nor a
need for unconditional extra passes.

## Artifacts and reproduction

All paths below are relative to this worktree unless absolute:

- `.context/md-edit/run.sh`: starts the built actual application; accepts its
  existing `--check`, `--shot`, and `--window-check` options.
- `MD_REPLAY_POLICY=1 .context/md-edit/run.sh --check`: no-extra private control.
- `.context/md-edit/application.patch`: clipboard migration and probe-only policy
  and target-geometry instrumentation against the untouched external source.
- `.context/md-edit/private-cui.patch`: input hook and italic extension against
  this branch's two-patch CUI source.
- `.context/md-edit/replay-probe.x`, `focus-probe.x`: actual-editor probes.
- `.context/md-edit/app/builds/replay-cases.csv`, `focus-results.txt`: failures
  and successes, including exact text/focus states.
- `.context/md-edit/app/builds/replay-bench.csv`: final timing trials.
- `.context/md-edit/summarize.py`, `results.json`: independent count/pass and
  measurement validation.
- `.context/md-edit/rebuild.py --work /tmp/md-edit-reproduction`: reproduces the
  private package and app in a fresh directory, checking archive and source
  fingerprints. It refuses an existing destination. It does not install files.
- `.context/md-edit/reproduced/`: a completed independent rebuild, with identical
  case output, passing existing checks, and matching focus failure observations.
- `.context/md-edit/app/builds/editor.png`, `native-public-editor.png`: actual
  software/native-rendered application images.

The scratch artifacts are retained locally, not added to recurring gates.
Shared package files remain at the experimental integration revision above.
No app was deployed and no shared input/focus changes were published.

## Design review

Reuse: existing input entry points, interaction flags, focus owner/order/layers,
public clipboard, and scroll container. Avoid: a second event queue, custom
focus registry, generic invalidation framework, or mandatory per-event extra
pass. Remaining design risk: focus transfer and popup closure between queued
events. Remaining performance uncertainty: large-document edit work and native
input-to-visible latency. These are explicit prototype questions, not hidden
caller obligations or completed guarantees.
