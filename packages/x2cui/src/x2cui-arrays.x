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

// The remaining array components. Rerun tools/gen-arrays.py to refresh.

/* gen-arrays: begin generated macros */

/** Calls `Ui.tour` with the count of each array. */
macro Expression $cui.tour(
  Expr $ui, Expr $id, Expr $steps, Expr $step, Expr $opts) =>
  $ui.tour($id, $steps, $cui.count($steps), $step, $opts);

/** Calls `Ui.reactions` with the count of each array. */
macro Expression $cui.reactions(Expr $ui, Expr $id, Expr $items) =>
  $ui.reactions($id, $items, $cui.count($items));

/** Calls `Ui.speed_dial` with the count of each array. */
macro Expression $cui.speed_dial(
  Expr $ui, Expr $id, Expr $actions, Expr $opts) =>
  $ui.speed_dial($id, $actions, $cui.count($actions), $opts);

/** Calls `Ui.swipe_item_begin` with the count of each array. */
macro Stmt $cui.swipe_item_begin(Expr $ui, Expr $id, Expr $left, Expr $right) {
  $ui.swipe_item_begin(
    $id, $left, $cui.count($left), $right, $cui.count($right));
}

/** Calls `Ui.filter_bar` with the count of each array. */
macro Expression $cui.filter_bar(
  Expr $ui, Expr $id, Expr $fields, Expr $selected, Expr $search) =>
  $ui.filter_bar($id, $fields, $cui.count($fields), $selected, $search);

/** Calls `Ui.tree_table_begin` with the count of each array. */
macro Stmt $cui.tree_table_begin(
  Expr $ui, Expr $id, Expr $columns, Expr $nodes, Expr $opts) {
  $ui.tree_table_begin(
    $id, $columns, $cui.count($columns), $nodes, $cui.count($nodes), $opts);
}

/** Calls `Ui.diff_view_rows` with the count of each array. */
macro Expression $cui.diff_view_rows(
  Expr $ui, Expr $id, Expr $rows, Expr $first) =>
  $ui.diff_view_rows($id, $rows, $first, $cui.count($rows));

/** Calls `Ui.presence` with the count of each array. */
macro Stmt $cui.presence(
  Expr $ui, Expr $id, Expr $users, Expr $max_visible, Expr $size) {
  $ui.presence($id, $users, $cui.count($users), $max_visible, $size);
}

/** Calls `Ui.ticker` with the count of each array. */
macro Stmt $cui.ticker(Expr $ui, Expr $id, Expr $items, Expr $opts) {
  $ui.ticker($id, $items, $cui.count($items), $opts);
}

/** Calls `Ui.calendar_heatmap` with the count of each array. */
macro Expression $cui.calendar_heatmap(
  Expr $ui, Expr $id, Expr $start, Expr $values, Expr $opts) =>
  $ui.calendar_heatmap($id, $start, $values, $cui.count($values), $opts);

/** Calls `Ui.treemap` with the count of each array. */
macro Expression $cui.treemap(Expr $ui, Expr $id, Expr $items, Expr $opts) =>
  $ui.treemap($id, $items, $cui.count($items), $opts);

/** Calls `Ui.radar_chart` with the count of each array. */
macro Expression $cui.radar_chart(
  Expr $ui, Expr $id, Expr $series, Expr $axes, Expr $opts) =>
  $ui.radar_chart($id, $series, $cui.count($series), $axes, $opts);

/** Calls `Ui.funnel` with the count of each array. */
macro Expression $cui.funnel(Expr $ui, Expr $id, Expr $stages, Expr $opts) =>
  $ui.funnel($id, $stages, $cui.count($stages), $opts);

/** Calls `Ui.sankey` with the count of each array. */
macro Expression $cui.sankey(
  Expr $ui, Expr $id, Expr $nodes, Expr $links, Expr $opts) =>
  $ui.sankey($id, $nodes, $links, $cui.count($links), $opts);

/** Calls `Ui.waffle` with the count of each array. */
macro Expression $cui.waffle(Expr $ui, Expr $id, Expr $items, Expr $opts) =>
  $ui.waffle($id, $items, $cui.count($items), $opts);

/** Calls `Ui.split_bar` with the count of each array. */
macro Expression $cui.split_bar(Expr $ui, Expr $id, Expr $items, Expr $opts) =>
  $ui.split_bar($id, $items, $cui.count($items), $opts);

/** Calls `Ui.bar_list` with the count of each array. */
macro Expression $cui.bar_list(Expr $ui, Expr $id, Expr $items, Expr $opts) =>
  $ui.bar_list($id, $items, $cui.count($items), $opts);

/** Calls `Ui.activity_rings` with the count of each array. */
macro Expression $cui.activity_rings(
  Expr $ui, Expr $id, Expr $rings, Expr $opts) =>
  $ui.activity_rings($id, $rings, $cui.count($rings), $opts);

/** Calls `Ui.scatter_chart` with the count of each array. */
macro Expression $cui.scatter_chart(
  Expr $ui, Expr $id, Expr $series, Expr $opts) =>
  $ui.scatter_chart($id, $series, $cui.count($series), $opts);

/** Calls `Ui.candlestick` with the count of each array. */
macro Expression $cui.candlestick(
  Expr $ui, Expr $id, Expr $candles, Expr $opts) =>
  $ui.candlestick($id, $candles, $cui.count($candles), $opts);

/** Calls `Ui.tab_bar` with the count of each array. */
macro Expression $cui.tab_bar(
  Expr $ui, Expr $id, Expr $items, Expr $selected, Expr $opts) =>
  $ui.tab_bar($id, $items, $cui.count($items), $selected, $opts);

/** Calls `Ui.waveform` with the count of each array. */
macro Expression $cui.waveform(
  Expr $ui, Expr $id, Expr $peaks, Expr $progress, Expr $opts) =>
  $ui.waveform($id, $peaks, $cui.count($peaks), $progress, $opts);

/** Calls `Ui.agent_plan` with the count of each array. */
macro Expression $cui.agent_plan(
  Expr $ui, Expr $id, Expr $steps, Expr $opts) =>
  $ui.agent_plan($id, $steps, $cui.count($steps), $opts);

/** Calls `Ui.source_list` with the count of each array. */
macro Expression $cui.source_list(Expr $ui, Expr $id, Expr $sources) =>
  $ui.source_list($id, $sources, $cui.count($sources));

/** Calls `Ui.prompt_suggestions` with the count of each array. */
macro Expression $cui.prompt_suggestions(
  Expr $ui, Expr $id, Expr $items, Expr $opts) =>
  $ui.prompt_suggestions($id, $items, $cui.count($items), $opts);

/** Calls `Ui.model_picker` with the count of each array. */
macro Expression $cui.model_picker(
  Expr $ui, Expr $id, Expr $models, Expr $selected, Expr $opts) =>
  $ui.model_picker($id, $models, $cui.count($models), $selected, $opts);

/** Calls `Ui.week_calendar` with the count of each array. */
macro Expression $cui.week_calendar(
  Expr $ui, Expr $id, Expr $week_start, Expr $events, Expr $opts) =>
  $ui.week_calendar($id, $week_start, $events, $cui.count($events), $opts);

/** Calls `Ui.month_calendar` with the count of each array. */
macro Expression $cui.month_calendar(
  Expr $ui, Expr $id, Expr $month, Expr $events, Expr $opts) =>
  $ui.month_calendar($id, $month, $events, $cui.count($events), $opts);

/** Calls `Ui.gantt` with the count of each array. */
macro Expression $cui.gantt(
  Expr $ui, Expr $id, Expr $tasks, Expr $origin, Expr $days, Expr $opts) =>
  $ui.gantt($id, $tasks, $cui.count($tasks), $origin, $days, $opts);

/** Calls `Ui.toc` with the count of each array. */
macro Expression $cui.toc(Expr $ui, Expr $scroll_id, Expr $items) =>
  $ui.toc($scroll_id, $items, $cui.count($items));

/** Calls `Ui.checklist` with the count of each array. */
macro Expression $cui.checklist(Expr $ui, Expr $id, Expr $steps, Expr $opts) =>
  $ui.checklist($id, $steps, $cui.count($steps), $opts);

/** Calls `Ui.histogram_slider` with the count of each array. */
macro Expression $cui.histogram_slider(
  Expr $ui, Expr $label, Expr $bins, Expr $lo, Expr $hi, Expr $min, Expr $max,
  Expr $opts) =>
  $ui.histogram_slider(
    $label, $bins, $cui.count($bins), $lo, $hi, $min, $max, $opts);

/** Calls `Ui.level_meter` with the count of each array. */
macro Expression $cui.level_meter(
  Expr $ui, Expr $id, Expr $levels, Expr $opts) =>
  $ui.level_meter($id, $levels, $cui.count($levels), $opts);

/** Calls `Ui.doc_tabs` with the count of each array. */
macro Expression $cui.doc_tabs(
  Expr $ui, Expr $id, Expr $tabs, Expr $selected, Expr $opts) =>
  $ui.doc_tabs($id, $tabs, $cui.count($tabs), $selected, $opts);

/** Calls `Ui.prop_vec` with the count of each array. */
macro Expression $cui.prop_vec(
  Expr $ui, Expr $label, Expr $value, Expr $opts) =>
  $ui.prop_vec($label, $value, $cui.count($value), $opts);

/** Calls `Ui.hex_view` with the count of each array. */
macro Expression $cui.hex_view(
  Expr $ui, Expr $id, Expr $data, Expr $sel, Expr $opts) =>
  $ui.hex_view($id, $data, $cui.count($data), $sel, $opts);

/** Calls `Ui.flame_graph` with the count of each array. */
macro Expression $cui.flame_graph(
  Expr $ui, Expr $id, Expr $spans, Expr $view, Expr $selected, Expr $opts) =>
  $ui.flame_graph($id, $spans, $cui.count($spans), $view, $selected, $opts);

/** Calls `Ui.curve_editor` with the count of each array. */
macro Expression $cui.curve_editor(
  Expr $ui, Expr $id, Expr $keys, Expr $count, Expr $opts) =>
  $ui.curve_editor($id, $keys, $count, $cui.count($keys), $opts);

/** Calls `Ui.gradient_editor` with the count of each array. */
macro Expression $cui.gradient_editor(
  Expr $ui, Expr $id, Expr $stops, Expr $count, Expr $opts) =>
  $ui.gradient_editor($id, $stops, $count, $cui.count($stops), $opts);

/** Calls `Ui.timeline_editor` with the count of each array. */
macro Expression $cui.timeline_editor(
  Expr $ui, Expr $id, Expr $tracks, Expr $time, Expr $opts) =>
  $ui.timeline_editor($id, $tracks, $cui.count($tracks), $time, $opts);

/** Calls `Ui.kv_editor` with the count of each array. */
macro Expression $cui.kv_editor(
  Expr $ui, Expr $id, Expr $pairs, Expr $count, Expr $opts) =>
  $ui.kv_editor($id, $pairs, $count, $cui.count($pairs), $opts);

/** Calls `Ui.problems` with the count of each array. */
macro Expression $cui.problems(Expr $ui, Expr $id, Expr $diags, Expr $opts) =>
  $ui.problems($id, $diags, $cui.count($diags), $opts);

/** Calls `Ui.pipeline` with the count of each array. */
macro Expression $cui.pipeline(
  Expr $ui, Expr $id, Expr $stages, Expr $jobs, Expr $opts) =>
  $ui.pipeline($id, $stages, $jobs, $cui.count($jobs), $opts);

/** Calls `Ui.query_builder` with the count of each array. */
macro Expression $cui.query_builder(
  Expr $ui, Expr $id, Expr $fields, Expr $nodes, Expr $count, Expr $opts) =>
  $ui.query_builder(
    $id, $fields, $cui.count($fields), $nodes, $count, $cui.count($nodes),
    $opts);

/** Calls `Ui.keymap` with the count of each array. */
macro Expression $cui.keymap(Expr $ui, Expr $id, Expr $bindings, Expr $opts) =>
  $ui.keymap($id, $bindings, $cui.count($bindings), $opts);

/** Calls `Ui.commit_graph` with the count of each array. */
macro Expression $cui.commit_graph(
  Expr $ui, Expr $id, Expr $commits, Expr $opts) =>
  $ui.commit_graph($id, $commits, $cui.count($commits), $opts);

/** Calls `Ui.graph_view` with the count of each array. */
macro Expression $cui.graph_view(
  Expr $ui, Expr $id, Expr $nodes, Expr $edges, Expr $opts) =>
  $ui.graph_view(
    $id, $nodes, $cui.count($nodes), $edges, $cui.count($edges), $opts);

/** Calls `Ui.waterfall` with the count of each array. */
macro Expression $cui.waterfall(
  Expr $ui, Expr $id, Expr $requests, Expr $opts) =>
  $ui.waterfall($id, $requests, $cui.count($requests), $opts);

/** Calls `Ui.trace_view` with the count of each array. */
macro Expression $cui.trace_view(
  Expr $ui, Expr $id, Expr $tracks, Expr $spans, Expr $view, Expr $selected,
  Expr $opts) =>
  $ui.trace_view(
    $id, $tracks, $cui.count($tracks), $spans, $cui.count($spans), $view,
    $selected, $opts);

/** Calls `Ui.test_explorer` with the count of each array. */
macro Expression $cui.test_explorer(
  Expr $ui, Expr $id, Expr $items, Expr $opts) =>
  $ui.test_explorer($id, $items, $cui.count($items), $opts);

/** Calls `Ui.stack_trace` with the count of each array. */
macro Expression $cui.stack_trace(
  Expr $ui, Expr $id, Expr $frames, Expr $opts) =>
  $ui.stack_trace($id, $frames, $cui.count($frames), $opts);

/** Calls `Ui.uptime` with the count of each array. */
macro Expression $cui.uptime(Expr $ui, Expr $id, Expr $services, Expr $opts) =>
  $ui.uptime($id, $services, $cui.count($services), $opts);

/** Calls `Ui.time_histogram` with the count of each array. */
macro Expression $cui.time_histogram(
  Expr $ui, Expr $id, Expr $start, Expr $bucket_seconds, Expr $buckets,
  Expr $series, Expr $sel_start, Expr $sel_end, Expr $opts) =>
  $ui.time_histogram(
    $id, $start, $bucket_seconds, $buckets, $series, $cui.count($series),
    $sel_start, $sel_end, $opts);

/** Calls `Ui.coverage` with the count of each array. */
macro Expression $cui.coverage(Expr $ui, Expr $id, Expr $files, Expr $opts) =>
  $ui.coverage($id, $files, $cui.count($files), $opts);

/** Calls `Ui.blame` with the count of each array. */
macro Expression $cui.blame(
  Expr $ui, Expr $id, Expr $lines, Expr $line_commit, Expr $line_count,
  Expr $commits, Expr $opts) =>
  $ui.blame(
    $id, $lines, $line_commit, $line_count, $commits, $cui.count($commits),
    $opts);

/** Calls `Ui.feature_flags` with the count of each array. */
macro Expression $cui.feature_flags(
  Expr $ui, Expr $id, Expr $flags, Expr $envs, Expr $opts) =>
  $ui.feature_flags($id, $flags, $cui.count($flags), $envs, $opts);

/** Calls `Ui.api_explorer` with the count of each array. */
macro Expression $cui.api_explorer(
  Expr $ui, Expr $id, Expr $endpoints, Expr $opts) =>
  $ui.api_explorer($id, $endpoints, $cui.count($endpoints), $opts);

/** Calls `Ui.draw_polyline` with the count of each array. */
macro Stmt $cui.draw_polyline(
  Expr $ui, Expr $points, Expr $thickness, Expr $color, Expr $closed) {
  $ui.draw_polyline($points, $cui.count($points), $thickness, $color, $closed);
}

/** Calls `Ui.draw_polygon` with the count of each array. */
macro Stmt $cui.draw_polygon(Expr $ui, Expr $points, Expr $color) {
  $ui.draw_polygon($points, $cui.count($points), $color);
}

/* gen-arrays: end generated macros */
