#pragma once

/*  x2cui-arrays.x -- components that take an array of CUI records

    A component such as a table or a chart reads an array of CUI's own
    records: its columns, its series, its items. In x2c that array is a C
    array of those records, written with designated initializers, and its
    count comes from `$cui.count`:

      static cui_tab_bar_item tabs[] = {
        { CUI_ICON_HOUSE, "Home" }, { CUI_ICON_SEARCH, "Search" } };
      ui.tab_bar("tabs", tabs, $cui.count(tabs), selected, {});

    The array may be static, a local, or a variable-length array filled
    from a collection. CUI writes into the arrays of the components that
    edit their records. `$cui.count` of a pointer does not compile, so a
    count is never taken from the wrong thing; a program that holds a
    pointer passes its own count.

    The two block components that take an array are macros here, and
    supply the count themselves.
*/

/** Returns how many elements the C array `$array` holds. A pointer is
    refused: its type equals the type of a pointer to its first element.
*/
macro Expression $cui.count(Expr $array) =>
  ((int) (sizeof($array) / sizeof(($array)[0])) +
   0 * (int) sizeof(char[1 - 2 * __builtin_types_compatible_p(
     __typeof__($array), __typeof__(&($array)[0]))]));

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
