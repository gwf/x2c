# x2cui builder redesign: tasks, not records

> Status: Gary approved slice 1 on 2026-11-26 and it is implemented; see
> "Slice 1 as built". He then asked for slice 2 and for slice 1's
> faults to be fixed, both as seen fit; see "Slice 2 as built". On
> 2026-11-27 he asked for slice 3, then slice 4; see "Slice 3 as built"
> and "Slice 4 as built". Slice 5 is not started. The plan replaces
> the interaction design of [the x2cui builder](x2cui-builder.md), whose
> first version Gary judged far from usable on 2026-11-25: too many
> options shown, and no clear way to get a wanted effect. The document
> model, `View`, messages, and CUI's layout stay. Placement by
> coordinates stays rejected.

## What went wrong

The first builder shows the toolkit's records. A selected row gets about
40 editors in the record's declaration order, most of them free-text
fields. A person building a UI has tasks instead: put these side by
side, space them, make this one stretch, make this press do something.
The audit of `examples/builder.x` found these concrete causes:

- No outline of the tree. A block is visible only as a faint border, and
  a click always selects the innermost component, so a row is reached by
  clicking its padding or pressing Parent.
- Gap and padding belong to the block, but a click selects the child.
- No way to wrap components in a row or column, duplicate, or copy.
- Numbers, sizes, and colors are typed as text. Each key is an undo step,
  and a half-typed size raises.
- The palette is a flat list of 31 names. A new component starts with its
  own name as its label and no spacing.
- A handler is added only by typing a Lisp form into `on_click`.

## The six tasks and their controls

The builder makes six tasks direct. Everything else is behind "All
options". Each control below is copied from a tool that is known to work;
the sources are in "Evidence".

| Task | Control |
| --- | --- |
| Add | A palette in five groups (Layout, Text, Input, Display, Container) with a search field. A click adds after the selection or into a selected block. A drag from the palette shows the insertion line. A new component has visible content and a new block has gap 8. |
| Arrange | An outline of the tree beside the canvas; selecting in either selects in both. Drag in either, with the insertion line. One command each for wrap in row, wrap in column, unwrap, duplicate, delete. Keys for parent, first child, next and previous sibling, and move among siblings. |
| Space | For a selected block: direction as a segmented control, gap and padding as numbers that are dragged or typed, alignment as a 3 by 3 grid, and "space between". When a child is selected the inspector also shows its block's spacing under "In row" or "In column", so spacing is found from either end. |
| Size | Width and height each as Fit, Fill, or Fixed, with a number for Fixed. The corner handle sets Fixed and the control shows it. |
| Style | The few options that matter for the component, such as a button's variant and size, with editors by type. |
| Wire | An Events group with one row per event the component reports. A row holds "send message NAME" or "call PROCEDURE". Run mode lists each event fired, the node that handled it, and the result. A one-line message box evaluates Lisp in the session. |

Canvas handles for gap and padding come after the inspector controls
work. Figma's users report changing padding by accident when resizing, so
the handles appear only on a selected block and away from the corner.

## Design

### Three panes

Left: the palette above the outline. Centre: the canvas. Right: the
inspector. The toolbar keeps Run and Edit, undo, redo, and save.

The outline is drawn with CUI's tree (`cui_tree_begin`,
`cui_tree_clicked`). It lists every node, including a spacer, a
separator, and a block hidden behind its children, which the canvas
cannot select by click. A context menu (`cui_context_menu_begin`) on the
canvas and the outline holds the Arrange commands, and `cui_shortcut`
gives them keys.

### An inspector built from a description of options

The inspector is generated; no component has inspector code. It uses
CUI's inspector rows: `cui_inspector_group`, `cui_prop_float_ex` (drag to
change, with minimum, step, and suffix), `cui_prop_enum_ex`,
`cui_prop_bool_ex`, and `cui_prop_color_ex`.

`View.components()` already gives each option's name, kind, and enum
members. It gives no grouping. The builder adds one table keyed by option
name, not by component: `gap` is in Layout, common, step 1, minimum 0,
with one line of help. Records share option names, so about 40 rows cover
the 31 components. An option with no row falls under "All options" with
the editor its kind gives. A component added to `View` later therefore
appears in the builder with typed editors and no builder change.

The default view shows the arguments, the common options, and any option
the node has set. A set option has a reset control, and an unset one
shows as unset, so the saved tree holds only what was changed. "All
options" and a search field reach the rest.

### Wiring

The Events group reads the events from the component table: a component
whose call reports a result has `on-click` or `on-change`. A block also
lists the messages it handles, its `(on name form)` options, which the
first inspector did not show. Choosing "send message" asks only for a
name; the message goes up the blocks as it does today. Choosing "call"
offers the procedures the session defines. Naming one that does not exist
adds a stub to the tree's `FILE.lisp`, which Save then writes.

### What changes in `View`

- A percent size, which CUI has (`CUI_PCT`) and a tree cannot write.
- The `gap` component, CUI's fixed space, beside `spacer`.
- An id for every watched node, so a spacer or separator has a rectangle.
- Built in slice 4: `reports` in each component row, and `View.trace`.
- The record's `id` is not listed as an option beside the view's own.

### What changes in the builder

`examples/builder.x` is rewritten around the six tasks and split into a
directory, as the first plan intended. Tree editing, undo, the id scope,
drag aiming, and the off-screen check are kept. Typing in a field becomes
one undo step per field visit, and redo is added.

## Slices

Each slice is usable alone and is shown to Gary in a window before the
next starts.

1. Outline, hierarchy keys, context menu, wrap, unwrap, duplicate.
2. The generated inspector: Layout and Size controls, the option table,
   common and all, "In row", undo by field.
3. Palette groups, search, drag from the palette, useful defaults.
4. Events group, stubs in `FILE.lisp`, the run log, the message box.
5. Canvas handles for gap and padding.

## Slice 1 as built

`examples/builder.x` gained the outline under the palette, the commands
in the table `keys`, and one menu shown on a right click over the tree
or a line of the outline. `builder --check` covers each of them off
screen. It differs from the design in four ways:

- The outline is drawn with CUI's list rows, not `cui_tree_begin`. A
  click anywhere on a tree row opens or closes it, which would fight a
  click that selects. The outline therefore does not collapse.
- Nothing is dragged in the outline.
- The palette shows two names to a line, so that it fits above the
  outline. Its groups and search are slice 3.
- The builder is still one file.

One fault was found: after a click on a line of the outline, CUI's
keyboard focus stayed on that line, and its focus ring did not follow a
selection changed by a key. Slice 2 repairs it: the input hook keeps a
left press on a line, so the line never takes focus.

## Slice 2 as built

The inspector is drawn from `View.components()` and the table `shown`
in `examples/builder.x`, which gives about 30 option names a group,
whether they are common, a step, and a line of help. Options group as
Content, Layout, Size, Style, Behavior, and Other. Rows use CUI's
inspector: `cui_prop_float_ex` for numbers, `cui_prop_enum_ex`,
`cui_prop_bool_ex`, `cui_prop_color_ex`, and `cui_prop_text_ex`. A value
that is a Lisp form is edited as text. A set option has a reset button.
A block's Layout group, and the "In row" or "In column" group of a
child, hold direction, gap, padding, and the alignment grid with "Space
between" and "Stretch". `builder --check` covers each of them off
screen, with typing a gap as one undo step, and undo and redo.

It differs from the design in these ways:

- Size has a fourth choice, Auto, which leaves the option unset. CUI's
  default is not Fit for every component: a column stretches its
  children.
- Percent sizes are not offered; `View` cannot read one yet.
- The inspector is 400 points wide, because CUI stacks a row's label
  over its editor below 380. The window opens at 1280 by 760, and the
  canvas scrolls rather than pushing the inspector out of the window.
- A record that lists `id` shows it once; `View` still lists it as an
  option of the record.
- The builder is still one file, now about 1,700 lines.

Three faults found in the check's pictures were repaired after
gwf/x2c#757. The alignment grid and the Stretch switch now show CUI's
defaults for an unset option: centred across a row, stretched across a
column. A stretch lights a whole line of the grid, and so does space
between. Number rows are unbounded, so CUI draws no range bar under
them. The toolbar shows the file's name, not its path, which had
squeezed the buttons' labels.

## Slice 3 as built

The palette lists the components under Layout, Text, Input, Display, and
Container, from the table `offers` in `examples/builder.x`; a component
the table does not name is listed under Other. A search field above it
keeps the names that contain its text, and Return adds the first. A
press on a name that moves more than four points carries a new
component: the canvas shows the block aimed at and the insertion line,
as for a moved component, and the release puts it there. The same table
gives a new component its text, such as "Button" or "Heading". A new
range runs to 100, a new progress bar is half full, a new spinner is 20
points, and a new block has gap 8. `builder --check` drags a row from
the palette before a button, and finds and adds a slider by search.

It differs from the design in these ways:

- The palette takes three fifths of the left column and the outline two,
  so that Layout, Text, and the start of Input show at the check's
  700-point height. The palette scrolls for the rest.
- Nothing follows the pointer while carrying; the insertion line and the
  outlined block show where the component will go.
- The builder is still one file, now about 1,900 lines.

## Slice 4 as built

The inspector's Events group follows Content. A component whose call
reports an event, which `View.components()` now marks with a fifth
element, `reports`, has one row: `on-click`, or `on-change` for a
component that edits a value. The row is None, Send, or Call, and a
fourth choice, Lisp, appears for a handler written otherwise. Send and
Call take a name, first made from the component's text ("Sign in" gives
`sign-in`); Call also offers the procedures `FILE.lisp` defines. A block
lists its `(on name form)` options, each with the body of its
`(lambda () body)` edited as Lisp, and offers Handle for each message
sent inside it that it does not handle.

A procedure the tree calls by name and the session lacks gets
`(def name (lambda () 'name))` in `FILE.lisp` when Run is pressed or
the tree is saved; Save writes the file. `View.trace` reports each
handler run with its node, event or message, and result. In run mode
the inspector's place lists them, newest first, under a one-line box
that evaluates Lisp in the session.

`builder --check` runs the scenario under "Validation" below, selecting
nodes by clicks on the canvas, and checks the message, the log, the
message box, and a stub written by Save.

It differs from the design in these ways:

- The procedures offered are those `FILE.lisp` defines, read from its
  text; the session itself cannot list its globals.
- A selected block shows its own Layout group before "In row" or "In
  column"; a component shows the block around it first.
- The builder writes option names with `-`, as a tree spells them; it
  wrote `on_click` before.
- A new input starts empty, not with the text `text`.
- The builder is still one file, now about 2,440 lines.

## Validation

One scripted scenario is the acceptance test for slices 1 to 4, run by
`builder --check` and by Gary in a window: build a sign-in form with a
heading, two labelled inputs, and a row of two buttons 12 points apart
at the right edge, then make the second button send a message that the
form handles. It must need no typed option name and no typed Lisp other
than the handler's body.

## Evidence

Three research reports from 2026-11-25. None of the tools was operated;
the claims come from their documentation.

- Outline synced with the canvas, and visible frames for layouts: Qt
  Designer, Webflow Navigator, Android Studio Component Tree.
- Wrap and unwrap in one command: Figma and Penpot (Shift+A), Qt Designer
  (Ctrl+1, Ctrl+2, Ctrl+0), Xcode (Embed In, Unembed).
- Fit, Fill, Fixed per axis: Figma (hug, fill, fixed), Plasmic, Framer.
- Alignment grid beside a direction control: Figma, Webflow.
- Common options first, all behind a toggle: Android Studio's Attributes
  panel. Options grouped by effect: Webflow's Style panel.
- Inspector generated from field descriptions: Godot export annotations,
  Unity attributes, Storybook argTypes, Framer property controls.
- Changed values marked with a reset: Qt Designer, Godot.
- Events as rows on the component that create a named handler: Delphi's
  Events page, Retool's event handlers. Messages that go up the
  containers: HyperCard.
- Reported mistakes to avoid: spacing handles that take resize drags
  (Figma), hidden modifier keys for drop targets (Figma), a resize handle
  that fixes a size without showing it (Android Studio), placement on a
  fixed grid (Retool, which added a Stack to recover reflow).

## Open questions for Gary

1. Whether the five slices and their order are right, and whether slice 5
   is wanted at all.
2. Whether PRs gwf/x2c#751 to gwf/x2c#755, the first builder, go to
   `dev` as they are or wait for slice 1.
3. Whether the option table lives in the builder, as proposed, or in
   `View.components()` so that other tools can use it.

## Plan review

- **Established facts.** CUI establishes layout and every rectangle. The
  component table establishes option names, kinds, and enum members. The
  builder's option table adds only presentation: group, common, step,
  help. It does not restate types.
- **Reuse and new mechanisms.** Reused: `View`, messages, the tree
  operations, drag aiming, and CUI's tree, inspector rows, context menu,
  and shortcuts, all of which x2cui already wraps. New: the option table,
  the outline pane, wrap and unwrap, and the Events group.
- **Idiom.** The document stays a List and edits stay List operations.
  The inspector is a loop over a table, not code per component.
- **Validators and diagnostics.** None added. A Fit block with a Fill
  child on the same axis is shown as a warning in the inspector, not
  rewritten.
