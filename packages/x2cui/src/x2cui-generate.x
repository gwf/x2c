#pragma once

#include "x2c.x"
#include "meta.x"
#include "x2cui-options.x"

/*  x2cui-generate.x -- Ui methods built from CUI's C signatures

    `$x2cui.method(cui_button_ex)` defines `Ui.button` from the type of
    `cui_button_ex` as the compiler read it from `cui.h`. The method keeps
    the C function's result and replaces each C parameter convention with
    its x2c form:

      cui_ctx *                        the Ui receiver
      const char *                     String
      char *, size_t                   TextField
      const char *const *, int         List of Strings
      const RECORD *, int              unchanged: an array and its count
      const RECORD *                   RECORD by value, as `{ .field = v }`
      T *                              T &

    A `const char *` result is a String.

    Every other parameter passes unchanged. The table of rows is in
    x2cui.x. A function that takes an array of records or numbers has no
    row here, because its pointer is not one of these conventions.

    A component that takes an option record, and each of CUI's block
    components, also gets a method form; see "Method forms" below.
*/

meta static int _pointer(List type) => type.len() > 1 && type[0] == <*>;

meta static int _const_pointer(List type) =>
  type.len() > 2 && type[0] == <*> && type[1] == <const>;

meta static int _function(List type) =>
  type.len() > 0 && type[0] == <func>;

meta static int _spelled(List type, String shape) => type.repr() == shape;

/* `cui_button_ex` is `button`, and `cui_draw_rect` is `draw_rect`. */
meta static String _method_name(String function) {
  String name = function[4:];
  return name.endswith("_ex") ? name[:name.len() - 3] : name;
}

/** Returns the `Ui` method that forwards to the C function `target`, and
    its method form when it has one.
*/
meta List x2cui_method(String function) {
  List target = x2c_ident(function);
  Type signature = Code.type(target);
  List types = Type.parameters(signature);
  Type result = Type.return_type(signature);
  // Returned text lives in CUI's frame memory; a String outlives the frame.
  if (_spelled(result, "(* const char)")) result = $!Type{ String };
  Array params = [], args = [], pairs = [];
  int lowers = 0;
  List ui = x2c_ident("ui");
  params.push($!Param{ cui_ctx *$ui });
  args.push($!( $ui ));
  int count = types.len();
  for (int i = 1; i < count; i++) {
    Type type = types[i];
    List p = x2c_ident(%"p$i");
    Type next = i + 1 < count ? types[i + 1] : NULL;
    lowers |= _lowers(type);
    if (_spelled(type, "(* const char)")) {
      params.push($!Param{ String $p });
      args.push($!( $p ));
    }
    else if (_spelled(type, "(* char)") && next &&
             _spelled(next, "(\"size_t\")")) {
      params.push($!Param{ TextField $p });
      args.push($!( x2cui_buffer($p) ));
      args.push($!( $p.capacity ));
      i++;
    }
    else if (_spelled(type, "(* const * const char)") && next &&
             _spelled(next, "(int)")) {
      params.push($!Param{ List $p });
      args.push($!( x2cui_strings($p) ));
      args.push($!( (int) $p.len() ));
      i++;
    }
    else if (_pointer(type) && (_spelled(Type.element(type), "(void)") ||
                                _function(Type.element(type)))) {
      // A void pointer and a callback pass as C.
      params.push($!Param{ $type $p });
      args.push($!( $p ));
    }
    else if (_const_pointer(type) && next && _spelled(next, "(int)")) {
      // An array of records and its count pass as C; the method form
      // supplies the count.
      pairs.push(params.len() - 1);
      params.push($!Param{ $type $p });
      args.push($!( $p ));
    }
    else if (_const_pointer(type)) {
      Type record = Type.element(type);
      params.push($!Param{ $record $p });
      args.push($!( &$p ));
    }
    else if (_pointer(type)) {
      Type value = Type.element(type);
      params.push($!Param{ $value &$p });
      args.push($!( &$p ));
    }
    else {
      params.push($!Param{ $type $p });
      args.push($!( $p ));
    }
  }
  List declared = params.list_free(), passed = args.list_free();
  String name = _method_name(function);
  List method = x2c_ident(name);
  List unit = _spelled(result, "(void)")
    ? $!Unit{ inline void Ui.$method(@declared) { $target(@passed); } }
    : $!Unit{ inline $result Ui.$method(@declared) =>
                $target(@passed); };
  Type last = types[count - 1];
  int options = count > 1 && _const_pointer(last) &&
                x2cui_option_record(Type.element(last));
  List form = _method_form(name, options || lowers, pairs.list_free());
  return form ? %($unit $form) : $(unit);
}

/* Whether `cui_value` lowers a value of the C type `type`: text, an enum,
   or another of CUI's types by value. */
meta static int _lowers(Type type) {
  if (Type.is_text(type) || Type.resolve(type) ~= %(enum *)) return 1;
  Var name = type.car();
  return name is <string> && ((String) name).startswith("cui_");
}

/** Defines the `Ui` method for the CUI function `$target`. */
macro Unit $x2cui.method(Name $target) { @x2cui_method($target) }

/*  Method forms

    A component whose last parameter is CUI's option record has a method
    form that takes the options as `name: value` arguments:

      ui.button("Add", variant: primary, icon: plus)
      ui.row (gap: 8, align: center) { ... }

    The form of a component is an Expression macro `$Ui.NAME`; the form of
    a block component, whose C functions are `cui_NAME_begin` and
    `cui_NAME_end`, is a decorator `$Ui.NAME`. Written in its own template,
    `ui.NAME(...)` is the method the form wraps. Each form is one of the two
    templates below, which takes its name from the method; its ordinary
    arguments are those before the first `name: value`. A component's
    form calls its method with the arguments `x2cui_arguments` returns, and
    a block's form calls its begin method through `x2cui_begin`; both read
    the method's parameter types and lower each value by its type; see
    x2cui-options.x.
*/

/* CUI's own block macros, `cui_NAME(ui, ...) { ... }`, which run their
   block between `cui_NAME_begin` and `cui_NAME_end`. Each has a block
   form. Those that CUI writes with `CUI__SCOPE_IF` run the block only
   while the begin call reports the block open. The node editor, its
   nodes, and the tree table are begin and end pairs that CUI gives no
   macro; they join the lists as CUI would write them. A table, a data
   grid, and a card stack have forms of their own in
   x2cui-containers.x. */
meta static List _scopes = %("node_content" "dockspace" "box" "row" "column"
  "card" "scroll" "split" "dialog_footer" "button_group" "reorder_item"
  "spotlight" "dock" "carousel" "carousel_slide" "card_stack_item"
  "menu_bar" "toolbar" "status_bar" "virtual_list" "node" "tree_table");
meta static List _openings = %("dock_panel" "popover" "menu" "context_menu"
  "dialog" "sheet" "accordion" "reasoning" "hover_card" "expandable_card"
  "user_menu" "menu_bar_menu" "inspector" "tree" "node_editor");

/** Returns the begin call of a block, `ui.NAME_begin(...)` with the
    arguments `x2cui_arguments` returns, as a test that is true while the
    block is open.
*/
meta List x2cui_begin(
  List ui, String block, List pairs, List options, List @args) {
  List begin = x2c_ident(%"$(block)_begin");
  List passed = x2cui_arguments(ui, %"$(block)_begin", pairs, options, @args);
  List call = $!( $ui.$begin(@passed) );
  return block in _openings ? call : $!( ($call, 1) );
}

/* The template of a component's form. `pairs` are the positions of its
   arrays whose count follows them; see `x2cui_arguments`. */
macro Unit $x2cui.widget(Name $method, Literal @pairs) {
  macro Expression $Ui.$method(Expr $ui, Expr @args, Entry @options) =>
    $ui.$method(@x2cui_arguments($ui, $method, $pairs, $options, @args));
}

/* The template of a block's form. The receiver is evaluated once; the end
   call is deferred, so it also runs when the block leaves early; a block
   whose begin call reports whether it is open runs only while it is
   open. */
macro Unit $x2cui.block(Name $block, Name $end, Literal @pairs) {
  macro Decorator $Ui.$block(
    Stmt $body, Expr $ui, Expr @args, Entry @options) {
    {
      typeof($ui) ui = $ui;
      if ($x2cui_begin(ui, $block, $pairs, $options, @args)) {
        defer ui.$end();
        $body
      }
    }
  }
}

/* A row and a column end as a box does. */
meta static String _end_method(String block) =>
  block == "row" || block == "column" ? "box_end" : %"$(block)_end";

/* The method form of `method`, whose arrays at `pairs` are followed by
   their counts. A block's begin method has a block form; another method
   has a component form when `lowered` is set, as it is when the method
   takes an option record, a value `x2cui_value` lowers, or an array.
   NULL when it has none. */
meta static List _method_form(String method, int lowered, List pairs) {
  String block = method.endswith("_begin") ? method[:method.len() - 6] : NULL;
  if (block && (block in _scopes || block in _openings))
    return Macro_apply($x2cui.block,
                       %($block $(_end_method(block)) @pairs));
  return (lowered || pairs) && !block
    ? Macro_apply($x2cui.widget, %($method @pairs)) : NULL;
}

/** Returns the method form of `method`, a `Ui` method written in x2c
    rather than generated, whose arrays at `pairs` are followed by their
    counts.
*/
meta List x2cui_form(String method, List pairs) {
  Type ui = $!Type{ Ui };
  List types = Type.parameters(Type.resolve_member(ui, method, 1)[2]).cdr();
  int lowered = 0;
  for (int i = 0; i < types.len(); i++) lowered |= _lowers(types[i]);
  List form = _method_form(method, lowered, pairs);
  return form ? $(form) : %();
}

