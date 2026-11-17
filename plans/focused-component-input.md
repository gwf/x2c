# Focused-component input handling

> Status: isolated implementation and measurements complete, 2026-11-16.
> See [prototype results](md-edit-dispatch-prototype.md). Shared CUI and x2cui
> implementation remains held for review. This contract reframes the earlier
> text-canvas proposal around components that own their keyboard behavior.

## Goal and division of responsibility

A focused component interprets keyboard input using its own key map and state.
It can edit a document, execute a programmatic operation, emit a host request,
or intentionally do nothing. CUI determines input ownership; it does not define
that component's command vocabulary.

For md-edit, formatting, Markdown transformations, selection, navigation,
suggestions, and list behavior belong to the editor. Opening a host dialog or
saving a file belongs to the host. A different focused component can assign
completely different meanings to the same inputs.

| Owner | Responsibility |
| --- | --- |
| Platform and CUI | Deliver ordered input, maintain physical key/modifier state, establish focus and overlay eligibility, provide default focus navigation |
| Focused component | Resolve bindings against its current state, execute its commands, return handled or unhandled |
| Enclosing host scope | Handle declined input and component requests, respecting modal boundaries |
| Application | Handle permitted application shortcuts when the active scope declines them |

The new participation capability is **component-owned keyboard handling**, not
text entry. A component can request committed text, use keys alone, or use both.
Button-style Enter/Space activation is suppressed for a component that owns its
keyboard handling. Ordinary focusable button canvases retain their behavior.
Text composition, caret placement, and accessibility remain separate capabilities.

## Input, commands, and notifications are different things

- An **input event** is a key down/up, modifier change, committed-text payload,
  or lifecycle notification. It is not yet an editing command.
- A **command** is an operation chosen by the component, such as ToggleBold,
  InsertText, Indent, or MoveSelection. It can contain ordinary typed arguments.
- A **host request** is a component-defined operation the enclosing application
  performs, such as OpenLinkEditor. It is not an unhandled input event.
- A **change notification** reports a result, such as selection or document
  changes. It does not cause the original input to be dispatched again.

CUI carries input and ownership. It does not acquire a shared command enum,
command registry, event bus, or knowledge of Markdown.

## Dispatch contract

For each queued keyboard or committed-text event:

An inactive window processes physical-state and lifecycle changes only. It does
not dispatch ordinary component, enclosing-scope, or application commands.

1. Use the last completed UI submission to establish the eligible focused
   component and active overlay scope. Apply current host eligibility decisions
   that have not yet been submitted, such as hiding or disabling the editor.
2. Maintain physical key/modifier state independently of action consumption.
   A handled release must still clear held state. Do not set legacy pressed-key
   actions or append text to CUI's default input buffer before routing decides.
3. Offer the event once to the eligible participating component. Its handler
   resolves a binding and executes the resulting command synchronously, or
   delivers a typed request to its host. No UI construction or recursive input
   dispatch occurs inside this handler.
4. If unhandled, offer it to the active enclosing scope, then permitted
   application commands. An open modal confines fallback; it does not expose
   background editors or unrelated application shortcuts. The host explicitly
   decides which application commands remain available inside a modal.
5. If still unhandled, apply CUI defaults once. In particular, unhandled Tab or
   Shift+Tab moves focus within the active scope. Other unhandled inputs can be
   offered to the existing widget input path. Unclaimed input can simply end.
6. Complete the event's UI submission and any required reconciliation before
   choosing the recipient of the next event. Never redispatch the same event
   to a newly focused component.

**Handled** means stop action dispatch. It includes a successful command,
a host request, and an intentionally blocked operation. It does not mean the
document necessarily changed. **Unhandled** means the component declines the
input and permits fallback; it must not already have performed an input action.
Unknown keys must not be swallowed by an unconditional final `return true`.

Routing follows the active focus scope, not a broadcast through every editor.
The enclosing scope chain is explicit host composition. This proposal does not
add DOM-style traversal or a CUI callback registry.

### Focus lifecycle

Retain the measured completed-submission focus boundary from
[the focus prototype](md-edit-focus-prototype.md). Generalize its participating
owner from a text canvas to an input-handling component.

Only one component owns keyboard input. Custom focus requests resolve against a
completed submission; the last request wins and expires there. Missing or
disabled targets do not acquire focus. Removal revocation remains scoped to
participating owners, preserving built-in forward-focus behavior.

Before delivering ordinary input under changed ownership, the host notifies the
old component that input ownership ended and the new component that it began.
These notifications do not bubble as shortcuts. On loss, a component cancels
held-key actions, incomplete chords, and transient keyboard modes that depend
on ownership. Selection and document state can remain. A release observed by a
new owner without a corresponding owned press must not execute a release-bound
command. Window deactivation cancels local keyboard state as well.

Callbacks and retained event data remain host-owned. Handlers borrow the event
and text for that call; a retained host request must own its payload. The host
cancels a component's input state before destroying it. No CUI-stored pointer to
the editor is needed for this contract.

## md-edit key map and command dispatch

Use a component-local resolver and ordinary x2c command functions. Separate
matching from execution so a toolbar, a key binding, or a host call can invoke
the same operation. Do not make programmatic operations simulate key presses.

Bindings match the key, required modifiers, press/release phase, and editor
context. Matching is exact for meaningful modifiers; Shift variants are
explicit. Primary means Command on macOS and Control where appropriate.
Repeated downs remain ordered input. Each binding chooses whether repeats
invoke its command: navigation/deletion repeat; toggles and dialog requests
normally act only on the initial down. The dispatcher must make repeated-down
status available from the key state before updating it, rather than collapsing
repeats into one pressed bit. The current event record has no repeat field; the
proposed dispatch callback receives that derived status as call metadata.

A caller-supplied resolver runs before the editor's defaults. It can choose a
command, explicitly consume without an action, explicitly decline to the host,
or report no match so the default map runs. These are local resolver choices;
the outward input result remains only handled or unhandled. A simple static
binding table and context-aware functions are sufficient. No configuration
language or persistent binding framework is proposed.

| Input and context | md-edit action | Outward result |
| --- | --- | --- |
| Primary+B | Execute ToggleBold through the same operation as the toolbar | Handled |
| Primary+K | Emit OpenLinkEditor with the editor and selected range | Handled; host opens dialog |
| Primary+S, no editor override | No editor command | Unhandled; application may Save |
| Committed space after a leading `*` in a paragraph | Insert text and convert the prefix to a bullet item | Handled |
| Enter in a list | Continue the item, or leave an empty list | Handled |
| Tab / Shift+Tab in a list | Indent / Outdent | Handled |
| Tab in a code block | Insert configured indentation | Handled |
| Tab in an ordinary paragraph | No local binding | Unhandled; CUI focus traversal |
| Escape with an editor-owned suggestion open | Dismiss the suggestion | Handled; enclosing dialog stays open |
| Escape with a selection and no suggestion | Collapse selection, preserving current editor behavior | Handled |
| Escape with no local action | No editor command | Unhandled; enclosing scope may close |
| Editing command in a read-only editor | Deliberately block mutation | Handled; no unrelated application action |
| Copy or selection movement in read-only mode | Execute allowed command | Handled |

Suggestions are a proposed example, not an implemented md-edit feature. If a
suggestion popup takes separate keyboard focus, its own handler gets first
refusal. If it leaves focus in the editor, the editor's resolver handles it.
Either form precedes the enclosing dialog's Escape action.

OpenLinkEditor is a deliberate semantic request, not fallback. The component
consumes Primary+K even if the host declines to open a dialog. A synchronous
request can identify the editor and its current selection. A delayed request
must copy its needed data and define how document changes affect that selection.
The initial md-edit example uses synchronous host delivery.

### Committed text and Markdown rules

Printable text enters through committed-text events. Do not reconstruct it from
physical key codes. After accepting text, md-edit can recognize a prefix,
transform the block, update selection, or invoke another component-defined
operation. The transformation belongs to the same editing command and undo
transaction; it is not another synthetic key event.

The copied source contains `MdDocument.prefix`, which recognizes bullet,
quotation, ordered-list, and heading prefixes. Source inspection found no
caller of that helper in the inspected app. Reuse its logic through the actual
InsertText command; do not claim automatic prefix conversion is already wired.
Preserve the document owner's transaction and revision rules when connecting it.

Typing and Paste are separate commands even though both insert text. Proposed
md-edit default: apply interactive prefix rules to committed typing, and insert
paste contents without those typing rules. Multi-codepoint commits remain
text; the component applies its rule to the resulting paragraph, not to an
assumed one-character event. Control chords such as Primary+A are key bindings,
not ASCII control bytes injected into text.

A command-oriented component can bind committed text to operations instead of
inserting it. For example, a navigation mode can interpret committed `j` as
MoveDown. This supports programmable character behavior without guessing the
keyboard layout.

**Key handling does not imply cancellation of later text.** Existing Cocoa and
web paths can emit key and text separately, and the captured events have no
association ID. Consuming a physical Space event cannot promise to suppress a
later committed space, especially if focus changes between them. Prefer a text
binding when the action is character-based. Arbitrary physical printable-key
remapping with guaranteed suppression requires a separate native/web adapter
contract; it is not silently included in this proposal. IME pre-edit and
composition cancellation are also not modeled as committed text.

## Concrete shared CUI changes proposed

The focus prototype is necessary groundwork, not a complete dispatcher.
The proposed shared additions are:

1. Opt-in component input participation and completed-state focus eligibility,
   with custom request/removal semantics described above. Keyboard ownership
   must not require an editable text buffer or a text-editor widget.
2. Optional ordered capture, retaining borrowed-event lifetime and host-owned
   queueing. Capturing an event is separate from consuming its eventual action.
3. An opt-in synchronous keyboard dispatch operation at the pre-submission
   boundary. It updates physical state, calls a host-supplied route function,
   then applies unhandled CUI defaults. The route function invokes the focused
   component and permitted host fallback. The function pointer is borrowed for
   this call, not registered in a second component tree.

The third operation is new relative to the prototype. It should reuse the
existing key-state update and focus-traversal code, separating bookkeeping from
pressed-key/text actions. For opt-in dispatch, Tab traversal runs after refusal,
not exclusively at frame start. Clear its default action after applying it so
it cannot run twice. Applications using the existing input path keep their
current scheduling and behavior. This proposal adds no CUI event queue or
unconditional replay pass.

Exact exported names and signatures remain provisional. The semantic boundary
above is the proposed decision: one dispatch call around host interpretation,
not independently callable begin/finish event transactions.

### Built-in compatibility and current gaps

The existing built-in controls do not report general unhandled input to a host.
This contract initially covers participating components and their explicit host
fallback. A built-in owner keeps its current CUI path. Do not claim universal
component-first bubbling for all existing widgets; adapting them would be a
separate extension. Existing explicitly reserved application shortcuts remain
host policy, not an implicit new priority layer.

The prototype's current route-before-draw loop does not satisfy every rule:

- CUI processes Tab at `begin_frame`; replaying an unhandled Tab afterward can
  lose traversal when `end_frame` clears pressed keys.
- The capture hook returns before key state updates. Consuming an up after a
  forwarded down can leave held state stale without separated bookkeeping.
- MdApp currently checks dialog Escape and Find before editor routing.
- MdEditor consumes all key releases and unmatched keys, which prevents real
  fallback. These must become deliberate mapping decisions.
- Same-frame visual focus, nested overlay combinations, physical-key/text
  cancellation, and composition have not been established by the focus tests.

These are source findings, not newly executed failure probes. The previous
native checks and timing results remain valid for their tested sequences only.

## Proposed implementation and acceptance scope, after review

First extend the isolated prototype to the proposed dispatch operation and
md-edit resolver. Reuse current document commands and toolbar actions. Replace
the duplicated keyboard branches with calls to those operations; remove the
unconditional unmatched-key consumption and host-first local Escape handling.
Keep the original source and shared package untouched during this comparison.

Focused acceptance cases must establish:

- A custom binding invokes a local command or typed host request exactly once.
  A toolbar invokes the same command without synthetic input.
- An override can replace, block, or decline a default binding. A read-only editing command
  remains consumed while an unknown shortcut reaches the permitted host.
- `*` then committed space becomes a bullet item with correct selection and
  undo; paste follows its separate rule. Test multi-codepoint and Unicode text.
- Tab/Shift+Tab indent a list but traverse from a paragraph. Traversal occurs
  once after refusal, remains in the modal, and works in a queued batch.
- Suggestion Escape precedes dialog Escape. A second Escape can fall through.
- Repeated movement acts repeatedly; a toggle/request does not repeat unless
  its binding requests that behavior. Key-up clears state regardless of handling.
- Focus loss cancels old-owner keyboard state. The next component's map applies,
  and a later release does not execute a stale command in either component.
- Existing Apply/Remove/Escape/cold-open transitions, both submission orders,
  popup exclusion, read-only behavior, and built-in forward focus still pass.
- Repeat the comparable replay measurements after the routing change. Do not
  extrapolate the prior timing results to this unimplemented dispatch path.

These are task-specific acceptance checks, not additions to recurring gates.
No shared implementation or publication is part of this proposal revision.

## Plan review

CUI already owns focus, component layers, and physical input state. The host
must consume that authority rather than reconstructing it from editor booleans.
Current host visibility/options are genuinely new information before submission;
checking them at routing is not a duplicate focus validator. The document owns
editing transactions and revisions; command dispatch calls those operations.

Reuse the existing input event representation, focus bookkeeping, key-state
updates, focus traversal, editor commands, and prefix-recognition logic. The
new dispatch operation is needed to separate state maintenance from action
consumption and put Tab defaults after refusal. The component resolver makes
customization explicit without moving Markdown commands into CUI. Lifecycle
notifications cancel component-local keyboard state; they add no focus registry.

Ordinary x2c functions and small local command values are sufficient. No generic
command bus, configuration language, bubbling tree, queue, global dirty protocol,
or new recurring validation step is proposed. No dedicated validators or new
diagnostics are proposed. The negative acceptance cases protect specific public
behaviors: no blocked-command fallthrough, no stuck keys, no duplicate traversal,
no background modal input, and no stale release actions after focus changes.
