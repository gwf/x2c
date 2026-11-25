#pragma once

/*  x2cui-view.x -- a UI held as a List and drawn every frame

    A `View` draws the tree a Lisp session holds in one global, with the
    draw functions x2cui-view-generate.x builds from CUI's C signatures;
    that file describes the tree. This is a unit of its own, so a program
    that uses no `View` links neither it nor the Lisp runtime.
*/

#include "x2cui.x"
#include "lisp-bindings.x"
#include "x2cui-view-generate.x"

enum { PLAIN = 64 };

// The text a bound input edits, kept between frames by its global's name.
static typedef struct ViewField {
  char *name;
  TextField field;
  struct ViewField *next;
} ViewField;

// What a `View` points to; the type itself is declared in x2cui.x.
static typedef struct ViewState {
  Lisp lisp;
  String global;
  ViewField *fields;
  // What one draw collects: the events reported, and the open blocks.
  Array fired, path;
  int blocks;
  // Set by a `free` node for the box that draws it: place its children.
  int placing;
  /* For a watcher: the last id before a component's call, the id of the
     box around a component CUI gives none, and the components learned
     to need one. */
  cui_id marked, wrapped;
  Var plain[PLAIN];
  int plain_count;
  // The node a running handler belongs to, and whether it passed.
  List chain;
  int depth, passed;
  void (*hook)(void *user, List node, cui_id id);
  void *hook_user;
} *ViewState;

// The view whose handlers are running, for `ui-send` and `ui-pass`.
static ViewState _view_running = NULL;

// values

/* The spelling of a name, with `-` as `_`: a compact Symbol reads both
   as `-`, and CUI's fields are spelled with `_`. */
static String _view_name(Var value) {
  if (value is <string>) return value;
  String spelled = ((Atom) value).str();
  if (!spelled)
    raise %(bad-arg (operation "View.draw") (reason "a name is expected")
            (value $value));
  return spelled.replace("-", "_");
}

// Text shows a String as it is and any other value as it is written.
static String _view_string(Var value) =>
  value is <string> ? (String) value : value.repr();

static double _view_number(Var value) => value.double();

static cui_size _view_size(Var value) {
  if (value is <list>) return CUI_GROW(_view_number(((List) value)[1]));
  if (value.is_atom()) {
    String name = _view_name(value);
    if (name == "fill") return CUI_FILL;
    if (name == "fit") return CUI_FIT;
    raise %(bad-arg (operation "View.draw") (reason "a size is expected")
            (value $value));
  }
  return CUI_PX(_view_number(value));
}

static cui_color _view_color(Var value) => CUI_RGB(value.int());

/* The member of an enum that `value` names among `names`. */
static int _view_member(
  Var value, const char *const *names, int *members, int count) {
  String name = _view_name(value);
  for (int i = 0; i < count; i++)
    if (name == String.new(names[i])) return members[i];
  raise %(bad-arg (operation "View.draw") (reason "no such member")
          (value $value));
}

// nodes

/* The value at position `at` of `node`, with `(eval form)` evaluated. */
static Var _view_value(ViewState view, Var value) {
  if (value is not <list>) return value;
  List form = value;
  return form.len() == 2 && form[0] == <eval> ? view.lisp.eval(form[1])
                                              : value;
}

static Var _view_argument(ViewState view, List node, int at) {
  if (at >= node.len())
    raise %(bad-arg (operation "View.draw") (reason "an argument is missing")
            (node $node));
  return _view_value(view, node[at]);
}

/* The value of the view's own option `name` on `node`, or void. */
static Var _view_option(List node, String name) {
  foreach (List row in (List) node[1])
    if (_view_name(row[0]) == name) return row[1];
  return void;
}

static int _view_own(String name) =>
  name == "bind" || name == "on_click" || name == "on_change" ||
  name == "id" || name == "on" || name == "x" || name == "y";

/* Sets each row of the node's options in `record` through `set`. */
static void _view_options(
  ViewState view, List node, int (*set)(void *, String, Var), void *record) {
  foreach (List row in (List) node[1]) {
    String name = _view_name(row[0]);
    if (_view_own(name)) continue;
    if (!set(record, name, _view_value(view, row[1])))
      raise %(bad-arg (operation "View.draw") (reason "no such option")
              (option $name) (node $node));
  }
}

/* Records the event `node` reported, with the blocks open around it. */
static void _view_fire(ViewState view, List node) {
  Var handler = _view_option(node, "on_click");
  if (handler.is_void()) handler = _view_option(node, "on_change");
  if (handler.is_void()) return;
  view.path.push(node);
  view.fired.push(%( $(view.path.list()) $handler ));
  view.path.pop();
}

static void _view_drawn(ViewState view, List node, cui_id id) {
  if (view.hook) view.hook(view.hook_user, node, id);
}

static void _view_mark(ViewState view, Ui ui) {
  if (view.hook) view.marked = ui.last_id();
}

static int _view_plain(ViewState view, Var component) {
  for (int i = 0; i < view.plain_count; i++)
    if (view.plain[i] == component) return 1;
  return 0;
}

/* Reports a component with the id of the box drawn around it, or with
   the id its call left as the last one. A call that left the last id as
   it was gave its component none, as text has none: the component is
   reported with 0 this frame and is drawn in a box from the next. */
static void _view_drawn_leaf(ViewState view, Ui ui, List node) {
  if (!view.hook) return;
  cui_id id = view.wrapped ? view.wrapped : ui.last_id();
  if (!view.wrapped && id == view.marked) {
    id = 0;
    if (view.plain_count < PLAIN && node.len() > 2)
      view.plain[view.plain_count++] = node[0];
  }
  view.wrapped = 0;
  view.hook(view.hook_user, node, id);
}

/* The id CUI gives a block whose record's id field is `id`. A block the
   tree gives no id has none in CUI, so while a watcher is installed it
   gets one by its place in the frame's order of blocks. */
static cui_id _view_identify(ViewState view, Ui ui, const char **id) {
  if (!*id && view.hook) *id = %"x2cui-view-$(view.blocks++)";
  return *id ? ui.make_id(String.new(*id)) : 0;
}

/* Whether `node` is the node whose `id` option is `id`. */
static int _view_named(List node, Var id) {
  if (node.len() < 2 || node[1] is not <list>) return 0;
  Var own = _view_option(node, "id");
  return !own.is_void() && own == id;
}

// bound values

static String _view_bind(List node) {
  Var name = _view_option(node, "bind");
  if (name.is_void())
    raise %(bad-arg (operation "View.draw")
            (reason "the component needs a bind option") (node $node));
  return ((Atom) name).str();
}

static double _view_bound(ViewState view, List node) {
  Var value = void;
  return view.lisp.try_get(_view_bind(node), value) ? value.double() : 0;
}

static void _view_bound_keep(
  ViewState view, List node, double was, double now) {
  if (now != was) view.lisp.set_global(_view_bind(node), now);
}

// Called with the session's storage active, which then owns the field.
static ViewField *_view_field_new(ViewState view, String name) {
  ViewField *kept = xcalloc(1, sizeof *kept);
  kept.name = xmalloc(name.len() + 1);
  strcpy(kept.name, name);
  kept.field = TextField.new(1024);
  kept.next = view.fields;
  return view.fields = kept;
}

/* The field that holds the text of the node's bound global. Text the
   session set since the last frame replaces the field's. */
static TextField _view_field(ViewState view, List node) {
  String name = _view_bind(node);
  ViewField *kept = view.fields;
  while (kept && name != String.new(kept.name)) kept = kept.next;
  if (!kept) auto (view.lisp.storage()) kept = _view_field_new(view, name);
  TextField field = kept.field;
  Var value = void;
  if (view.lisp.try_get(name, value) && value is <string> &&
      (String) value != field.text())
    field.set(value);
  return field;
}

static void _view_field_keep(ViewState view, List node, TextField field) {
  String name = _view_bind(node);
  Var value = void;
  if (view.lisp.try_get(name, value) && value is <string> &&
      (String) value == field.text())
    return;
  auto (view.lisp.storage()) view.lisp.set_global(name, field.text());
}

// drawing

$x2cui.view();

/* Draws the child of a `cards` node that its `show` option names by
   `id`, or the first child when the option is absent. */
static void _view_cards(ViewState view, Ui ui, List node) {
  Var shown = _view_value(view, _view_option(node, "show"));
  view.path.push(node);
  defer view.path.pop();
  for (int i = 2; i < node.len(); i++) {
    if (shown.is_void() ? i > 2 : !_view_named(node[i], shown)) continue;
    _view_node(view, ui, node[i]);
    return;
  }
}

static void _view_component(ViewState view, Ui ui, List node) {
  String name = _view_name(node[0]);
  if (!_view_component_draw(view, ui, name, node))
    raise %(bad-arg (operation "View.draw") (reason "no such component")
            (component $name));
}

static void _view_node(ViewState view, Ui ui, List node) {
  if (node[0] == <cards>) return _view_cards(view, ui, node);
  // A `free` node is a box that places its children.
  if (node[0] == <free>) {
    view.placing = 1;
    if (!_view_component_draw(view, ui, "box", node)) view.placing = 0;
    return;
  }
  if (!view.hook || !_view_plain(view, node[0]))
    return _view_component(view, ui, node);
  /* A watched component with no id of its own is drawn in a box that
     has one and takes the component's width. */
  cui_box box = {};
  Var width = _view_option(node, "width");
  if (!width.is_void()) box.width = _view_size(_view_value(view, width));
  cui_id id = _view_identify(view, ui, &box.id);
  cui_box_begin(ui, &box);
  defer cui_box_end(ui);
  view.wrapped = id;
  _view_component(view, ui, node);
}

/* Draws `node` at the point its `x` and `y` options give inside the
   block around it, outside that block's flow. */
static void _view_placed(ViewState view, Ui ui, List node) {
  Var x = _view_value(view, _view_option(node, "x"));
  Var y = _view_value(view, _view_option(node, "y"));
  cui_place_begin(ui, 0, x.is_void() ? 0 : (float) _view_number(x),
                  y.is_void() ? 0 : (float) _view_number(y), 0, 0);
  defer cui_place_end(ui);
  _view_node(view, ui, node);
}

static void _view_children(ViewState view, Ui ui, List node, int from) {
  int placing = view.placing;
  view.placing = 0;
  view.path.push(node);
  defer view.path.pop();
  // A watcher points at blocks, and a block with no children has no size.
  if (view.hook && from >= node.len()) {
    cui_box_begin(ui, &(cui_box){ .width = CUI_PX(72), .height = CUI_PX(32) });
    cui_box_end(ui);
  }
  for (int i = from; i < node.len(); i++) {
    if (placing) _view_placed(view, ui, node[i]);
    else _view_node(view, ui, node[i]);
  }
}

// handlers and messages

/* Offers the message `name` to the node at `depth` of `chain` and then to
   each block around it. The first `(on name form)` option that matches
   handles it, and the message goes further up only when that handler
   calls `ui-pass`. A message no node handles is dropped. */
static void _view_deliver(
  ViewState view, List chain, int depth, Var name, List arguments) {
  for (int i = depth; i >= 0; i--) {
    foreach (List row in (List) ((List) chain[i])[1]) {
      if (row.len() != 3 || _view_name(row[0]) != "on" || row[1] != name)
        continue;
      view.chain = chain;
      view.depth = i;
      view.passed = 0;
      view.lisp.apply(view.lisp.eval(row[2]), arguments);
      if (!view.passed) return;
      break;
    }
  }
}

/* Runs one entry of `fired`: `(chain handler)` for a reported event, or
   `(chain depth name arguments)` for a message a handler sent. */
static void _view_run(ViewState view, List entry) {
  List chain = entry[0];
  if (entry.len() == 4)
    return _view_deliver(view, chain, entry[1].int(), entry[2], entry[3]);
  int depth = chain.len() - 1;
  view.chain = chain;
  view.depth = depth;
  match (entry[1]) {
    case %(send ?name *arguments): {
      Array values = [];
      foreach (Var argument in arguments)
        values.push(_view_value(view, argument));
      return _view_deliver(view, chain, depth, name, values.list_free());
    }
  }
  view.lisp.apply(view.lisp.eval(entry[1]), %());
}

/** Returns a view of the tree the session `lisp` holds in the global
    `global`. The session owns the view's storage and releases it when the
    session is destroyed; the view is not used after that.
*/
View View.new(Lisp lisp, String global) {
  ViewState view = NULL;
  auto (lisp.storage()) view = xcalloc(1, sizeof *view);
  view.lisp = lisp;
  view.global = global;
  return (View) view;
}

/** Sets the tree the view draws: the session's global becomes `tree`,
    which the session borrows.
*/
void View.set(View v, List tree) {
  ViewState view = (ViewState) v;
  view.lisp.set_global(view.global, tree);
}

/** Returns the tree the view draws, or NULL when the global is unset. */
List View.tree(View v) {
  ViewState view = (ViewState) v;
  Var tree = void;
  return view.lisp.try_get(view.global, tree) && tree is <list> ? tree : NULL;
}

/** Draws the tree into the frame `ui` has open, then runs the handler of
    each component that reported its event, in the order drawn. A handler
    may replace the tree; the next frame draws the new one. A handler
    written `(send name argument ...)` sends a message instead: the node
    and then each block around it is offered the message, and the first
    with an `(on name form)` option handles it.
    Raises: `<bad-arg>` for a node, option, or value the tree misspells,
    after closing the blocks it opened, or any cause a handler or an
    `(eval form)` raises.
*/
void View.draw(View v, Ui ui) {
  ViewState view = (ViewState) v;
  List tree = v.tree();
  if (!tree) return;
  Array fired = [], path = [];
  view.fired = fired;
  view.path = path;
  view.blocks = 0;
  _view_node(view, ui, tree);
  ViewState outer = _view_running;
  _view_running = view;
  defer _view_running = outer;
  // A handler that sends a message appends to `fired`.
  for (int i = 0; i < fired.len(); i++) _view_run(view, fired[i]);
}

/** Calls `hook` with `user` for each node as it is drawn, with the id
    CUI gave the node's component, whose rectangle `ui.get_rect` then
    returns. A NULL `hook` stops the calls. CUI gives some components no
    id, so while a hook is installed the view supplies one: a box, row,
    column, or scroll area the tree gives no id gets one by its place in
    the frame, and a component such as text is drawn inside a box that
    has one, from the frame after its first. A card, a component with no
    arguments, and a component in its first frame are reported with id 0,
    and a `cards` node, which has no component, is not reported. A block
    with no children is drawn 72 by 32 points while a hook is installed,
    so that it can be pointed at.
*/
void View.watch(
  View v, void (*hook)(void *user, List node, cui_id id), void *user) {
  ViewState view = (ViewState) v;
  view.hook = hook;
  view.hook_user = user;
}

/** Returns one row for each component a tree can name, as
    `(name block arguments options)`; `x2cui_view_table` describes a row.
*/
List View.components(void) => $x2cui.view.table();

// Lisp

// Whether the elements after the options of `tree` are child nodes.
static int _view_has_children(List tree) =>
  tree.len() >= 2 &&
  (tree[0] == <cards> || tree[0] == <free> ||
   _view_is_block(_view_name(tree[0])));

$lisp.binding(x2cui_lisp, "ui-replace")
static List _lisp_ui_replace(List tree, Var id, List node) {
  if (_view_named(tree, id)) return node;
  if (!_view_has_children(tree)) return tree;
  // Blocks have only child nodes after the options.
  Array items = [tree[0], tree[1]];
  for (int i = 2; i < tree.len(); i++)
    items.push(tree[i] is <list>
                 ? (Var) _lisp_ui_replace(tree[i], id, node) : tree[i]);
  return items.list_free();
}

$lisp.binding(x2cui_lisp, "ui-find")
static List _lisp_ui_find(List tree, Var id) {
  if (_view_named(tree, id)) return tree;
  if (!_view_has_children(tree)) return %();
  for (int i = 2; i < tree.len(); i++) {
    if (tree[i] is not <list>) continue;
    List found = _lisp_ui_find(tree[i], id);
    if (found) return found;
  }
  return %();
}

$lisp.binding(x2cui_lisp, "ui-text")
static String _lisp_ui_text(List @parts) {
  Buffer out = auto Buffer.new();
  foreach (Var part in parts) {
    // The empty String is NULL, which a Buffer does not take.
    String shown = _view_string(part);
    if (shown) out.write(shown);
  }
  return out;
}

static ViewState _view_handling(String operation) {
  if (!_view_running)
    raise %(bad-state (operation $operation)
            (reason "no handler of a view is running"));
  return _view_running;
}

$lisp.binding(x2cui_lisp, "ui-send")
static Var _lisp_ui_send(Var name, List @arguments) {
  ViewState view = _view_handling("ui-send");
  view.fired.push(%( $(view.chain) $(view.depth) $name $arguments ));
  return name;
}

$lisp.binding(x2cui_lisp, "ui-pass")
static Var _lisp_ui_pass(void) {
  _view_handling("ui-pass").passed = 1;
  return void;
}

/** Binds `ui-replace`, `ui-find`, `ui-text`, `ui-send`, and `ui-pass`
    into `lisp`. `(ui-replace tree id node)` returns `tree` with the node
    whose `id` option is `id` replaced by `node`, and `(ui-find tree id)`
    returns that node, or the empty List. `(ui-text part ...)` returns the
    parts as one String, each as a component shows it. Inside a handler,
    `(ui-send name argument ...)` sends a message from the handler's node
    after the handlers already waiting, and `(ui-pass)` lets the message
    being handled go on to the next block out; outside one they raise
    `<bad-state>`.
*/
void ViewLisp.install(Lisp lisp) {
  $lisp.install(lisp, x2cui_lisp);
}
