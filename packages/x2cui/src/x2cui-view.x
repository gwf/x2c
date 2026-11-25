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
  Array fired;
} *ViewState;

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
  name == "id";

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

static void _view_fire(ViewState view, List node) {
  Var handler = _view_option(node, "on_click");
  if (handler.is_void()) handler = _view_option(node, "on_change");
  if (!handler.is_void()) view.fired.push(handler);
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

static void _view_node(ViewState view, Ui ui, List node) {
  String name = _view_name(node[0]);
  if (!_view_component_draw(view, ui, name, node))
    raise %(bad-arg (operation "View.draw") (reason "no such component")
            (component $name));
}

static void _view_children(ViewState view, Ui ui, List node, int from) {
  for (int i = from; i < node.len(); i++) _view_node(view, ui, node[i]);
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
    may replace the tree; the next frame draws the new one.
    Raises: `<bad-arg>` for a node, option, or value the tree misspells,
    after closing the blocks it opened, or any cause a handler or an
    `(eval form)` raises.
*/
void View.draw(View v, Ui ui) {
  ViewState view = (ViewState) v;
  List tree = v.tree();
  if (!tree) return;
  Array fired = [];
  view.fired = fired;
  _view_node(view, ui, tree);
  foreach (Var handler in fired)
    view.lisp.apply(view.lisp.eval(handler), %());
}

// Lisp

/* Whether `node` is the node whose `id` option is `id`. A List argument,
   such as the labels of a select, has no options and is no node. */
static int _view_named(List node, Var id) {
  if (node.len() < 2 || node[1] is not <list>) return 0;
  Var own = _view_option(node, "id");
  return !own.is_void() && own == id;
}

$lisp.binding(x2cui_lisp, "ui-replace")
static List _lisp_ui_replace(List tree, Var id, List node) {
  if (_view_named(tree, id)) return node;
  // The component and its options stay; each child is searched.
  Array items = [tree[0], tree[1]];
  for (int i = 2; i < tree.len(); i++)
    items.push(tree[i] is <list>
                 ? (Var) _lisp_ui_replace(tree[i], id, node) : tree[i]);
  return items.list_free();
}

$lisp.binding(x2cui_lisp, "ui-find")
static List _lisp_ui_find(List tree, Var id) {
  if (_view_named(tree, id)) return tree;
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
  foreach (Var part in parts) out.write(_view_string(part));
  return out;
}

/** Binds `ui-replace`, `ui-find`, and `ui-text` into `lisp`.
    `(ui-replace tree id node)` returns `tree` with the node whose `id`
    option is `id` replaced by `node`, and `(ui-find tree id)` returns
    that node, or the empty List. `(ui-text part ...)` returns the parts
    as one String, each as a component shows it.
*/
void ViewLisp.install(Lisp lisp) {
  $lisp.install(lisp, x2cui_lisp);
}
