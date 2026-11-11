#pragma once

/*  x2cui-containers.x -- CUI's block components as statement decorators

    `$cui.row(ui, { .gap = 8 }) { ... }` begins a row, runs the block, and
    ends the row. Each macro here has the name and the arguments of the CUI
    macro `cui_NAME`, with the options as one last `{ ... }` argument where
    CUI takes named arguments. The end call is deferred, so it also runs
    when the block leaves through `return`, `break`, or `continue`, which
    CUI's own C macros skip.

    A component that reports whether it is open, such as a dialog or a
    menu, runs its block only while it is open.

    The `ui` argument is evaluated for the begin call and again for the end
    call, as in CUI's own macros. Pass a variable or `app.ui()`.
*/

/** Runs the block inside `cui_node_content`. */
macro Decorator $cui.node_content(Stmt $body, Expr $ui) {
  {
    $ui.node_content_begin();
    defer cui_node_content_end($ui);
    $body
  }
}

/** Runs the block inside `cui_dockspace`. */
macro Decorator $cui.dockspace(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    $ui.dockspace_begin($id, $opts);
    defer cui_dockspace_end($ui);
    $body
  }
}

/** Runs the block while `cui_dock_panel` is open. */
macro Decorator $cui.dock_panel(
  Stmt $body, Expr $ui, Expr $title, Expr $open, Expr $opts) {
  {
    if ($ui.dock_panel_begin($title, $open, $opts)) {
      defer cui_dock_panel_end($ui);
      $body
    }
  }
}

/** Runs the block inside `cui_box`. */
macro Decorator $cui.box(Stmt $body, Expr $ui, Expr $opts) {
  {
    $ui.box_begin($opts);
    defer cui_box_end($ui);
    $body
  }
}

/** Runs the block inside `cui_row`. */
macro Decorator $cui.row(Stmt $body, Expr $ui, Expr $opts) {
  {
    $ui.row_begin($opts);
    defer cui_box_end($ui);
    $body
  }
}

/** Runs the block inside `cui_column`. */
macro Decorator $cui.column(Stmt $body, Expr $ui, Expr $opts) {
  {
    $ui.column_begin($opts);
    defer cui_box_end($ui);
    $body
  }
}

/** Runs the block inside `cui_card`. */
macro Decorator $cui.card(Stmt $body, Expr $ui, Expr $opts) {
  {
    $ui.card_begin($opts);
    defer cui_card_end($ui);
    $body
  }
}

/** Runs the block inside `cui_scroll`. */
macro Decorator $cui.scroll(Stmt $body, Expr $ui, Expr $opts) {
  {
    $ui.scroll_begin($opts);
    defer cui_scroll_end($ui);
    $body
  }
}

/** Runs the block inside `cui_split`. */
macro Decorator $cui.split(
  Stmt $body, Expr $ui, Expr $id, Expr $ratio, Expr $opts) {
  {
    $ui.split_begin($id, $ratio, $opts);
    defer cui_split_end($ui);
    $body
  }
}

/** Runs the block inside `cui_id_scope`. */
macro Decorator $cui.id_scope(Stmt $body, Expr $ui, Expr $key) {
  {
    $ui.push_id($key);
    defer cui_pop_id($ui);
    $body
  }
}

/** Runs the block inside `cui_disabled_scope`. */
macro Decorator $cui.disabled_scope(Stmt $body, Expr $ui, Expr $disabled) {
  {
    $ui.push_disabled($disabled);
    defer cui_pop_disabled($ui);
    $body
  }
}

/** Runs the block while `cui_popover` is open. */
macro Decorator $cui.popover(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    if ($ui.popover_begin($id, $opts)) {
      defer cui_popover_end($ui);
      $body
    }
  }
}

/** Runs the block while `cui_menu` is open. */
macro Decorator $cui.menu(Stmt $body, Expr $ui, Expr $label, Expr $opts) {
  {
    if ($ui.menu_begin($label, $opts)) {
      defer cui_menu_end($ui);
      $body
    }
  }
}

/** Runs the block while `cui_context_menu` is open. */
macro Decorator $cui.context_menu(Stmt $body, Expr $ui, Expr $id) {
  {
    if ($ui.context_menu_begin($id)) {
      defer cui_context_menu_end($ui);
      $body
    }
  }
}

/** Runs the block while `cui_dialog` is open. */
macro Decorator $cui.dialog(
  Stmt $body, Expr $ui, Expr $title, Expr $open, Expr $opts) {
  {
    if ($ui.dialog_begin($title, $open, $opts)) {
      defer cui_dialog_end($ui);
      $body
    }
  }
}

/** Runs the block inside `cui_dialog_footer`. */
macro Decorator $cui.dialog_footer(Stmt $body, Expr $ui) {
  {
    $ui.dialog_footer_begin();
    defer cui_dialog_footer_end($ui);
    $body
  }
}

/** Runs the block while `cui_sheet` is open. */
macro Decorator $cui.sheet(
  Stmt $body, Expr $ui, Expr $title, Expr $open, Expr $opts) {
  {
    if ($ui.sheet_begin($title, $open, $opts)) {
      defer cui_sheet_end($ui);
      $body
    }
  }
}

/** Runs the block while `cui_accordion` is open. */
macro Decorator $cui.accordion(Stmt $body, Expr $ui, Expr $title, Expr $open) {
  {
    if ($ui.accordion_begin($title, $open)) {
      defer cui_accordion_end($ui);
      $body
    }
  }
}

/** Runs the block while `cui_tree` is open. */
macro Decorator $cui.tree(
  Stmt $body, Expr $ui, Expr $label, Expr $open, Expr $opts) {
  {
    if ($ui.tree_begin($label, $open, $opts)) {
      defer cui_tree_end($ui);
      $body
    }
  }
}

/** Runs the block inside `cui_virtual_list`. */
macro Decorator $cui.virtual_list(
  Stmt $body, Expr $ui, Expr $id, Expr $count, Expr $row_height,
  Expr $height, Expr $first, Expr $last) {
  {
    $ui.virtual_list_begin($id, $count, $row_height, $height, $first, $last);
    defer cui_virtual_list_end($ui);
    $body
  }
}

/** Runs the block inside `cui_button_group`. */
macro Decorator $cui.button_group(Stmt $body, Expr $ui) {
  {
    $ui.button_group_begin();
    defer cui_button_group_end($ui);
    $body
  }
}

/** Runs the block inside `cui_reorder_item`. */
macro Decorator $cui.reorder_item(Stmt $body, Expr $ui, Expr $position) {
  {
    $ui.reorder_item_begin($position);
    defer cui_reorder_item_end($ui);
    $body
  }
}

/** Runs the block while `cui_reasoning` is open. */
macro Decorator $cui.reasoning(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    if ($ui.reasoning_begin($id, $opts)) {
      defer cui_reasoning_end($ui);
      $body
    }
  }
}

/** Runs the block inside `cui_spotlight`. */
macro Decorator $cui.spotlight(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    $ui.spotlight_begin($id, $opts);
    defer cui_spotlight_end($ui);
    $body
  }
}

/** Runs the block inside `cui_dock`. */
macro Decorator $cui.dock(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    $ui.dock_begin($id, $opts);
    defer cui_dock_end($ui);
    $body
  }
}

/** Runs the block inside `cui_carousel`. */
macro Decorator $cui.carousel(
  Stmt $body, Expr $ui, Expr $id, Expr $count, Expr $index, Expr $opts) {
  {
    $ui.carousel_begin($id, $count, $index, $opts);
    defer cui_carousel_end($ui);
    $body
  }
}

/** Runs the block inside `cui_carousel_slide`. */
macro Decorator $cui.carousel_slide(Stmt $body, Expr $ui) {
  {
    $ui.carousel_slide_begin();
    defer cui_carousel_slide_end($ui);
    $body
  }
}

/** Runs the block inside `cui_card_stack_item`. */
macro Decorator $cui.card_stack_item(Stmt $body, Expr $ui, Expr $depth) {
  {
    $ui.card_stack_item_begin($depth);
    defer cui_card_stack_item_end($ui);
    $body
  }
}

/** Runs the block while `cui_hover_card` is open. */
macro Decorator $cui.hover_card(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    if ($ui.hover_card_begin($id, $opts)) {
      defer cui_hover_card_end($ui);
      $body
    }
  }
}

/** Runs the block while `cui_expandable_card` is open. */
macro Decorator $cui.expandable_card(
  Stmt $body, Expr $ui, Expr $title, Expr $open, Expr $opts) {
  {
    if ($ui.expandable_card_begin($title, $open, $opts)) {
      defer cui_expandable_card_end($ui);
      $body
    }
  }
}

/** Runs the block while `cui_user_menu` is open. */
macro Decorator $cui.user_menu(Stmt $body, Expr $ui, Expr $name, Expr $opts) {
  {
    if ($ui.user_menu_begin($name, $opts)) {
      defer cui_user_menu_end($ui);
      $body
    }
  }
}

/** Runs the block inside `cui_menu_bar`. */
macro Decorator $cui.menu_bar(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    $ui.menu_bar_begin($id, $opts);
    defer cui_menu_bar_end($ui);
    $body
  }
}

/** Runs the block while `cui_menu_bar_menu` is open. */
macro Decorator $cui.menu_bar_menu(
  Stmt $body, Expr $ui, Expr $label, Expr $opts) {
  {
    if ($ui.menu_bar_menu_begin($label, $opts)) {
      defer cui_menu_bar_menu_end($ui);
      $body
    }
  }
}

/** Runs the block inside `cui_toolbar`. */
macro Decorator $cui.toolbar(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    $ui.toolbar_begin($id, $opts);
    defer cui_toolbar_end($ui);
    $body
  }
}

/** Runs the block inside `cui_status_bar`. */
macro Decorator $cui.status_bar(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    $ui.status_bar_begin($id, $opts);
    defer cui_status_bar_end($ui);
    $body
  }
}

/** Runs the block while `cui_inspector` is open. */
macro Decorator $cui.inspector(Stmt $body, Expr $ui, Expr $id, Expr $opts) {
  {
    if ($ui.inspector_begin($id, $opts)) {
      defer cui_inspector_end($ui);
      $body
    }
  }
}

/** Runs the block with the integer `$index` on the id stack, so the same
    components in a loop keep separate state.
*/
macro Decorator $cui.id_index(Stmt $body, Expr $ui, Expr $index) {
  {
    $ui.push_id_int($index);
    defer cui_pop_id($ui);
    $body
  }
}
