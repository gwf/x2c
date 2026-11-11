#pragma once

/*  x2cui-arrays.x -- components that take an array of CUI records

    A component such as a table or a chart reads an array of CUI's own
    records: its columns, its series, its items. In x2c that array is a C
    array of those records, written with designated initializers:

      static cui_table_column columns[] = {
        { "Name" }, { "Commits", .align = CUI_TEXT_RIGHT } };
      $cui.table(ui, "people", columns, { .striped = true }) { ... }

    Each macro here takes the array itself and supplies its count, so no
    call site writes one. The array may be static, a local, or a
    variable-length array filled from a collection. CUI writes into the
    arrays of the components that edit their records.

    The array argument must be an array, not a pointer: `$cui.count` of a
    pointer does not compile. A program that holds a pointer and a count
    calls the method of the same name, which takes both.
*/

/** Returns how many elements the C array `$array` holds. A pointer is
    refused: its type equals the type of a pointer to its first element.
*/
macro Expression $cui.count(Expr $array) =>
  ((int) (sizeof($array) / sizeof(($array)[0])) +
   0 * (int) sizeof(char[1 - 2 * __builtin_types_compatible_p(
     __typeof__($array), __typeof__(&($array)[0]))]));

/** Draws a line chart of the `cui_series` array `$series`, with the List
    `$labels` along the x axis, or NULL for none.
*/
macro Stmt $cui.line_chart(
  Expr $ui, Expr $id, Expr $series, Expr $labels, Expr $opts) {
  $ui.line_chart($id, $series, $cui.count($series), $labels, $opts);
}

/** Draws a bar chart of the `cui_series` array `$series`, with the List
    `$labels` along the x axis, or NULL for none.
*/
macro Stmt $cui.bar_chart(
  Expr $ui, Expr $id, Expr $series, Expr $labels, Expr $opts) {
  $ui.bar_chart($id, $series, $cui.count($series), $labels, $opts);
}

/** Shows a command palette over the `cui_command` array `$commands` while
    `$open` is true. Returns the index of the chosen command, or -1.
*/
macro Expression $cui.command_palette(
  Expr $ui, Expr $open, Expr $commands) =>
  $ui.command_palette($open, $commands, $cui.count($commands));

/** Draws one selectable card for each `cui_choice` of the array
    `$choices` and keeps the chosen index in `$index`. Returns true when
    the choice changes.
*/
macro Expression $cui.radio_cards(
  Expr $ui, Expr $id, Expr $choices, Expr $index, Expr $opts) =>
  $ui.radio_cards($id, $choices, $cui.count($choices), $index, $opts);

/** Runs the block inside a table with the `cui_table_column` array
    `$columns`. The block begins each row with `ui.table_row`.
*/
macro Decorator $cui.table(
  Stmt $body, Expr $ui, Expr $id, Expr $columns, Expr $opts) {
  {
    if ($ui.table_begin($id, $columns, $cui.count($columns), $opts)) {
      defer cui_table_end($ui);
      $body
    }
  }
}

/** Runs the block inside a data grid of `$rows` rows with the
    `cui_grid_column` array `$columns`. The grid draws only the rows on
    screen: the block builds rows `$first` up to `$last`, two `int`
    variables this macro declares, and begins each with
    `ui.data_grid_row`.
*/
macro Decorator $cui.data_grid(
  Stmt $body, Expr $ui, Expr $id, Expr $columns, Expr $rows, Name $first,
  Name $last, Expr $opts) {
  {
    int $first = 0, $last = 0;
    if ($ui.data_grid_begin($id, $columns, $cui.count($columns), $rows,
                            $first, $last, $opts)) {
      defer cui_data_grid_end($ui);
      $body
    }
  }
}
