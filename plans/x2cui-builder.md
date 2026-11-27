# x2cui builder: edit a live UI by direct manipulation

> Status: first version implemented 2026-11-24, after Gary approved the
> plan that day. It depends on
> [the x2cui Lisp surface](x2cui-lisp-surface.md). Gary set the layout
> direction on 2026-11-24: CUI's own layout is the default; free placement
> is included only where it is low cost. On 2026-11-25 Gary rejected
> placement by coordinates: a placed component cannot reflow, and spacing
> belongs to padding, gap, alignment, and sizes. "As built" below records
> what exists and what does not; the design sections are kept as
> proposed, and their `free` container is not to be built.

## As built

`packages/x2cui/examples/builder.x` is the application. The library
gained `View.watch`, `View.components`, messages (`send`, `on`,
`ui-send`, `ui-pass`), and `cards`.

- **Built:** selection by click in edit mode, with an outline; a palette
  that adds a component after the selection or inside a selected block;
  an inspector generated from the component table, with a text field,
  switch, or select for each argument and option; Parent, Up, Down,
  Delete, Undo, and Save; run mode; a tree file and an optional
  `FILE.lisp` beside it.
- **Dragging** (added 2026-11-24): a press that moves more than four
  points drags the selection. The drop goes to the innermost block under
  the pointer, before the first child whose middle the pointer has not
  passed along the block's direction, and a line shows where.
- **Drop targets** (repaired 2026-11-25, after Gary found dragging hard
  to aim in a window): edit mode outlines every block; a watched view
  draws a block with no children 72 by 32 points; within 6 points of a
  block's edge a drop goes beside the block; with nothing under the
  pointer it goes to the root. A running tree is not watched.
- **Free placement** was added and removed on 2026-11-25, with its CUI
  patch, the `free` block, and the `x` and `y` options. See the status
  note above.
- **Layout options first** (2026-11-25): the inspector shows `width`,
  `height`, `pad`, `gap`, `align`, and `justify` under "Layout", ahead of
  the view's own options and the rest of the record.
- **Resize handle** (added 2026-11-25): one square at the selection's
  corner sets `width` and `height` as fixed sizes, where the component
  has those options.
- **Outline, commands, and keys** (2026-11-26): slice 1 of
  [the redesign](x2cui-builder-redesign.md).
- **Generated inspector** (2026-11-26): slice 2 of the redesign. It
  replaces "Layout options first" and makes undo one step per field
  visit, with redo.
- **Grouped palette** (2026-11-27): slice 3 of the redesign: groups,
  search, a drag from the palette, and useful defaults.
- **Events and the run log** (2026-11-27): slice 4 of the redesign.
- **Not built:** handles on the other corners and edges.
- **Ids.** CUI gives a box an id only when its record names one, and gives
  text none. While a watcher is installed the view gives each block an id
  by its place in the frame and draws each id-less component in a box
  that has one. A card and a component with no arguments, such as a
  spacer, are not selectable by click; Parent reaches a card.
- **Rectangles.** `ui.get_rect` answers from the last frame's layout, and
  the builder reads it at the start of a frame, before submitting.
- **Messages** are an option form, `(on-click (send name ...))`, and the
  Lisp functions are named `ui-send` and `ui-pass`, not `send` and
  `pass`. `cards` takes `(show name)`; a handler changes cards by setting
  the global the option evaluates, so there is no `go`.
- **Undo** keeps whole trees, one per change, up to 200. Each key typed in
  the inspector is one change.
- **Checked:** `builder --check` selects, adds, runs, edits a label
  through the inspector, moves, deletes, undoes, saves, tells two equal
  nodes apart, drags a component into another block, before a sibling,
  into an empty block, and beside a block, resizes a component, and
  edits a block's width in the inspector, off screen.
  No test opens a window.

## Result

An x2cui application, the builder, opens a UI tree file, draws it live, and
lets a person change it with the pointer:

- select a component by clicking it;
- reorder it among its siblings, move it into another container, add a
  component from a palette, and delete it;
- edit its options in an inspector;
- attach handlers and name the messages it sends;
- switch between edit mode and run mode, where the UI behaves normally;
- save the tree as text that `View` in the Lisp surface plan loads.

The saved file is the application's UI. A program that loads it with
`View` needs no builder code.

## Layout: CUI's model first

The builder edits CUI's layout as it is: columns, rows, grids, and stacks,
with gap, padding, alignment, and fit, fill, fixed, and percent sizes. A
drag changes a component's position in the tree. A resize handle sets a
fixed width or height, and the inspector returns it to fit or fill. This
needs no change to CUI.

Free placement is one optional container, `free`. Its children carry `x`,
`y`, `width`, and `height` options and are placed at those points. Inside
it, a drag changes `x` and `y`, and a handle changes the size. Everything
outside a `free` container keeps CUI's layout.

A probe on 2026-11-24 established the cost. CUI has an internal function
`cui__absolute(ui, id, x, y, w, h)` that places a node at a point inside
its parent, outside the flow. The probe placed three buttons and a slider
with it. Positions were exact, clicks reached the right button, the later
of two overlapping buttons received the click, and a slider drag worked.
The probe source is not kept in the repository.

Shipping it needs one small patch in `packages/x2cui/patches/`, in the
style of `table-row-state.patch`, that declares a public begin and end
pair over the internal function. The estimate is about 20 lines. If the
patch proves larger, or a later CUI pin drops the internal function, the
`free` container is removed and the rest of the builder is unaffected.

Two probe findings shape the `free` container:

- A widget keeps its own height inside a taller placed node. The builder
  passes height through the widget's own option, not only through the node.
- `get_rect` returns the previous frame's layout. Handles inside `free` are
  drawn from the stored `x`, `y`, `width`, and `height`, not from
  `get_rect`.

The probe did not cover text fields and keyboard focus inside a placed
node, placed nodes nested in placed nodes, a scrolling `free` container, a
real window, or wasm. Each is checked when the container is implemented.

## Design

### The builder is a View around a View

The builder draws the edited tree with the same interpreter a finished
application uses. The interpreter gains one hook: a callback given each
node and its CUI id as the node is drawn. In edit mode the builder uses the
hook to record id, node, and parent for the frame. After the frame it reads
each rectangle with `cui_get_rect`. That record is the builder's only
knowledge of where things are.

### Edit mode input

`ui.set_input_hook` sees pointer and key events before CUI's widgets. In
edit mode the hook consumes events over the edited tree, so a click selects
a button and does not press it. The hook hit-tests against the recorded
rectangles, innermost node first. Events over the builder's own palette and
inspector pass through to CUI.

### Selection and handles

The edited tree sits in a CUI stack with a canvas above it. The canvas
draws the selection outline, resize handles, and the insertion line that
shows where a dragged component will land. Cursors come from
`cui_set_cursor`.

A drag over a row or column computes the insertion index from the sibling
rectangles along the container's axis. Dropping edits the tree; the next
frame shows the result.

### Inspector and palette

The inspector lists the selected node's options from the generated
component table: a number field for numbers, a toggle for bools, a select
for enums with the enum's member names, a text field for Strings. It uses
CUI's inspector and property rows. An option left at its default is absent
from the tree, so saved files stay short. CUI's defaults exist only as
header comments; the inspector shows an unset option as "default" and does
not display a default value.

The palette lists the component table's names. Dragging one into the tree
inserts a node with its required positional arguments filled with
placeholders.

### Containment and messages

This follows HyperCard's model with CUI's containers as the hierarchy.

- A handler option on a node, such as `(on-click ...)`, holds either a Lisp
  callable or a message: `(send name argument ...)`.
- A node handles a message when its options include `(on name callable)`.
- A sent message goes to the sending node first, then to each enclosing
  container in turn, then to the view. The first node with a matching
  `on` option handles it. A handler passes the message further up by
  calling `(pass)`.
- Messages are queued and delivered after the frame, in order, on the UI
  thread. A handler that sends a message appends it to the queue. The
  sender never waits for a reply. This is the asynchronous part; it needs
  no threads.
- A `card` node shows one of several child trees, and `(go name)` changes
  which. A tree with cards is a stack.

The message queue belongs to `View`, not to the builder, because a
finished application needs it at run time. It extends the handler list in
the Lisp surface plan; it does not add a second delivery path.

CUI's built-in widgets do not take part in this chain. A message starts
only from a handler option on a node.

### Files

A saved UI is one text file holding the tree and, optionally, a Lisp
prelude that defines handlers. `Buffer.write_datum` and the Lisp reader
already write and read this text. The builder keeps an undo list of whole
trees; trees are small and Lists share structure.

## Scope

| Piece | Estimate |
| --- | --- |
| Draw hook and per-frame node record | 150-250 lines |
| Edit-mode input, selection, handles, reorder and reparent | 400-700 lines |
| Inspector and palette from the component table | 200-300 lines |
| Message queue, `send`, `on`, `pass`, cards | 300-500 lines |
| Save, load, undo | about 150 lines |
| `free` container and its CUI patch | about 20 lines of patch, 100-150 in the builder |

The estimates are not measurements. The builder lives in
`packages/x2cui/examples/builder/` as an application, not in the package
library. Only the draw hook, the message queue, and the `free` container
are added to the library.

Out of scope for the first version: snapping guides, multiple selection,
copy and paste between files, a visual wire-drawing view of messages,
theming, and a browser build of the builder.

## Validation

- An off-screen test loads a tree, enters edit mode, injects a click on a
  button, and checks that the node is selected and the button's handler did
  not run.
- An off-screen test drags a node past a sibling and checks the saved tree.
- An off-screen test sends a message from a nested node and checks which
  ancestor handled it, with and without `(pass)`.
- A round trip: load, save, and compare the text.
- For `free`: the probe's checks as a test, plus a text field that takes
  focus and typed text inside a placed node.

## Plan review

- **Established facts.** CUI establishes every rectangle; the builder reads
  them with `cui_get_rect` and never computes layout. The component table
  establishes option names, types, and enum members; the inspector does not
  keep a second list. The interpreter establishes which node maps to which
  CUI id through the draw hook.
- **Reuse and new mechanisms.** Reused: the interpreter, the component
  table, the input hook, canvas drawing, CUI's inspector rows, the datum
  writer. New: the draw hook, because CUI cannot enumerate its nodes; the
  message queue, because x2cui reports events only as return values; and
  the `free` container, which is optional and removable.
- **Idiom.** The edited document is a List. Edits are List operations.
  There is no document object model, no observer graph, and no second
  layout engine.
- **Validators and diagnostics.** None beyond the Lisp surface plan's
  unknown-name Error. A message with no handler is dropped silently, as in
  HyperCard; that is deliberate behavior, not a missing check.
