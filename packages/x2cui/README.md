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
  App app = auto App.open({ .title = "Hello", .width = 420, .height = 300 });
  bool notify = true;
  int clicks = 0;
  while (app.frame()) {
    Ui ui = app.ui();
    $cui.column(ui, { .pad = 24, .gap = 12 }) {
      ui.heading("Hello, CUI", 2);
      ui.switch("Notifications", notify, {});
      if (ui.button("Click me", { .variant = CUI_BUTTON_PRIMARY })) clicks++;
      ui.text(%"Clicked $clicks times.", {});
    }
  }
  return 0;
}
```

CUI's records, enums, constants, and icons, such as `cui_box`,
`CUI_BUTTON_PRIMARY`, `CUI_FILL`, and `CUI_ICON_PLUS`, arrive under their
own names through the published `src/cui-1.3.h`. The package's own types,
`Ui`, `App`, `Offscreen`, and `TextField`, are `x2cui__*` names and need
`with` or the alias.

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
| `cui_button(ui, "Add", .variant = CUI_BUTTON_PRIMARY)` | `ui.button("Add", { .variant = CUI_BUTTON_PRIMARY })` |
| `cui_checkbox(ui, "Done", &task->done)` | `ui.checkbox("Done", task.done, {})` |
| `cui_input(ui, "name", buf, sizeof buf, .width = CUI_FILL)` | `ui.input("name", field, { .width = CUI_FILL })` |
| `cui_segmented(ui, "view", items, 3, &index)` | `ui.segmented("view", %("All" "Open" "Done"), index, {})` |
| `cui_row(ui, .gap = 8) { ... }` | `$cui.row(ui, { .gap = 8 }) { ... }` |

- **Options** are the last argument and are always written: `{}` means all
  defaults. Field names are those of CUI's option record.
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
- **A block component** is a statement decorator. Its end call is deferred,
  so it also runs when the block leaves through `return`, `break`, or
  `continue`. CUI's own C macros skip the end call there. A component that
  reports whether it is open, such as `$cui.dialog` or `$cui.menu`, runs
  its block only while open. Decorators stack:

  ```x2c
  $cui.id_index(ui, i) $cui.row(ui, { .gap = 8 }) {
    ui.checkbox(task.title, task.done, {});
  }
  ```

The methods are built at compile time from CUI's C signatures by
`src/x2cui-generate.x`. To read a method's exact signature, find
`x2cui__Ui_NAME` in `builds/x2cui.h` after `make build`.

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

`App.open` opens a window and raises `<init-fail>` when it cannot.
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

A `Ui` belongs to one thread. Several windows each on their own thread are
allowed by CUI; this package does not test that.

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

A component such as a table, a chart, or a calendar reads an array of
CUI's own records. In x2c that array is a C array of those records,
written with designated initializers, and `$cui.count` supplies its count:

```x2c
static cui_tab_bar_item tabs[] = {
  { CUI_ICON_HOUSE, "Home" }, { CUI_ICON_SEARCH, "Search" } };
ui.tab_bar("tabs", tabs, $cui.count(tabs), selected, {});
```

The array may be static, a local, or a variable-length array filled from
a collection. CUI writes into the array of a component that edits its
records, such as a calendar whose events are dragged. `$cui.count` of a
pointer does not compile; a program that holds a pointer passes its own
count.

Two block components take the array itself and supply the count:
`$cui.table(ui, id, columns, opts) { ... }` and
`$cui.data_grid(ui, id, columns, rows, first, last, opts) { ... }`. The
data grid draws only the rows on screen, from `first` up to `last`.

Chart numbers may also be a packed `ArrayFloat`:
`cui_series.of(name, values)` builds a series over one, and
`ui.donut_chart` and `ui.sparkline` take one. A chart's x axis labels are
a `List` parameter.

`tools/gen-arrays.py` writes the methods of these components from the
pinned header, with CUI's parameter names.

An option record keeps its C field types. A field that is a pointer to
caller state takes an address, as in `{ .toggle = &bold }`, and a field
that is an array takes a C array.

A tree leaf has no open flag: `ui.tree_begin(name, NULL, { .leaf = true })`.

A callback that CUI calls, such as a canvas paint function, is an ordinary
function. Where its type names `cui_ctx *`, declare that parameter as
`cui_ctx *` and assign it to a `Ui` to call methods.

## What has no x2c form

Functions that fill caller buffers without a `cui_ctx`, such as
`cui_terminal_init`, `cui_log_init`, and `cui_fs_list`, are called as C.

## No Lisp surface

A `Ui` is a native object that lasts across frames, and every component
call acts on it. This package has no Lisp bindings.

## Examples

`examples/todo.x` is the short application (`make short-example`). It
keeps tasks in an `Array`, adds one from a text field, filters the list,
removes a task, confirms before clearing the finished ones, and saves the
list to a file after each change. `make run-interactive` opens it.
`todo --shot IMAGE.png` draws three sample tasks off screen.

`examples/gallery.x` is the broader application (`make example`). It is
a port of CUI's own gallery, `examples/gallery_ui.c` and
`examples/gallery_more.c` in CUI's source: the same 26 pages, sections,
and layout, with each page in a file under `examples/gallery/`. Read a
page beside its C original to compare the two forms. `make run-gallery`
opens it, and `gallery --shots DIR` draws every page off screen. Drawn
that way, each page is the same image, byte for byte, as the same page of
CUI's C gallery.

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

`make web` writes `builds/web/gallery.js`, `gallery.wasm`, and
`index.html`. It needs Emscripten. The program is 64-bit WebAssembly and
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
