# x2cui Lisp surface: a UI described by a List

> Status: implemented in the package on 2026-11-24, after Gary approved
> reversing the "No Lisp surface" decision in
> [the x2cui plan](x2cui-package.md). "As built" below records where the
> source differs from the design sections, which are kept as proposed.
> [The builder](x2cui-builder.md) and
> [runtime native modules](runtime-native-modules.md) build on it and are
> not started.

## As built

The source is `packages/x2cui/src/x2cui-view-generate.x` (the generator)
and `x2cui-view.x` (the `View` and its Lisp functions). The view is a unit
of its own: a program that uses no `View` links neither it nor the Lisp
runtime, and `examples/todo.x` builds to the same 2,527,496 bytes as
before the change. `examples/live.x`, which uses a view, is 3,000,488.

- **The tree is a Lisp global.** `View.new(lisp, "ui")` draws the value
  of the session global `ui`. Lisp code changes the UI with `(def ui
  ...)`, so there are no `ui-set` and `ui-tree` functions and no
  `View.submit`. A host evaluates Lisp text in the session between
  frames; `examples/live.x` reads the terminal that way.
- **Bound state is a Lisp global.** `(bind name)` reads the global before
  the component's call and sets it when the component changed the value.
  The view keeps storage only for the text buffer of an input.
- **`(eval form)`** as an argument or option value is evaluated on every
  frame. The design had no way to show a changing value without replacing
  the tree.
- **Handlers are forms.** `(on-click form)` is evaluated after the frame
  to a procedure, so a name and a `lambda` both work. `on-change` is the
  same option.
- **Storage.** The session's Scope owns the view and its input buffers,
  so a view is released with its session and has no close.
- **Functions bound:** `ui-replace`, `ui-find`, and `ui-text`.
- **Generated code.** One setter per option record and one draw function
  per component, from the C types; a chain of name comparisons selects
  the draw function. There is no table object at run time.
- **Names.** The reader gives a short name as a `Symbol` and a long one
  as an `Atom`; both are compared by spelling, with `-` read as `_`.
- **Components:** 31, listed in `_view_functions`. Grid, image, and icon
  are not among them: an icon is a C macro and an image takes a texture.
- **Measured.** Off screen on an Apple M4 Max, 1,251 components a frame
  took 0.63 ms drawn from a tree and 0.14 ms drawn by the same calls in
  x2c source, the mean of 200 frames, layout and painting excluded.
- **Not done:** a browser build of the example, and a test in a real
  window. The package's existing browser build (`make web`) still passes.

## Result

A program holds a UI as a List, and x2cui draws that List every frame. A
Lisp session can build the List, replace any part of it, and attach Lisp
callables as handlers. The running window shows the change on the next
frame.

```lisp
(column ((pad 24) (gap 12))
  (heading () "A tiny counter" 2)
  (button ((variant primary) (on-click bump)) "Add one")
  (text ((bind clicks-label))))
```

```c
Lisp lisp = auto Lisp.new();
UiLisp.install(lisp);
View view = View.new(lisp, lisp.eval_file("counter.lisp"));
while (app.frame()) view.draw(app.ui());
```

The existing compile-time surface (`ui.button("Add", variant: primary)`,
block components, `ui.each`) does not change and stays the way to write an
x2cui program in x2c.

## Current facts

- x2cui is immediate mode: the program redraws inside `while (app.frame())`.
  A stored List walked every frame fits this with no retained widget
  objects inside CUI.
- The method forms are compile-time only. `name: value` options, short
  values such as `primary`, and block components are macros and metas in
  `packages/x2cui/src/x2cui-options.x` and `x2cui-generate.x`. No runtime
  table maps an option name to a record field.
- The compiler already reads every CUI option record at compile time
  through `Type.fields`, `Type.parameters`, and `Type.members`.
- Packages expose Lisp functions with `$lisp.binding` and `$lisp.install`
  (`lib/lisp-bindings.x`). pcre2, sqlite, libcurl, yyjson, and torch do so.
- x2c calls a stored Lisp callable with `Lisp.apply`. A `Func` adapter made
  from a lambda runs only while its own session is active
  (`lib/lisp/native.x`), so a handler kept across frames goes through
  `Lisp.apply`.
- A `Lisp` session is unsynchronized, and x2cui draws on one thread.
- `Symbol` keeps at most ten characters. Option names such as
  `min_column_width` and `border_color` are longer.

## Design

### The form

Every node has one shape: `(component (options) arguments-and-children)`.
The options List holds `(name value)` pairs and may be empty. Positional
arguments follow in the order the x2cui method takes them. For a block
component the remaining elements are child nodes. One shape means the
interpreter and the builder never guess whether an element is an option or
a child.

Option values are Lisp values: numbers, Strings, and names. A name in an
enum-typed option selects the enum member, as `primary` does in x2c source.
Size options accept `fill`, `fit`, a number for pixels, and `(grow n)`.

### Generated component table

A meta in the package emits one row per supported component: its name, its
positional parameters with types, whether it is a block, and one setter per
option field of its record. The meta reuses the type queries that
`x2cui_record` already makes, so the table follows the pinned CUI header
without a hand list of fields. Option names are compared by full spelling as
Strings, not as Symbols, because of the ten-character limit.

The first table covers the components the examples use: column, row, box,
grid, card, heading, text, button, checkbox, switch, slider, text field,
select, segmented, tabs, divider, spacer, badge, icon, progress, image. The
table is a list of names; adding a component is one more name when its
parameters are types the interpreter already converts.

### State and handlers

Lisp has no references, and CUI widgets write through pointers. A node
names its state with `(bind name)`. The view keeps one cell per bound name
(a number, a bool, or a `TextField`), passes its address to CUI, and
exposes the value to the session as the global `name`. A Lisp assignment to
that global changes the cell before the next frame.

A handler option such as `(on-click f)` holds a Lisp callable or a name
bound in the session. When the component reports its event for the frame,
the view records the handler. After the frame's tree is complete, the view
calls each recorded handler with `Lisp.apply`. Handlers therefore never run
while CUI blocks are open.

### Errors

A handler runs after the frame's blocks are closed, so a Lisp error in a
handler cannot leave CUI unbalanced. The interpreter itself raises only on
a malformed tree. `View.draw` closes the blocks it opened with `defer` and
then lets the Error continue to the caller.

### Changing a live UI

`View.set(tree)` replaces the tree. `UiLisp.install` binds `ui-set`,
`ui-tree`, and `ui-replace` (replace the node with a given `id` option) so
Lisp code changes the tree from inside a handler. An outside source of
Lisp text, such as a console or a socket, hands text to `View.submit`. The
view evaluates submitted text between frames on the UI thread and calls
`cui_request_wakeup` so a sleeping `App.frame` returns.

## Scope

| Piece | Where | Estimate |
| --- | --- | --- |
| Component table meta | `packages/x2cui/src/` | 150-300 lines |
| Interpreter, cells, handler queue | `packages/x2cui/src/x2cui-view.x` | 600-900 lines |
| Lisp bindings and installer | same unit | under 100 lines |
| Example, tests, README and book section | package | one example, one test unit |

The estimates are not measurements. Out of scope: every CUI component,
`ui.each` and tables from data, node editor and dockspace, a wasm console.

## Compatibility

No existing x2cui method or macro changes. The README section "No Lisp
surface", the sentence at `docs/src/guide/x2cui.md:473`, and the lines in
`plans/x2cui-package.md` that exclude a Lisp surface and a retained tree
are rewritten to describe this layer.

## Validation

- An off-screen test draws a tree, injects a click, and checks that the
  Lisp handler ran once and the bound cell changed.
- An off-screen test replaces a subtree and checks the next frame's
  rectangles.
- The package `run-lisp` target runs the example, as other packages do.
- One measurement: frames per second of the stress example's widget count
  drawn from a tree against the same count drawn from x2c source.

## Questions for Gary

1. Reverse the no-Lisp-surface decision for x2cui? Approved 2026-11-24.
2. Accept the one-shape form `(component (options) ...)`, or prefer another
   spelling? Accepted 2026-11-24.

## Plan review

- **Established facts.** The compiler's type queries establish each option
  record's fields and types; the table copies them and the interpreter does
  not check a field's type again. CUI establishes layout and input; the
  view does not track rectangles or focus.
- **Reuse and new mechanisms.** The table meta reuses the queries behind
  `x2cui_record`. Bindings use `$lisp.binding`. Handlers use `Lisp.apply`.
  Three mechanisms are new: the table, because no runtime field map exists;
  the cells, because CUI needs addresses and Lisp has none; and the
  deferred handler list, because a handler may replace the tree being
  walked.
- **Idiom.** The tree is an ordinary List matched by structure. There is no
  widget class hierarchy, virtual DOM, or diffing; CUI already redraws
  every frame.
- **Validators and diagnostics.** One: an unknown component or option name
  raises an Error naming it. Without it, a misspelled option is silently
  dropped and the UI draws wrong. No negative fixtures beyond that test.
