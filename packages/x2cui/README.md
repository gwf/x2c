# x2cui: CUI components from x2c

This package provides an x2c interface to [CUI](https://github.com/yappologistic/CUI)
1.3.1, an immediate-mode UI library that draws its own components. A program
describes the screen with calls on every frame. CUI lays it out, handles the
mouse and keyboard, and draws it in a window or into pixels. `PROFILE.md`
records the build.

It is an importable package: `src/x2cui.x` is its entry unit and every
public name compiles to `x2cui__*`.

```x2c
import "x2cui" with App, Ui;

int main(void) {
  App app = auto App.open(title: "Hello", width: 420, height: 300);
  bool notify = true;
  int clicks = 0;
  while (app.frame()) {
    Ui ui = app.ui();
    ui.column (pad: 24, gap: 12) {
      ui.heading("Hello, CUI", 2);
      ui.switch("Notifications", notify);
      if (ui.button("Click me", variant: primary)) clicks++;
      ui.text(%"Clicked $clicks times.");
    }
  }
  return 0;
}
```

## Status

The package is a preview. Native builds are supported on macOS arm64
only. The browser build needs Memory64, JavaScript Promise Integration,
and WebGL 2; it was run in a Chromium-based browser and under Node. The
Linux build is not run. CUI has no accessibility tree, no inline
input-method composition, and no bidirectional text. The package
applies two patches to CUI, `table-row-state` and `focusable-canvas`
(see `PROFILE.md`), and an upgrade of CUI must remake them. A program
draws from one thread.

CUI's records, enums, constants, and icons, such as `cui_box`,
`CUI_BUTTON_PRIMARY`, `CUI_FILL`, and `CUI_ICON_PLUS`, arrive under their
own names through the published `src/cui-1.3.h`, the raw API. The
package's own types, such as `Ui`, `App`, `Offscreen`, `TextField`, and
the collections below, are `x2cui__*` names and need `with` or the alias.

## Build from a checkout

x2cui has no release bundle. Build it from a checkout, then compile a
program that imports it, such as the example above saved as `hello.x`:

```sh
make -C packages/x2cui build
./x2c build --package-dir packages \
  --c-include-dir packages/x2cui/deps/include \
  -I packages/x2cui/deps/include --output hello hello.x
./hello
```

Platforms: source only. macOS is built and tested, and the gallery runs
in a browser; see [In a browser](#in-a-browser). The Linux profile is
written and has not been built; see `PROFILE.md`.

The driver adds the package's `builds` and `src` directories and links
`builds/libx2cui.a` with CUI and the system frameworks. The `-I` lets x2c's
own collection read CUI's headers.

## Writing a component

Each CUI component keeps its name. The C calling conventions change:

| C | x2c |
| --- | --- |
| `cui_button(ui, "Add", .variant = CUI_BUTTON_PRIMARY)` | `ui.button("Add", variant: primary)` |
| `cui_checkbox(ui, "Done", &task->done)` | `ui.checkbox("Done", task.done)` |
| `cui_input(ui, "name", buf, sizeof buf, .width = CUI_FILL)` | `ui.input("name", field, width: fill)` |
| `cui_segmented(ui, "view", items, 3, &index)` | `ui.segmented("view", %("All" "Open" "Done"), index)` |
| `cui_icon_button(ui, CUI_ICON_X, .size = CUI_SIZE_SM)` | `ui.icon_button(x, size: sm)` |
| `cui_row(ui, .gap = 8) { ... }` | `ui.row (gap: 8) { ... }` |

- **Options** follow the other arguments as `name: value`, with the names
  of the fields of CUI's option record, and may be left out. A call builds
  no Map: each becomes a field of the record in a C designated
  initializer, and a misspelled name is a C error that names the field.
  Values may be short names; see [Short values](#short-values).
- **Labels and ids** are Strings: a literal, a variable, or an
  interpolation such as `%"Row $i"`.
- **State** that a component changes is passed by reference, with no `&`:
  a `bool`, an `int`, a `float`, a `cui_date`.
- **Text** that a component edits is a `TextField`, which holds a buffer of
  fixed capacity. `field.text()` returns its text as a String, `field.set`
  replaces it, `field.take()` returns the text and clears the field, and
  `field.empty()` tests it.
- **A list of strings** is a `List`.
- **A text result** is a String, or NULL where CUI returns none.
- **A block component** is written as a method with a block,
  `ui.row (gap: 8) { ... }`, with a space before its arguments by
  convention. Its end call is deferred, so it also runs when the block
  leaves through `return`, `break`, or `continue`. CUI's own C macros skip
  the end call there. A component that reports whether it is open, such as
  `ui.dialog` or `ui.menu`, runs its block only while open. Blocks stack:

  ```x2c
  ui.id (i) ui.row (gap: 8, align: center) {
    ui.checkbox(task.title, task.done);
  }
  ```

  `ui.id (key)` keeps the components drawn for different keys apart, with
  a text or an integer key, and `ui.disabled (condition)` disables the
  components in its block.
- **A block that reports a result** declares the name it is given, and
  the statements after the block read it: `ui.card_stack (swiped,
  "deck", 3) { ... }`, `ui.swipe_item (action, "row", left, right)
  { ... }`, and `ui.reorder (changed, "tasks", order) { ... }` store what
  their end reports; `ui.kanban_column (added, title, count) { ... }` and
  `ui.kanban_card (clicked, id) { ... }` store what their begin reports,
  before the block runs; `ui.kanban (moved, move, "board") { ... }`
  declares `moved` and the `cui_kanban_move` `move`, set when a card was
  dropped. Because the form declares a name, it is a block of its own: an
  unbraced loop or `if` cannot take it as its one statement.

These forms are built at compile time from CUI's C signatures by
`src/x2cui-generate.x`.

### Short values

A value, or an ordinary argument, that is a lower-case name with no
declaration of its own is a short name for a CUI constant. The C type of
its field or parameter decides the constant:

| Type | Short name | Constant |
| --- | --- | --- |
| an enum, such as `cui_align` or `cui_button_variant` | `center`, `primary` | the member with the enum's prefix: `CUI_ALIGN_CENTER`, `CUI_BUTTON_PRIMARY` |
| `cui_size` | `fill`, `fit` | `CUI_FILL`, `CUI_FIT` |
| another `cui_T`, such as `cui_color` or `cui_font` | `accent`, `medium` | `CUI_COLOR_ACCENT`, `CUI_FONT_MEDIUM` |
| an icon: an option named `icon`, `icon_*`, or `*_icon`, or a parameter CUI names `icon` | `plus` | `CUI_ICON_PLUS` |

A number for a `cui_color` is `0xRRGGBB`: `color: 0x3b82f6` is
`CUI_RGB(0x3b82f6)`. A number for a `cui_size` is pixels: `width: 26` is
`CUI_PX(26)`, and `grow(1.5)` is `CUI_GROW(1.5)`. In `font: m.unread ? medium : body`, each
arm is lowered. A declared name keeps its own value, and so does a C
macro such as `CUI_FILL` or `NULL`.

### Lists and tables

`ui.each (T x in items, key: expression)` runs its block once for each
element, with `x` declared as `foreach` declares it. Each pass pushes an
id made from `key:`, or from the element's position when there is none,
so a row keeps its state when the list is filtered or reordered.
`ui.item (row, selected: ...) { ... }` is an interactive row: it draws a
quiet fill when selected or hovered, and inside `ui.each` a hairline
along its top edge unless it is the first item or it or the item before
it is selected. Tab reaches each item in order, and Enter or Space clicks
the focused item, as they click a button; the focused item draws CUI's
focus ring. `row` is a `RowState` with `hovered`, `pressed`, and
`clicked` for this frame:

```x2c
ui.each (Message m in shown, key: m.id)
ui.item (row, selected: a.selected == m) {
  if (row.clicked) a.selected = m;
  ui.text(m.subject, font: medium);
}
```

`ui.table` takes its columns as a Map literal of titles and widths, which
it lowers at compile time to a static `cui_table_column` array. A width is
pixels, `fill`, `fit`, or `grow(w)`; `right(w)` and `center(w)` align the
column, and `unsorted(w)` keeps it from sorting. `ui.table_row (row,
selected: ...)` begins a row, and `ui.cell () { ... }` and
`ui.cell_text(text)` are its cells:

```x2c
ui.table ("orders", sort: &s.sort, selectable: true,
          columns: {"Order": 90, "Customer": fill, "Amount": right(110)})
ui.each (Order o in shown, key: o.id)
ui.table_row (row, selected: s.selected == o) {
  if (row.clicked) s.selected = o;
  ui.cell_text(o.id);
  ui.cell () ui.avatar(o.customer, size: 28);
  ui.cell_text(o.price);
}
```

A table row's `hovered` and `pressed` come from `cui_table_row_hovered` and
`cui_table_row_pressed`, two functions this package's build adds to CUI;
see `PROFILE.md`.

A CUI function that takes a `printf` format and C variadic arguments is a
method that takes the format and x2c values, as `String.format` does:

```x2c
ui.textf("Ln %d, Col %d", result.line, result.column);
ui.table_cell_textf("%.1f", score);
terminal.printf("%s: command not found\n", command);
log.append(CUI_LOG_WARN, "step took %.1f ms", elapsed);
```

`terminal` is a `cui_terminal_buffer` and `log` is a `cui_log_buffer`.
Each formatted text is a String, as an interpolated label is.

## Windows and frames

`App.open` opens a window and raises `<init-fail>` when it cannot. Its
`name: value` rows set the fields of CUI's `cui_app_desc`, as in
`App.open(title: "Mail", width: 420, height: 600, min_width: 320)`.
`app.frame()` presents the last frame, waits for input or animation, and
begins the next; it returns false once the window has closed. On macOS it
also gives the window's title bar the background color of the current
theme, so the title bar follows `ui.set_theme` and fades with it. `app.ui()`
is the window's borrowed `Ui`. `App` adopts `Cleanup`, so
`App app = auto App.open(...)` closes the window when the scope ends.

Draw each frame with an ordinary call:

```x2c
while (app.frame()) draw(app.ui(), state);
```

Do not wrap the frame in an `auto` region. Drawing is where a program
changes its state: a click adds a task or replaces a list. A region would
free those objects when the frame ends. Drawing itself leaves nothing
behind to free: the to-do example holds 8.4 MB of resident memory after
500 frames and after 16,000.

Draw on one thread. CUI allows several windows each on their own thread,
but this package keeps one unlocked table of the arrays it builds for
Lists of Strings, shared by every `Ui` in the process, so it supports
drawing on one thread only.

## Drawing without a window

`Offscreen` draws frames with CUI's software renderer into pixels:

```x2c
Offscreen screen = auto Offscreen.open(520, 640);
for (int frame = 0; frame < 3; frame++) {
  screen.begin();
  draw(screen.ui(), state);
  screen.end();
}
screen.write_png("todo.png");
```

The first frame measures, and later frames settle layout and animations,
so draw a few before writing. `screen.commands()` is the number of draw
commands in the last frame. `write_png` raises `<io-fail>` when it cannot
write. The package's tests drive components this way, with CUI's own
`ui.input_mouse_move`, `ui.input_mouse_button`, and `ui.input_text`.

## Arrays of records

A component such as a chart or a calendar reads an array of CUI's own
records. Constant data is an Array literal, written where the component
takes the array. Each element is a Map literal of the record's fields,
lowered by the type of each field as options are, and the form passes
the count:

```x2c
ui.tab_bar("tabs", [{icon: house, label: "Home"},
                    {icon: search, label: "Search"}], selected);
ui.radial_gauge("cpu", 64, 0, 100, bands: [
  {to: 60, tone: success}, {to: 85, tone: warning}, {to: 100, tone: danger}]);
```

An element that is not a Map literal is one value: `["Mon", "Tue"]` for
labels, and in an option named `icons` or `*_icons`, `[bold, italic]` is
an array of icons. An Array literal inside a record is an array too, as
in `{name: "1.0", values: [82, 64, 90]}`, and a record field is a Map
literal, as in `{combo: {mods: 0, key: f5}}`. A count field after the
array, as `band_count` follows `bands` and `count` follows `values`, is
filled. `[]` is NULL with a count of 0.

The literal is constant. It lowers to a `static const` C array that is
initialized once, so it costs nothing per frame, and every element must
be a constant: a literal, a short name, an enum constant, the name of a
static array, or a C macro such as `CUI_RGBA(...)` on constants. The form
refuses a variable or a function call in an element, because the static
array would keep its first value. CUI reads some arrays until the frame
ends, so the form does not build an array on the stack instead.

A record a program builds is written `T.of(name: value ...)`, with the
same short names: `cui_reaction.of(icon: heart, count: 4)` is a
`cui_reaction`. Every CUI record type has one, except `cui_series`, whose
`cui_series.of(name, values)` takes an `ArrayFloat`.

Data a program keeps, and every array a component writes into, is a
**collection**: CUI's records packed in one block that the component
reads and writes in place, with no copy. A collection is written with
an Array literal of `name: value` rows, copied once, or built with
`push`:

```x2c
static Reactions reactions = Reactions.of([
  {icon: thumbs_up, count: 12, active: true}, {icon: heart, count: 4}]);
...
ui.reactions("reactions", reactions);
reactions[1].count += 1;
reactions.push(cui_reaction.of(icon: rocket, count: 7));
foreach (cui_reaction *r in reactions) total += r.count;
```

A form takes a collection where its component takes an array, and passes
its records and length. An editor that grows its array, the key-value
editor, the query builder, and the curve and gradient editors, takes the
collection alone: the form keeps one record to spare past the end, which
CUI types a new record into, and stores CUI's count back as the length.

| Operation | What it does |
| --- | --- |
| `T.of([...])` | a collection of the rows of an Array literal |
| `c[i]` | a pointer to record `i`, so `c[i].field = v` changes it |
| `c.len()` | how many records it holds |
| `c.push(r)`, `c.insert(i, r)`, `c.remove(i)` | grow or shrink it |
| `foreach (T r in c)` | each record, by value |
| `c.data()` | the records, for a raw CUI call such as `cui_trace_sort` |

The collections:

| Collection | Record |
| --- | --- |
| `CalEvents` | `cui_cal_event` |
| `Candles` | `cui_candle` |
| `CheckSteps` | `cui_check_step` |
| `CurveKeys` | `cui_curve_key` |
| `DocTabs` | `cui_doc_tab` |
| `FeatureFlags` | `cui_feature_flag` |
| `FlameSpans` | `cui_flame_span` |
| `GanttTasks` | `cui_gantt_task` |
| `GradientStops` | `cui_gradient_stop` |
| `KvPairs` | `cui_kv_pair` |
| `MonthEvents` | `cui_month_event` |
| `PlanSteps` | `cui_plan_step` |
| `PromptSuggestions` | `cui_prompt_suggestion` |
| `QueryFields` | `cui_query_field` |
| `QueryNodes` | `cui_query_node` |
| `Reactions` | `cui_reaction` |
| `Series` | `cui_series` |
| `Sources` | `cui_source` |
| `SpeedActions` | `cui_speed_action` |
| `TimelineTracks` | `cui_timeline_track` |
| `TocItems` | `cui_toc_item` |
| `TourSteps` | `cui_tour_step` |
| `TraceSpans` | `cui_trace_span` |
| `TraceTracks` | `cui_trace_track` |
| `TreeNodes` | `cui_tree_node` |
| `Vec2s` | `cui_vec2` |
| `VizItems` | `cui_viz_item` |
| `ScatterSeries` | `cui_scatter_series` |

A form refuses a C array of CUI's records, and an Array literal where
CUI writes through the array, with a message that names a collection.
Change a collection between frames, or after the call that passes it:
`c[i]` and `data` are valid until the collection grows. CUI copies what it
paints during the call, as `ui.line_chart` and `ui.bar_list` do, and an
editor writes only during its call.

`KvPairs.of_url(url)` reads a URL's query parameters,
`field.set_url_params(pairs)` writes them back into a `TextField`, and
`fields.text(nodes)` is the sentence a query builder's nodes say.

A tone or a log level kept in quoted data is a Symbol:
`cui_tone.named(<violet>)` is the tone it names, and
`cui_log_level.named(<warn>)` the log level. A list of labels is a
`List`, as `attachments: files` takes one, and an array of numbers is an
`ArrayFloat` or an `ArrayInt`, which a form passes as it passes a
collection.

The table and the data grid take their columns as a Map literal; see
[Lists and tables](#lists-and-tables). The data grid draws only the
rows on screen: its block builds rows `first` up to `last`, two `int`
variables the form declares, and its widths are points. A grid's cells are
`ui.grid_cell () { ... }` and `ui.grid_cell_text(text)`, as a table's are
`ui.cell` and `ui.cell_text`; which a cell is in is known only while the
frame runs, so the two kinds have their own names:

```x2c
ui.data_grid ("people", people.len(), first, last,
              columns: {"Name": 240, "Commits": right(100)},
              height: 300, selected: selected, sort: &sort)
  for (int row = first; row < last; row++) {
    ui.data_grid_row(row);
    ui.grid_cell_text(names[row]);
    ui.grid_cell_text(%"$(commits[row])");
  }
```

Chart numbers may also be a packed `ArrayFloat`:
`cui_series.of(name, values)` builds a series over one, and
`ui.donut_chart` and `ui.sparkline` take one. A chart's x axis labels are
a `List` parameter.

`tools/gen-arrays.py` writes the methods of these components from the
pinned header, with CUI's parameter names.

An option keeps its C field type. A field that is a pointer to caller
state takes an address, as in `toggle: &bold`, and a field that is an
array takes a C array.

A tree leaf has no open flag and never opens, so its block is empty:
`ui.tree (name, NULL, leaf: true) {}`.

A callback that CUI calls, such as a canvas paint function, is an ordinary
function. Where its type names `cui_ctx *`, declare that parameter as
`cui_ctx *` and assign it to a `Ui` to call methods.

## What has no x2c form

Functions that fill caller buffers without a `cui_ctx`, such as
`cui_terminal_init`, `cui_log_init`, and `cui_fs_list`, are called as C.

Short names apply only where a component's parameter or field gives the
C type, so a comparison, a flag test, or an assignment on a variable of a
CUI enum type spells the constant: `status == CUI_STATUS_BUSY`.

## No Lisp surface

A `Ui` is a native object that lasts across frames, and every component
call acts on it. This package has no Lisp bindings.

## Examples

`examples/todo.x` is the short application (`make short-example`). It
keeps tasks in an `Array`, adds one from a text field, filters the list,
removes a task, confirms before clearing the finished ones, and saves the
list to a file after each change. `make run-interactive` opens it.
`todo --shot IMAGE.png` draws three sample tasks off screen.

`examples/mail.x` is a mail message list: `ui.each` over the messages of
one folder that match a search, one `ui.item` row each, with a context
menu. `examples/orders.x` is a table of recent orders with a Map of
columns, sorted by the header clicked. `mail --shot IMAGE.png` and
`orders --shot IMAGE.png` draw them off screen.

`examples/gallery.x` is the broader application (`make example`). It is
a port of CUI's own gallery, `examples/gallery_ui.c` and
`examples/gallery_more.c` in CUI's source: the same 26 pages, sections,
and layout, with each page in a file under `examples/gallery/`. Read a
page beside its C original to compare the two forms. `make run-gallery`
opens it, and `gallery --shots DIR` draws every page off screen. Drawn
that way, each page is the same image, byte for byte, as the same page of
CUI's C gallery.

`examples/stress.x` is an animation load with a displayed frame rate
(`make run-stress`). It redraws on every frame and animates as many items
as its slider asks for: moving circles on a canvas, or cards that each
hold a spinner, a badge, and a moving progress bar. The header shows
frames per second, the time between frames, the time the program spent
describing the frame, and the frame's vertices and triangles. A
window waits for the display, so the rate stops at the display's rate;
`stress --no-vsync` lifts that to CUI's limit of 120 frames per second.
`stress --frames N [shapes|components [ITEMS]]` times N frames off screen
with the software renderer and prints the means.

`examples/scenes.x` is a check, not an application. It has one small
scene for each of CUI's 201 components, named for the component and
grouped into families under `examples/scenes/`. `scenes --shots DIR`
draws every scene off screen to `DIR/NAME.png`, and `scenes --list` prints
the names. `scenes --check HEADER` compares the names with the
`#define cui_NAME(` lines of CUI's `cui.h` and fails when a component has
no scene. A menu that opens only on a click is drawn closed.

## In a browser

The gallery also runs in a browser, from the same x2c source:

```sh
make wasm-runtime                 # at the repository root, once
make -C packages/x2cui web-serve  # then open http://127.0.0.1:4399/
```

`make web` writes `builds/web/gallery.js`, `gallery.wasm`, `stress.js`,
`stress.wasm`, and `index.html`. `http://127.0.0.1:4399/?stress` opens the
stress test in place of the gallery. It needs Emscripten. The program is 64-bit WebAssembly and
draws with WebGL 2 through CUI's SDL2 window layer. The browser must
support 64-bit WebAssembly memory and JavaScript Promise Integration;
`web/index.html` says so where one is missing. `gallery.wasm` is 2.6 MB,
1.0 MB compressed with gzip.

`make web-check` draws every gallery page off screen under Node. Of the
26 images, 22 match the native build's to within one step of one colour
channel in fewer than 1,200 bytes of 23.8 million. The four others
differ where the platform differs: two table rows with equal sort keys
change places, the keymap shows Ctrl for Cmd, and the file pages list
another directory.

`web-check` and `web` are not part of `make check`, which needs no
Emscripten. `PROFILE.md` records the browser build.

A program of your own builds the same way as the gallery does in the
`Makefile`: `x2c build -c --cc tools/wasm-cc` compiles its units, and
`tools/wasm-cc` links them with the package's browser archive, x2c's
browser runtime, and CUI's browser archive.

## Native API

`src/cui-1.3.h` includes the real upstream headers and rejects a different
minor version. Importing the package is enough to reach them:
`tests/test-raw-api.x` uses only `import "x2cui"` and then calls
`cui_create`, `cui_textf`, `cui_button_ex`, and `cui_get_draw_data`
directly. `Ui` is CUI's `cui_ctx *` and `App` is its `cui_app *`, so raw
calls and methods mix on the same object.

Use the raw API for the components listed above, for the custom renderer
interface (`cui_renderer_iface`), and for a custom platform layer.

## Build and test

`make prepare` downloads, verifies, and builds CUI in the shared dependency
cache. `make run` and `make test` prepare it automatically when absent and
reuse it when present. Set `X2C_DEPS_DIR` to move the shared cache, or
`CUI_PREFIX` to diagnose another compatible installation.

```sh
make verify-pins
make test
make run
make check
```

`make run` draws the to-do application and every scene off screen, then
checks that every component of the pinned header has a scene.
No check opens a window, because a window needs a display.
