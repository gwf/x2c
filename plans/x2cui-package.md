# x2cui: a first-class x2c package over CUI

> Status: in progress on the long-lived branch `x2cui`, 2026-11-10.
> Gary accepted the plan's decisions and the to-do example. Delivery 0 is
> published on `dev` (gwf/x2c#653). Delivery 1 is on `x2cui`; see
> [Delivery 1 progress](#delivery-1-progress). Nothing in this plan is on
> `dev` except Delivery 0.
> Baseline: x2c `239408687`, CUI `v1.3.1`.
> Every "verified" statement below was compiled and run on macOS arm64.
> Statements marked "not verified" were not.

## Result

`import "x2cui"` gives an x2c program all of CUI: a UI library with about 190
drawn components, its own software and OpenGL renderers, and its own window
layer. The package keeps CUI's C implementation and wraps it. It does not
fork or rewrite CUI.

A program written with x2cui contains no C plumbing at the call site:

```x2c
import "x2cui" with App, Ui, TextField;

static void draw(Ui ui, Array tasks, TextField draft) {
  $cui.column(ui, { .pad = 24, .gap = 12, .width = CUI_FILL }) {
    ui.heading("To do", 2);
    $cui.row(ui, { .gap = 8 }) {
      ui.input("new-task", draft, { .placeholder = "Add a task" });
      if (ui.button("Add", { .variant = CUI_BUTTON_PRIMARY }) && !draft.empty())
        tasks.push(Task.new(draft.take()));
    }
    for (int i = 0; i < (int) tasks.len(); i++) {
      Task task = tasks[i];
      $cui.id(ui, i) ui.checkbox(task.title, task.done, {});
    }
  }
}

int main(void) {
  Array tasks = [];
  TextField draft = TextField.new(96);
  App app = auto App.open({ .title = "To do", .width = 520, .height = 640 });
  while (app.frame()) draw(app.ui(), tasks, draft);
  return 0;
}
```

This program is a sketch. Each construct in it was verified separately; see
[Evidence](#evidence). `TextField` and `App` do not exist yet.

## Settled choices

Gary decided these on 2026-11-10:

- Wrap CUI; do not rewrite it in x2c. The rewrite study estimated a 5 to 20
  percent line reduction and the loss of CUI's native Windows build, its
  small binary, and its C distribution.
- Containers use the qualified `$cui.` macro form. The package declares no
  `keyword` aliases.
- Labels are ordinary Strings in the process pool. No per-frame pool.
- No Lisp surface in this plan.
- Completeness is measured against CUI's own component list, and a check
  counts it.
- The component gallery is a deliverable.
- A browser build is in scope.

Windows stays out. x2c packages support macOS and Linux only.

## Evidence

Planning probes are short programs built with `builds/0/x2c` against CUI.
The essential ones are reproduced in [Appendix A](#appendix-a-probe-sources)
because the planning scratch directory is temporary.

Verified:

1. A zero-wrapper x2c program calls CUI and renders headless. Its PNG is
   byte-identical to the plain C build of the same program.
2. One program used all of these together and rendered the expected image:
   `$cui.column(ui, { ... }) { ... }` with a bare brace option argument, the
   empty option form `{}`, a `bool &` state parameter, chained decorators
   (`$cui.id(ui, i) $cui.row(ui, { ... }) { ... }`), `continue` inside a
   container with a `defer`red end call, and a conditional container
   (`$cui.dialog`).
3. One compile-time function builds a component method from the type of the
   C function. From `cui_slider_ex` it produced
   `bool Ui.slider(Ui, String, float &, float, float, cui_slider_opts)`.
   Four generated components built and ran.
4. CUI's release tool `tools/amalgamate.py` writes one `cui.c`. It compiles
   in one step in 10 seconds with
   `cc -O2 -x objective-c -fobjc-arc -D_DARWIN_C_SOURCE`. A program linked
   against it renders the same PNG as one linked against the CMake build.
5. x2c reads all 4,518 lines of `cui.h`. Translating a unit that includes it
   costs about 40 ms more than an empty unit.

6. The headless program builds for the browser target with the existing
   `tools/wasm-build` and runs under Node. Its PNG is byte-identical to the
   native PNG. An interactive build with CUI's SDL2 window layer links and
   runs under Node with a stub page; a synthetic click updated the label.

Not verified: an open window on any platform, a real browser, frame time,
Linux, and the `TextField` type.

Census of the pinned `cui.h` (script in Appendix A):

| Item | Count |
| --- | --- |
| Public functions in `cui.h` | 471 |
| Functions whose first parameter is `cui_ctx *` | 433 |
| Variadic or `va_list` functions | 5 |
| Component macros (`#define cui_name(...)`) | 205 |
| ... regular widgets | 96 |
| ... containers (begin/end) | 36 |
| ... text widgets (`char *buf, size_t cap`) | 13 |
| ... string-list widgets (`const char *const *, int`) | 11 |
| ... record widgets (array of C structs) | 41 |
| ... other array or pointer inputs | 8 |

No pair of functions collides under the method naming rule below.

## Compiler prerequisites

Three x2c defects were found. Each is separate `fix-x2c-bug` work delivered
to `dev` on its own. The package work does not repair them.

**P1. An unseen prefix macro before a type name misreads a collected
header. Blocked the package. Repaired in gwf/x2c#653, submitted to the
integrator on 2026-11-10 and not yet published.** x2c could not read
`cui_app.h` or `cui_render.h`.

```c
/* api.h */
#define API
typedef struct handle handle;

/* device.h */
#include "api.h"
API handle *open_device(void);      /* was read as a variable named handle */
API bool ready(handle *device);     /* was: parse: expected ')' */
```

Cause: collection walks each included file in a compiler of its own, so a
macro that `api.h` defines has no visible definition in `device.h`.
`_unseen_prefix` in `src/parse/types.x` read such a name as a prefix only
before a declaration keyword. Before a type name the parser took the prefix
as the type and the type as the declared name. That shadowed the type, and
a declaration such as `API bool ready(void);` was dropped with no
diagnostic. The repair reads an undeclared name before a second name that a
declarator follows as a prefix.

With the repair, a program that includes all four CUI headers through the
shim builds and runs, and x2c checks calls to `cui_app_*` and `cui_sw_*`
declarations by arity and type. Verified.

The repair covers collected `.h` files. A unit that itself writes a
declaration with a prefix macro from an included header still fails. The
package does not need that case.

**P2. `expand` over a macro whose body splices a meta result crashes the
compiler. Does not block.** The compiler exits with status 139 and no
diagnostic:

```x2c
#include "x2c.x"
#include "meta.x"
meta static List make(String name) {
  List fn = x2c_ident(name);
  List unit = $!Unit{ int $fn(void) { return 1; } };
  return $(unit);
}
expand %("one" "two")
macro Unit(Literal $name) { @make($name) }
int main(void) { return one() + two() == 2 ? 0 : 1; }
```

The same macro given a name and invoked once per row works. x2cui uses named
invocations. If P2 is fixed first, the component table becomes one `expand`.

**P3. A user converter is skipped inside a designated initializer. Does not
block.** With `Sz int.sz(int)` and a field `Sz width`, `{ .width = 5 }`
emits `.width = 5` unchanged, and C brace elision sets the wrong member
without a diagnostic. A `Symbol` converter in the same initializer is
applied. x2cui does not depend on converters: sizes are written
`CUI_PX(560)`, as in C.

A header-defined string macro next to a string literal, as in
`CUI_ICON_CHECK " ok"`, does not parse in a unit, because the unit sees no
definition for the macro. Programs write `%"$(CUI_ICON_CHECK) ok"` or pass
the icon through an option field. Not planned.

Two smaller observations, reported but not planned: a `foreach (Type t in
types)` over `Type.parameters` yields an empty type where indexed access
works, and `Code.type` of an identifier built by `x2c_ident` returns the
identifier, so the generator takes the C function as a captured `Expr`.

## Specification

### Package layout

```text
packages/x2cui/
  Makefile
  dependency-darwin.json      CUI v1.3.1, window layer on Cocoa
  dependency-linux.json       CUI v1.3.1, window layer on X11
  headers.sha256  licenses.sha256
  LICENSES/                   CUI MIT, OFL 1.1 (Inter, Geist), ISC (Lucide),
                              Unicode V3, stb
  PROFILE.md  README.md
  src/cui-1.3.h               shim: includes the four CUI headers, version check
  src/x2cui.x                 App, Ui, Offscreen, TextField, errors
  src/x2cui-generate.x        the compile-time method generator
  src/x2cui-components.x      one generator row per CUI function; containers
  src/x2cui-records.x         Delivery 2: record and array widgets
  examples/todo.x             the screen-sized application
  examples/gallery.x          the gallery; examples/gallery/*.x hold scenes
  tests/test-x2cui.x  tests/test-raw-api.x  tests/test-gallery.x
```

The package is named `x2cui`, not `cui`. A package named `cui` would
generate `cui.h` and `libcui.a`, the names CUI itself uses.

### Native dependency

- Source: the GitHub archive of tag `v1.3.1` of `yappologistic/CUI`, pinned
  by sha256. The repository is public and MIT licensed.
- Build steps: `python3 tools/amalgamate.py {work}`, one `{cc}` compile of
  `cui.c`, one `{ar}`, then copy `include/cui/*.h`. Python 3 is already
  required by `packages/tools/deps.py`.
- macOS: compile with `-x objective-c -fobjc-arc -D_DARWIN_C_SOURCE`; link
  `-framework Cocoa -framework QuartzCore -framework OpenGL`.
- Linux: compile as C; link `-lX11 -ldl -lm -lpthread`. This needs X11
  headers on the build host. Not verified. If a gate host lacks them, the
  Linux manifest defines `CUI_NO_APP`, and `App` is unavailable there.
- One profile per platform. The gated check uses only the software
  renderer, so linking the window layer does not need a display.
- CUI's option structs change between minor versions. The package pins one
  version and compiles CUI from source, so layouts always agree.

### Types

| x2c type | Is | Owns | Release |
| --- | --- | --- | --- |
| `Ui` | `cui_ctx *` | nothing by itself | see `App`, `Offscreen` |
| `App` | `cui_app *` | window and its `Ui` | `close`, through `Cleanup` |
| `Offscreen` | package class | software renderer, `Ui`, pixels | `close`, through `Cleanup` |
| `TextField` | package class | one editable `char` buffer | ordinary x2c storage |

`Ui` and `App` are typedefs of CUI's own pointers. A raw CUI call therefore
takes them directly: `cui_textf(ui, "Elapsed: %.1f s", seconds)`. No
`native()` accessor is needed for them. `Offscreen.ui()` returns its `Ui`.

Upstream records, enums, constants, and macros keep their C names:
`cui_box`, `CUI_BUTTON_PRIMARY`, `CUI_FILL`, `CUI_PX(560)`, `CUI_ICON_PLUS`,
`CUI_SUBMITTED`. The package adds no Symbol or converter layer over them.

### Method rules

Every `cui.h` function whose first parameter is `cui_ctx *` has a `Ui`
method. A variadic function has a method that takes a List rest parameter;
see [Formatted text](#formatted-text).

Name: remove `cui_`; remove a trailing `_ex`. `cui_button_ex` is
`ui.button`; `cui_draw_rect` is `ui.draw_rect`.

Parameters map by C type, in order:

| C parameter | x2c parameter | Passed as |
| --- | --- | --- |
| `cui_ctx *` (first) | receiver `Ui` | itself |
| `const char *` | `String` | itself |
| `T *`, scalar or enum `T`, not const | `T &` | address |
| `const cui_X_opts *` or `const cui_box *` | `cui_X_opts` by value | address |
| `char *buf, size_t cap` pair | `TextField` | its buffer and capacity |
| `const char *const *items, int count` pair | `List` of Strings | stack array and length |
| anything else | unchanged | unchanged |

Results are unchanged: `bool` for clicked or changed, `int` flags for text
widgets, CUI's `cui_*_result` records by value.

Options are the last argument and are always written. `{}` means all
defaults. x2c has no default arguments, and a `Map` rest parameter would
allocate one Map per widget per frame.

The record and array widgets (49) do not follow these rules. Delivery 2
specifies them.

### Containers

Each of CUI's 36 block macros is one `$cui.` decorator macro over the
generated begin method:

```x2c
macro Decorator $cui.row(Stmt $body, Expr $ui, Expr $opts) {
  { $ui.row_begin($opts); defer cui_box_end($ui); $body }
}
macro Decorator $cui.dialog(
  Stmt $body, Expr $ui, Expr $title, Expr $open, Expr $opts) {
  { if ($ui.dialog_begin($title, $open, $opts)) {
      defer cui_dialog_end($ui); $body } }
}
```

CUI defines 23 block macros of the first kind (`CUI__SCOPE`) and 16 of the
second (`CUI__SCOPE_IF`). Of these 39, the census counts 36 as containers;
the other 3 take record arrays and belong to Delivery 2. The `defer` runs
the end call on `return`, `break`, and `continue`. CUI's C macros skip it
in those cases.

### Application lifetime

```x2c
App App.open(cui_app_desc desc);          // raises when the window fails
bool App.frame(App app);
Ui App.ui(App app);
void App.close(App app);                  // idempotent
```

`App.open` with a `while (app.frame())` loop is the only form. The package
does not wrap `cui_app_run`, so no x2c function is called back from C and
no Error can unwind through a C frame. The browser probe shows that a
blocking frame loop runs in the browser target when the program is linked
with `-sJSPI` or `-sASYNCIFY`; see Delivery 3.

The frame call is not wrapped in an `auto` region. An earlier version of
this plan and of the to-do example did that, and it was a defect: a task
added by a click was allocated in the frame's region and freed when the
frame ended, and the window crashed in `cui_checkbox_ex` on the next read
of its title. Drawing is where a program changes its state, so a frame
region frees live state. Drawing itself leaves nothing to free: the to-do
example holds 8.4 MB resident after 500 frames and after 16,000.

### Headless rendering

```x2c
Offscreen Offscreen.open(int width, int height);
Ui Offscreen.ui(Offscreen screen);
void Offscreen.begin(Offscreen screen);   // cui_begin_frame
void Offscreen.end(Offscreen screen);     // cui_end_frame, then render
void Offscreen.write_png(Offscreen screen, String path);   // raises on failure
```

It serves tests, the gallery check, and programs that produce images.

### Text fields

```x2c
TextField TextField.new(int capacity);
String TextField.str(TextField field);    // the current text as a String
String TextField.take(TextField field);   // returns the text and clears it
void TextField.set(TextField field, String text);
bool TextField.empty(TextField field);
```

A field edits in place in a fixed buffer, as CUI requires. The program
gets a String only when it asks. A String per keystroke would add one pool
entry per edit.

### Formatted text

Interpolated labels are the ordinary form. CUI's four variadic functions
also have methods: `ui.textf`, `ui.table_cell_textf`,
`cui_terminal_buffer.printf`, and `cui_log_buffer.append`. Each takes a
format and a List rest parameter, formats with `String.format`, and
passes the result to the C function through `"%s"`. Each formatted text
is a String in the global pool, as a label is. An earlier version of this
plan said variadic functions had no x2c form; that was wrong, because the
rest parameter was not tried.

### Errors

Only acquisition and file operations raise: `App.open`, `Offscreen.open`,
`Offscreen.write_png`, image loading, and font loading. Each raises
`%(cause (library "cui") (operation ...) (message ...))`. Widget outcomes,
a cancelled file dialog, and a closed window are ordinary results.

### Generator

`src/x2cui-generate.x` holds one `meta` function. It receives a C function
as captured code, reads its type with `Code.type`, `Type.parameters`, and
`Type.return_type`, applies the parameter table above, and returns the
method as a `$!Unit{ ... }`. `src/x2cui-components.x` is the table:

```x2c
$cui.method(cui_button_ex);
$cui.method(cui_checkbox_ex);
$cui.method(cui_draw_rect);
```

The method name comes from the function's spelling. A wrong row fails to
compile, because x2c checks the generated call against `cui.h`. Generated
parameters need real names for documentation and editor help; the row
supplies them where the positional default (`label`, `value`, `opts` by
type) is not enough. The exact row form is a routine implementation choice.

### Definition of complete

1. **Raw tier.** Every declaration in the four CUI headers is usable through
   `src/cui-1.3.h`. `tests/test-raw-api.x` calls representative ones.
2. **Component tier.** Each of the 205 component macros in the pinned
   `cui.h` has an x2c form with no C plumbing at the call site: no
   `&(type){...}` literal, no pointer and count pair, no `char` buffer with
   a capacity, and no manual end call.
3. **Gallery.** `examples/gallery.x` has one scene per component, named for
   it. `tests/test-gallery.x` reads the `#define cui_name(` lines from the
   pinned `cui.h` and fails when a component has no scene. The scene list
   is the only registry; the package keeps no second list.
4. **Rendering.** `gallery --shots DIR` draws every scene through
   `Offscreen` and writes one PNG each. The check requires a nonzero draw
   command count and a PNG of the requested size for every scene.
5. **Applications.** `examples/todo.x` is the short application. The
   gallery is the broader one.
6. **Outside the definition.** Lisp, Windows, and the custom renderer
   interface (`cui_renderer_iface`), which stays raw.

This replaces the task-list rule in `packages/AGENTS.md` for this package.
Gary still accepts the developer experience of `examples/todo.x` before the
package claims completion.

## Deliveries

Gary set the branch policy on 2026-11-10:

- All CUI-specific work lives on the branch `x2cui` and stays off `dev`
  until the whole package is proven. That covers `packages/x2cui`, this
  plan, and the package's entries in `packages/README.md` and the book.
- The x2cui session owns `x2cui` and merges into it at will. It does not
  go through the shared integrator. gwf/x2c#654, the first submission of
  Delivery 1 to `dev`, was withdrawn and closed.
- A change to x2c itself (compiler, runtime, tools, or shared package
  machinery) is never made on `x2cui`. It goes to `dev` as its own PR
  through the integrator, as Delivery 0 did. `x2cui` then takes it by
  merging `dev`.
- When the package is proven, `x2cui` is proposed to `dev` as a whole.

The package `check` target is the focused evidence for each delivery.

### Delivery 0: compiler fix P1

Done as gwf/x2c#653: the repair in `_unseen_prefix`, the reference
paragraph, and the extended `c-unseen-prefix-macro` fixture. Focused
evidence: that fixture, 91 header and preprocessor fixtures, `make
stage-2`, and the header cache probe. It waits for the integrator. P2 and
P3 are not repaired.

### Delivery 1: package, regular components, gallery

1. Dependency manifests, shim, Makefile, licenses, `PACKAGES` entry.
2. `App`, `Offscreen`, `TextField`, errors.
3. Write `examples/todo.x` against the intended surface and show it to
   Gary. Adjust the surface before generating the rest.
4. The generator and the table for the 433 `cui_ctx` functions.
5. The 36 container macros.
6. Text widgets (13) and string-list widgets (11) through the same
   generator.
7. The gallery with scenes for these 156 components, windowed and
   `--shots`.
   The render check runs now. The completeness test arrives with
   Delivery 2, when all 205 scenes exist; the package keeps no list of
   pending components.
8. Tests, README, PROFILE, a section in `docs/src/guide/packages.md`, and
   the package index.

Estimated size: about 450 lines of package source apart from the table,
about 470 table rows, about 2,500 lines of gallery, about 600 lines of
tests. These are estimates.

#### Delivery 1 progress

State on 2026-11-10, macOS arm64, branch `x2cui` at `dev` `239408687`
plus the package commits.

Done and verified:

- `make -C packages/x2cui check` passes: 11 tests, the to-do example drawn
  off screen, and 140 gallery scenes drawn off screen with none empty.
- `App`, `Offscreen`, and `TextField`.
- The generator and a table of 352 rows, plus two hand-written methods.
- 37 container macros.
- `examples/todo.x`. Its `draw` function was driven off screen through
  add, toggle, delete, filter, and clear with simulated input.
- `examples/gallery.x` with six scene families and 140 scenes. Each scene
  ran 400 frames under random mouse and keyboard input with freed memory
  scribbled, with no crash. The todo and gallery windows start and stay
  up; their contents were not inspected in a window.
- README, PROFILE, the package index, and the book's package guide.

Not done:

- Linux. `dependency.json` is unbuilt, so the package is not in
  `PACKAGES`.
- Parameter names. Generated methods name their parameters `p1`, `p2`.
- The completeness check, which arrived with Delivery 2 as
  `scenes --check`; see "Every component has a scene" below.
- Menus that open only on a click are drawn closed in `--shots`.

Facts that differ from the specification above:

- **The pinned tag has 201 component macros and 429 `cui_ctx` functions.**
  The census above read CUI's working tree, 14 commits after the tag.
- **75 functions wait for Delivery 2.** They take arrays of records,
  numbers, or flags, or are variadic. The 354 others have methods. They
  leave 61 of the 201 components for Delivery 2.
- **A List of Strings is kept as a native array for the process.** CUI
  reads a wheel picker's items when it paints, after the call returns, so
  an array on the method's stack crashed. `x2cui_strings` keeps one array
  for each distinct List; Lists are canonical, so the set is bounded by
  the distinct lists a program uses.
- **Option records keep their C field types.** A pointer field takes an
  address and an array field takes a C array.
- **The text method is `field.text()`.** `str` is a conversion name that
  x2c reserves, so the buffer member is `buffer` and the method is `text`.
- **A text result is a String.** Six functions return `const char *` into
  CUI's frame memory.
- **Container macros keep CUI's names**, for example `$cui.id_scope` and
  `$cui.disabled_scope`. `$cui.id_index(ui, i)` is the one addition, over
  `cui_push_id_int`. Each evaluates its `ui` argument once, through a
  `typeof` local, since gwf/x2c#657.
- **There is no frame region.** See Application lifetime. Gary hit the
  crash it caused on 2026-11-10. The cause was confirmed from the crash
  report and reproduced off screen; the corrected example was then driven
  through add, toggle, delete, filter, and clear with simulated input.
- **`dependency.json` is the Linux X11 profile and is untested.**
  `package.mk` requires a file of that name; `dependency-darwin.json` is
  the tested macOS profile.

Compiler observations from this work, none repaired and none blocking:

- A type name quoted in a meta function, `$!Param{ TextField $p }`, loses
  its package prefix in the emitted C. The generator takes the type from a
  package function's parameter instead.
- `Type.return_type` reports a `const T *` result without its `const`. Two
  methods with such results are written by hand.
- `"button_ex"[:-3]` yields `"button_"`. Whether that is the intended
  slice rule is not checked.

### Delivery 2: record and array widgets

75 functions and 61 components take arrays of records, numbers, or flags.

The rules first written here were: a packed typed Array for numbers, and a
`List` of rows for records, converted to a C array on each call. A study
of the 75 functions on 2026-11-10 showed the second rule does not hold:

- CUI writes into many record arrays: calendar events and Gantt tasks that
  are dragged, checklist steps, key-value pairs, curve keys, feature flags.
  A converted copy cannot carry those changes back.
- Many records hold fields a `List` row cannot: `cui_size`, `cui_color`,
  fixed `char` arrays, and nested arrays.
- CUI may read an array when it paints, after the call returns, so a
  converted copy needs storage that lasts the frame.

Revised rules, built and verified for the line chart, bar chart, table,
and data grid:

- **An array of CUI records is a C array of those records**, written with
  designated initializers. A `$cui.` macro takes the array itself and
  supplies its count with `$cui.count`, so no call site writes one.
  `$cui.count` of a pointer does not compile. The array may be static, a
  local, or a variable-length array filled from a collection. CUI writes
  into the caller's own array. This needs no copy, no converter, and no
  frame storage.
- **A method of the same name takes the pointer and the count**, for a
  program that holds its records another way.
- **Numbers are a packed `ArrayFloat`.** `cui_series.of(name, values)`
  builds a chart series over one, so no record holds a count by hand.
- **Rows of data stay in x2c collections.** A table or grid block draws
  each row from a `List` or `Array`, as the gallery scenes do.
- **An array option that every use needs becomes a parameter.** A chart's
  x axis labels are a `List` parameter, not two option fields.

Gary reviews the chart, table, and data grid scenes in
`examples/scenes/data.x` before the other components are converted. That
review is still open.

#### The gallery is a port of CUI's gallery

On 2026-11-10 Gary ran the first x2c gallery and found it did not look
like CUI's. It was not a port: it showed one component at a time, modeled
on CUI's `tests/component_shots.c`, where CUI's gallery shows many
components on topic pages. Gary chose to have both:

- `examples/gallery.x` is a port of CUI's `examples/gallery_ui.c` and
  `examples/gallery_more.c`, page for page, with each page in a file under
  `examples/gallery/`. It is the application to browse and to read beside
  the C original.
- `examples/scenes.x` keeps the per-component scenes as a check that draws
  off screen and opens no window. The completeness test compares its
  scene names with CUI's header.

State on 2026-11-10: the frame and all 26 pages are ported.

- **Fidelity.** `gallery --shots` draws each page on a 1240 by 4800
  surface. Each of the 26 images is byte-identical to the same page of
  CUI's C gallery drawn the same way.
- **Stability.** The gallery ran 26,000 frames under random mouse,
  keyboard, and scroll input with freed memory scribbled, at wide and
  narrow widths, with no crash.
- **Memory.** Resident memory is flat over 20,000 or more frames a page,
  as the C gallery's is. An earlier version grew up to 250 bytes a frame:
  the string-list table was a `Map`, which boxed an address on every
  lookup. It is now a small open-addressed table.
- **Size.** 3,670 lines of x2c for 2,497 lines of C. The C lines run to
  180 columns and the x2c lines stop at 79.
- Nobody has operated the extended pages in a window.

#### Every component has a scene

State on 2026-11-10: `examples/scenes.x` has 201 scenes, one for each of
the 201 component macros in the pinned `cui.h`.

- **The check.** `scenes --check HEADER` reads the `#define cui_NAME(`
  lines of the header and fails when a component has no scene or a scene
  names no component. `make run`, and so `make check`, runs it against
  the pinned header. It replaces the `tests/test-gallery.x` that this plan
  specified: the scene table is in the `scenes` program, so the program
  checks itself and the package keeps no second list.
- **The families.** `viz.x` (19 scenes), `devtools.x` (18), and
  `choices.x` (20) hold the 57 scenes added for the array components.
  All 201 scenes draw, none empty, also with freed memory scribbled.
- **Names.** `ui.prop_vec2`, `ui.prop_vec3`, and `ui.prop_vec4` were
  added so each of those components keeps its CUI name.
- `cui_flame_sort` and `cui_trace_sort` take an array and no `cui_ctx`
  and are called as C.
- The week calendar reads the system clock, so its image changes with
  the date. The file browser and file picker images change with the
  directory they list.

#### The array form after the port

Gary accepted C arrays of CUI records on 2026-11-10. Porting the gallery
then settled the call form:

- `tools/gen-arrays.py` writes one `Ui` method for each of 62 array
  components from the pinned header, with CUI's parameter names. A call
  passes the array and `$cui.count(array)`.
- A first version also generated 59 `$cui.` macros that took the array
  whole. The seven workers who ported the pages used them 16 times and
  used `$cui.count` with a method 57 times, because CUI's gallery ignores
  most results and x2c does not let a value-returning macro stand alone as
  a statement. The macros were removed. `$cui.table` and `$cui.data_grid`
  remain, because they are blocks.
- The functions that fill caller buffers without a `cui_ctx` have no form
  and are called as C. The variadic functions have methods; see
  [Formatted text](#formatted-text).

### Delivery 3: browser

Goal: the gallery runs in a browser from the same x2c source, through
x2c's existing browser target (`make wasm-runtime`, `tools/wasm-build`,
Emscripten Memory64).

CUI's own web build cannot be reused. It uses plain `clang --target=wasm32`
with its own libc and JavaScript host, and x2c output needs Emscripten.
CUI's C is compiled with Emscripten instead. See
[Browser probe results](#browser-probe-results) for what already works.

Work:

1. **x2c: package support in the browser build.** `tools/wasm-build`
   translates one `.x` file and links only the runtime. A program that
   imports a package fails at the C compile
   (`'autodiff.h' file not found`). It needs the package's include
   directories, its translated sources, a browser archive per package, and
   extra flags that add to the defaults. This is a change to x2c tooling
   and needs its own short design.
2. **A browser dependency profile for CUI.** The CUI sources plus
   `cui_app_sdl2.c`, compiled with `emcc -m64`, linked with `-sUSE_SDL=2`
   and `-sJSPI`. Emscripten downloads its SDL2 port (zlib license) on first
   use; the license review covers it.
3. **WebGL.** The software renderer works. The OpenGL path links but is
   unverified: CUI's SDL2 layer requests a desktop core profile, and it
   probably must request an ES 3.0 context under Emscripten. That would be
   a patch carried in the manifest's `inputs`, or a change proposed
   upstream.
4. **Host page.** Canvas, focus and keyboard, HiDPI, resize, and a notice
   for browsers without Memory64 or JSPI.
5. **Verification in a real browser**, including keyboard and text input.

#### Delivery 3 state

State on 2026-11-10: the gallery runs in a browser from the same source.

- **No change to x2c was needed.** Item 1 above was wrong about the
  route. `x2c build -c --cc <wrapper>` already compiles a program that
  imports a package to objects for another compiler, with the package's
  include directories. The package's `Makefile` compiles the gallery and
  the package that way through `tools/wasm-cc`, and links with Emscripten.
  `tools/wasm-build` is unchanged and still handles one file without
  packages.
- **Profile.** `dependency-wasm.json` builds CUI with its SDL2 window
  layer through the shared dependency cache, with `CC=emcc AR=emar`.
- **WebGL.** `patches/web-opengl-es.patch` makes CUI's SDL2 layer ask for
  OpenGL ES 3.0 under Emscripten. With it the gallery draws through
  WebGL 2 at the display's full density. Without it CUI fell back to the
  software renderer and drew into a quarter of the canvas.
- **Host page.** `web/index.html` gives the canvas the whole window and
  the keyboard focus, and names the missing feature in a browser without
  64-bit memory or JavaScript Promise Integration.
- **Verified in the Claude desktop app's browser pane (Chromium):** the
  gallery opens; a click changes the page; keys type into a field and
  Backspace deletes; the wheel scrolls the page under the pointer; the
  dark theme applies; resizing the window resizes the canvas.
- **Verified under Node:** `make web-check` draws all 26 pages. 22 match
  the native images to within one step of one colour channel. Four
  differ where the platform differs: the order of two table rows with
  equal sort keys, Ctrl for Cmd in two places, and the listed directory.
- **Size.** `gallery.wasm` is 2,576,741 bytes, 1,034,111 with `gzip -9`.

Not done or not verified:

- Safari and Firefox were not run.
- Pasting, an input method editor, and touch input were not tested.
- The to-do example has no browser build; it saves to a file, which a
  browser page does not keep.
- The software fallback draws at quarter size on a high-density display.
  It is reached only when WebGL 2 is unavailable.
- The browser checks are outside `make check`, which needs no Emscripten.

Compiler observation: `-Xcc` arguments also reach the meta compiler that
`--meta-cc` names. `-Xcc -m64 -Xcc -sUSE_SDL=2` with `--cc emcc
--meta-cc cc` fails in the meta build with clang's "unknown argument".
The wrapper `tools/wasm-cc` carries the flags instead.

## Decisions accepted

Gary accepted these on 2026-11-10:

1. **License admission.** SIL OFL 1.1 (the embedded Inter and Geist fonts)
   and the Unicode License V3 (generated Unicode data) are admitted for the
   x2cui profile. `LICENSES/` carries both, and `PROFILE.md` records the
   admission. The default fonts stay enabled.
2. **Developer experience.** The Result example is the target surface.
   `examples/todo.x` is still shown running before the package claims
   completion.
3. **Options argument.** Every widget call ends with an options argument,
   `{}` when empty. There is one method per widget.

## Risks

- CUI's first commit is dated 2026-11-05. It has had four releases in five
  days. A pin goes stale quickly; each version bump reruns the completeness
  check, which names added and removed components.
- No package has shipped an interactive window. The window path cannot be
  gated; it is checked by hand with `make run-interactive`.
- Linux is not verified at all.
- The x2c runtime adds about 385 KB stripped to a native executable in the
  probe build (422 KB for the C program, 807 KB for the x2c one), and about
  860 KB to a browser build.
- The browser build needs Memory64 and JSPI in the browser, or the larger
  Asyncify build.
- Frame time through the wrappers is not measured. The wrappers are inline
  forwarders that copy one option struct per call.

## Browser probe results

Run on 2026-11-10 with emcc 6.0.13 and Node 26, flags
`-fsigned-char -Os -m64 -sSUPPORT_LONGJMP=emscripten`.

- `make wasm-runtime` and the documented sample work on this machine.
- CUI's 54 core source files compile under `emcc -m64` with no warnings.
- The headless x2c program links with
  `WASM_CFLAGS="<defaults> -I CUI/include" WASM_LDFLAGS=libcui.a
  tools/wasm-build main.x out`. Under Node it prints the native counts
  (`vertices=196 indices=336 cmds=20`), and its PNG is byte-identical to
  the native PNG.
- The software renderer tries to start threads for large frames. Without
  `-pthread` the attempt fails and CUI falls back to one thread. CUI's own
  web host calls `cui_sw_set_threads(sw, 1)` to skip the attempt.
- Emscripten's SDL2 port builds under `-m64`. An x2c counter program using
  `cui_app_run` and CUI's SDL2 window layer links with `-sASYNCIFY` or
  `-sJSPI`. Under Node with a stub page, a synthetic click changed its label
  from "0 clicks" to "1 clicks". It was not run in a browser.
- Without Asyncify or JSPI the frame loop would busy-wait and freeze the
  page.

Sizes of the `.wasm` file:

| Build | Bytes | gzip -9 |
| --- | --- | --- |
| x2c runtime alone (empty program) | 861,538 | 304,365 |
| CUI headless program in plain C | 253,172 | 174,878 |
| The same program in x2c | 1,082,689 | 464,688 |
| Interactive counter, `-sJSPI` | 1,682,106 | 631,659 |
| Interactive counter, `-sASYNCIFY` | 2,788,852 | 869,840 |

The x2c runtime is about 80 percent of the headless build, because
`tools/wasm-build` links it with `--whole-archive`.

## Appendix A: probe sources

**Forms probe (evidence item 2).** Built with
`x2c build -I CUI/include -o q1 q1.x libcui.a` and run headless.

```x2c
typedef cui_ctx *Ui;

inline void Ui.label(Ui ui, String text) => cui_label(ui, text);
inline bool Ui.button(Ui ui, String label, cui_button_opts opts) =>
  cui_button_ex(ui, label, &opts);
inline bool Ui.checkbox(Ui ui, String label, bool &value, cui_check_opts opts) =>
  cui_checkbox_ex(ui, label, &value, &opts);
inline void Ui.column_begin(Ui ui, cui_box opts) => cui_column_begin(ui, &opts);
inline void Ui.row_begin(Ui ui, cui_box opts) => cui_row_begin(ui, &opts);

macro Decorator $cui.column(Stmt $body, Expr $ui, Expr $opts) {
  { $ui.column_begin($opts); defer cui_box_end($ui); $body }
}
macro Decorator $cui.row(Stmt $body, Expr $ui, Expr $opts) {
  { $ui.row_begin($opts); defer cui_box_end($ui); $body }
}
macro Decorator $cui.id(Stmt $body, Expr $ui, Expr $key) {
  { cui_push_id_int($ui, $key); defer cui_pop_id($ui); $body }
}

class Item { String title; bool done; } *;
void Item.init(Item item, String title) { item.title = title; }

static void frame(Ui ui, Array items) {
  $cui.column(ui, { .pad = 24, .gap = 12, .width = CUI_FILL }) {
    ui.label("Hello");
    ui.button("Save", { .variant = CUI_BUTTON_PRIMARY });
    ui.button("Plain", {});
    for (int i = 0; i < (int) items.len(); i++) {
      Item t = items[i];
      $cui.id(ui, i) $cui.row(ui, { .gap = 8 }) {
        ui.checkbox(t.title, t.done, {});
        if (i == 1) continue;
        ui.label(%"row $i");
      }
    }
  }
}
```

**Generator probe (evidence item 3).**

```x2c
#include "x2c.x"
#include "meta.x"

meta static int is_pointer(List type) => type.len() > 0 && type[0] == <*>;
meta static int is_const(List type) => type.len() > 1 && type[1] == <const>;

meta static List component(String name, Code target) {
  Type signature = Code.type(target);
  List types = Type.parameters(signature);
  Type result = Type.return_type(signature);
  Array params = [], args = [];
  for (int i = 0; i < (int) types.len(); i++) {
    Type type = types[i];
    List p = x2c_ident(%"p$i");
    if (i == 0) {
      params.push($!Param{ Ui $p });
      args.push($!( $p ));
    } else if (Type.is_text(type)) {
      params.push($!Param{ String $p });
      args.push($!( $p ));
    } else if (is_pointer(type) && is_const(type)) {
      Type record = Type.element(type);
      params.push($!Param{ $record $p });
      args.push($!( &$p ));
    } else if (is_pointer(type)) {
      Type value = Type.element(type);
      params.push($!Param{ $value &$p });
      args.push($!( &$p ));
    } else {
      params.push($!Param{ $type $p });
      args.push($!( $p ));
    }
  }
  List declared = params.list_free(), passed = args.list_free();
  List method = x2c_ident(name);
  List unit = $!Unit{ inline $result Ui.$method(@declared) => $target(@passed); };
  return $(unit);
}
macro Unit $gen.component(Literal $name, Expr $target) {
  @component($name, $target)
}
$gen.component("slider", cui_slider_ex);
```

**Census.** A Python script strips comments from `cui.h`, collects each
`CUI_API` prototype and each `#define cui_name(...)`, resolves the first
CUI function a macro calls, and classifies its parameters by the table in
[Method rules](#method-rules).

## Plan review

**Facts existing owners establish, and rechecks.** `cui.h` establishes
every C signature and option field; x2c checks each generated call and each
brace option against it. CUI establishes widget state, ids, layout, and
frame memory. The package rechecks none of these. The generator reads
signatures from the compiler instead of restating them, so no second
description of the C API exists. The gallery scene list is the single
component registry; the completeness test compares it to the header and
keeps no list of its own.

**Reuse, deletion, and new mechanisms.** The package reuses CUI's
amalgamation tool for the build, `package.mk` and `deps.py` for packaging,
`$cleanup.by` for release, decorator macros and `defer` for containers,
reference parameters for state, and brace arguments for options. Nothing is
deleted. New lasting mechanisms: the method generator, needed because 433
hand-written forwarders would restate the header; `TextField`, needed
because a String cannot be edited in place; `Offscreen`, needed for the
gated check and for image output; and the record converters in Delivery 2,
needed because an x2c List is not a C struct array. `x2c bind` was
considered for the method tier and not used: it emits `const char *`
parameters and positional names, and cannot map option, state, or text
parameters.

**Why this is direct x2c.** Call sites use methods, references, Strings,
brace initializers, decorators, and `auto`. CUI's names for records,
enums, and constants stay visible. No widget object model, retained tree,
keyword set, Symbol vocabulary, or converter layer is added over CUI's
immediate-mode calls.

**Validators, diagnostics, and negative fixtures.** The package adds no
validator and no dedicated diagnostic. Its checks are the compile of the
table against `cui.h`, the completeness test, and the headless render
check. The completeness test protects a deliberate public claim: every
pinned component has an x2c form. The compiler work in Delivery 0 adds one
fixture case for P1, which protects against wrong output: a header
declaration that was dropped or misread without a diagnostic.

## After the compiler repairs (2026-11-11)

gwf/x2c#655 to #659 are on `dev`, and `x2cui` contains them.

- The generator names `TextField`, `x2cui_buffer`, and `x2cui_strings`
  directly. It takes a function's name and reads its type.
- The component table in `src/x2cui.x` is one `expand` over 356 names.
  `Ui.get_strings` and `Ui.get_draw_data` are rows; a `const` result is
  visible to the generator. `tools/gen-arrays.py` reads the table.
- Each decorator evaluates its `ui` argument once.
- No example needed a string macro beside a literal, so none changed.
- The generated header differs from the earlier one only in the receiver
  spelling of those two methods. `make check` passes, and the gallery's 26
  pages remain byte-identical to CUI's C gallery.

`App.frame` gives a macOS window's title bar the theme's background
color before each frame, with the matching light or dark appearance for
its title and buttons. CUI sets the appearance only when it creates the
window, and the system's own dark title bar is a gray that matches no CUI
color. `src/x2cui-window.c` holds the calls, written against the
Objective-C runtime in C; it does nothing on other platforms. Captures of
a real window gave equal title bar and content pixels: (18, 18, 18) in
the dark theme and (255, 255, 255) in the light theme. During the theme's
fade the title bar is one frame behind the content.


## Stress example (2026-11-11)

CUI has no stress-test component and no frame-rate display; its
`tests/bench.c` and `tests/soak.c` are headless. `examples/stress.x` is an
x2c example built from existing components: a canvas of moving circles
and a grid of animated cards, with a header of frame figures. `make run`
times 30 frames of it off screen as a check. The browser build makes it
too; `index.html?stress` opens it.

Measured on this Mac on 2026-11-11, off screen at 1240 by 820 with the
software renderer, mean of a whole frame: 2,000 shapes 0.96 ms native and
4.9 ms under Node; 20,000 shapes 6.0 ms native; 2,000 components 2.2 ms
native and 7.8 ms under Node. In a window with `--no-vsync`, 2,000 shapes
ran at 110 frames per second, near CUI's limit of 120. The components
load draws only the cards in view, so its vertex count stops growing once
the window is full; its layout work still grows with the item count.

The browser rule for a single-unit program passes `--output`, because
`x2c build -c` of one unit writes its object beside the working
directory, not under `--build-dir`.

## Method forms and lists (2026-11-11)

Recorded in [x2cui lists and tables](x2cui-lists-and-tables.md); on a
local branch over `x2cui` merged with `dev` and the compiler change for
method-form macros, not on `x2cui`.

- Every component that takes an option record, and each of CUI's block
  components, has a method form generated by `src/x2cui-generate.x`:
  `ui.button("Add", variant: primary)`, `ui.row (gap: 8) { ... }`. This
  replaces the settled choice that containers use only the qualified
  `$cui.` form; those decorators remain beside the method forms.
- Options are `name: value` rows lowered to a designated initializer by
  `src/x2cui-options.x`; a lower-case undeclared name is a short name for
  the CUI constant its field's C type selects. Options are no longer
  always written: `{}` is gone from method calls.
- `ui.each`, `ui.item`, `ui.table`, `ui.table_row`, `ui.cell`, and
  `ui.cell_text` are new. `examples/mail.x` and `examples/orders.x` use
  them, and `make run` draws both.
- The gallery, scenes, stress example, and tests use the method forms for
  components. Their 229 images are byte-identical to the earlier ones.

