/*  check.x -- `builder --check`: the builder driven off screen

    Each step injects input through CUI, as a person's pointer and keys
    would, and checks the tree, the selection, or the log after it.
*/

static void frame(Offscreen screen, Builder &b) {
  screen.begin();
  draw(screen.ui(), b);
  screen.end();
}

static void click(Offscreen screen, Builder &b, cui_rect target) {
  Ui ui = screen.ui();
  ui.input_mouse_move(target.x + target.w / 2, target.y + target.h / 2);
  frame(screen, b);
  ui.input_mouse_button(left, true);
  frame(screen, b);
  ui.input_mouse_button(left, false);
  frame(screen, b);
  frame(screen, b);
}

/* Presses at the centre of `from`, moves to `x`, `y`, and releases.
   A `shot` is written while the button is still down. */
static void drag(Offscreen screen, Builder &b, cui_rect from, float x,
                 float y, String shot) {
  Ui ui = screen.ui();
  ui.input_mouse_move(from.x + from.w / 2, from.y + from.h / 2);
  frame(screen, b);
  ui.input_mouse_button(left, true);
  frame(screen, b);
  ui.input_mouse_move(x, y);
  frame(screen, b);
  frame(screen, b);
  if (shot) screen.write_png(shot);
  ui.input_mouse_button(left, false);
  frame(screen, b);
  frame(screen, b);
}

static void press(Offscreen screen, Builder &b, cui_key key, int mods) {
  Ui ui = screen.ui();
  ui.input_key(key, true, mods);
  frame(screen, b);
  ui.input_key(key, false, mods);
  frame(screen, b);
  frame(screen, b);
}

// The rectangle of the first `name` component the view drew.
static cui_rect drawn_rect(Builder &b, Ui ui, Symbol name) {
  for (int i = 0; i < b.drawn_count; i++)
    if (b.drawn[i].node[0] == name) return ui.get_rect(b.drawn[i].id);
  return (cui_rect){ 0 };
}

// Where the palette offers the component `name`.
static cui_rect offered_rect(Builder &b, String name) {
  for (int i = 0; i < b.offered_count; i++)
    if (b.offered_name[i] == name) return b.offered[i];
  return (cui_rect){ 0 };
}

static int clicks(Builder &b) {
  Var value = void;
  return b.lisp.try_get("clicks", value) ? value.int() : -1;
}

// Finds the component `name` with the palette's search, and adds it.
static void find_and_add(Offscreen screen, Builder &b, String name) {
  b.find.buffer[0] = 0;
  click(screen, b, b.find_field);
  screen.ui().input_text(name);
  frame(screen, b);
  press(screen, b, CUI_KEY_ENTER, 0);
}

/* Replaces the text of the inspector field named `field` with `text`. A
   number field selects its text when clicked; a text field is emptied. */
static void retype(Offscreen screen, Builder &b, String field,
                   bool number, String text) {
  for (int i = 0; i < 60; i++) frame(screen, b);
  click(screen, b, located(b, field));
  if (!number) {
    press(screen, b, CUI_KEY_END, 0);
    for (int i = 0; i < 24; i++) press(screen, b, CUI_KEY_BACKSPACE, 0);
  }
  screen.ui().input_text(text);
  frame(screen, b);
  press(screen, b, CUI_KEY_ENTER, 0);
}

/* Selects the node at `where` with a click on the canvas `dx`, `dy`
   points in from its top left corner, or from its right edge when `dx`
   is negative. */
static void pick(Offscreen screen, Builder &b, Where where, float dx,
                 float dy) {
  for (int i = 0; i < 60; i++) frame(screen, b);
  cui_rect r = drawn_at(b, screen.ui(), where);
  click(screen, b, (cui_rect){ dx < 0 ? r.x + r.w + dx : r.x + dx,
                               r.y + dy, 1, 1 });
}

/* The plan's acceptance test: a sign-in form with a heading, two
   labelled inputs, and a row of two buttons 12 points apart at the
   right edge, whose second button sends a message the form handles.
   Nothing is typed but component names, numbers, and the handler's
   body. */
static int sign_in(Offscreen screen, Builder &b, String image) {
  Var empty = void;
  read_value("(column ((pad 24) (gap 12)))", empty);
  change(b, empty);
  select_at(b, (Where){ 0 });
  foreach (String name in %("heading" "label" "input" "label" "input"
                            "row" "button" "button"))
    find_and_add(screen, b, name);
  // The row is the column's seventh element; a click right of its buttons.
  pick(screen, b, (Where){ 1, { 7 } }, -10, 10);
  retype(screen, b, "gap", true, "12");
  click(screen, b, located(b, "cell 2 1"));
  pick(screen, b, (Where){ 2, { 7, 3 } }, 10, 10);
  cui_rect modes = located(b, "on_click mode");
  modes.x += modes.w / 3;
  modes.w /= 3;
  click(screen, b, modes);
  pick(screen, b, (Where){ 0 }, 6, 6);
  click(screen, b, located(b, "handle button"));
  retype(screen, b, "on button", false, "(def signed-in 1)");
  List row = b.tree[7];
  int spaced = row[0] == <row> && option(row, "gap").int() == 12 &&
               spelled(option(row, "justify")) == "end";
  // At the right edge: the second button ends where the row's padding
  // would begin, and the row has none.
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect across = drawn_at(b, screen.ui(), (Where){ 1, { 7 } });
  cui_rect second = drawn_at(b, screen.ui(), (Where){ 2, { 7, 3 } });
  int right = fabsf(second.x + second.w - (across.x + across.w)) < 2;
  screen.write_png(image + ".sign-in.png");
  click(screen, b, b.mode_button);
  for (int i = 0; i < 3; i++) frame(screen, b);
  click(screen, b, second);
  Var signed_in = void;
  int handles_it = b.lisp.try_get("signed-in", signed_in) &&
                   signed_in.int() == 1;
  printf("sign-in: spaced %d, right %d, handled %d, %s\n", spaced, right,
         handles_it, written(b.tree));
  return spaced && right && handles_it ? 0 : 1;
}

module int check(String image) {
  static Builder b;
  Offscreen screen = auto Offscreen.open(1200, 700);
  Ui ui = screen.ui();

  /* The notebook the builder opens by default draws without an error,
     and a click on its formatting toolbar's padding selects that row. */
  open_file(b, ui, NULL, notebook, notebook_program);
  for (int i = 0; i < 30; i++) frame(screen, b);
  int notes = !b.status && b.drawn_count > 30;
  cui_rect toolbar_row = drawn_at(b, ui, (Where){ 2, { 4, 2 } });
  click(screen, b, (cui_rect){ toolbar_row.x + 3, toolbar_row.y + 3, 1, 1 });
  for (int i = 0; i < 30; i++) frame(screen, b);
  notes = notes && b.selected && b.where.depth == 2 &&
          node_at(b.tree, b.where)[0] == <row>;
  screen.write_png(image + ".notebook.png");
  printf("notebook: %d nodes drawn, status %s, selected %s\n",
         b.drawn_count, b.status ? (char *) b.status : "none",
         b.selected ? written(node_at(b.tree, b.where)[0]) : "nothing");
  if (!notes) return 1;

  open_file(b, ui, NULL, sample, sample_program);
  for (int i = 0; i < 3; i++) frame(screen, b);

  // In edit mode a click selects the button and does not press it.
  click(screen, b, drawn_rect(b, ui, <button>));
  int selects = b.selected && node_at(b.tree, b.where)[0] == <button> &&
                clicks(b) == 0;
  printf("edit: selected %s, clicked %d\n",
         b.selected ? written(node_at(b.tree, b.where)[0]) : "nothing",
         clicks(b));

  // The palette adds a button after the selection, with a label.
  int before = b.tree.len();
  click(screen, b, b.add_button);
  int adds = b.tree.len() == before + 1 && is_node(b.tree[4]) &&
             (String) ((List) b.tree[4])[2] == "Button";
  printf("add: %d children, selected position %d\n", b.tree.len() - 2,
         b.where.at[0]);

  // In run mode the same click presses the button.
  cui_rect pressed = drawn_rect(b, ui, <button>);
  cui_rect added = drawn_at(b, ui, b.where);
  click(screen, b, b.mode_button);
  click(screen, b, pressed);
  int runs = !b.editing && clicks(b) == 1;
  printf("run: clicked %d\n", clicks(b));
  /* The added button has the palette button's label. Pressing it presses
     only it: the tree's ids are apart from the builder's own. */
  click(screen, b, added);
  int apart = b.tree.len() == before + 1;
  printf("run: %d children after pressing the added button\n",
         b.tree.len() - 2);

  // Back in edit mode, the inspector's first field edits the label.
  click(screen, b, b.mode_button);
  for (int i = 0; i < 3; i++) frame(screen, b);
  click(screen, b, drawn_rect(b, ui, <button>));
  click(screen, b, b.first_field);
  ui.input_text("!");
  frame(screen, b);
  frame(screen, b);
  String label = node_at(b.tree, b.where)[2];
  int edits = label == "Add one!";
  printf("inspect: label %s\n", label);
  screen.write_png(image);

  // The toolbar's operations, and a save read back.
  List edited_tree = b.tree;
  move_selected(b, 1);
  int moves = b.where.at[0] == 4 && b.tree[4] == edited_tree[3];
  remove_selected(b);
  int removes = b.tree.len() == edited_tree.len() - 1 && !b.selected;
  undo(b);
  undo(b);
  int undoes = written(b.tree) == written(edited_tree);
  b.file = image + ".tree";
  save(b);
  Path saved = b.file;
  Var again = void;
  int saves = read_value(saved.read_text(), again) &&
              written(again) == written(b.tree);
  printf("move %d, delete %d, undo %d, save %d\n", moves, removes, undoes,
         saves);
  puts(written(b.tree));

  /* Two equal nodes are one List: a click on the second selects the
     second, and an edit changes only it. */
  Var twins = void;
  read_value(%"(column ((pad 24) (gap 16))
                 (row () (button () \"Same\"))
                 (row () (button () \"Same\")))", twins);
  change(b, twins);
  b.selected = false;
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect second = { 0 };
  for (int i = 0; i < b.drawn_count; i++)
    if (b.drawn[i].node[0] == <button>) second = ui.get_rect(b.drawn[i].id);
  click(screen, b, second);
  int picks = b.selected && b.where.depth == 2 && b.where.at[0] == 3;
  // A second press on the field this soon would be a double click.
  for (int i = 0; i < 60; i++) frame(screen, b);
  click(screen, b, b.first_field);
  ui.input_text("!");
  frame(screen, b);
  frame(screen, b);
  int keeps = written(b.tree) ==
    "(column ((pad 24) (gap 16)) (row () (button () \"Same\")) "
    "(row () (button () \"Same!\")))";
  printf("twins: selected child %d, %s\n", b.where.at[0], written(b.tree));

  // A drag moves the second button into the first row, after its button.
  cui_rect first = drawn_rect(b, ui, <button>);
  drag(screen, b, second, first.x + first.w - 4, first.y + first.h / 2,
       image + ".drag.png");
  int reparents = written(b.tree) ==
    "(column ((pad 24) (gap 16)) (row () (button () \"Same\") "
    "(button () \"Same!\")) (row ()))" &&
    b.where.depth == 2 && b.where.at[0] == 2 && b.where.at[1] == 3;
  printf("drag in: %s\n", written(b.tree));
  // A second drag puts it before the first button; a click moves nothing.
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect moved = drawn_at(b, ui, b.where);
  first = drawn_rect(b, ui, <button>);
  drag(screen, b, moved, first.x + 4, first.y + first.h / 2, NULL);
  List row = b.tree[2];
  int reorders = ((List) row[2])[2] == "Same!" && b.where.at[1] == 2;
  int changes = b.undo.len();
  for (int i = 0; i < 3; i++) frame(screen, b);
  click(screen, b, drawn_at(b, ui, b.where));
  int stays = b.undo.len() == changes;
  printf("drag before: %s\n", written(b.tree));

  // A block with no children has a size in edit mode and takes a drop.
  Where empty = { 1, { 3 } };
  cui_rect hollow = drawn_at(b, ui, empty);
  drag(screen, b, drawn_at(b, ui, b.where), hollow.x + hollow.w / 2,
       hollow.y + hollow.h / 2, NULL);
  int fills = hollow.w > 0 && hollow.h > 0 && written(b.tree) ==
    "(column ((pad 24) (gap 16)) (row () (button () \"Same\")) "
    "(row () (button () \"Same!\")))";
  printf("drag into empty: %g by %g, %s\n", hollow.w, hollow.h,
         written(b.tree));
  // A drop at a block's edge goes beside the block, into the one around.
  for (int i = 0; i < 3; i++) frame(screen, b);
  Where top = { 1, { 2 } };
  cui_rect above = drawn_at(b, ui, top);
  drag(screen, b, drawn_at(b, ui, b.where), above.x + above.w / 2,
       above.y + 2, NULL);
  int besides = written(b.tree) ==
    "(column ((pad 24) (gap 16)) (button () \"Same!\") "
    "(row () (button () \"Same\")) (row ()))";
  printf("drag beside: %s\n", written(b.tree));

  // A drag of the handle at the selection's corner sets a fixed size.
  Var sized = void;
  read_value(%"(column ((pad 24)) (button () \"B\"))", sized);
  change(b, sized);
  b.selected = false;
  for (int i = 0; i < 3; i++) frame(screen, b);
  Where only = { 1, { 2 } };
  cui_rect now = drawn_at(b, ui, only);
  for (int i = 0; i < 60; i++) frame(screen, b);
  click(screen, b, now);
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect corner = { now.x + now.w - 1, now.y + now.h - 1, 2, 2 };
  drag(screen, b, corner, now.x + now.w + 30, now.y + now.h + 10, NULL);
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect grown = drawn_at(b, ui, only);
  int sizes = grown.w == whole(now.w + 30).int();
  printf("resize: %g by %g to %g by %g, %s\n", now.w, now.h, grown.w,
         grown.h, written(b.tree));

  /* The inspector spaces a block: typing a gap is one step of undo, the
     grid's middle centres the children, and Row makes it a row. */
  b.where.depth = 0;
  b.refill = true;
  for (int i = 0; i < 60; i++) frame(screen, b);
  int steps_before = b.undo.len();
  click(screen, b, located(b, "gap"));
  ui.input_text("20");
  frame(screen, b);
  press(screen, b, CUI_KEY_ENTER, 0);
  int spaces = option(b.tree, "gap").int() == 20 &&
               b.undo.len() == steps_before + 1;
  printf("gap: %s, %d steps\n", written(b.tree),
         (int) b.undo.len() - steps_before);
  click(screen, b, located(b, "cell 1 1"));
  int centres = spelled(option(b.tree, "align")) == "center" &&
                spelled(option(b.tree, "justify")) == "center";
  cui_rect turn = located(b, "direction");
  turn.x += turn.w / 2;
  turn.w /= 2;
  click(screen, b, turn);
  int turns = b.tree[0] == <row> && option(b.tree, "pad").int() == 24;
  printf("align and direction: %s\n", written(b.tree));
  screen.write_png(image + ".layout.png");

  /* A child's inspector shows its block's spacing under "In row", and
     its own size as Auto, Fit, Fill, or Fixed. */
  select_at(b, (Where){ 1, { 2 } });
  for (int i = 0; i < 60; i++) frame(screen, b);
  click(screen, b, located(b, "around gap"));
  ui.input_text("6");
  frame(screen, b);
  press(screen, b, CUI_KEY_ENTER, 0);
  int arounds = option(b.tree, "gap").int() == 6 && b.where.depth == 1;
  cui_rect fill_choice = located(b, "width");
  fill_choice.x += fill_choice.w / 2;
  fill_choice.w /= 4;
  click(screen, b, fill_choice);
  List button = node_at(b.tree, b.where);
  int fills_size = spelled(option(button, "width")) == "fill";
  // A rectangle is the last frame's: the fill moved the reset button.
  frame(screen, b);
  click(screen, b, located(b, "reset width"));
  button = node_at(b.tree, b.where);
  int resets = option(button, "width").is_void();
  undo(b);
  int back = spelled(option(node_at(b.tree, (Where){ 1, { 2 } }), "width"))
             == "fill";
  redo(b);
  int forth = option(node_at(b.tree, (Where){ 1, { 2 } }), "width")
              .is_void();
  printf("in row %d, fill %d, reset %d, undo %d, redo %d: %s\n", arounds,
         fills_size, resets, back, forth, written(b.tree));

  // Only common and set options show until "All options" is on.
  select_at(b, (Where){ 1, { 2 } });
  for (int i = 0; i < 3; i++) frame(screen, b);
  int hidden = located(b, "tooltip").w == 0;
  click(screen, b, b.all_switch);
  int shows_all = b.all && located(b, "tooltip").w > 0;
  screen.write_png(image + ".all.png");
  click(screen, b, b.all_switch);
  printf("all options: hidden %d, shown %d\n", hidden, shows_all);
  int lays = spaces && centres && turns && arounds && fills_size && resets &&
             back && forth && hidden && shows_all;

  // A click on a line of the outline selects its node; keys select around.
  Var counter = void;
  read_value(sample, counter);
  change(b, counter);
  b.selected = false;
  for (int i = 0; i < 60; i++) frame(screen, b);
  // The line takes no keyboard focus; the selection follows the keys.
  cui_id focused = ui.focused_id();
  click(screen, b, b.listed[1]);
  int lists = b.selected && b.where.depth == 1 && b.where.at[0] == 2 &&
              ui.focused_id() == focused;
  press(screen, b, CUI_KEY_DOWN, 0);
  int steps = b.where.at[0] == 3;
  press(screen, b, CUI_KEY_LEFT, 0);
  steps = steps && b.where.depth == 0;
  press(screen, b, CUI_KEY_RIGHT, 0);
  press(screen, b, CUI_KEY_DOWN, 0);
  steps = steps && b.where.depth == 1 && b.where.at[0] == 3;
  printf("outline: listed %d, keys %d\n", lists, steps);

  // Keys wrap the selection in a row, unwrap it, duplicate, move, delete.
  press(screen, b, CUI_KEY_R, CUI_MOD_SHIFT);
  List wrapped = b.tree[3];
  int wraps = wrapped[0] == <row> && wrapped[2] == ((List) counter)[3] &&
              b.where.depth == 1;
  printf("wrap: %s\n", written(wrapped));
  screen.write_png(image + ".outline.png");
  press(screen, b, CUI_KEY_U, CUI_MOD_SHIFT);
  int unwraps = written(b.tree) == written(counter) && b.selected &&
                b.where.at[0] == 3;
  press(screen, b, CUI_KEY_D, CUI_MOD_PRIMARY);
  int copies = b.tree.len() == 6 && b.tree[4] == b.tree[3] &&
               b.where.at[0] == 4;
  press(screen, b, CUI_KEY_UP, CUI_MOD_ALT);
  press(screen, b, CUI_KEY_DELETE, 0);
  int clears = written(b.tree) == written(counter) && !b.selected;
  printf("unwrap %d, duplicate %d, move and delete %d\n", unwraps, copies,
         clears);

  /* A right click selects and opens the menu, whose fourth item
     duplicates. The menu takes the keys while it is open. */
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect text = drawn_rect(b, ui, <text>);
  ui.input_mouse_move(text.x + 8, text.y + text.h / 2);
  frame(screen, b);
  ui.input_mouse_button(right, true);
  frame(screen, b);
  ui.input_mouse_button(right, false);
  for (int i = 0; i < 30; i++) frame(screen, b);
  int opens = b.menu_open && b.selected && b.where.at[0] == 4;
  screen.write_png(image + ".menu.png");
  for (int i = 0; i < 4; i++) press(screen, b, CUI_KEY_DOWN, 0);
  int holds = b.where.at[0] == 4;
  press(screen, b, CUI_KEY_ENTER, 0);
  for (int i = 0; i < 30; i++) frame(screen, b);
  int menus = opens && holds && !b.menu_open && b.tree.len() == 6 &&
              written(b.tree[5]) == written(b.tree[4]);
  printf("menu: opened %d, held %d, open %d, %d children\n", opens, holds,
         b.menu_open, b.tree.len() - 2);
  // A right click on a line of the outline does the same for its node.
  cui_rect line = b.listed[1];
  ui.input_mouse_move(line.x + line.w / 2, line.y + line.h / 2);
  frame(screen, b);
  ui.input_mouse_button(right, true);
  frame(screen, b);
  ui.input_mouse_button(right, false);
  for (int i = 0; i < 30; i++) frame(screen, b);
  int offers = b.menu_open && b.selected && b.where.at[0] == 2;
  press(screen, b, CUI_KEY_ESCAPE, 0);
  for (int i = 0; i < 30; i++) frame(screen, b);
  offers = offers && !b.menu_open && b.tree.len() == 6;
  printf("outline menu: %d\n", offers);
  if (!(lists && steps && wraps && unwraps && copies && clears && menus &&
        offers))
    return 1;

  if (!(apart && lays && fills && besides && sizes && selects && adds &&
        runs && edits && moves && removes && undoes && saves && picks &&
        keeps && reparents && reorders && stays))
    return 1;

  /* A drag from the palette puts a new row, spaced 8 points, where the
     line shows: before the button. */
  change(b, counter);
  b.selected = false;
  for (int i = 0; i < 60; i++) frame(screen, b);
  cui_rect aimed = drawn_rect(b, ui, <button>);
  drag(screen, b, offered_rect(b, "row"), aimed.x + 20, aimed.y + 3,
       image + ".carry.png");
  List placed = b.tree[3];
  int carries = b.tree.len() == ((List) counter).len() + 1 &&
                placed[0] == <row> && option(placed, "gap").int() == 8 &&
                b.selected && b.where.depth == 1 && b.where.at[0] == 3;
  printf("carry: %s\n", written(b.tree));
  // The search finds a name, and Return adds it into the selected row.
  for (int i = 0; i < 60; i++) frame(screen, b);
  click(screen, b, b.find_field);
  ui.input_text("sli");
  for (int i = 0; i < 3; i++) frame(screen, b);
  int finds = b.offered_count == 1 && b.offered_name[0] == "slider";
  screen.write_png(image + ".find.png");
  press(screen, b, CUI_KEY_ENTER, 0);
  List slider = node_at(b.tree, b.where);
  int submits = slider[0] == <slider> && (String) slider[2] == "Amount" &&
                slider[4].int() == 100 && b.where.depth == 2;
  printf("find: %d found, added %s\n", b.offered_count, written(slider));
  if (!(carries && finds && submits)) return 1;

  /* The counter's button calls `bump`. Send makes it send a message
     named from its label, which the column handles with a typed body. */
  change(b, counter);
  select_at(b, (Where){ 1, { 3 } });
  for (int i = 0; i < 60; i++) frame(screen, b);
  int calls = handler_mode(option(b.tree[3], "on_click")) == 2;
  cui_rect modes = located(b, "on_click mode");
  modes.x += modes.w / 3;
  modes.w /= 3;
  click(screen, b, modes);
  int sends = written(option(b.tree[3], "on_click")) == "(send add-one)";
  screen.write_png(image + ".events.png");
  select_at(b, (Where){ 0 });
  for (int i = 0; i < 3; i++) frame(screen, b);
  click(screen, b, located(b, "handle add-one"));
  Atom message = Atom.intern("add-one");
  int handled = handles(b.tree, message);
  for (int i = 0; i < 60; i++) frame(screen, b);
  click(screen, b, located(b, "on add-one"));
  press(screen, b, CUI_KEY_END, 0);
  for (int i = 0; i < 20; i++) press(screen, b, CUI_KEY_BACKSPACE, 0);
  ui.input_text("(bump)");
  frame(screen, b);
  press(screen, b, CUI_KEY_ENTER, 0);
  List handler = ((List) b.tree[1]).find(
    %!(List row) => row.len() == 3 && row[1] == message);
  int bodies = handler &&
               written(handler) == "(on add-one (lambda () (bump)))";
  printf("events: calls %d, sends %d, handled %d, %s\n", calls, sends,
         handled, written(b.tree[1]));

  /* In run mode a press logs the message sent and the block that
     handled it, and the message box evaluates Lisp in the session. */
  int clicked = clicks(b);
  /* A running tree is not watched, so the button is found before, and
     is pressed near its left edge: unwatched, it is only as wide as its
     label. */
  cui_rect pressing = drawn_rect(b, ui, <button>);
  pressing.w = 20;
  click(screen, b, b.mode_button);
  for (int i = 0; i < 3; i++) frame(screen, b);
  click(screen, b, pressing);
  int lines = b.log.len();
  String sent_line = lines >= 2 ? (String) b.log[lines - 2] : "none";
  String handled_line = lines >= 1 ? (String) b.log[lines - 1] : "none";
  int logs = strstr(sent_line, "on-click: (send add-one)") &&
             strstr(handled_line, "column add-one") &&
             clicks(b) == clicked + 1;
  printf("run: %s / %s\n", sent_line, handled_line);
  click(screen, b, b.message_field);
  ui.input_text("(bump)");
  frame(screen, b);
  press(screen, b, CUI_KEY_ENTER, 0);
  String last = b.log.len() ? (String) b.log[b.log.len() - 1] : "none";
  int evaluates = strstr(last, "> (bump)") && clicks(b) == clicked + 2;
  screen.write_png(image + ".run.png");
  printf("run log: %d lines, last %s\n", (int) b.log.len(), last);

  // Calling a procedure FILE.lisp lacks gives it a stub, which Save writes.
  click(screen, b, b.mode_button);
  select_at(b, (Where){ 1, { 3 } });
  for (int i = 0; i < 60; i++) frame(screen, b);
  modes = located(b, "on_click mode");
  modes.x += modes.w * 2 / 3;
  modes.w /= 3;
  click(screen, b, modes);
  b.file = image + ".events.tree";
  save(b);
  Path program = %"$(b.file).lisp";
  int stubs = option(b.tree[3], "on_click") == message &&
              program.exists() &&
              strstr(program.read_text(),
                     "(def add-one (lambda () 'add-one))");
  printf("stub: %d\n", stubs);
  if (!(calls && sends && handled && bodies && logs && evaluates && stubs))
    return 1;

  /* A selected block has a handle in each side's padding and in each
     gap. Dragging the top one sets the padding, and dragging the second
     gap's sets the gap, each one step of undo; a component has none. */
  Var spaced = void;
  read_value(%"(column ((pad 16) (gap 8))
                 (button () \"A\") (button () \"B\") (button () \"C\"))",
             spaced);
  change(b, spaced);
  select_at(b, (Where){ 0 });
  for (int i = 0; i < 60; i++) frame(screen, b);
  int handles = b.spacer_count == 6;
  cui_rect padding = b.spacers[0].at, second_gap = b.spacers[5].at;
  int steps_at = b.undo.len();
  drag(screen, b, padding, padding.x + padding.w / 2,
       padding.y + padding.h / 2 + 10, image + ".spacing.png");
  int pads = option(b.tree, "pad").int() == 26 &&
             b.undo.len() == steps_at + 1;
  for (int i = 0; i < 3; i++) frame(screen, b);
  second_gap = b.spacers[5].at;
  drag(screen, b, second_gap, second_gap.x + second_gap.w / 2,
       second_gap.y + second_gap.h / 2 + 8, NULL);
  int gaps = option(b.tree, "gap").int() == 12 &&
             b.undo.len() == steps_at + 2;
  undo(b);
  int undoes_gap = option(b.tree, "gap").int() == 8 &&
                   option(b.tree, "pad").int() == 26;
  select_at(b, (Where){ 1, { 2 } });
  for (int i = 0; i < 3; i++) frame(screen, b);
  int none = b.spacer_count == 0;
  printf("spacing: %d handles, pad %d, gap %d, undo %d, none %d: %s\n",
         handles, pads, gaps, undoes_gap, none, written(b.tree));
  if (!(handles && pads && gaps && undoes_gap && none)) return 1;
  return sign_in(screen, b, image);
}
