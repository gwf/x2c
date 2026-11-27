#pragma once

/*  x2cui-view-generate.x -- draw functions for a UI held as a List

    A `View` draws the tree a Lisp session holds in one global. Every node
    of the tree has one shape:

      (component (options) arguments-and-children)

      (column ((pad 24) (gap 12))
        (heading () "A tiny counter" 2)
        (button ((variant primary) (on-click bump)) "Add one")
        (text () (eval (string-append "Clicked " (string clicks)))))

    The options are `(name value)` rows. Each sets the field `name` of the
    option record the component's C function takes, and its value is
    converted by the C type of that field: a name selects an enum member,
    as `primary` does; a size is a number of pixels, `fill`, `fit`, or
    `(grow w)`; a color is a number 0xRRGGBB. The arguments follow in the
    order the C function takes them, and a block component's remaining
    elements are its child nodes. A name is spelled with `-` or `_`.

    An argument or option value written `(eval form)` is evaluated in the
    session on every frame. Three options belong to the view, not to a
    record: `(bind name)` keeps the value a component edits in the session
    global `name`; `(on-click form)`, also spelled `on-change`, is
    evaluated to a procedure that runs, after the frame's tree is drawn,
    when the component reports its event; `(id name)` names a node for
    `ui-replace`.

    The draw function of each component is generated from the type of its
    C function as the compiler read it from `cui.h`; `_view_functions`
    lists them. The session, the tree, and a view are used from the one
    thread that draws.
*/

#include "x2cui-generate.x"

// generated draw functions

/* The CUI functions a tree can name, each as the component its `Ui`
   method names: `cui_button_ex` is `button`, `cui_row_begin` is `row`. */
meta static List _view_functions = %(
  "cui_box_begin" "cui_row_begin" "cui_column_begin" "cui_card_begin"
  "cui_scroll_begin" "cui_text_ex" "cui_heading" "cui_label" "cui_muted"
  "cui_code" "cui_kbd" "cui_link" "cui_separator" "cui_spacer"
  "cui_button_ex" "cui_checkbox_ex" "cui_switch_ex" "cui_radio_ex"
  "cui_slider_ex" "cui_number_ex" "cui_input_ex" "cui_textarea_ex"
  "cui_select_ex" "cui_segmented_ex" "cui_tabs_ex" "cui_chip_ex"
  "cui_badge_ex" "cui_progress_ex" "cui_alert_ex" "cui_spinner_ex"
  "cui_avatar_ex");

meta static int _view_spelled(Type type, String shape) =>
  type.repr() == shape;

/* `button` for `cui_button_ex`, and `row` for `cui_row_begin`. */
meta static String _view_component(String function) {
  String name = function[4:];
  if (name.endswith("_ex")) name = name[:name.len() - 3];
  return name.endswith("_begin") ? name[:name.len() - 6] : name;
}

/* How a tree gives a value of the C type `type`: "size", "color",
   "text", "enum", "bool", or "number"; NULL for a type it cannot give. */
meta static String _view_kind(Type type) {
  if (type ~= %("cui_size")) return "size";
  if (type ~= %("cui_color")) return "color";
  if (Type.is_text(type)) return "text";
  Type resolved = Type.resolve(type);
  if (resolved ~= %(enum *)) return "enum";
  if (_view_spelled(resolved, "(\"bool\")")) return "bool";
  return Type.numeric(resolved) ? "number" : NULL;
}

/* The expression that converts the Var `value` to the C type `type`, or
   NULL for a type a tree cannot give. */
meta static List _view_convert(Type type, List value) {
  String kind = _view_kind(type);
  if (!kind) return NULL;
  if (kind == "size") return $!( _view_size($value) );
  if (kind == "color") return $!( _view_color($value) );
  if (kind == "text") return $!( _view_string($value) );
  if (kind == "bool") return $!( _view_number($value) != 0 );
  if (kind == "number") return $!( ($type) _view_number($value) );
  List members = Type.members(Type.resolve(type));
  int count = members.len();
  List names = x2cui_member_names(members);
  List constants = x2cui_member_constants(members);
  return $!( ($type) _view_member(
    $value, (const char *const[]){ @names }, (int[]){ @constants },
    $count) );
}

/* One row of `x2cui_view_table` for a value named `name` of type `type`:
   its name, its kind, and an enum's member names. */
meta static List _view_described(String name, Type type) {
  String kind = _view_kind(type);
  if (kind != "enum") return %($name $kind);
  List names = x2cui_member_names(Type.members(Type.resolve(type)));
  return %($name $kind @names);
}

/* The function that sets one field of the option record `record` from a
   row's name and value, and reports whether the record has that field. */
meta static List _view_setter(String record) {
  Type type = %($record);
  List o = x2c_ident("o"), p = x2c_ident("p");
  List name = x2c_ident("name"), value = x2c_ident("value");
  Array arms = [];
  foreach (List field in Type.fields(type)) {
    String spelled = field.car();
    if (spelled.startswith("_")) continue;
    List convert = _view_convert(field[1], value);
    if (!convert) continue;
    List member = x2c_ident(spelled);
    arms.push($!{
      if ($name == $spelled) { $o->$member = $convert; return 1; } });
  }
  List body = arms.list_free();
  List setter = x2c_ident(%"_view_set_$record");
  return $!Unit{
    static int $setter(void *$p, String $name, Var $value) {
      $type *$o = $p;
      @body
      return 0;
    } };
}

// Whether the option record `record` has an `id` field.
meta static int _view_has_id(Type record) {
  foreach (List field in Type.fields(record))
    if (field.car() == "id") return 1;
  return 0;
}

// Whether a call's result stands for an event: not void and not an id.
meta static int _view_reports(Type result) =>
  !_view_spelled(result, "(void)") && !_view_spelled(result, "(\"cui_id\")");

/* The draw function of the component `function` names: it reads the
   node's arguments by the types of the C parameters, calls the function,
   and reports the event a result other than an id stands for. A block
   then draws the node's remaining elements as children before its end
   call, which is deferred. */
meta static List _view_draw(String function) {
  List target = x2c_ident(function);
  Type signature = Code.type(target);
  List types = Type.parameters(signature);
  Type result = Type.return_type(signature);
  List view = x2c_ident("view"), u = x2c_ident("u");
  List node = x2c_ident("node");
  List field = x2c_ident("field"), items = x2c_ident("items");
  List options = x2c_ident("options"), bound = x2c_ident("bound");
  List was = x2c_ident("was"), fired = x2c_ident("fired");
  Type view_type = %("ViewState"), ui_type = %("Ui");
  Array before = [], args = [], after = [];
  List identity = NULL;
  args.push($!( $u ));
  int at = 2, count = types.len();
  for (int i = 1; i < count; i++) {
    Type type = types[i];
    Type next = i + 1 < count ? types[i + 1] : NULL;
    if (_view_spelled(type, "(* char)") && next &&
        _view_spelled(next, "(\"size_t\")")) {
      Type text = %("TextField");
      before.push($!{ $text $field = _view_field($view, $node); });
      args.push($!( x2cui_buffer($field) ));
      args.push($!( $field.capacity ));
      after.push($!{ _view_field_keep($view, $node, $field); });
      i++;
    }
    else if (_view_spelled(type, "(* const * const char)") && next &&
             _view_spelled(next, "(int)")) {
      before.push($!{ List $items = _view_argument($view, $node, $at); });
      args.push($!( $items.c_strings() ));
      args.push($!( (int) $items.len() ));
      at++;
      i++;
    }
    else if (type.len() > 2 && type[0] == <*> && type[1] == <const> &&
             x2cui_option_record(Type.element(type))) {
      Type record = Type.element(type);
      List setter = x2c_ident(%"_view_set_$((String) record.car())");
      before.push($!{ $record $options = {}; });
      before.push($!{ _view_options($view, $node, $setter, &$options); });
      args.push($!( &$options ));
      // A block is found again by the id its record carries.
      if (_view_has_id(record))
        identity = $!( _view_identify($view, $u, &($options).id) );
    }
    else if (type.len() > 1 && type[0] == <*> && !Type.is_text(type)) {
      Type value = Type.element(type);
      before.push($!{ double $was = _view_bound($view, $node); });
      before.push($!{ $value $bound = ($value) $was; });
      args.push($!( &$bound ));
      after.push($!{ _view_bound_keep($view, $node, $was, (double) $bound); });
    }
    else {
      List convert = _view_convert(
        type, $!( _view_argument($view, $node, $at) ));
      if (!convert)
        raise %(bad-arg (operation "x2cui view component")
                (function $function) (reason "a parameter has no tree form"));
      args.push(convert);
      at++;
    }
  }
  String name = _view_component(function);
  List draw = x2c_ident(%"_view_draw_$name");
  int block = function.endswith("_begin");
  /* A component is reported with the id CUI gave it, which the view
     finds by comparing the last id before and after the call. A block has
     an id only through its record, and is reported before it opens; a
     block whose record has none is reported with 0. */
  if (!block) {
    before.push($!{ _view_mark($view, $u); });
    after.push($!{ _view_drawn_leaf($view, $u, $node); });
  }
  else if (identity)
    before.push($!{ _view_drawn($view, $node, $identity); });
  else before.push($!{ _view_drawn($view, $node, 0); });
  List setup = before.list_free(), passed = args.list_free();
  List kept = after.list_free();
  List call = _view_reports(result)
    ? $!{ if ($target(@passed)) _view_fire($view, $node); }
    : $!{ $target(@passed); };
  if (!block)
    return $!Unit{
      static void $draw($view_type $view, $ui_type $u, List $node) {
        @setup
        $call
        @kept
      } };
  List end = x2c_ident(
    name == "row" || name == "column" ? "cui_box_end" : %"cui_$(name)_end");
  return $!Unit{
    static void $draw($view_type $view, $ui_type $u, List $node) {
      @setup
      $call
      @kept
      defer $end($u);
      _view_children($view, $u, $node, $at);
    } };
}

/* The option records the listed functions take, each once. */
meta static List _view_records(void) {
  Array records = [];
  foreach (String function in _view_functions) {
    List types = Type.parameters(Code.type(x2c_ident(function)));
    Type last = types[types.len() - 1];
    if (last.len() < 3 || last[0] != <*>) continue;
    Type record = Type.element(last);
    if (!x2cui_option_record(record)) continue;
    String spelled = record.car();
    if (!(spelled in records)) records.push(spelled);
  }
  return records.list_free();
}

/** Returns one row for each component a tree can name:
    `(name block arguments options reports)`. `block` is 1 for a component
    with children, and `reports` is 1 for a component without children
    whose call reports an event, which runs its `on-click` or `on-change`
    handler. Each argument and option is `(name kind member...)`, where
    `kind` is "text", "number", "bool", "size", "color", or "enum" with
    its member names; an argument can also be "items" for a List of
    labels, "bound" for a number kept by a `bind` option, and "field" for
    text kept by one.
*/
meta List x2cui_view_table(void) {
  Array rows = [];
  foreach (String function in _view_functions) {
    List types = Type.parameters(Code.type(x2c_ident(function)));
    Array arguments = [], options = [];
    int count = types.len();
    for (int i = 1; i < count; i++) {
      Type type = types[i];
      Type next = i + 1 < count ? types[i + 1] : NULL;
      String name = x2cui_parameter_name(function, i);
      if (_view_spelled(type, "(* char)") && next &&
          _view_spelled(next, "(\"size_t\")")) {
        arguments.push(%($name "field"));
        i++;
      }
      else if (_view_spelled(type, "(* const * const char)") && next &&
               _view_spelled(next, "(int)")) {
        arguments.push(%($name "items"));
        i++;
      }
      else if (type.len() > 2 && type[0] == <*> && type[1] == <const> &&
               x2cui_option_record(Type.element(type))) {
        foreach (List field in Type.fields(Type.element(type))) {
          String spelled = field.car();
          if (spelled.startswith("_") || !_view_kind(field[1])) continue;
          options.push(_view_described(spelled, field[1]));
        }
      }
      else if (type.len() > 1 && type[0] == <*> && !Type.is_text(type))
        arguments.push(%($name "bound"));
      else arguments.push(_view_described(name, type));
    }
    int block = function.endswith("_begin");
    Type result = Type.return_type(Code.type(x2c_ident(function)));
    int reports = !block && _view_reports(result);
    rows.push(%($(_view_component(function)) $block
                $(arguments.list_free()) $(options.list_free()) $reports));
  }
  return rows.list_free();
}

/** Expands to the List `x2cui_view_table` returns. */
macro Expression $x2cui.view.table() =>
  $_x2c_literal_list($x2cui_view_table());

/** Returns the setters, draw functions, component dispatch, and block
    lookup for the functions `_view_functions` lists.
*/
meta List x2cui_view(void) {
  Array units = [];
  foreach (String record in _view_records()) units.push(_view_setter(record));
  List view = x2c_ident("view"), u = x2c_ident("u");
  List node = x2c_ident("node"), name = x2c_ident("name");
  Type view_type = %("ViewState"), ui_type = %("Ui");
  Array arms = [], blocks = [];
  foreach (String function in _view_functions) {
    units.push(_view_draw(function));
    String component = _view_component(function);
    List draw = x2c_ident(%"_view_draw_$component");
    arms.push($!{
      if ($name == $component) { $draw($view, $u, $node); return 1; } });
    if (function.endswith("_begin"))
      blocks.push($!{ if ($name == $component) return 1; });
  }
  List body = arms.list_free(), block_body = blocks.list_free();
  List dispatch = x2c_ident("_view_component_draw");
  List is_block = x2c_ident("_view_is_block");
  units.push($!Unit{
    static int $dispatch(
      $view_type $view, $ui_type $u, String $name, List $node) {
      @body
      return 0;
    } });
  units.push($!Unit{
    static int $is_block(String $name) {
      @block_body
      return 0;
    } });
  return units.list_free();
}

/** Defines the functions `x2cui_view` returns; x2cui.x expands it once. */
macro Unit $x2cui.view() { @x2cui_view() }
