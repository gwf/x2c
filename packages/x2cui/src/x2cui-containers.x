#pragma once

/*  x2cui-containers.x -- block forms written by hand

    The generator gives every one of CUI's own block macros a method form,
    `ui.row (gap: 8) { ... }`. The forms here are those it cannot
    generate: the id and disabled scopes, which CUI writes as push and pop
    calls; the blocks whose begin or end call reports a result, which CUI
    gives no block macro; and the lists and tables below. Each evaluates
    its receiver once, and its end call is deferred, so it also runs when
    the block leaves early.
*/

#include <stdbool.h>
#include "x2cui-options.x"

/** Runs the block with `$key` on the id stack, so the same components
    drawn for different keys keep separate state: `ui.id (i) { ... }`. A
    text key pushes `cui_push_id`, and any other key `cui_push_id_int`.
*/
macro Decorator $Ui.id(Stmt $body, Expr $ui, Expr $key) {
  {
    typeof($ui) ui = $ui;
    $x2cui_push_id(ui, $key);
    defer cui_pop_id(ui);
    $body
  }
}

/** Runs the block with its components disabled while `$disabled` holds:
    `ui.disabled (locked) { ... }`.
*/
macro Decorator $Ui.disabled(Stmt $body, Expr $ui, Expr $disabled) {
  {
    typeof($ui) ui = $ui;
    cui_push_disabled(ui, $disabled);
    defer cui_pop_disabled(ui);
    $body
  }
}

/* The template of a block whose end call reports a result, as a card
   stack and a swipe item do. The end call's result is stored in
   `$result`, an `int` variable of the caller's. `pairs` are as for
   `x2cui_arguments`. */
macro Unit $x2cui.result_block(
  Name $block, Name $begin, Name $end, Literal @pairs) {
  macro Decorator $Ui.$block(
    Stmt $body, Expr $ui, Expr $result, Expr @args, Entry @options) {
    {
      typeof($ui) ui = $ui;
      ui.$begin(@x2cui_arguments(ui, $begin, $pairs, $options, @args));
      defer $result = ui.$end();
      $body
    }
  }
}

/* `ui.card_stack (swiped, "deck", 3) { ... }` stores in `swiped` the
   direction the top card was swiped this frame, or 0; its items are
   `ui.card_stack_item (depth) { ... }`. */
$x2cui.result_block(card_stack, card_stack_begin, card_stack_end);

/* `ui.swipe_item (action, "row", left, right) { ... }` stores in
   `action` the swipe action taken this frame, or -1; it supplies the
   counts of the arrays of actions. */
$x2cui.result_block(swipe_item, swipe_item_begin, swipe_item_end, 1, 3);

/* `ui.reorder (changed, "tasks", order) { ... }` stores in `changed`
   whether the user dropped an item in a new place this frame; its items
   are `ui.reorder_item (position) { ... }`. */
$x2cui.result_block(reorder, reorder_begin, reorder_end);

/* The template of a block whose begin call reports a result, as a kanban
   column and card do. The result is stored in `$result`, an `int` or
   `bool` variable of the caller's, before the block runs. */
macro Unit $x2cui.begin_result_block(Name $block, Name $begin, Name $end) {
  macro Decorator $Ui.$block(
    Stmt $body, Expr $ui, Expr $result, Expr @args, Entry @options) {
    {
      typeof($ui) ui = $ui;
      $result =
        ui.$begin(@x2cui_arguments(ui, $begin, %(), $options, @args));
      defer ui.$end();
      $body
    }
  }
}

/* `ui.kanban_column (add, "Backlog", count) { ... }` stores in `add`
   whether its "+" was clicked; `ui.kanban_card (clicked, id) { ... }`
   stores whether the card was clicked. */
$x2cui.begin_result_block(kanban_column, kanban_column_begin,
                          kanban_column_end);
$x2cui.begin_result_block(kanban_card, kanban_card_begin, kanban_card_end);

/** Runs the block inside a kanban board, whose columns are
    `ui.kanban_column` blocks. `$moved` is a `bool` and `$move` a
    `cui_kanban_move` of the caller's: when a card was dropped in a new
    place this frame, `$moved` is set and `$move` says where.
*/
macro Decorator $Ui.kanban(
  Stmt $body, Expr $ui, Expr $moved, Expr $move, Expr $id) {
  {
    typeof($ui) ui = $ui;
    ui.kanban_begin($id);
    defer $moved = ui.kanban_end($move);
    $body
  }
}

/*  Lists and tables

    `ui.each` runs a block once for each element of a collection, under an
    id of its own; `ui.item` is an interactive row of such a list. A table
    takes its columns as a Map literal and its rows from `ui.table_row`,
    whose cells are `ui.cell` and `ui.cell_text`:

      ui.each (Message m in shown, key: m.id)
      ui.item (row, selected: a.selected == m) {
        if (row.clicked) a.selected = m;
        ui.text(m.subject);
      }

      ui.table ("orders", columns: {"Order": 90, "Customer": fill})
      ui.each (Order o in shown, key: o.id)
      ui.table_row (row, selected: s.selected == o) {
        ui.cell_text(o.id);
        ui.cell () ui.avatar(o.customer, size: 28);
      }
*/

/** What a row of a list or a table did in this frame: `ui.item` and
    `ui.table_row` bind one to the name they are given.
*/
typedef struct RowState { bool hovered, pressed, clicked; } RowState;

/** The options of `ui.item` and `ui.table_row`. */
typedef struct RowOptions { bool selected; } RowOptions;

/** What `ui.each` has seen of the items drawn in it so far. */
typedef struct ItemTrail { bool listing, selected; int items; } ItemTrail;

/** Runs the block once for each element of `$items`, with `$element`
    declared as `foreach` declares it. Each pass pushes the id `key:`
    names, or the element's position, so a row keeps its state when the
    list is filtered or reordered. The id is popped on every exit.
*/
macro Decorator $Ui.each(
  Stmt $body, Expr $ui, Decl $element, Expr $items, Entry @options) {
  using ItemTrail;
  {
    typeof($ui) ui = $ui;
    ItemTrail trail = ui.each_begin();
    defer ui.each_end(trail);
    int position = 0;
    foreach ($element in $items) {
      $x2cui_push_key(ui, position, $options);
      defer {
        cui_pop_id(ui);
        position++;
      }
      $body
    }
  }
}

/** Runs the block inside a row of a list made by `Ui.item_begin`, with
    `$row` bound to the `RowState` of this frame.
*/
macro Decorator $Ui.item(Stmt $body, Expr $ui, Name $row, Entry @options) {
  using RowState;
  {
    typeof($ui) ui = $ui;
    RowState $row = $x2cui_call(ui, "item_begin", $options);
    defer cui_box_end(ui);
    $body
  }
}

/** Runs the block while the table `$id` is open. `columns:` is a Map
    literal of titles and widths, lowered at compile time to a static
    `cui_table_column` array by `x2cui_columns`. The other options are those
    of `cui_table_opts`.
*/
macro Decorator $Ui.table(Stmt $body, Expr $ui, Expr $id, Entry @options) {
  {
    typeof($ui) ui = $ui;
    static cui_table_column columns[] = {
      @x2cui_columns("cui_table_column", $options) };
    if (ui.table_begin(
      $id, columns, $x2cui.count(columns),
      $x2cui_options(ui, "table_begin", $options))) {
      defer cui_table_end(ui);
      $body
    }
  }
}

/** Runs the block while the data grid `$id` of `$rows` rows is open.
    `columns:` is a Map literal of titles and widths in points, lowered as
    for `ui.table` to a static `cui_grid_column` array. The grid draws only
    the rows on screen: the block builds rows `$first` up to `$last`, two
    `int` variables this macro declares, and begins each with
    `ui.data_grid_row`. The other options are those of `cui_grid_opts`.
*/
macro Decorator $Ui.data_grid(
  Stmt $body, Expr $ui, Expr $id, Expr $rows, Name $first, Name $last,
  Entry @options) {
  {
    int $first = 0, $last = 0;
    typeof($ui) ui = $ui;
    static cui_grid_column columns[] = {
      @x2cui_columns("cui_grid_column", $options) };
    if (ui.data_grid_begin(
      $id, columns, $x2cui.count(columns), $rows, $first, $last,
      $x2cui_options(ui, "data_grid_begin", $options))) {
      defer cui_data_grid_end(ui);
      $body
    }
  }
}

/** Runs the block as one row of a table, with `$row` bound to the
    `RowState` of this frame. Its cells follow as `ui.cell` and
    `ui.cell_text`.
*/
macro Decorator $Ui.table_row(
  Stmt $body, Expr $ui, Name $row, Entry @options) {
  using RowState;
  {
    typeof($ui) ui = $ui;
    RowState $row = $x2cui_call(ui, "table_row_begin", $options);
    $body
  }
}

/** Runs the block in the next cell of a table row. */
macro Decorator $Ui.cell(Stmt $body, Expr $ui) {
  {
    typeof($ui) ui = $ui;
    cui_table_cell(ui);
    $body
  }
}

/** Runs the block in the next cell of a data grid's or a tree table's
    row. CUI keeps a grid's cells apart from a table's, and which one a
    call is in is known only while the frame runs, so the grid's cell has
    a name of its own.
*/
macro Decorator $Ui.grid_cell(Stmt $body, Expr $ui) {
  {
    typeof($ui) ui = $ui;
    cui_data_grid_cell(ui);
    $body
  }
}
