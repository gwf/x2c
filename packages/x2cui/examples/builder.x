/*  builder.x -- edit a UI held as a List by pointing at it

    The window draws a tree with a `View`, as a finished program would,
    between a palette of components and an inspector. In edit mode a
    click selects the component under the pointer instead of pressing it:
    the palette adds a component after the selection or inside a selected
    block, the inspector edits the selection's arguments and options, and
    the toolbar moves or deletes it. Dragging a component moves it to the
    line shown, among its siblings or into another block. In run mode the
    tree behaves as it will in a program. The tree uses CUI's own layout,
    so a component's place is its position among its siblings.

    Usage:
      builder [FILE]             edit FILE, a tree written as one datum
      builder --check IMAGE.png  select, add, and run off screen

    A file `FILE.lisp` beside FILE, when there is one, is evaluated first
    and defines what the tree's handlers call.
*/
import "x2cui" with App, Offscreen, TextField, Ui, View, ViewLisp;

#include "datum.x"
#include "path.x"
#include <stdio.h>
#include <string.h>

enum { DEPTH = 32, DRAWN = 2048, FIELDS = 64, UNDO = 200 };

// How near a block's edge a drop goes beside the block, not into it.
static const float EDGE = 6;
// The side of the square handle at the selection's corner.
static const float HANDLE = 10;

// Where a node is: the position of each node on the way from the root.
typedef struct Where { int depth; int at[DEPTH]; } Where;

/* A node the view drew this frame, the id CUI gave its component, and
   where the node is. Equal Lists are one List, so two equal nodes are
   told apart only by where they are. */
typedef struct Drawn { List node; cui_id id; Where where; } Drawn;

typedef struct Builder {
  Lisp lisp;
  View view;
  List tree;
  Array undo;
  String file, status;
  bool editing, selected;
  Where where;
  // What the view drew last frame, for hit tests and the outline.
  Drawn drawn[DRAWN];
  int drawn_count;
  // The pointer as the input hook saw it, and a click it kept.
  cui_id canvas_id;
  cui_rect canvas;
  cui_vec2 pointer;
  bool clicked;
  /* A press held on the tree, where it began, whether the pointer has
     moved far enough to be dragging, and a drag just released. */
  bool pressed, dragging, dropped;
  cui_vec2 press;
  /* Where a drop would put the selection: a block and a position, with
     a line there. Into a `free` block it is a point instead, with the
     outline `ghost` there. */
  bool aimed, placed;
  Where target;
  cui_id target_id;
  int target_index;
  cui_rect line, ghost;
  cui_vec2 place;
  /* The selection's rectangle, the handle at its corner, and a press
     that began on the handle and so sizes the selection. */
  cui_rect chosen, handle;
  bool sizing, sized;
  // The inspector's text, reloaded from the node when `refill` is set.
  TextField fields[FIELDS];
  bool refill;
  int bound;
  // Where the check finds the builder's own controls.
  cui_rect mode_button, add_button, free_button, first_field;
} Builder;

static String sample = %"
  (column ((pad 24) (gap 12))
    (heading () \"A tiny counter\" 2)
    (button ((variant primary) (on-click bump)) \"Add one\")
    (text () (eval (ui-text \"Clicked \" clicks \" times.\"))))";

static String sample_program = %"
  (def clicks 0)
  (def bump (lambda () (def clicks (+ clicks 1))))";

// trees

static String spelled(Var name) => ((Atom) name).str().replace("-", "_");

// A node is a List that starts with a component's name.
static bool is_node(Var value) =>
  value is <list> && ((List) value).len() >= 2 &&
  ((List) value)[0].is_atom();

static List node_at(List tree, Where where) {
  List node = tree;
  for (int i = 0; i < where.depth; i++) node = node[where.at[i]];
  return node;
}

// `node` with the node at `where`, from `level` down, replaced by `with`.
static List replaced(List node, Where where, int level, List with) {
  if (level == where.depth) return with;
  Array items = [];
  for (int i = 0; i < node.len(); i++)
    items.push(i == where.at[level]
                 ? (Var) replaced(node[i], where, level + 1, with) : node[i]);
  return items.list_free();
}

static List without(List node, int index) {
  Array items = [];
  for (int i = 0; i < node.len(); i++)
    if (i != index) items.push(node[i]);
  return items.list_free();
}

// `node` with `child` at `index`; an index past the end appends.
static List inserted(List node, int index, Var child) {
  Array items = [];
  for (int i = 0; i < node.len(); i++) {
    if (i == index) items.push(child);
    items.push(node[i]);
  }
  if (index >= node.len()) items.push(child);
  return items.list_free();
}

// The value of the option `name` of `node`, or void.
static Var option(List node, String name) {
  foreach (List row in (List) node[1])
    if (spelled(row[0]) == name) return row[1];
  return void;
}

// `node` with its option `name` set to `value`, or removed for void.
static List with_option(List node, String name, Var value) {
  Array rows = [];
  bool placed = value.is_void();
  foreach (List row in (List) node[1]) {
    if (spelled(row[0]) != name) rows.push(row);
    else if (!value.is_void()) {
      rows.push(%( $(row[0]) $value ));
      placed = true;
    }
  }
  if (!placed) rows.push(%( $(Atom.intern(name)) $value ));
  Array items = [node[0], rows.list_free()];
  for (int i = 2; i < node.len(); i++) items.push(node[i]);
  return items.list_free();
}

static List with_argument(List node, int at, Var value) {
  Array items = [];
  for (int i = 0; i < node.len(); i++) items.push(i == at ? value : node[i]);
  return items.list_free();
}

// text

static String written(Var value) {
  Buffer out = auto Buffer.new();
  if (!out.write_datum(value, 0)) return value.repr();
  return out;
}

static bool read_value(String text, Var &value) {
  unsigned cursor = 0;
  try return text.read_lisp_form(cursor, value) == <value>;
  catch %(?cause *detail): return false;
}

// the document

/* The table row that describes the component `name`. A `free` block is
   a box that places its children, and has the box's row. */
static List component(String name) {
  String known = name == "free" ? "box" : name;
  return View.components().find(%!(List row) => row[0] == known);
}

static bool has_option(List node, String name) {
  List row = component(spelled(node[0]));
  foreach (List described in row ? (List) row[3] : %())
    if (described[0] == name) return true;
  return false;
}

static bool is_block(List node) {
  String name = spelled(node[0]);
  List row = component(name);
  return name == "cards" || (row && (int) row[1]);
}

static void change(Builder &b, List tree) {
  if (b.undo.len() == UNDO) b.undo.remove(0);
  b.undo.push(b.tree);
  b.tree = tree;
  b.view.set(tree);
  b.status = NULL;
}

static void undo(Builder &b) {
  if (!b.undo.len()) return;
  b.tree = b.undo[b.undo.len() - 1];
  b.undo.pop();
  b.view.set(b.tree);
  b.selected = false;
}

// A new node of the component `row` describes, with an argument of each
// kind filled in and a fresh global for a value it edits.
static List fresh(Builder &b, String name) {
  List row = component(name);
  Array options = [], items = [];
  foreach (List argument in (List) row[2]) {
    String kind = argument[1], what = argument[0];
    if (kind == "bound" || kind == "field") {
      String global = %"value$(++b.bound)";
      b.lisp.set_global(global, kind == "field" ? (Var) "text" : (Var) 0);
      options.push(%( bind $(Atom.intern(global)) ));
    }
    else if (kind == "text")
      items.push(what == "id" ? %"$name$(++b.bound)" : name);
    else if (kind == "items") items.push(%("One" "Two" "Three"));
    else if (kind == "enum") items.push(Atom.intern(argument[2]));
    else items.push(what == "max" ? 1 : what == "level" ? 2 : 0);
  }
  return %( $(Atom.intern(name)) $(options.list_free())
            @(items.list_free()) );
}

/* Adds a node inside the selected block, after the selected component, or
   at the end of the root. */
static void add(Builder &b, String name) {
  List node = fresh(b, name);
  Where where = b.where;
  if (!b.selected) where.depth = 0;
  List target = node_at(b.tree, where);
  int index = target.len();
  if (!is_block(target)) {
    if (!where.depth) {
      b.status = "Select a block to add to.";
      return;
    }
    index = where.at[--where.depth] + 1;
    target = node_at(b.tree, where);
  }
  change(b, replaced(b.tree, where, 0, inserted(target, index, node)));
  b.where = where;
  b.where.at[b.where.depth++] = index;
  b.selected = b.refill = true;
}

static void remove_selected(Builder &b) {
  if (!b.selected || !b.where.depth) return;
  Where parent = b.where;
  int index = parent.at[--parent.depth];
  change(b, replaced(b.tree, parent, 0,
                     without(node_at(b.tree, parent), index)));
  b.selected = false;
}

// Moves the selection one place among its siblings, toward `step`.
static void move_selected(Builder &b, int step) {
  if (!b.selected || !b.where.depth) return;
  Where parent = b.where;
  int index = parent.at[--parent.depth], other = index + step;
  List block = node_at(b.tree, parent);
  if (other < 2 || other >= block.len() || !is_node(block[other])) return;
  List moved = inserted(without(block, index), other, block[index]);
  change(b, replaced(b.tree, parent, 0, moved));
  b.where.at[parent.depth] = other;
}

static void save(Builder &b) {
  Path path = b.file;
  path.write_text(written(b.tree) + "\n");
  b.status = %"Saved $(b.file)";
}

// input and selection

static bool within(cui_rect r, cui_vec2 p) =>
  p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h;

/* In edit mode a press on the tree is kept for `select_under` and goes no
   further, so the component under it is not pressed. A press that moves
   more than a few points becomes a drag, which its release drops. */
static bool capture(cui_ctx *ui, const cui_input_event *event, void *user) {
  Builder *b = user;
  if (event.kind == CUI_INPUT_MOUSE_MOVE) {
    b.pointer = event.position;
    float dx = b.pointer.x - b.press.x, dy = b.pointer.y - b.press.y;
    if (b.pressed && dx * dx + dy * dy > 16) b.dragging = true;
  }
  if (event.kind != CUI_INPUT_MOUSE_BUTTON || !b.editing) return false;
  if (event.button == CUI_MOUSE_LEFT && !event.down && b.pressed) {
    b.dropped = b.dragging && !b.sizing;
    b.sized = b.dragging && b.sizing;
    b.pressed = b.dragging = b.sizing = false;
    return true;
  }
  if (!within(b.canvas, b.pointer)) return false;
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

static bool same_place(Where a, Where b) =>
  a.depth == b.depth && !memcmp(a.at, b.at, a.depth * sizeof a.at[0]);

// Selects the innermost node drawn under the pointer: the last one drawn.
static void select_under(Builder &b, Ui ui) {
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

// dragging

// Whether the node at `inner` is the node at `outer` or inside it.
static bool inside(Where inner, Where outer) =>
  inner.depth >= outer.depth &&
  !memcmp(inner.at, outer.at, outer.depth * sizeof outer.at[0]);

// The rectangle of the node drawn at `where`, or an empty one.
static cui_rect drawn_at(Builder &b, Ui ui, Where where) {
  for (int i = 0; i < b.drawn_count; i++)
    if (same_place(b.drawn[i].where, where))
      return ui.get_rect(b.drawn[i].id);
  return (cui_rect){ 0 };
}

static bool is_row(List block) {
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
   it. The selection and what is inside it are passed over, and with
   nothing under the pointer the block is the root. Returns -1 for none. */
static int aimed_block(Builder &b, Ui ui) {
  int hit = -1;
  for (int i = 0; i < b.drawn_count; i++)
    if (!inside(b.drawn[i].where, b.where) &&
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

/* Finds where a drop would put the selection. In a `free` block that is
   the point that keeps the selection under the pointer as it was pressed.
   In any other block it is the position before the first child whose
   middle the pointer has not passed, along the block's direction, and
   `line` is where that is. */
static void aim(Builder &b, Ui ui) {
  int hit = aimed_block(b, ui);
  b.aimed = hit >= 0;
  if (!b.aimed) return;
  List block = b.drawn[hit].node;
  cui_rect area = ui.get_rect(b.drawn[hit].id);
  b.target = b.drawn[hit].where;
  b.target_id = b.drawn[hit].id;
  b.target_index = block.len();
  b.placed = block[0] == <free>;
  if (b.placed) {
    b.ghost = (cui_rect){ b.chosen.x + b.pointer.x - b.press.x,
                          b.chosen.y + b.pointer.y - b.press.y,
                          b.chosen.w, b.chosen.h };
    b.place = (cui_vec2){ b.ghost.x - area.x, b.ghost.y - area.y };
    return;
  }
  bool row = is_row(block);
  b.line = row ? (cui_rect){ area.x + 3, area.y + 3, 3, area.h - 6 }
               : (cui_rect){ area.x + 3, area.y + 3, area.w - 6, 3 };
  Where child = b.target;
  child.depth++;
  for (int i = 2; i < block.len(); i++) {
    child.at[child.depth - 1] = i;
    cui_rect r = drawn_at(b, ui, child);
    if (r.w <= 0 || same_place(child, b.where)) continue;
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

static Var whole(float value) => (Var) (int) (value < 0 ? value - 0.5f
                                                        : value + 0.5f);

/* Moves the selection to the aimed position. A node dropped into a
   `free` block takes the point as its `x` and `y`, stays in its place
   among its siblings when the block is its own, and goes last, which is
   on top, when it is not. A node dropped anywhere else gives them up.
   Taking the node out moves its later siblings down one place, and the
   target with them when it is one of them or inside one. */
static void drop(Builder &b) {
  Where from = b.where, to = b.target;
  int index = b.target_index, at = from.at[--from.depth];
  List was = node_at(b.tree, b.where);
  List node = with_option(
    with_option(was, "x", b.placed ? whole(b.place.x) : void),
    "y", b.placed ? whole(b.place.y) : void);
  if (same_place(to, from)) {
    if (b.placed || index == at || index == at + 1) {
      if ((void *) node != (void *) was)
        change(b, replaced(b.tree, b.where, 0, node));
      b.refill = true;
      return;
    }
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
static void resize(Builder &b) {
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
typedef struct Marks {
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
  if (marks.lined) cui_draw_rect(ui, marks.line, CUI_CORNERS(1), accent);
  if (marks.ghosted) outline(ui, marks.ghost, 0, accent, 1);
}

// the window

static void toolbar(Ui ui, Builder &b) {
  ui.row (gap: 8, align: center, pad: 8) {
    if (ui.button(b.editing ? "Run" : "Edit", variant: primary, size: sm)) {
      b.editing = !b.editing;
      b.status = NULL;
    }
    b.mode_button = ui.last_rect();
    if (ui.button("Undo", size: sm)) undo(b);
    if (ui.button("Parent", size: sm) && b.selected && b.where.depth) {
      b.where.depth--;
      b.refill = true;
    }
    if (ui.button("Up", size: sm)) move_selected(b, -1);
    if (ui.button("Down", size: sm)) move_selected(b, 1);
    if (ui.button("Delete", size: sm)) remove_selected(b);
    if (ui.button("Save", size: sm)) save(b);
    ui.spacer();
    ui.muted(b.status ? b.status : b.file);
  }
}

static void palette(Ui ui, Builder &b) {
  ui.scroll (id: "palette", width: 150, height: fill, pad: 8, gap: 2) {
    foreach (List row in View.components()) {
      String name = row[0];
      if (ui.button(name, variant: ghost, size: sm, width: fill)) add(b, name);
      if (name == "button") b.add_button = ui.last_rect();
    }
    if (ui.button("free", variant: ghost, size: sm, width: fill))
      add(b, "free");
    b.free_button = ui.last_rect();
  }
}

static void canvas(Ui ui, Builder &b) {
  // A box has an id, and so a rectangle to ask for, only when given one.
  b.canvas_id = cui_box_begin(ui, &(cui_box){
    .id = "canvas", .dir = CUI_STACK, .width = CUI_FILL,
    .height = CUI_FILL, .border = 1 });
  defer cui_box_end(ui);
  b.drawn_count = 0;
  // Only an edited tree is watched: a running one is drawn as it ships.
  b.view.watch(b.editing ? note_drawn : NULL, &b);
  ui.column (width: fill, height: fill) {
    // A tree the inspector left half typed raises; the next edit mends it.
    try b.view.draw(ui);
    catch %(?cause *detail): b.status = %"$(cause.repr()) $(detail.repr())";
  }
  Where root = { 0 };
  int next = 0;
  place_drawn(b, b.tree, root, next);
  if (!b.editing) return;
  bool moving = b.dragging && !b.sizing && b.aimed;
  Marks marks = { &b, selected_id(b), moving ? b.target_id : 0,
                  moving && !b.placed, b.dragging && (b.sizing || b.placed),
                  b.line, b.sizing ? sized_to(b) : b.ghost };
  if (b.dragging && !b.sizing && !b.aimed) marks.ghosted = false;
  ui.canvas("marks", fill, fill, paint_marks, &marks, sizeof marks);
  if (b.dragging) ui.set_cursor(CUI_CURSOR_MOVE);
}

/* One text field of the inspector, showing `value`. Returns 1 with `out`
   set when the text was changed to something that reads as a value, and 2
   when it was emptied. Text that starts a form is read, and other text
   of a `text` kind is itself the value. */
static int edited(Ui ui, Builder &b, int slot, String label, String kind,
                  Var value, Var &out) {
  if (slot >= FIELDS) return 0;
  TextField field = b.fields[slot];
  if (b.refill) {
    field.buffer[0] = 0;
    if (!value.is_void())
      field.set(kind == "text" && value is <string> ? (String) value
                                                    : written(value));
  }
  int flags = ui.input(%"inspect-$slot", field, label: label, size: sm);
  if (!slot) b.first_field = ui.last_rect();
  if (!(flags & CUI_CHANGED)) return 0;
  if (field.empty()) return 2;
  if (kind == "text" && field.buffer[0] != '(') {
    out = field.text();
    return 1;
  }
  return read_value(field.text(), out);
}

static void inspector(Ui ui, Builder &b) {
  ui.scroll (id: "inspector", width: 260, height: fill, pad: 12, gap: 8) {
    if (!b.selected) {
      ui.muted(b.editing ? "Click a component to select it."
                         : "The tree is running. Edit to change it.");
      return;
    }
    List node = node_at(b.tree, b.where), edit = NULL;
    String name = spelled(node[0]);
    List row = component(name);
    ui.heading(name, 4);
    int slot = 0, at = 2;
    Var value = void;
    foreach (List argument in row ? (List) row[2] : %()) {
      String kind = argument[1];
      if (kind == "bound" || kind == "field") continue;
      if (at < node.len() &&
          edited(ui, b, slot, argument[0], kind, node[at], value) == 1)
        edit = with_argument(node, at, value);
      slot++;
      at++;
    }
    foreach (String own in %("id" "bind" "on_click" "show" "x" "y")) {
      int did = edited(ui, b, slot++, own, "form", option(node, own), value);
      if (did) edit = with_option(node, own, did == 1 ? value : void);
    }
    ui.separator();
    foreach (List described in row ? (List) row[3] : %()) {
      String what = described[0], kind = described[1];
      Var now = option(node, what);
      if (kind == "bool") {
        bool on = !now.is_void() && now.double() != 0;
        if (ui.switch(what, on))
          edit = with_option(node, what, on ? (Var) 1 : void);
      }
      else if (kind == "enum") {
        List members = described.cdr().cdr();
        int index = 0, i = 1;
        foreach (String member in members) {
          if (!now.is_void() && spelled(now) == member) index = i;
          i++;
        }
        ui.muted(what);
        if (ui.select(%"inspect-$what", %("default" @members), index))
          edit = with_option(node, what, index
            ? (Var) Atom.intern(members[index - 1]) : void);
      }
      else {
        int did = edited(ui, b, slot++, what, kind, now, value);
        if (did) edit = with_option(node, what, did == 1 ? value : void);
      }
    }
    b.refill = false;
    if (edit) change(b, replaced(b.tree, b.where, 0, edit));
  }
}

static void draw(Ui ui, Builder &b) {
  // Rectangles are read before this frame submits anything: they are the
  // last frame's layout, which is what the pointer was aimed at.
  b.canvas = ui.get_rect(b.canvas_id);
  if (b.clicked) select_under(b, ui);
  b.clicked = false;
  if (!b.pressed || b.sizing)
    b.chosen = b.selected ? drawn_at(b, ui, b.where) : (cui_rect){ 0 };
  else if (!b.dragging && b.selected) b.chosen = drawn_at(b, ui, b.where);
  b.handle = (cui_rect){ b.chosen.x + b.chosen.w - HANDLE,
                         b.chosen.y + b.chosen.h - HANDLE, 2 * HANDLE,
                         2 * HANDLE };
  if (b.chosen.w <= 0) b.handle = (cui_rect){ 0 };
  b.aimed = false;
  if ((b.dragging || b.dropped) && b.selected && b.where.depth) aim(b, ui);
  if (b.dropped && b.aimed) drop(b);
  if (b.sized && b.selected) resize(b);
  b.dropped = b.sized = false;
  ui.column (width: fill, height: fill) {
    toolbar(ui, b);
    ui.separator();
    ui.row (width: fill, height: fill) {
      palette(ui, b);
      canvas(ui, b);
      inspector(ui, b);
    }
  }
}

// starting

static void open_file(Builder &b, Ui ui, String file) {
  b.lisp = Lisp.new();
  ViewLisp.install(b.lisp);
  b.file = file ? file : "builder.tree";
  Path saved = b.file, program = %"$(b.file).lisp";
  String text = file && saved.exists() ? saved.read_text() : sample;
  if (program.exists()) b.lisp.eval_string(program.read_text());
  else if (!file) b.lisp.eval_string(sample_program);
  Var tree = void;
  if (!read_value(text, tree) || !is_node(tree))
    raise %(bad-arg (operation "builder") (path $(b.file))
            (reason "the file is not one tree"));
  b.tree = tree;
  b.undo = [];
  b.view = View.new(b.lisp, "ui");
  b.view.set(b.tree);
  b.editing = true;
  for (int i = 0; i < FIELDS; i++) b.fields[i] = TextField.new(512);
  ui.set_input_hook(capture, &b);
}

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

// The rectangle of the first `name` component the view drew.
static cui_rect drawn_rect(Builder &b, Ui ui, Symbol name) {
  for (int i = 0; i < b.drawn_count; i++)
    if (b.drawn[i].node[0] == name) return ui.get_rect(b.drawn[i].id);
  return (cui_rect){ 0 };
}

static int clicks(Builder &b) {
  Var value = void;
  return b.lisp.try_get("clicks", value) ? value.int() : -1;
}

static int check(String image) {
  static Builder b;
  Offscreen screen = auto Offscreen.open(1000, 640);
  Ui ui = screen.ui();
  open_file(b, ui, NULL);
  for (int i = 0; i < 3; i++) frame(screen, b);

  // In edit mode a click selects the button and does not press it.
  click(screen, b, drawn_rect(b, ui, <button>));
  int selects = b.selected && node_at(b.tree, b.where)[0] == <button> &&
                clicks(b) == 0;
  printf("edit: selected %s, clicked %d\n",
         b.selected ? written(node_at(b.tree, b.where)[0]) : "nothing",
         clicks(b));

  // The palette adds a button after the selection.
  int before = b.tree.len();
  click(screen, b, b.add_button);
  int adds = b.tree.len() == before + 1 && is_node(b.tree[4]);
  printf("add: %d children, selected position %d\n", b.tree.len() - 2,
         b.where.at[0]);

  // In run mode the same click presses the button.
  cui_rect pressed = drawn_rect(b, ui, <button>);
  click(screen, b, b.mode_button);
  click(screen, b, pressed);
  int runs = !b.editing && clicks(b) == 1;
  printf("run: clicked %d\n", clicks(b));

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

  /* A `free` block places its children at their `x` and `y`. A drag
     inside it moves a child by as much as the pointer moved. */
  Var placed = void;
  read_value(%"(column ((pad 24))
                 (free ((width 400) (height 300) (border 1))
                   (button () \"A\") (button ((x 100) (y 50)) \"B\")))",
             placed);
  change(b, placed);
  b.selected = false;
  for (int i = 0; i < 3; i++) frame(screen, b);
  Where inner = { 1, { 2 } }, second_child = { 2, { 2, 3 } };
  cui_rect sheet = drawn_at(b, ui, inner);
  cui_rect at = drawn_at(b, ui, second_child);
  int places = at.x == sheet.x + 100 && at.y == sheet.y + 50;
  printf("free: sheet at %g,%g, B at %g,%g\n", sheet.x, sheet.y, at.x, at.y);
  drag(screen, b, at, at.x + at.w / 2 + 40, at.y + at.h / 2 + 30,
       image + ".free.png");
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect now = drawn_at(b, ui, second_child);
  int frees = now.x == at.x + 40 && now.y == at.y + 30 &&
              option(node_at(b.tree, second_child), "x").int() == 140 &&
              option(node_at(b.tree, second_child), "y").int() == 80;
  printf("free drag: %s\n", written(b.tree));
  // A drag of the handle at the selection's corner sets fixed sizes.
  for (int i = 0; i < 60; i++) frame(screen, b);
  click(screen, b, now);
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect corner = { now.x + now.w - 1, now.y + now.h - 1, 2, 2 };
  drag(screen, b, corner, now.x + now.w + 30, now.y + now.h + 10, NULL);
  for (int i = 0; i < 3; i++) frame(screen, b);
  cui_rect grown = drawn_at(b, ui, second_child);
  int sizes = grown.w == whole(now.w + 30).int() &&
              option(node_at(b.tree, second_child), "x").int() == 140;
  printf("resize: %g by %g to %g by %g, %s\n", now.w, now.h, grown.w,
         grown.h, written(b.tree));
  return fills && besides && places && frees && sizes && selects && adds &&
         runs && edits && moves && removes && undoes &&
         saves && picks && keeps && reparents && reorders && stays ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc == 3 && !strcmp(argv[1], "--check")) return check(argv[2]);
  static Builder b;
  App app = auto App.open(title: "Builder", width: 1100, height: 700);
  open_file(b, app.ui(), argc > 1 ? argv[1] : NULL);
  while (app.frame()) draw(app.ui(), b);
  return 0;
}
