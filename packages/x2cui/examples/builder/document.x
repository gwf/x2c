/*  document.x -- the edited tree and the edits made to it

    A tree is a List, `(component (options) arguments-and-children)`, and
    a node is found by its `Where`. Every edit builds a new tree and goes
    through `change`, which keeps the one before for undo.
*/

/* A component's group in the palette, and the text a new one shows. A
   component this table does not name is offered under Other. */
module typedef struct Offer { char *name, *group, *sample; } Offer;

static Offer offers[] = {
  { "row", "Layout" }, { "column", "Layout" }, { "box", "Layout" },
  { "spacer", "Layout" }, { "separator", "Layout" },
  { "heading", "Text", "Heading" }, { "text", "Text", "Some text" },
  { "label", "Text", "Label" }, { "muted", "Text", "A note" },
  { "code", "Text", "code" }, { "kbd", "Text", "Cmd K" },
  { "link", "Text", "A link" },
  { "button", "Input", "Button" }, { "input", "Input" },
  { "textarea", "Input" }, { "checkbox", "Input", "Option" },
  { "switch", "Input", "Setting" }, { "radio", "Input", "Choice" },
  { "slider", "Input", "Amount" }, { "number", "Input" },
  { "select", "Input" }, { "segmented", "Input" }, { "tabs", "Input" },
  { "chip", "Input", "Tag" },
  { "badge", "Display", "New" }, { "progress", "Display" },
  { "spinner", "Display" }, { "alert", "Display", "Something to know" },
  { "avatar", "Display", "Ada Lovelace" },
  { "card", "Container" }, { "scroll", "Container" },
};

module List offer_groups =
  %("Layout" "Text" "Input" "Display" "Container" "Other");

module Offer *offer_of(String name) {
  for (int i = 0; i < (int) (sizeof offers / sizeof offers[0]); i++)
    if (!strcmp(offers[i].name, name)) return &offers[i];
  return NULL;
}

module String spelled(Var name) => ((Atom) name).str().replace("-", "_");

// A node is a List that starts with a component's name.
module bool is_node(Var value) =>
  value is <list> && ((List) value).len() >= 2 &&
  ((List) value)[0].is_atom();

module List node_at(List tree, Where where) {
  List node = tree;
  for (int i = 0; i < where.depth; i++) node = node[where.at[i]];
  return node;
}

// `node` with the node at `where`, from `level` down, replaced by `with`.
module List replaced(List node, Where where, int level, List with) {
  if (level == where.depth) return with;
  Array items = [];
  for (int i = 0; i < node.len(); i++)
    items.push(i == where.at[level]
                 ? (Var) replaced(node[i], where, level + 1, with) : node[i]);
  return items.list_free();
}

module List without(List node, int index) {
  Array items = [];
  for (int i = 0; i < node.len(); i++)
    if (i != index) items.push(node[i]);
  return items.list_free();
}

// `node` with `child` at `index`; an index past the end appends.
module List inserted(List node, int index, Var child) {
  Array items = [];
  for (int i = 0; i < node.len(); i++) {
    if (i == index) items.push(child);
    items.push(node[i]);
  }
  if (index >= node.len()) items.push(child);
  return items.list_free();
}

// The value of the option `name` of `node`, or void.
module Var option(List node, String name) {
  foreach (List row in (List) node[1])
    if (spelled(row[0]) == name) return row[1];
  return void;
}

// `node` with its option `name` set to `value`, or removed for void.
module List with_option(List node, String name, Var value) {
  Array rows = [];
  bool placed = value.is_void();
  foreach (List row in (List) node[1]) {
    if (spelled(row[0]) != name) rows.push(row);
    else if (!value.is_void()) {
      rows.push(%( $(row[0]) $value ));
      placed = true;
    }
  }
  // A tree spells a name with `-`, as `on-click`.
  if (!placed) rows.push(%( $(Atom.intern(name.replace("_", "-"))) $value ));
  Array items = [node[0], rows.list_free()];
  for (int i = 2; i < node.len(); i++) items.push(node[i]);
  return items.list_free();
}

module List with_argument(List node, int at, Var value) {
  Array items = [];
  for (int i = 0; i < node.len(); i++) items.push(i == at ? value : node[i]);
  return items.list_free();
}

module String written(Var value) {
  Buffer out = auto Buffer.new();
  if (!out.write_datum(value, 0)) return value.repr();
  return out;
}

module bool read_value(String text, Var &value) {
  unsigned cursor = 0;
  try return text.read_lisp_form(cursor, value) == <value>;
  catch %(?cause *detail): return false;
}

module List component(String name) =>
  View.components().find(%!(List row) => row[0] == name);

module bool has_option(List node, String name) {
  List row = component(spelled(node[0]));
  foreach (List described in row ? (List) row[3] : %())
    if (described[0] == name) return true;
  return false;
}

module bool is_block(List node) {
  String name = spelled(node[0]);
  List row = component(name);
  return name == "cards" || (row && (int) row[1]);
}

module void change(Builder &b, List tree) {
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

module void undo(Builder &b) => step_back(b, b.undo, b.redo);

module void redo(Builder &b) => step_back(b, b.redo, b.undo);

/* A number a new component starts with: a range up to 100, a heading
   of level 2, a bar half full, a spinner of 20 points. */
static Var fresh_number(String name, String what) {
  if (what == "max") return 100;
  if (what == "level") return 2;
  if (what == "size") return 20;
  return name == "progress" ? (Var) 0.5 : (Var) 0;
}

/* A new node of the component `name`, with an argument of each kind
   filled in, text that shows what it is, and a fresh global for a value
   it edits. A new block spaces its children 8 points apart. */
module List fresh(Builder &b, String name) {
  List row = component(name);
  Offer *offered = offer_of(name);
  String shown = offered && offered.sample ? offered.sample : name;
  Array options = [], items = [];
  foreach (List argument in (List) row[2]) {
    String kind = argument[1], what = argument[0];
    if (kind == "bound" || kind == "field") {
      String global = %"value$(++b.bound)";
      b.lisp.set_global(global, kind == "field" ? (Var) "" : (Var) 0);
      options.push(%( bind $(Atom.intern(global)) ));
    }
    else if (kind == "text")
      items.push(what == "id" ? %"$name$(++b.bound)" : shown);
    else if (kind == "items") items.push(%("One" "Two" "Three"));
    else if (kind == "enum") items.push(Atom.intern(argument[2]));
    else items.push(fresh_number(name, what));
  }
  List node = %( $(Atom.intern(name)) $(options.list_free())
                 @(items.list_free()) );
  return is_block(node) && has_option(node, "gap")
    ? with_option(node, "gap", 8) : node;
}

// Puts `node` at `index` in the block at `where`, and selects it.
module void put(Builder &b, Where where, int index, List node) {
  List block = node_at(b.tree, where);
  if (index > block.len()) index = block.len();
  change(b, replaced(b.tree, where, 0, inserted(block, index, node)));
  b.where = where;
  b.where.at[b.where.depth++] = index;
  b.selected = b.refill = true;
}

/* Adds a node inside the selected block, after the selected component, or
   at the end of the root. */
module void add(Builder &b, String name) {
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
  }
  put(b, where, index, fresh(b, name));
}

module void remove_selected(Builder &b) {
  if (!b.selected || !b.where.depth) return;
  Where parent = b.where;
  int index = parent.at[--parent.depth];
  change(b, replaced(b.tree, parent, 0,
                     without(node_at(b.tree, parent), index)));
  b.selected = false;
}

// Moves the selection one place among its siblings, toward `step`.
module void move_selected(Builder &b, int step) {
  if (!b.selected || !b.where.depth) return;
  Where parent = b.where;
  int index = parent.at[--parent.depth], other = index + step;
  List block = node_at(b.tree, parent);
  if (other < 2 || other >= block.len() || !is_node(block[other])) return;
  List moved = inserted(without(block, index), other, block[index]);
  change(b, replaced(b.tree, parent, 0, moved));
  b.where.at[parent.depth] = other;
}

module void select_at(Builder &b, Where where) {
  b.where = where;
  b.selected = b.refill = true;
}

module void select_parent(Builder &b) {
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

module void run(Builder &b, Command command) {
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

// Writes the tree, and its `FILE.lisp` when it has one.
module void save(Builder &b) {
  add_stubs(b);
  Path path = b.file, program = %"$(b.file).lisp";
  path.write_text(written(b.tree) + "\n");
  if (b.program.len()) program.write_text(b.program);
  b.status = %"Saved $(b.file)";
}
