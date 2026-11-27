/*  canvas.x -- the edited tree drawn live, and the pointer over it

    The input hook keeps a press on the tree from reaching its components,
    so a click selects. A press that moves drags the selection, the size
    handle, or a spacing handle; a drop goes where the line shows.
*/

static cui_rect grown(cui_rect r, float by) =>
  (cui_rect){ r.x - by, r.y - by, r.w + 2 * by, r.h + 2 * by };

module bool within(cui_rect r, cui_vec2 p) =>
  p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h;

/* In edit mode a press on the tree is kept for `select_under` and goes no
   further, so the component under it is not pressed. A press that moves
   more than a few points becomes a drag, which its release drops. */
module bool capture(cui_ctx *ui, const cui_input_event *event, void *user) {
  Builder *b = user;
  if (event.kind == CUI_INPUT_MOUSE_MOVE) {
    b.pointer = event.position;
    float dx = b.pointer.x - b.press.x, dy = b.pointer.y - b.press.y;
    if (b.pressed && dx * dx + dy * dy > 16) b.dragging = true;
    if (b.carry && dx * dx + dy * dy > 16) b.carrying = true;
  }
  if (event.kind != CUI_INPUT_MOUSE_BUTTON || !b.editing) return false;
  // An open menu lies over the tree, and a press on it is the menu's.
  if (b.menu_open) return false;
  /* A press on a name in the palette goes on to its button, which adds
     the component on a click. Moved far enough, it carries a new one,
     placed where it is released. */
  if (event.button == CUI_MOUSE_LEFT && !event.down && b.carry) {
    b.placed = b.carrying;
    if (!b.placed) b.carry = 0;
    b.carrying = false;
    return false;
  }
  if (event.button == CUI_MOUSE_LEFT && event.down &&
      within(b.palette_area, b.pointer))
    for (int i = 0; i < b.offered_count; i++)
      if (within(b.offered[i], b.pointer)) {
        b.carry = i + 1;
        b.press = b.pointer;
        return false;
      }
  // A press on a spacing handle of the selected block drags the handle.
  if (event.button == CUI_MOUSE_LEFT && !event.down && b.holding) {
    b.holding = 0;
    return true;
  }
  if (event.button == CUI_MOUSE_LEFT && event.down)
    for (int i = 0; i < b.spacer_count; i++)
      if (within(grown(b.spacers[i].at, 5), b.pointer)) {
        b.holding = i + 1;
        b.held = b.spacers[i];
        b.held_from = b.pointer;
        b.held_changed = false;
        return true;
      }
  if (event.button == CUI_MOUSE_LEFT && !event.down && b.pressed) {
    b.dropped = b.dragging && !b.sizing;
    b.sized = b.dragging && b.sizing;
    b.pressed = b.dragging = b.sizing = false;
    return true;
  }
  /* A left press on a line of the outline is kept, so the line takes no
     keyboard focus and its ring does not stay behind the selection. */
  if (event.button == CUI_MOUSE_LEFT && event.down &&
      within(b.outline_area, b.pointer))
    for (int i = 0; i < b.lines && i < LISTED; i++)
      if (within(b.listed[i], b.pointer)) {
        b.picked = i + 1;
        return true;
      }
  if (!within(b.canvas, b.pointer)) return false;
  // A right press selects, and goes on to open the menu.
  if (event.button == CUI_MOUSE_RIGHT) {
    b.clicked = b.clicked || event.down;
    return false;
  }
  if (event.down && event.button == CUI_MOUSE_LEFT) {
    b.pressed = true;
    b.sizing = b.selected && within(b.handle, b.pointer);
    b.clicked = !b.sizing;
    b.press = b.pointer;
  }
  return true;
}

static void note_drawn(void *user, List node, cui_id id) {
  Builder *b = user;
  if (b.drawn_count < DRAWN) b.drawn[b.drawn_count++] = (Drawn){ node, id };
}

/* Gives each drawn node its place. The view reports nodes in the order
   it draws them, a block before its children, so walking the tree in
   that order meets them one by one; `next` is the report to meet. A
   `cards` node is not reported and draws one child, the next reported. */
static void place_drawn(Builder &b, List node, Where &where, int &next) {
  bool cards = node[0] == <cards>;
  if (!cards) {
    if (next == b.drawn_count) return;
    b.drawn[next++].where = where;
    if (!is_block(node)) return;
  }
  if (where.depth == DEPTH) return;
  for (int i = 2; i < node.len() && next < b.drawn_count; i++) {
    if (cards && (void *) b.drawn[next].node != (void *) (List) node[i])
      continue;
    where.at[where.depth++] = i;
    place_drawn(b, node[i], where, next);
    where.depth--;
    if (cards) return;
  }
}

module bool same_place(Where a, Where b) =>
  a.depth == b.depth && !memcmp(a.at, b.at, a.depth * sizeof a.at[0]);

// Selects the innermost node drawn under the pointer: the last one drawn.
module void select_under(Builder &b, Ui ui) {
  b.selected = false;
  for (int i = 0; i < b.drawn_count; i++) {
    if (!within(ui.get_rect(b.drawn[i].id), b.pointer)) continue;
    b.where = b.drawn[i].where;
    b.selected = true;
  }
  b.refill = true;
}

// The id CUI gave the selected node's component this frame, or 0.
static cui_id selected_id(Builder &b) {
  if (!b.selected) return 0;
  for (int i = 0; i < b.drawn_count; i++)
    if (same_place(b.drawn[i].where, b.where)) return b.drawn[i].id;
  return 0;
}

// Whether the node at `inner` is the node at `outer` or inside it.
static bool inside(Where inner, Where outer) =>
  inner.depth >= outer.depth &&
  !memcmp(inner.at, outer.at, outer.depth * sizeof outer.at[0]);

/* Whether the node at `where` moves with a drag: the selection and what
   is inside it, unless the drag carries a new component. */
static bool carried(Builder &b, Where where) =>
  !b.carry && inside(where, b.where);

// The rectangle of the node drawn at `where`, or an empty one.
module cui_rect drawn_at(Builder &b, Ui ui, Where where) {
  for (int i = 0; i < b.drawn_count; i++)
    if (same_place(b.drawn[i].where, where))
      return ui.get_rect(b.drawn[i].id);
  return (cui_rect){ 0 };
}

module bool is_row(List block) {
  Var dir = option(block, "dir");
  return block[0] == <row> || (!dir.is_void() && spelled(dir) == "row");
}

// The report of the node drawn at `where`, or -1.
static int drawn_index(Builder &b, Where where) {
  for (int i = 0; i < b.drawn_count; i++)
    if (same_place(b.drawn[i].where, where)) return i;
  return -1;
}

/* The block a drop at the pointer goes into: the innermost node drawn
   under the pointer, when it is a block and the pointer is not near its
   edge, and otherwise the block around that node. Near the edge of a
   block that fits its children tightly, this reaches the block around
   it. What moves with the drag is passed over, and with nothing under
   the pointer the block is the root. Returns -1 for none. */
static int aimed_block(Builder &b, Ui ui) {
  int hit = -1;
  for (int i = 0; i < b.drawn_count; i++)
    if (!carried(b, b.drawn[i].where) &&
        within(ui.get_rect(b.drawn[i].id), b.pointer))
      hit = i;
  if (hit < 0) return b.drawn_count && is_block(b.drawn[0].node) ? 0 : -1;
  cui_rect r = ui.get_rect(b.drawn[hit].id);
  cui_rect inner = { r.x + EDGE, r.y + EDGE, r.w - 2 * EDGE, r.h - 2 * EDGE };
  Where where = b.drawn[hit].where;
  if (is_block(b.drawn[hit].node) &&
      (!where.depth || within(inner, b.pointer)))
    return hit;
  // A `cards` node is not drawn, so the block around may be further out.
  while (where.depth) {
    where.depth--;
    int outer = drawn_index(b, where);
    if (outer >= 0) return outer;
  }
  return -1;
}

/* Finds where a drop would put the selection: the position before the
   first child whose middle the pointer has not passed, along the block's
   direction. `line` is where that is. */
module void aim(Builder &b, Ui ui) {
  int hit = aimed_block(b, ui);
  b.aimed = hit >= 0;
  if (!b.aimed) return;
  List block = b.drawn[hit].node;
  cui_rect area = ui.get_rect(b.drawn[hit].id);
  b.target = b.drawn[hit].where;
  b.target_id = b.drawn[hit].id;
  b.target_index = block.len();
  bool row = is_row(block);
  b.line = row ? (cui_rect){ area.x + 3, area.y + 3, 3, area.h - 6 }
               : (cui_rect){ area.x + 3, area.y + 3, area.w - 6, 3 };
  Where child = b.target;
  child.depth++;
  for (int i = 2; i < block.len(); i++) {
    child.at[child.depth - 1] = i;
    cui_rect r = drawn_at(b, ui, child);
    if (r.w <= 0 || carried(b, child)) continue;
    bool before = row ? b.pointer.x < r.x + r.w / 2
                      : b.pointer.y < r.y + r.h / 2;
    // The line sits before this child, or after it for a later one.
    float edge = row ? r.x + (before ? -4 : r.w + 1)
                     : r.y + (before ? -4 : r.h + 1);
    b.line = row ? (cui_rect){ edge, r.y, 3, r.h }
                 : (cui_rect){ r.x, edge, r.w, 3 };
    if (!before) continue;
    b.target_index = i;
    return;
  }
}

module Var whole(float value) => (Var) (int) (value < 0 ? value - 0.5f
                                                        : value + 0.5f);

/* Moves the selection to the aimed position. Taking the node out moves
   its later siblings down one place, and the target with them when it is
   one of them or inside one. */
module void drop(Builder &b) {
  Where from = b.where, to = b.target;
  int index = b.target_index, at = from.at[--from.depth];
  List node = node_at(b.tree, b.where);
  if (same_place(to, from)) {
    if (index == at || index == at + 1) return;
    if (index > at) index--;
  }
  else if (inside(to, from) && to.at[from.depth] > at) to.at[from.depth]--;
  List tree = replaced(b.tree, from, 0, without(node_at(b.tree, from), at));
  List block = node_at(tree, to);
  if (index > block.len()) index = block.len();
  change(b, replaced(tree, to, 0, inserted(block, index, node)));
  b.where = to;
  b.where.at[b.where.depth++] = index;
  b.refill = true;
}

// The size a drag of the handle asks for: the pointer's corner.
static cui_rect sized_to(Builder &b) {
  float w = b.pointer.x - b.chosen.x, h = b.pointer.y - b.chosen.y;
  return (cui_rect){ b.chosen.x, b.chosen.y, w < 8 ? 8 : w, h < 8 ? 8 : h };
}

// Gives the selection the size the handle was dragged to, as fixed sizes.
module void resize(Builder &b) {
  cui_rect to = sized_to(b);
  List node = node_at(b.tree, b.where);
  if (has_option(node, "width"))
    node = with_option(node, "width", whole(to.w));
  if (has_option(node, "height"))
    node = with_option(node, "height", whole(to.h));
  change(b, replaced(b.tree, b.where, 0, node));
  b.refill = true;
}

/* What the overlay paints: an outline of every block, the selection's
   outline and handle, and for a drag the block aimed at with the drop
   line, or the outline of where the selection would be. */
static typedef struct Marks {
  Builder *builder;
  cui_id selected, target;
  bool lined, ghosted;
  cui_rect line, ghost;
} Marks;

static void outline(cui_ctx *ui, cui_rect r, float grow, cui_color color,
                    float width) {
  if (r.w > 0)
    cui_draw_rect_border(
      ui, (cui_rect){ r.x - grow, r.y - grow, r.w + 2 * grow, r.h + 2 * grow },
      CUI_CORNERS(4), (cui_color){ 0 }, color, width);
}

// Paints when the frame ends, so the outlines are this frame's layout.
static void paint_marks(cui_ctx *ui, cui_rect area, void *user) {
  Marks *marks = user;
  Builder *b = marks.builder;
  cui_color accent = cui_color_of(ui, CUI_COLOR_ACCENT), faint = accent;
  faint.a = 70;
  for (int i = 0; i < b.drawn_count; i++)
    if (b.drawn[i].id && is_block(b.drawn[i].node))
      outline(ui, cui_get_rect(ui, b.drawn[i].id), 0, faint, 1);
  if (marks.target) outline(ui, cui_get_rect(ui, marks.target), 0, accent, 2);
  cui_rect r = cui_get_rect(ui, marks.selected);
  if (marks.selected) outline(ui, r, 2, accent, 2);
  if (marks.selected && r.w > 0 && !marks.target)
    cui_draw_rect(
      ui, (cui_rect){ r.x + r.w - HANDLE / 2, r.y + r.h - HANDLE / 2, HANDLE,
                      HANDLE }, CUI_CORNERS(2), accent);
  // The selected block's spacing handles; the one held is full colour.
  cui_color soft = accent;
  soft.a = 150;
  for (int i = 0; marks.selected && !marks.target && i < b.spacer_count; i++)
    cui_draw_rect(ui, b.spacers[i].at, CUI_CORNERS(2),
                  b.holding == i + 1 ? accent : soft);
  if (marks.lined) cui_draw_rect(ui, marks.line, CUI_CORNERS(1), accent);
  if (marks.ghosted) outline(ui, marks.ghost, 0, accent, 1);
}

module void canvas(Ui ui, Builder &b) {
  // A box has an id, and so a rectangle to ask for, only when given one.
  b.canvas_id = cui_box_begin(ui, &(cui_box){
    .id = "canvas", .dir = CUI_STACK, .width = CUI_FILL,
    .height = CUI_FILL, .border = 1, .scroll_x = true, .scroll_y = true });
  defer cui_box_end(ui);
  b.drawn_count = 0;
  // Only an edited tree is watched: a running one is drawn as it ships.
  b.view.watch(b.editing ? note_drawn : NULL, &b);
  ui.column (width: fill, height: fill) {
    /* CUI finds a component by an id made from its label, so a tree
       button labelled as a palette button would be that button. The
       tree's ids are made under a name of their own. */
    cui_push_id(ui, "edited-tree");
    defer cui_pop_id(ui);
    // A tree the inspector left half typed raises; the next edit mends it.
    try b.view.draw(ui);
    catch %(?cause *detail): {
      b.status = %"$(cause.repr()) $(detail.repr())";
      if (!b.editing) note(b, b.status);
    }
  }
  Where root = { 0 };
  int next = 0;
  place_drawn(b, b.tree, root, next);
  if (!b.editing) return;
  bool moving = (b.dragging && !b.sizing || b.carrying) && b.aimed;
  Marks marks = { &b, selected_id(b), moving ? b.target_id : 0,
                  moving, b.dragging && b.sizing, b.line, sized_to(b) };
  ui.canvas("marks", fill, fill, paint_marks, &marks, sizeof marks);
  node_menu(ui, b, "tree-menu");
  if (b.dragging || b.carrying) ui.set_cursor(CUI_CURSOR_MOVE);
  // A spacing handle, held or under the pointer, shows the way it moves.
  for (int i = 0; i < b.spacer_count; i++)
    if (b.holding == i + 1 ||
        (!b.holding && within(grown(b.spacers[i].at, 5), b.pointer)))
      ui.set_cursor(b.spacers[i].axis ? CUI_CURSOR_RESIZE_NS
                                      : CUI_CURSOR_RESIZE_EW);
}

/* The option that sets the padding of one side: the side's own, or its
   axis's, when set, and otherwise `pad`. */
static String padding_option(List node, String side, String axis) {
  if (!option(node, side).is_void()) return side;
  if (!option(node, axis).is_void()) return axis;
  return "pad";
}

static float option_value(List node, String name) {
  Var value = option(node, name);
  return is_number(value) ? value.double() : 0;
}

// A handle's bar, centred at `x`, `y`, lying across the way it moves.
static cui_rect bar(float x, float y, int axis) =>
  axis ? (cui_rect){ x - 9, y - 2, 18, 4 } : (cui_rect){ x - 2, y - 9, 4, 18 };

static void add_spacer(Builder &b, cui_rect at, String option, float value,
                       int axis, float scale) {
  if (b.spacer_count < SPACERS)
    b.spacers[b.spacer_count++] = (Spacer){ at, option, value, axis, scale };
}

/* Places a selected block's handles from the last frame's layout: one in
   the middle of each side's padding, never at a corner, where the size
   handle is, and one in each gap between its children. Dragging a gap's
   handle moves every child before it, so its option changes by the
   movement shared among them. */
module void place_spacers(Builder &b, Ui ui) {
  b.spacer_count = 0;
  if (!b.selected || !b.editing) return;
  List node = node_at(b.tree, b.where);
  cui_rect r = drawn_at(b, ui, b.where);
  if (!is_block(node) || r.w <= 0) return;
  if (has_option(node, "pad")) {
    String sides[4][2] = { { "pad_top", "pad_y" }, { "pad_bottom", "pad_y" },
                           { "pad_left", "pad_x" }, { "pad_right", "pad_x" } };
    for (int i = 0; i < 4; i++) {
      String name = padding_option(node, sides[i][0], sides[i][1]);
      float value = option_value(node, name);
      float inset = value / 2 > 3 ? value / 2 : 3;
      int axis = i < 2;
      float sign = i % 2 ? -1 : 1;
      float x = axis ? r.x + r.w / 2 : i == 2 ? r.x + inset
                                              : r.x + r.w - inset;
      float y = !axis ? r.y + r.h / 2 : i == 0 ? r.y + inset
                                               : r.y + r.h - inset;
      add_spacer(b, bar(x, y, axis), name, value, axis, sign);
    }
  }
  if (!has_option(node, "gap")) return;
  bool row = is_row(node);
  Where child = b.where;
  child.depth++;
  cui_rect before = { 0 };
  int gaps = 0;
  for (int i = 2; i < node.len(); i++) {
    child.at[child.depth - 1] = i;
    cui_rect next = drawn_at(b, ui, child);
    if (next.w <= 0) continue;
    if (before.w > 0) {
      float apart = row ? next.x - (before.x + before.w)
                        : next.y - (before.y + before.h);
      float x = row ? next.x - apart / 2 : next.x + next.w / 2;
      float y = row ? next.y + next.h / 2 : next.y - apart / 2;
      gaps++;
      add_spacer(b, bar(x, y, !row), "gap", apart, !row, 1.0f / gaps);
    }
    before = next;
  }
}

/* Sets the held handle's option from how far the pointer has moved. The
   first change of a drag is one step of undo, and the rest join it. */
module void drag_spacer(Builder &b) {
  Spacer held = b.held;
  float moved = held.axis ? b.pointer.y - b.held_from.y
                          : b.pointer.x - b.held_from.x;
  float to = held.value + moved * held.scale;
  int value = (int) (to > 0 ? to + 0.5f : 0);
  List node = node_at(b.tree, b.where);
  b.status = %"$(held.option.replace("_", "-")) $value";
  if (is_number(option(node, held.option)) &&
      option(node, held.option).int() == value)
    return;
  List tree = replaced(b.tree, b.where, 0,
                       with_option(node, held.option, value));
  if (b.held_changed) {
    b.tree = tree;
    b.view.set(tree);
  }
  else change(b, tree);
  b.held_changed = b.refill = true;
}
