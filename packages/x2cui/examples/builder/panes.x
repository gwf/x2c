/*  panes.x -- the toolbar, the menu and keys, the outline, and the
    palette
*/

module void toolbar(Ui ui, Builder &b) {
  ui.row (gap: 8, align: center, pad: 8) {
    if (ui.button(b.editing ? "Run" : "Edit", variant: primary, size: sm)) {
      if (b.editing) add_stubs(b);
      b.editing = !b.editing;
      b.status = NULL;
    }
    b.mode_button = ui.last_rect();
    if (ui.button("Undo", size: sm, disabled: !b.undo.len())) undo(b);
    if (ui.button("Redo", size: sm, disabled: !b.redo.len())) redo(b);
    if (ui.button("Parent", size: sm)) select_parent(b);
    if (ui.button("Up", size: sm)) move_selected(b, -1);
    if (ui.button("Down", size: sm)) move_selected(b, 1);
    if (ui.button("Delete", size: sm)) remove_selected(b);
    if (ui.button("Save", size: sm)) save(b);
    ui.spacer();
    // The file's name only, so a long path does not squeeze the buttons.
    char *slash = strrchr(b.file, '/');
    ui.muted(b.status ? b.status : slash ? slash + 1 : b.file);
  }
}

// The menu of the commands that have a label. A choice is done next frame.
module void node_menu(Ui ui, Builder &b, String id) {
  ui.context_menu (id) {
    b.menu_shown = true;
    for (int i = 0; i < (int) (sizeof keys / sizeof keys[0]); i++) {
      if (!keys[i].label) continue;
      if (keys[i].command == MOVE_UP || keys[i].command == DELETE)
        ui.menu_separator();
      if (ui.menu_item(keys[i].label, shortcut: keys[i].shown,
                       disabled: !b.selected,
                       danger: keys[i].command == DELETE))
        b.command = keys[i].command;
    }
  }
}

// A key asks for its command, unless a text field or a menu takes the keys.
module void keyed(Ui ui, Builder &b) {
  if (!b.editing || b.menu_open || ui.wants_keyboard()) return;
  for (int i = 0; i < (int) (sizeof keys / sizeof keys[0]); i++)
    if (ui.shortcut(keys[i].mods, keys[i].key)) b.command = keys[i].command;
}

// A node as the outline names it: its component and its first text.
module String listed(List node) {
  String name = written(node[0]);
  return node.len() > 2 && node[2] is <string>
    ? %"$name \"$((String) node[2])\"" : name;
}

/* One line of the outline for `node`, then its children's lines, each a
   step further in. `row` counts the lines; equal nodes have equal names,
   so a line's id is made under its count. */
static void outline_rows(Ui ui, Builder &b, List node, Where &where,
                         int &row) {
  cui_push_id_int(ui, row);
  ui.row (width: fill, align: center) {
    if (where.depth) ui.gap(14 * where.depth);
    bool chosen = b.selected && same_place(where, b.where);
    // A left press on the line is the input hook's; see `capture`.
    ui.list_item(listed(node), selected: chosen);
    cui_rect line = ui.last_rect();
    if (row < LISTED) {
      b.listed[row] = line;
      b.listed_where[row] = where;
    }
    if (ui.mouse_clicked(CUI_MOUSE_RIGHT) && within(line, b.pointer))
      select_at(b, where);
    if (b.selected && same_place(where, b.where))
      node_menu(ui, b, "outline-menu");
  }
  cui_pop_id(ui);
  row++;
  if (!is_block(node) || where.depth == DEPTH) return;
  for (int i = 2; i < node.len(); i++) {
    if (!is_node(node[i])) continue;
    where.at[where.depth++] = i;
    outline_rows(ui, b, node[i], where, row);
    where.depth--;
  }
}

module void outline_pane(Ui ui, Builder &b) {
  ui.row (pad: 8, gap: 8, align: center) {
    ui.label("Outline");
    ui.muted("Right-click for commands");
  }
  b.outline_id = cui_box_begin(ui, &(cui_box){
    .id = "outline-area", .width = CUI_FILL, .height = CUI_FILL });
  defer cui_box_end(ui);
  ui.scroll (id: "outline", width: fill, height: fill, pad: 4, gap: 0) {
    Where root = { 0 };
    int row = 0;
    outline_rows(ui, b, b.tree, root, row);
    b.lines = row;
  }
}

// The names of the palette's group `group` that the search finds.
static List offered_in(Builder &b, String group) {
  Array names = [];
  foreach (List row in View.components()) {
    String name = row[0];
    Offer *offered = offer_of(name);
    if (strcmp(offered ? offered.group : "Other", group) == 0 &&
        (b.find.empty() || strstr(name, b.find.text())))
      names.push(name);
  }
  return names.list_free();
}

/* The components by group, two names to a line so that more show above
   the outline. A click on a name adds it, and Return in the search adds
   the first name found. */
module void palette(Ui ui, Builder &b) {
  ui.row (width: fill, pad: 8) {
    int typed = ui.search("palette-search", b.find, size: sm,
                          placeholder: "Find a component");
    b.find_field = ui.last_rect();
    if (typed & CUI_SUBMITTED && b.offered_count) add(b, b.offered_name[0]);
  }
  b.palette_id = cui_box_begin(ui, &(cui_box){
    .id = "palette-area", .width = CUI_FILL, .height = CUI_FILL });
  defer cui_box_end(ui);
  b.offered_count = 0;
  ui.scroll (id: "palette", width: fill, height: fill, pad: 8, gap: 4) {
    foreach (String group in offer_groups) {
      List names = offered_in(b, group);
      if (!names.len()) continue;
      ui.muted(group);
      ui.row (width: fill, wrap: true, gap: 2) {
        foreach (String name in names) {
          if (ui.button(name, variant: ghost, size: sm, width: 100))
            add(b, name);
          if (b.offered_count < OFFERED) {
            b.offered[b.offered_count] = ui.last_rect();
            b.offered_name[b.offered_count++] = name;
          }
          if (name == "button") b.add_button = ui.last_rect();
        }
      }
    }
  }
}
