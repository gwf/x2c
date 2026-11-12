# x2cui lists and tables

> Status: Gary accepted decisions 1 to 5 on 2026-11-11, and approved the
> To-Do, Mail, and Orders sources and images. Implemented on `x2cui`
> (gwf/x2c#663, `7a7129f20`), over `dev` with the compiler change for
> [method-form macros](method-form-macros.md). The data grid's form and
> the migration of the package's programs are on the local branch
> `gwf/x2cui-data-grid`. Not on `dev`.
> Every "verified" statement below was compiled and run on macOS arm64
> with that branch's stage 0, built from its bootstrap seed. Statements
> marked "not verified" were not.

## Result

Two CUI screens hold most of the awkward code a CUI program writes: a list of
interactive rows and a table. Both now compile in the target syntax, as
`packages/x2cui/examples/mail.x` and `packages/x2cui/examples/orders.x`, and
`make check` draws each off screen. Verified.

| Construct | Replaces |
| --- | --- |
| `ui.each (T x in items, key: ...)` | `cui_push_id_int` / `cui_pop_id`, `$cui.id_index` |
| `ui.item (row, selected: ...) { }` | a stack box, a canvas, a paint callback, and a hover flag kept in `cui_state` |
| `ui.table (..., columns: {...})` | a `cui_table_column` array, its count, and `CUI_PX` widths |
| `ui.table_row (row, ...) { }` and `ui.cell () { }` | `ui.table_row(...)` and `ui.table_cell()` as loose calls |

The method forms of every other component come from the package's
generator, and the option values are lowered by their C type; see
[Option values](#option-values).

## The mail message list

The C original is `examples/mail.c:97-153` in CUI. `examples/mail.x` holds
the note's `message_list` with these differences, each forced by something
other than the constructs:

- `ui.dot(size: 7, color: accent)` is
  `ui.box (width: 7, height: 7, radius: 4, bg: accent) {}`, as `mail.c`
  writes it. CUI has no dot component, and the package adds none.
- Two lines are wrapped to stay within 80 columns: the `row.clicked` body
  and the unread dot's `if`.
- The program around the list is new: a `Message` class filled from a
  List of rows, a `Mail` record, `in_folder`, `matches`, and `--shot`.

`make run` writes its image to `builds/mail.png`, and the orders table's
to `builds/orders.png`.

## The dashboard orders table

The C original is `examples/dashboard.c:155-193` in CUI. `examples/orders.x`
holds the note's `recent_orders` unchanged. Around it:

- `matches` returns `int`. `List.filter` refuses a lambda whose result is
  `bool`: "cannot convert bool to Var without loss".
- `Order.sort_key` returns a `Var`, and sorts the price as a number.
- Prices in a List literal are written `"\$184.20"`; a `$` in a quoted
  string starts an interpolation.

## The constructs

### `ui.each (T x in items, key: expression) TARGET`

Runs `TARGET` once for each element, with `x` holding it. Each pass pushes
an ID made from `key`, a text or an integer, and pops it on every exit,
including `continue`. Without `key:` the ID is the element's position.

- The `in` form reuses the `Decl` hole; argument capture accepts `in`
  after a declaration, also after a method form's receiver. Verified.
- `x` is visible in the target. Verified, also from the `key:` expression,
  which is captured before `x` exists. `ui.each` forwards its `Decl` hole
  into `foreach ($element in $items)`, so the loop uses the collection's
  own typed cursor.
- A `key:` row after `in items` needs a `Decl`, an `Expr`, and an
  `Entry @rows` hole in one argument list. Verified.

### `ui.item (row, options) { }`

An interactive list row. `Ui.item_begin` opens a stack box, paints it
through a canvas, and keeps the hover flag in `cui_state`, as `mail.c`
does. `row` is a `RowState` with `hovered`, `pressed`, and `clicked`.

- `row` is a `Name` argument bound in the block. Verified.
- The fill, hairline, and hover memory are library code. Implemented. The
  hairline is inset 12 points at each end; `mail.c` insets it 26 on the
  left, under the names. Not an option.
- Decision 4, the top-edge hairline: an item draws it unless it is the
  first item of its `ui.each` or it or the item before it is selected.
  `ui.each` keeps that trail in a thread-local record, saved and restored
  around a nested `ui.each`. An item outside `ui.each` draws no hairline.
  Verified in the mail image.

### `ui.table (id, columns: {...}, options) ROWS`

`columns:` is a Map literal of titles and widths. `cui_columns` lowers it
at compile time to the initializers of a `static cui_table_column` array.
x2c gives that block-scope static a guarded one-time initializer, because
`CUI_PX` is a compound literal; no frame builds a Map. Verified by reading
the generated C.

- Width values: a number is pixels, `fill` and `fit` as for rows,
  `grow(1.2)` is `CUI_GROW(1.2)`. Verified.
- `right(110)` and `center(110)` align the column; `unsorted(90)` marks a
  column that cannot be sorted; they nest. Every other column is sortable.
  Verified: the test draws the same pixels as the equivalent C array.
- Undeclared calls such as `right(110)` survive capture as calls of an
  unbound name. Verified; the `%(right 110)` fallback is not needed.

### `ui.data_grid (id, rows, first, last, options) ROWS`

CUI has no block macro for its data grid, so the form is written by hand
beside `ui.table`, on the same helpers. `columns:` is a Map literal lowered
by `cui_columns` to a static `cui_grid_column` array; a width is lowered by
the type of the record's `width` field, so a grid's widths are points
where a table's are sizes. `first` and `last` are `int` variables the form
declares, as `$cui.data_grid` declares them. The other options are those
of `cui_grid_opts`, through `cui_options`. The gallery's data grid page
and the data grid scene use it, and their images are byte-identical. A
test draws the same pixels with the form and with `$cui.data_grid`.
Verified.

The form writes its begin call itself and asks `cui_options` only for
the record, because `first` and `last` are `Name` holes, which reach a
meta function as their spellings rather than as expressions.

### `ui.table_row (row, options) { }` and `ui.cell () { }`

`ui.table_row` begins a row and binds `row` as `ui.item` does.
`ui.cell ()` begins the next cell and runs its target there;
`ui.cell_text(text)` is a method. Implemented.

- `cui_table_row` returns only a click, and CUI's public API has no way to
  read the row's hover or press: the row's id and rectangle are internal.
  `patches/table-row-state.patch` adds `cui_table_row_hovered` and
  `cui_table_row_pressed`, which return the interaction `cui_table_row`
  already computes for its highlight, so they respect what the highlight
  respects. A test moves the pointer onto the second row, presses, and
  releases, checks the other rows stay false, and checks that a disabled
  table reports nothing. Verified. Popups above the table and its scroll
  area act through CUI's own hit test, which decides the highlight; they
  are not tested separately. The patch changes nothing CUI draws; all 229
  images stay byte-identical. Verified.

### Short values inside expressions

`font: m.unread ? medium : body` lowers each arm. Verified. A number for a
`cui_size` field, `width: 26`, becomes `CUI_PX(26)`; so does any numeric
expression there. Verified.

## Option values

`name: value` arguments arrive in an `Entry @options` hole.
`src/x2cui-options.x` rewrites each row as a field of the option record in a
designated initializer, reading keys and values with Match patterns over
the canonical `map-entry` form. The record and each field's type come from
the method's signature and `Type.fields`.

A value that is a lower-case name with no declaration of its own is a short
name. The constant comes from the field's C type, not the option's name:

- an enum: its member with the prefix all its members share, from
  `Type.members` (`center` is `CUI_ALIGN_CENTER`, `primary` is
  `CUI_BUTTON_PRIMARY`, `sm` is `CUI_SIZE_SM`, `stack` is `CUI_STACK`);
- `cui_size`: `CUI_FILL`, `CUI_FIT`;
- another `cui_T`: `CUI_T_NAME` (`cui_color`, `cui_font`);
- text: an icon, `CUI_ICON_NAME`.

The constant is emitted as a free name that binds where the expansion
lands, like a template's free name, so `CUI_FILL` and the color tokens are
CUI's own macros. No CUI macro internals are copied. A positional argument
is lowered by its parameter's type the same way, so
`ui.icon_button(x, ...)` works. Upper-case names keep their value, which
keeps `NULL` and `CUI_*` constants working.

## Generated method forms

`src/x2cui-generate.x` gives every generated component whose last C
parameter is an option record an Expression macro `$Ui.NAME`, and each of
CUI's own block macros a decorator `$Ui.NAME`. All component forms come
from one template and all block forms from another: the macro takes its
name from a Name hole, `$Ui.$method`, and an `Expr @args` hole before the
final `Entry @options` hole takes the ordinary arguments, however many.
The virtual list, with six, has a form. `tools/gen-arrays.py`
writes the table of the methods written in x2c that also take an option
record, so the array components, the charts, and `ui.tree` have forms too.
A script migrated the gallery, scenes, stress example, and tests to the
method forms: 809 calls of 157 component names. All 229 of their images
are byte-identical to `origin/x2cui`'s, drawn back to back. Their blocks
keep the `$cui.NAME` decorators.
The to-do example's image is byte-identical to the one drawn with
`$cui.row` forms, and the mail and orders images are byte-identical to
the ones Gary approved. Verified.

## Decisions

1. Adopt `ui.each` as the keyed loop, with the element's position as the
   default key. Done.
2. Adopt `ui.item` and `ui.table_row` binding a row-state name, with
   `hovered`, `pressed`, and `clicked`. Done, through a CUI patch for a
   table row.
2. Adopt a Map literal of titles and widths as the column template, with
   `right(...)`, `center(...)`, and `unsorted(...)` as width wrappers.
   Done.
3. The hairline rule for `ui.item`: top edge, skipped when it or the
   previous item is selected. Done.
4. Per-frame collections: allowed for now. Measurement: `stress --frames
   300` gives the same frame time before and after this work (shapes 1.06
   and 1.05 ms, components 1.19 to 1.43 ms and 1.18 to 1.26 ms, three
   alternating runs each, load average about 5). The stress example builds
   no per-frame collection, so it cannot measure `List.filter`'s cost; the
   frame-arena question needs a workload that filters per frame. Not
   measured.

## Limits

1. Short values need a meta function, so `Entry @options` rows are
   lowered by `cui_arguments`, `cui_call`, `cui_begin`, and
   `cui_options`, not forwarded. Forwarding passes rows to a
   `Map @rest` parameter or another `Entry` hole; CUI's methods take an
   option record. These helpers run in the importing file's compiler, so
   they are public.
2. A component's form writes its method call in its own template,
   `$ui.$method(@cui_arguments(...))`, because the self-call rule is
   lexical: a call built by a meta function is not in the template, so it
   would be the form again and recurse. A block's begin method and the
   list constructs' methods have no forms, so `cui_begin` and `cui_call`
   still build those calls.
3. A call that passes an option record value, rather than `name: value`
   rows, must call the method as `Ui.NAME(ui, ..., record)`; the method
   form takes the call. The earlier `$cui.NAME(ui, ..., { ... })`
   decorators remain.
4. Method forms work in statement and expression positions only, not at
   file scope.
5. A table row's hover and press come from a patch to CUI; see
   `PROFILE.md`. A new CUI version needs the patch remade.
6. The mail and orders examples have no tests of their own beyond drawing
   an image; the package test covers clicks, hover, and the column
   lowering.
