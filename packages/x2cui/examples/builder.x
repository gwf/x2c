/*  builder.x -- edit a UI held as a List by pointing at it

    The window draws a tree with a `View`, as a finished program would,
    between a palette of components and an inspector. In edit mode a
    click selects the component under the pointer instead of pressing it:
    the palette adds a component after the selection or inside a selected
    block, the inspector edits the selection's arguments and options, and
    the toolbar moves or deletes it. Dragging a component moves it to the
    line shown, among its siblings or into another block. The inspector
    groups the options, sets a block's spacing and alignment, and gives
    sizes as Auto, Fit, Fill, or Fixed. An outline under the palette
    lists every node, and a click on a line selects its node. A right
    click on the tree or the outline, or a key, selects around the
    selection, wraps it in a row or column, unwraps a block, duplicates,
    moves, and deletes; `keys` lists them. In run mode the tree behaves
    as it will in a program. The tree uses CUI's own layout,
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

enum { DEPTH = 32, DRAWN = 2048, FIELDS = 64, LISTED = 64, UNDO = 200 };

// How near a block's edge a drop goes beside the block, not into it.
static const float EDGE = 6;
// The side of the square handle at the selection's corner.
static const float HANDLE = 10;
// The width of the inspector's labels.
static const float LABEL = 96;

// Where a node is: the position of each node on the way from the root.
typedef struct Where { int depth; int at[DEPTH]; } Where;

/* A node the view drew this frame, the id CUI gave its component, and
   where the node is. Equal Lists are one List, so two equal nodes are
   told apart only by where they are. */
typedef struct Drawn { List node; cui_id id; Where where; } Drawn;

// What a key or a menu item asks of the selection.
typedef enum Command {
  NOTHING, TO_PARENT, TO_CHILD, TO_PREVIOUS, TO_NEXT, MOVE_UP, MOVE_DOWN,
  WRAP_ROW, WRAP_COLUMN, UNWRAP, DUPLICATE, DELETE, UNDO_LAST, REDO_LAST
} Command;

// The inspector's groups of options.
enum { CONTENT, LAYOUT, SIZE, STYLE, BEHAVIOR, OTHER, GROUPS };

#ifdef __APPLE__
#define PRIMARY "Cmd "
#else
#define PRIMARY "Ctrl "
#endif

/* A command's key, and for one the menu offers, its label and the key as
   the menu shows it. */
typedef struct Key {
  Command command;
  int mods;
  cui_key key;
  char *label, *shown;
} Key;

static Key keys[] = {
  { WRAP_ROW, CUI_MOD_SHIFT, CUI_KEY_R, "Wrap in row", "Shift R" },
  { WRAP_COLUMN, CUI_MOD_SHIFT, CUI_KEY_C, "Wrap in column", "Shift C" },
  { UNWRAP, CUI_MOD_SHIFT, CUI_KEY_U, "Unwrap", "Shift U" },
  { DUPLICATE, CUI_MOD_PRIMARY, CUI_KEY_D, "Duplicate", PRIMARY "D" },
  { MOVE_UP, CUI_MOD_ALT, CUI_KEY_UP, "Move earlier", "Alt Up" },
  { MOVE_DOWN, CUI_MOD_ALT, CUI_KEY_DOWN, "Move later", "Alt Down" },
  { TO_PARENT, 0, CUI_KEY_LEFT, "Select parent", "Left" },
  { TO_CHILD, 0, CUI_KEY_RIGHT, "Select first child", "Right" },
  { DELETE, 0, CUI_KEY_DELETE, "Delete", "Delete" },
  { DELETE, 0, CUI_KEY_BACKSPACE },
  { TO_PREVIOUS, 0, CUI_KEY_UP },
  { TO_NEXT, 0, CUI_KEY_DOWN },
  { UNDO_LAST, CUI_MOD_PRIMARY, CUI_KEY_Z },
  { REDO_LAST, CUI_MOD_PRIMARY | CUI_MOD_SHIFT, CUI_KEY_Z },
};

typedef struct Builder {
  Lisp lisp;
  View view;
  List tree;
  // Trees before each change, and trees an undo went back from.
  Array undo, redo;
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
  // Where a drop would put the selection: a block, a position, a line.
  bool aimed;
  Where target;
  cui_id target_id;
  int target_index;
  cui_rect line;
  /* The selection's rectangle, the handle at its corner, and a press
     that began on the handle and so sizes the selection. */
  cui_rect chosen, handle;
  bool sizing, sized;
  // The inspector's text, reloaded from the node when `refill` is set.
  TextField fields[FIELDS];
  bool refill;
  int bound, slot;
  /* The field an edit of the inspector came from, while that field keeps
     the keyboard or the pointer; its edits are one step of undo. */
  String visiting;
  // Open groups, whether every option shows, and the text that finds one.
  bool open[GROUPS], open_around, all;
  TextField search;
  // What a key or a menu item asked for, done when the next frame starts.
  Command command;
  // Whether a menu was open last frame, and whether one is open in this.
  bool menu_open, menu_shown;
  /* The outline's area, each line and where its node is, and a press on
     a line, kept by the input hook as the line's number plus one. */
  cui_id outline_id;
  cui_rect outline_area, listed[LISTED];
  Where listed_where[LISTED];
  int lines, picked;
  // Where the check finds the builder's own controls.
  cui_rect mode_button, add_button, first_field, all_switch;
  Map located;
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

static List component(String name) =>
  View.components().find(%!(List row) => row[0] == name);

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
  b.redo = [];
  b.tree = tree;
  b.view.set(tree);
  b.status = NULL;
  b.visiting = NULL;
}

// Moves the last tree of `from` to the tree shown, and the shown to `to`.
static void step_back(Builder &b, Array from, Array to) {
  if (!from.len()) return;
  to.push(b.tree);
  b.tree = from[from.len() - 1];
  from.pop();
  b.view.set(b.tree);
  b.selected = false;
  b.visiting = NULL;
}

static void undo(Builder &b) => step_back(b, b.undo, b.redo);

static void redo(Builder &b) => step_back(b, b.redo, b.undo);

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

static void select_at(Builder &b, Where where) {
  b.where = where;
  b.selected = b.refill = true;
}

static void select_parent(Builder &b) {
  if (!b.selected || !b.where.depth) return;
  b.where.depth--;
  b.refill = true;
}

static void select_child(Builder &b) {
  if (!b.selected || b.where.depth == DEPTH) return;
  List block = node_at(b.tree, b.where);
  if (!is_block(block)) return;
  for (int i = 2; i < block.len(); i++) {
    if (!is_node(block[i])) continue;
    b.where.at[b.where.depth++] = i;
    b.refill = true;
    return;
  }
}

// Selects the sibling one place from the selection, toward `step`.
static void select_sibling(Builder &b, int step) {
  if (!b.selected || !b.where.depth) return;
  int level = b.where.depth - 1, other = b.where.at[level] + step;
  Where parent = b.where;
  parent.depth--;
  List block = node_at(b.tree, parent);
  if (other < 2 || other >= block.len() || !is_node(block[other])) return;
  b.where.at[level] = other;
  b.refill = true;
}

// Puts the selection in a new block, `name`, which becomes the selection.
static void wrap_selected(Builder &b, String name) {
  if (!b.selected) return;
  List node = node_at(b.tree, b.where);
  List block = %( $(Atom.intern(name)) ((gap 8)) $node );
  change(b, replaced(b.tree, b.where, 0, block));
  b.refill = true;
}

/* Puts the selected block's children where the block was, and selects
   the first of them. The root has no place to leave them. */
static void unwrap_selected(Builder &b) {
  if (!b.selected || !b.where.depth) return;
  List block = node_at(b.tree, b.where);
  if (!is_block(block)) return;
  Where parent = b.where;
  int index = parent.at[--parent.depth], next = index;
  List around = without(node_at(b.tree, parent), index);
  for (int i = 2; i < block.len(); i++)
    if (is_node(block[i])) around = inserted(around, next++, block[i]);
  change(b, replaced(b.tree, parent, 0, around));
  b.selected = next > index;
  b.refill = true;
}

// Adds a copy of the selection after it, and selects the copy.
static void duplicate_selected(Builder &b) {
  if (!b.selected || !b.where.depth) return;
  Where parent = b.where;
  int index = parent.at[--parent.depth];
  List block = node_at(b.tree, parent);
  change(b, replaced(b.tree, parent, 0,
                     inserted(block, index + 1, block[index])));
  b.where.at[parent.depth] = index + 1;
  b.refill = true;
}

static void run(Builder &b, Command command) {
  switch (command) {
    case NOTHING: return;
    case TO_PARENT: return select_parent(b);
    case TO_CHILD: return select_child(b);
    case TO_PREVIOUS: return select_sibling(b, -1);
    case TO_NEXT: return select_sibling(b, 1);
    case MOVE_UP: return move_selected(b, -1);
    case MOVE_DOWN: return move_selected(b, 1);
    case WRAP_ROW: return wrap_selected(b, "row");
    case WRAP_COLUMN: return wrap_selected(b, "column");
    case UNWRAP: return unwrap_selected(b);
    case DUPLICATE: return duplicate_selected(b);
    case DELETE: return remove_selected(b);
    case UNDO_LAST: return undo(b);
    case REDO_LAST: return redo(b);
  }
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
  // An open menu lies over the tree, and a press on it is the menu's.
  if (b.menu_open) return false;
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

/* Finds where a drop would put the selection: the position before the
   first child whose middle the pointer has not passed, along the block's
   direction. `line` is where that is. */
static void aim(Builder &b, Ui ui) {
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

/* Moves the selection to the aimed position. Taking the node out moves
   its later siblings down one place, and the target with them when it is
   one of them or inside one. */
static void drop(Builder &b) {
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
static void node_menu(Ui ui, Builder &b, String id) {
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
static void keyed(Ui ui, Builder &b) {
  if (!b.editing || b.menu_open || ui.wants_keyboard()) return;
  for (int i = 0; i < (int) (sizeof keys / sizeof keys[0]); i++)
    if (ui.shortcut(keys[i].mods, keys[i].key)) b.command = keys[i].command;
}

// A node as the outline names it: its component and its first text.
static String listed(List node) {
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

static void outline_pane(Ui ui, Builder &b) {
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

static void palette(Ui ui, Builder &b) {
  // Two names to a line, so more of them show above the outline.
  ui.scroll (id: "palette", width: fill, height: fill, pad: 8)
  ui.row (width: fill, wrap: true, gap: 2) {
    foreach (List row in View.components()) {
      String name = row[0];
      if (ui.button(name, variant: ghost, size: sm, width: 100)) add(b, name);
      if (name == "button") b.add_button = ui.last_rect();
    }
  }
}

static void canvas(Ui ui, Builder &b) {
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
    catch %(?cause *detail): b.status = %"$(cause.repr()) $(detail.repr())";
  }
  Where root = { 0 };
  int next = 0;
  place_drawn(b, b.tree, root, next);
  if (!b.editing) return;
  bool moving = b.dragging && !b.sizing && b.aimed;
  Marks marks = { &b, selected_id(b), moving ? b.target_id : 0,
                  moving, b.dragging && b.sizing, b.line, sized_to(b) };
  ui.canvas("marks", fill, fill, paint_marks, &marks, sizeof marks);
  node_menu(ui, b, "tree-menu");
  if (b.dragging) ui.set_cursor(CUI_CURSOR_MOVE);
}

// the inspector

/* How the inspector shows an option: its group, whether it shows before
   "All options", the step of a number, and a line of help. An option
   with no row is in Other and shows under "All options" or once set. */
typedef struct Shown {
  char *name, *group;
  bool common;
  float step;
  char *help;
} Shown;

static Shown shown[] = {
  { "gap", "Layout", true, 1, "Space between the children" },
  { "pad", "Layout", true, 1, "Space inside the edge" },
  { "wrap", "Layout", false, 0, "Start a new line when the row is full" },
  { "columns", "Layout", false, 1, "The columns of a grid" },
  { "pad_x", "Layout", false, 1, "Space inside the left and right edges" },
  { "pad_y", "Layout", false, 1, "Space inside the top and bottom edges" },
  { "width", "Size", true, 1, "Fit the content, fill the space, or fixed" },
  { "height", "Size", true, 1, "Fit the content, fill the space, or fixed" },
  { "min_width", "Size", false, 1, "The least width" },
  { "max_width", "Size", false, 1, "The greatest width" },
  { "min_height", "Size", false, 1, "The least height" },
  { "max_height", "Size", false, 1, "The greatest height" },
  { "variant", "Style", true, 0, "The look of the button" },
  { "size", "Style", true, 1, "How large it is" },
  { "tone", "Style", true, 0, "Its color, by what it means" },
  { "color", "Style", false, 0, "The color of its text or mark" },
  { "bg", "Style", false, 0, "The background color" },
  { "border", "Style", false, 1, "The width of the border" },
  { "border_color", "Style", false, 0, "The color of the border" },
  { "radius", "Style", false, 1, "How round the corners are" },
  { "elevation", "Style", false, 0, "How far its shadow falls" },
  { "label", "Content", true, 0, "The text beside the control" },
  { "placeholder", "Content", true, 0, "The text shown while it is empty" },
  { "description", "Content", false, 0, "A second line under the label" },
  { "on_click", "Behavior", true, 0, "A Lisp form run on a press" },
  { "on_change", "Behavior", false, 0, "A Lisp form run on a change" },
  { "disabled", "Behavior", true, 0, "Ignore the pointer and the keys" },
  { "bind", "Behavior", false, 0, "The Lisp global the control edits" },
  { "id", "Behavior", false, 0, "A name that keeps the node's state" },
  { "show", "Behavior", true, 0, "The id of the card to show" },
};

static char *group_names[] = {
  "Content", "Layout", "Size", "Style", "Behavior", "Other"
};

// The view's own options, which no component's record lists.
static List own_options = %(("on_click" "form") ("on_change" "form")
                            ("bind" "form") ("id" "text"));

// Options a block's Layout group draws with controls of their own.
static bool laid_out(String name) =>
  name in %("dir" "gap" "pad" "align" "justify");

// A label beside a control, like the label of an inspector row.
static void row_label(Ui ui, String text) =>
  ui.text(text, width: LABEL,
          color: cui_color_of(ui, CUI_COLOR_TEXT_SECONDARY));

static Shown *shown_row(String name) {
  for (int i = 0; i < (int) (sizeof shown / sizeof shown[0]); i++)
    if (!strcmp(name, shown[i].name)) return &shown[i];
  return NULL;
}

static int group_of(String name) {
  Shown *row = shown_row(name);
  for (int i = 0; row && i < OTHER; i++)
    if (!strcmp(row.group, group_names[i])) return i;
  return OTHER;
}

/* What the inspector draws: a node, where it is, and the node it asks
   for, set when the frame's controls change the node. */
typedef struct Inspecting {
  Where where;
  List node, edited;
  // What was changed, which names one step of undo.
  String field;
  // Whether the rows edit the block around the selection.
  bool around;
} Inspecting;

static List current(Inspecting &in) => in.edited ? in.edited : in.node;

static void set_option(Inspecting &in, String name, Var value) {
  in.edited = with_option(current(in), name, value);
  in.field = name;
}

// The option value `name` when `on`, and otherwise void, the default.
static Var unless_default(bool on, String name) =>
  on ? (Var) Atom.intern(name) : void;

// `name` as an option value, or none when it is the default `usual`.
static Var unless_usual(String name, String usual) =>
  unless_default(strcmp(name, usual) != 0, name);

static List renamed(List node, String name) =>
  %( $(Atom.intern(name)) @(node.cdr()) );

// Notes where a row is, for the check.
static void locate(Builder &b, Inspecting &in, String name, cui_rect r) {
  b.located[in.around ? %"around $name" : name] =
    %( $((double) r.x) $((double) r.y) $((double) r.w) $((double) r.h) );
}

static cui_rect located(Builder &b, String name) {
  List r = b.located[name];
  return r ? (cui_rect){ r[0].double(), r[1].double(), r[2].double(),
                         r[3].double() }
           : (cui_rect){ 0 };
}

/* One text field of the inspector, showing `value`. Returns true with
   `out` set when the text was changed to something that reads as a
   value: void for no text, the text itself for a `text` kind that does
   not start a form, and otherwise the form read. */
static bool typed(Ui ui, Builder &b, String label, String kind, Var value,
                  Var &out) {
  if (b.slot >= FIELDS) return false;
  TextField field = b.fields[b.slot++];
  if (b.refill) {
    field.buffer[0] = 0;
    if (!value.is_void())
      field.set(kind == "text" && value is <string> ? (String) value
                                                    : written(value));
  }
  Shown *row = shown_row(label);
  bool changed = ui.prop_text(label, field, tooltip: row ? row.help : NULL,
                              placeholder: kind == "text" ? "" : "Lisp");
  if (b.slot == 1) b.first_field = ui.last_rect();
  if (!changed) return false;
  out = void;
  if (field.empty()) return true;
  if (kind == "text" && field.buffer[0] != '(') {
    out = field.text();
    return true;
  }
  return read_value(field.text(), out);
}

static bool is_number(Var value) =>
  value.is_integer() || value.is_floating();

// Whether `value` is what a control for `kind` shows, not a Lisp form.
static bool plain(String kind, Var value) {
  if (value.is_void()) return true;
  if (kind == "number" || kind == "color" || kind == "bool")
    return is_number(value);
  if (kind == "size")
    return is_number(value) || value.is_atom() || value is <list>;
  return kind != "enum" || value.is_atom();
}

static int index_of(List members, Var value) {
  for (int i = 0; !value.is_void() && i < members.len(); i++)
    if (spelled(value) == (String) members[i]) return i;
  return -1;
}

static void enum_row(Ui ui, Inspecting &in, String what, List members,
                     Var now, String help) {
  int index = index_of(members, now) + 1;
  if (ui.prop_enum(what, %("default" @members), index, tooltip: help))
    set_option(in, what,
               index ? (Var) Atom.intern(members[index - 1]) : void);
}

static void number_row(Ui ui, Inspecting &in, String what, Var now,
                       Shown *row) {
  float value = now.is_void() ? 0 : now.double(), step = row ? row.step : 0;
  /* The row is unbounded, so CUI draws no range bar; a row with whole
     steps stays at zero or above. */
  if (ui.prop_float(what, value, step: step,
                    format: now.is_void() ? "default" : NULL,
                    tooltip: row ? row.help : NULL))
    set_option(in, what, step >= 1 ? whole(value > 0 ? value : 0)
                                    : (Var) (double) value);
}

static void color_row(Ui ui, Inspecting &in, String what, Var now,
                      String help) {
  cui_color color = now.is_void() ? (cui_color){ 0, 0, 0, 255 }
                                  : CUI_RGB(now.int());
  if (ui.prop_color(what, color, tooltip: help))
    set_option(in, what,
               (Var) (color.r << 16 | color.g << 8 | color.b));
}

/* A width or height as Auto, Fit, Fill, or Fixed, and for Fixed its
   points. Fixed starts at the size the node is drawn. */
static void size_row(Ui ui, Builder &b, Inspecting &in, String what,
                     Var now) {
  int index = now.is_void() ? 0 : is_number(now) ? 3
            : now is <list> || spelled(now) == "fill" ? 2 : 1;
  ui.row (width: fill, align: center, gap: 12) {
    row_label(ui, what);
    if (ui.segmented(%"size-$what", %("Auto" "Fit" "Fill" "Fixed"), index,
                     size: sm)) {
      cui_rect r = drawn_at(b, ui, in.where);
      float drawn = what == "width" ? r.w : r.h;
      Var sizes[] = { void, <fit>, <fill>, whole(drawn > 0 ? drawn : 100) };
      set_option(in, what, sizes[index]);
    }
    locate(b, in, what, ui.last_rect());
  }
  if (index != 3) return;
  float points = now.double();
  if (ui.prop_float(%"$what points", points, step: 1, suffix: "pt"))
    set_option(in, what, whole(points > 1 ? points : 1));
}

/* The editor for one option of the node, by its kind. A value that is a
   Lisp form, not the kind's own value, is edited as text. */
static void editor(Ui ui, Builder &b, Inspecting &in, List described,
                   Var now) {
  String what = described[0], kind = described[1];
  Shown *row = shown_row(what);
  String help = row ? row.help : NULL;
  if (!plain(kind, now)) kind = "form";
  if (kind == "size") return size_row(ui, b, in, what, now);
  if (kind == "enum")
    enum_row(ui, in, what, described.cdr().cdr(), now, help);
  else if (kind == "number") number_row(ui, in, what, now, row);
  else if (kind == "color") color_row(ui, in, what, now, help);
  else if (kind == "bool") {
    bool on = !now.is_void() && now.double() != 0;
    if (ui.prop_bool(what, on, tooltip: help))
      set_option(in, what, on ? (Var) 1 : void);
  }
  else {
    Var value = void;
    if (typed(ui, b, what, kind, now, value)) set_option(in, what, value);
  }
  locate(b, in, what, ui.last_rect());
}

/* One option's row: its editor, and when the option is set, a button
   that removes it, so the node goes back to the component's default. */
static void option_row(Ui ui, Builder &b, Inspecting &in, List described) {
  String what = described[0];
  Var now = option(current(in), what);
  cui_push_id(ui, what);
  defer cui_pop_id(ui);
  ui.row (width: fill, align: center, gap: 4) {
    ui.column (width: fill, gap: 4) editor(ui, b, in, described, now);
    if (now.is_void()) ui.gap(28);
    else if (ui.icon_button(CUI_ICON_X, variant: ghost, size: sm, width: 28,
                            tooltip: "Reset to the default")) {
      set_option(in, what, void);
    }
    if (!now.is_void()) locate(b, in, %"reset $what", ui.last_rect());
  }
}

/* The options the component of `node` has, and the view's own, which a
   record may list too. */
static List options_of(List node) {
  List row = component(spelled(node[0]));
  if (!row) return own_options;
  Array options = [];
  foreach (List described in (List) row[3]) options.push(described);
  foreach (List own in own_options) {
    List listed = ((List) row[3]).find(%!(List d) => d[0] == own[0]);
    if (!listed) options.push(own);
  }
  return options.list_free();
}

static List described(List node, String name) =>
  options_of(node).find(%!(List row) => row[0] == name);

/* Column or row. A `row` or `column` becomes the other; a block of
   another kind gets the option `dir`. */
static void direction(Ui ui, Builder &b, Inspecting &in) {
  List node = current(in);
  int index = is_row(node);
  ui.row (width: fill, align: center, gap: 12) {
    row_label(ui, "direction");
    if (ui.segmented("direction", %("Column" "Row"), index, size: sm,
                     full_width: true)) {
      String name = spelled(node[0]);
      if (name == "row" || name == "column") {
        in.edited = renamed(with_option(node, "dir", void),
                            index ? "row" : "column");
        in.field = "dir";
      }
      else set_option(in, "dir", unless_default(index, "row"));
    }
    locate(b, in, "direction", ui.last_rect());
  }
}

/* Where the children sit, as a 3 by 3 grid: along the block by
   `justify` and across it by `align`. Two switches give the spacing
   CUI has besides: space between the children, and children stretched
   across the block. The grid shows CUI's defaults for an unset option:
   children at the start, centred across a row, stretched across a
   column. A stretch lights the whole line across the block, and space
   between the whole line along it. */
static void alignment(Ui ui, Builder &b, Inspecting &in) {
  List node = current(in), places = %("start" "center" "end");
  bool row = is_row(node);
  String usual = row ? "center" : "stretch";
  Var align = option(node, "align"), justify = option(node, "justify");
  String across_is = align.is_void() ? usual : spelled(align);
  String along_is = justify.is_void() ? "start" : spelled(justify);
  bool stretch = strcmp(across_is, "stretch") == 0;
  bool between = strcmp(along_is, "between") == 0;
  int across = index_of(places, Atom.intern(across_is));
  int along = index_of(places, Atom.intern(along_is));
  ui.row (width: fill, gap: 12, align: center) {
    row_label(ui, "align");
    ui.column (gap: 2) {
      for (int y = 0; y < 3; y++)
        ui.row (gap: 2) {
          for (int x = 0; x < 3; x++) {
            int on_along = row ? x : y, on_across = row ? y : x;
            cui_push_id_int(ui, y * 3 + x);
            bool here = (between || on_along == along)
                     && (stretch || on_across == across);
            if (ui.button(" ", size: sm, width: 22,
                          variant: here ? CUI_BUTTON_PRIMARY
                                        : CUI_BUTTON_SECONDARY)) {
              set_option(in, "justify",
                         unless_default(on_along, places[on_along]));
              set_option(in, "align",
                         unless_usual(places[on_across], usual));
            }
            if (y == 1 && x == 1) locate(b, in, "middle", ui.last_rect());
            cui_pop_id(ui);
          }
        }
    }
    ui.column (gap: 4) {
      if (ui.switch("Space between", between))
        set_option(in, "justify", unless_default(between, "between"));
      if (ui.switch("Stretch", stretch))
        set_option(in, "align",
                   unless_usual(stretch ? "stretch" : row ? "center"
                                                          : "start",
                                usual));
    }
  }
}

// A block's spacing: direction, gap, padding, and where children sit.
static void block_layout(Ui ui, Builder &b, Inspecting &in) {
  List node = current(in);
  if (described(node, "dir")) direction(ui, b, in);
  foreach (String name in %("gap" "pad")) {
    List row = described(node, name);
    if (row) option_row(ui, b, in, row);
  }
  if (described(node, "align") && described(node, "justify"))
    alignment(ui, b, in);
}

/* Whether the inspector shows the option `name` of `node` now. A block
   reports no event, so its handlers are not common. */
static bool showing(Builder &b, List node, String name) {
  if (b.all)
    return b.search.empty() || strstr(name, b.search.text()) != NULL;
  Shown *row = shown_row(name);
  bool common = row && row.common &&
                !(is_block(node) && name.startswith("on_"));
  return common || !option(node, name).is_void();
}

// The rows of one group: each option the group holds that shows now.
static void group_rows(Ui ui, Builder &b, Inspecting &in, int group) {
  List node = current(in);
  bool block = is_block(node);
  foreach (List row in options_of(node)) {
    String name = row[0];
    if (group_of(name) != group || (block && laid_out(name))) continue;
    if (name == "show" && node[0] != <cards>) continue;
    if (showing(b, node, name)) option_row(ui, b, in, row);
  }
}

// Whether a group has a row to show.
static bool group_shows(Builder &b, List node, int group) {
  foreach (List row in options_of(node)) {
    String name = row[0];
    if (group_of(name) == group && !(is_block(node) && laid_out(name)) &&
        (name != "show" || node[0] == <cards>) && showing(b, node, name))
      return true;
  }
  return false;
}

// The node's arguments, as text or numbers, in the Content group.
static void arguments(Ui ui, Builder &b, Inspecting &in) {
  List node = in.node, row = component(spelled(node[0]));
  int at = 2;
  foreach (List argument in row ? (List) row[2] : %()) {
    String kind = argument[1], what = argument[0];
    if (kind == "bound" || kind == "field") continue;
    if (at >= node.len()) break;
    Var value = void;
    if (kind == "number" && is_number(node[at])) {
      float number = node[at].double();
      if (ui.prop_float(what, number, step: 1)) {
        in.edited = with_argument(current(in), at, whole(number));
        in.field = what;
      }
    }
    else if (typed(ui, b, what, kind, node[at], value)) {
      in.edited = with_argument(current(in), at,
                                value.is_void() ? (Var) "" : value);
      in.field = what;
    }
    at++;
  }
}

/* Changes the tree for an inspector edit. The changes from one field,
   while it keeps the keyboard or the pointer, are one step of undo. */
static void change_field(Builder &b, Inspecting &in) {
  String key = %"$(in.field) $(in.around ? 1 : 0)";
  for (int i = 0; i < in.where.depth; i++) key = %"$key/$(in.where.at[i])";
  List tree = replaced(b.tree, in.where, 0, in.edited);
  if (b.visiting && b.visiting == key) {
    b.tree = tree;
    b.view.set(tree);
  }
  else change(b, tree);
  b.visiting = key;
}

/* Shows the selection's arguments; the spacing of the block it is in;
   its own spacing when it is a block; and its options by group. Only
   common and set options show until "All options" is on. */
static void inspector(Ui ui, Builder &b) {
  ui.scroll (id: "inspector", width: 400, height: fill, pad: 10, gap: 8) {
    if (!b.selected) {
      ui.muted(b.editing ? "Click a component to select it."
                         : "The tree is running. Edit to change it.");
      return;
    }
    Inspecting own = { b.where, node_at(b.tree, b.where) }, around = { 0 };
    ui.row (width: fill, align: center) {
      ui.heading(spelled(own.node[0]), 4);
      ui.spacer();
      if (ui.switch("All options", b.all)) b.refill = true;
      b.all_switch = ui.last_rect();
    }
    if (b.all && ui.search("inspect-search", b.search, size: sm) &
                 CUI_CHANGED)
      b.refill = true;
    b.slot = 0;
    b.located = {};
    cui_inspector_opts layout = { .label_width = LABEL };
    if (ui.inspector_begin("inspect", layout)) {
      List row = component(spelled(own.node[0]));
      bool argued = row && ((List) row[2]).len();
      if ((argued || group_shows(b, own.node, CONTENT)) &&
          ui.inspector_group("Content", b.open[CONTENT])) {
        arguments(ui, b, own);
        group_rows(ui, b, own, CONTENT);
      }
      if (own.where.depth) {
        around.where = own.where;
        around.where.depth--;
        around.node = node_at(b.tree, around.where);
        around.around = true;
        cui_push_id(ui, "around");
        if (ui.inspector_group(is_row(around.node) ? "In row" : "In column",
                               b.open_around))
          block_layout(ui, b, around);
        cui_pop_id(ui);
      }
      for (int group = LAYOUT; group < GROUPS; group++) {
        bool block = group == LAYOUT && is_block(own.node);
        if (!block && !group_shows(b, own.node, group)) continue;
        if (!ui.inspector_group(group_names[group], b.open[group])) continue;
        if (block) block_layout(ui, b, own);
        group_rows(ui, b, own, group);
      }
      ui.inspector_end();
    }
    if (own.edited) change_field(b, own);
    else if (around.edited) change_field(b, around);
    // Text the person is typing stays as typed.
    b.refill = (own.edited || around.edited) && !ui.wants_keyboard();
  }
}

static void draw(Ui ui, Builder &b) {
  // Rectangles are read before this frame submits anything: they are the
  // last frame's layout, which is what the pointer was aimed at.
  b.canvas = ui.get_rect(b.canvas_id);
  b.outline_area = ui.get_rect(b.outline_id);
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
  if (b.picked) select_at(b, b.listed_where[b.picked - 1]);
  b.picked = 0;
  if (!ui.wants_keyboard() && !ui.mouse_down(CUI_MOUSE_LEFT))
    b.visiting = NULL;
  b.menu_open = b.menu_shown;
  b.menu_shown = false;
  keyed(ui, b);
  run(b, b.command);
  b.command = NOTHING;
  ui.column (width: fill, height: fill) {
    toolbar(ui, b);
    ui.separator();
    ui.row (width: fill, height: fill) {
      ui.column (width: 220, height: fill) {
        palette(ui, b);
        ui.separator();
        outline_pane(ui, b);
      }
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
  b.redo = [];
  b.located = {};
  for (int i = 0; i < GROUPS; i++) b.open[i] = true;
  b.open_around = true;
  b.search = TextField.new(64);
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

static int clicks(Builder &b) {
  Var value = void;
  return b.lisp.try_get("clicks", value) ? value.int() : -1;
}

static int check(String image) {
  static Builder b;
  Offscreen screen = auto Offscreen.open(1200, 700);
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
  click(screen, b, located(b, "middle"));
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
  return apart && lays && fills && besides && sizes && selects && adds &&
         runs && edits && moves && removes && undoes &&
         saves && picks && keeps && reparents && reorders && stays ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc == 3 && !strcmp(argv[1], "--check")) return check(argv[2]);
  static Builder b;
  App app = auto App.open(title: "Builder", width: 1280, height: 760);
  open_file(b, app.ui(), argc > 1 ? argv[1] : NULL);
  while (app.frame()) draw(app.ui(), b);
  return 0;
}
