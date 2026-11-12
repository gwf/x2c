# Building Interfaces with x2cui

For the full component forms, collections, and build profile, see the
[x2cui package README](https://github.com/gwf/x2c/blob/main/packages/x2cui/README.md).
This chapter belongs to [Advanced Topics](../library/advanced-topics.md).

The `x2cui` package draws windows and user interfaces from x2c. It is an
interface to [CUI](https://github.com/yappologistic/CUI) 1.3.1, a C99
immediate-mode UI library that draws its own components. A program
describes the whole screen with calls on every frame. CUI lays the screen
out, handles the mouse and keyboard, and draws it in a window or into
pixels. The entry unit is `packages/x2cui/src/x2cui.x`, and every public
name compiles to `x2cui__*`.

The package is experimental. Native builds are supported on macOS arm64 and
on Linux arm64 and x86_64. On Linux the package passes its off-screen
checks; the windowed path has not been tested there. The package has
no release bundle, so a program builds it from a checkout. A browser build
of the gallery also exists. CUI has no accessibility tree, no inline
input-method composition, and no bidirectional text, and a program draws
from one thread. [Limits](#limits) lists these with the other limits.

## A first program

This program opens a window with a heading, a switch, a button, and a
line of text that counts the clicks:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
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

`App.open` opens the window and raises `<init-fail>` when it cannot. Its
`name: value` arguments set the fields of CUI's `cui_app_desc`. `App`
adopts `Cleanup`, so `auto` closes the window when `main` returns.
`app.frame()` presents the last frame, waits for input or animation, and
begins the next frame. It returns false once the window has closed.
`app.ui()` is the window's `Ui`, which every component call acts on.

The loop draws every frame again from the program's state. The switch
writes `notify`, and the button returns true on the frame it is clicked.
The program keeps no handle to either component.

Save the program as `hello.x`. Then, at the top of a checkout, build the
package and the program:

```sh
make -C packages/x2cui build
./x2c build --package-dir packages \
  --c-include-dir packages/x2cui/deps/include \
  -I packages/x2cui/deps/include --output hello hello.x
./hello
```

The first `make` downloads, verifies, and builds CUI in the shared
dependency cache. The driver links `builds/libx2cui.a` with CUI and the
system frameworks. The `-I` option lets x2c's own collection read CUI's
headers, and `--c-include-dir` gives the same headers to the C compiler.
Linux also needs the X11 development headers; the package's `PROFILE.md`
names them. `make -C packages/x2cui bundle` builds a movable bundle, as
[Packages](packages.md#movable-native-bundles) describes; a program that
uses it passes `--x-include-dir` with the bundle's `native/include`.

Do not wrap a frame in an `auto` region. A frame is where a program
changes its state, for example when a click adds a task. A region would
free those new objects when the frame ends. Drawing itself leaves nothing
to free.

## One form for every component

Every CUI component is a method form on `ui` and keeps CUI's name. A
component that draws one thing is a call, and a component that holds
other components takes a block:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
ui.button("Add", variant: primary, icon: plus);
ui.text("Saved", size: 12, color: text_muted);
ui.badge("Paid", tone: success, dot: true);
ui.box (width: fill) ui.heading("Inbox", 4);
ui.box (width: 7, height: 7, radius: 4, bg: accent) {}
```

[Method-form macros](../reference/language.md#method-form-macros) in the
language reference define how `ui.button(...)` and `ui.row (...) { ... }`
resolve. The package generates these forms at compile time from CUI's C
signatures.

The arguments follow a few rules:

- **Options** come after the other arguments as `name: value`, and each may
  be left out. The names are the fields of CUI's option record for that
  component. A misspelled name is a C error that names the field.
- **Short values** are lower-case names such as `primary`, `plus`,
  `success`, `fill`, and `text_muted`. The type of the option selects the
  CUI constant, so `variant: primary` and `tone: success` need no prefix.
  A plain number for a size is pixels, as in `width: 26`; a number for a
  color is `0xRRGGBB`.
- **Labels and ids** are Strings: a literal, a variable, or an
  interpolation such as `%"Row $i"`.
- **State** that a component changes is passed by reference with no `&`,
  as `ui.switch("Notifications", notify)` passes a `bool`.
- **A list of labels** is a `List`, as in
  `ui.segmented("filter", %("All" "Open" "Done"), filter)`.

Blocks nest, and a block form applies to the statement after it, as an
`if` does. `ui.id (key)` keeps the components drawn for different keys
apart. In this loop from `examples/todo.x`, two tasks with the same title
keep separate checkboxes:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
for (int i = 0; i < (int) s.tasks.len(); i++) {
  Task task = s.tasks[i];
  ui.id (i)
  ui.row (gap: 8, align: center, width: fill) {
    ui.checkbox(task.title, task.done);
    ui.spacer();
    if (ui.icon_button(x, tooltip: "Delete", variant: ghost, size: sm))
      s.removed = i;
  }
}
```

A block's end call is deferred, so it also runs when the block leaves
through `return`, `break`, or `continue`. A component that reports whether
it is open, such as `ui.dialog` or `ui.menu`, runs its block only while it
is open:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
ui.dialog ("Clear finished tasks?", s.confirm_clear, width: 380)
ui.dialog_footer () {
  if (ui.button("Cancel")) s.confirm_clear = false;
  if (ui.button("Clear", variant: danger)) {
    s.tasks = s.tasks.list().filter(%!(Task task) => !task.done);
    s.confirm_clear = false;
  }
}
```

Text that a component edits is a `TextField`, a buffer of fixed capacity
made by `TextField.new(96)`. `field.text()` returns its text,
`field.take()` returns the text and clears the field, and `field.empty()`
tests it. `ui.input` returns flags. A flag test is not a component
option, so it spells the CUI constant:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
ui.row (gap: 8) {
  int typed = ui.input("new-task", s.draft,
                       placeholder: "Add a task", width: fill);
  bool add = ui.button("Add", variant: primary, icon: plus,
                       disabled: s.draft.empty());
  if ((add || typed & CUI_SUBMITTED) && !s.draft.empty())
    s.tasks.push(Task.new(s.draft.take(), false));
}
```

## Lists and tables

`ui.each (T x in items, key: expression)` runs its block once for each
element and declares `x` as `foreach` does. Each pass pushes an id made
from `key:`, so a row keeps its state when the list is filtered or
reordered. `ui.item (row, selected: ...)` is an interactive row. It draws
a quiet fill when selected or hovered, Tab reaches it, and Enter or Space
clicks it. `row` is a `RowState` with `hovered`, `pressed`, and `clicked`
for this frame:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
ui.each (Message m in s.messages, key: m.id)
ui.item (row, selected: s.selected == m) {
  if (row.clicked) {
    s.selected = m;
    m.unread = false;
  }
  ui.column (gap: 3, width: fill, pad_y: 8) {
    ui.text(m.from, font: m.unread ? medium : body);
    ui.text(m.subject, size: 12, color: text_secondary);
  }
}
```

An item stacks its children on top of one another, so a row of several
components puts them in one `ui.column` or `ui.row`. Each arm of
`m.unread ? medium : body` is a short value for the `font` option.

`ui.table` takes its columns as a Map literal of titles and widths. A width
is pixels, `fill`, `fit`, or `grow(w)`; `right(w)` and `center(w)` align
a column, and `unsorted(w)` keeps a column from sorting. `ui.table_row`
begins a row, and `ui.cell () { ... }` and `ui.cell_text(text)` are its
cells. Clicking a header writes the column and direction into the
`cui_table_sort` that `sort:` points to; the program sorts its own rows:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
ui.table ("orders", sort: &s.sort, selectable: true,
          columns: {"Order": 90, "Customer": fill, "Amount": right(110)})
ui.each (Order o in s.orders, key: o.id)
ui.table_row (row, selected: s.chosen == o) {
  if (row.clicked) s.chosen = o;
  ui.cell_text(o.id);
  ui.cell () ui.avatar(o.customer, size: 28);
  ui.cell_text(o.price);
}
```

`examples/orders.x` sorts by `s.sort.column` before drawing. The README
also describes the data grid, which draws only the rows on screen.

## Data the UI changes

Some components read an array of CUI's own records, such as a tab bar's
tabs or a chart's bands. Constant data is an Array literal of Map literals,
written where the component takes the array. The form lowers each field
as it lowers options and passes the count:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
ui.tab_bar("tabs", [{icon: house, label: "Home"},
                    {icon: search, label: "Search"}], selected);
```

The literal becomes a `static const` C array, so every element must be a
constant. The form refuses a variable or a function call in an element.

`T.of(name: value ...)` builds one record of a CUI type with the same
short values: `cui_reaction.of(icon: heart, count: 4)` is a
`cui_reaction`.

Data a program keeps, and every array a component writes into, is a
collection. A collection packs CUI's records in one block that the
component reads and writes in place. `Reactions` holds `cui_reaction`
records:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
static Reactions reactions = Reactions.of([
  {icon: thumbs_up, count: 12, active: true}, {icon: heart, count: 4}]);

static int collection(Ui ui) {
  ui.reactions("reactions", reactions);
  reactions[1].count += 1;
  reactions.push(cui_reaction.of(icon: rocket, count: 7));
  reactions.remove(0);
  int total = 0;
  foreach (cui_reaction *r in reactions) total += r.count;
  return total;
}
```

`c[i]` is a pointer to record `i`, so `c[i].count += 1` changes it in
place. `c.len()` counts the records; `push`, `insert`, and `remove` grow
or shrink the collection; and `foreach` visits a pointer to each record.
`c[i]` stays valid until the collection grows. Change a collection
between frames, or after the call that passes it. The README lists all
28 collections, from `CalEvents` to `VizItems`.

A program declares a collection of its own record with two lines.
`$x2cui.collection(People, Person)` declares the type `People` and
`People.of`, and `$x2cui.records(Person, People)` declares the
operations. `$x2cui.record(Person)` adds `Person.of(name: value ...)`. A
field of a CUI type, such as `tone` here, takes the same short values as
a component's option:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
typedef struct Person {
  const char *name, *role;
  cui_tone tone;
} Person;

$x2cui.collection(People, Person);
$x2cui.records(Person, People);
$x2cui.record(Person);

static People people = People.of([
  {name: "Jonas Berg", role: "Owner", tone: success},
  {name: "Priya Nair", role: "Admin", tone: warning}]);

static void promote(void) {
  people.push(Person.of(name: "Aiko Tanaka", role: "Editor", tone: danger));
  people[0].role = "Founder";
  foreach (Person *p in people) printf("%s %s\n", p.name, p.role);
}
```

## Drawing without a window

`Offscreen` draws frames with CUI's software renderer into pixels and
writes them as a PNG file. It needs no display, so the package's tests
and examples use it to check a screen:

<!-- ignore: an import needs the built x2cui package archive. -->
```x2c,ignore
Offscreen screen = auto Offscreen.open(520, 640);
for (int frame = 0; frame < 3; frame++) {
  screen.begin();
  draw(screen.ui(), state);
  screen.end();
}
screen.write_png(argv[2]);
printf("%s: %d draw commands\n", argv[2], screen.commands());
```

Write the drawing as one function that takes a `Ui`, and call it from
both the window loop and the off-screen loop. The first frame measures,
and later frames settle layout and animations, so draw a few frames
before writing. `screen.commands()` is the number of draw commands in the
last frame. `write_png` raises `<io-fail>` when it cannot write.

A test can also drive input with CUI's own `ui.input_mouse_move`,
`ui.input_mouse_button`, and `ui.input_text` between frames.

## Examples

The examples are in `packages/x2cui/examples`. The `builds/` paths below
are relative to `packages/x2cui`. `make -C packages/x2cui run` draws the
to-do list, the mail list, the orders table, and every scene off screen:

- `todo.x` is a to-do list. It adds a task from a text field, filters
  the list, removes a task, confirms before clearing the finished tasks,
  and saves the list to a file after each change.
  `make -C packages/x2cui run-interactive` opens it in a window, and
  `builds/todo --shot IMAGE.png` draws three sample tasks.
- `mail.x` is a mail message list: `ui.each` over the messages of one
  folder that match a search, one `ui.item` row each, with a context
  menu. `builds/mail --shot IMAGE.png` draws the inbox.
- `orders.x` is a table of recent orders with a Map of columns, sorted
  by the header clicked. `builds/orders --shot IMAGE.png` draws it.
- `gallery.x` is a port of CUI's own gallery: the same 26 pages, with each
  page in a file under `examples/gallery/`. Read a page beside its C
  original to compare the two forms. `make -C packages/x2cui run-gallery`
  opens it, and `builds/gallery --shots DIR` draws every page. Each page
  drawn that way is the same image, byte for byte, as CUI's C gallery.
- `stress.x` animates as many moving circles or cards as its slider asks
  for and shows the frame rate. `make -C packages/x2cui run-stress` opens
  it. `builds/stress --frames N` times N frames off screen and prints the
  means.
- `scenes.x` is a check, not an application. It draws one small scene for
  each of CUI's 201 components, and `--check` fails when a component in
  CUI's header has no scene.

The gallery and the stress test also run in a browser, from the same x2c
source. The browser build needs Emscripten and x2c's browser runtime:

```sh
make wasm-runtime                 # at the repository root, once
make -C packages/x2cui web-serve  # then open http://127.0.0.1:4399/
```

`http://127.0.0.1:4399/?stress` opens the stress test. The program is
64-bit WebAssembly drawn with WebGL 2. The browser must support 64-bit
WebAssembly memory and JavaScript Promise Integration. The build has run
in a Chromium-based browser and under Node.

## The native API

Importing the package also makes CUI's C API available under its own
names, through the published header `src/cui-1.3.h`. `Ui` is CUI's
`cui_ctx *` and `App` is its `cui_app *`, so a raw CUI call and a method
form can act on the same object. `tests/test-raw-api.x` calls CUI's C
functions directly after `import "x2cui"`.

Use the native API for what has no x2c form:

- functions that fill a caller's buffer without a `cui_ctx`, such as
  `cui_terminal_init`, `cui_log_init`, and `cui_fs_list`;
- a comparison, flag test, or assignment on a CUI enum, which spells the
  constant, as in `status == CUI_STATUS_BUSY`;
- a custom renderer through `cui_renderer_iface`, and a custom platform
  layer.

The package has no Lisp bindings, because a `Ui` is a native object that
lasts across frames.

## Limits

- The package is experimental. Native builds are supported on macOS arm64
  and Linux arm64 and x86_64. On Linux the package passes its off-screen
  checks; the windowed path has not been tested there.
- There is no release bundle; build the package from a checkout.
- The browser build needs Memory64, JavaScript Promise Integration, and
  WebGL 2.
- CUI has no accessibility tree, no inline input-method composition, and
  no bidirectional text.
- A program draws from one thread. The package keeps one unlocked table,
  shared by every `Ui`, of the arrays it builds for Lists of Strings.
- The package applies two patches to CUI, `table-row-state` and
  `focusable-canvas`, and an upgrade of CUI must remake them.
  `PROFILE.md` describes both.

## Where to go next

- [Packages](packages.md) covers building, installing, and importing
  packages.
