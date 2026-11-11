#pragma once

#include "x2c.x"
#include "meta.x"
#include "x2cui-options.x"

/*  x2cui-generate.x -- Ui methods built from CUI's C signatures

    `$cui.method(cui_button_ex)` defines `Ui.button` from the type of
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

/* CUI names its option records `*_opts`, and its layout record `cui_box`. */
meta static int _option_record(Type type) {
  Var name = type.car();
  return name is <string> &&
         (((String) name).endswith("_opts") || name == "cui_box");
}

/** Returns the `Ui` method that forwards to the C function `target`, and
    its method form when it has one.
*/
meta List cui_method(String function) {
  List target = x2c_ident(function);
  Type signature = Code.type(target);
  List types = Type.parameters(signature);
  Type result = Type.return_type(signature);
  // Returned text lives in CUI's frame memory; a String outlives the frame.
  if (_spelled(result, "(* const char)")) result = $!Type{ String };
  Array params = [], args = [];
  List ui = x2c_ident("ui");
  params.push($!Param{ cui_ctx *$ui });
  args.push($!( $ui ));
  int count = types.len();
  for (int i = 1; i < count; i++) {
    Type type = types[i];
    List p = x2c_ident(%"p$i");
    Type next = i + 1 < count ? types[i + 1] : NULL;
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
      // An array of records and its count pass as C; see $cui.count.
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
                _option_record(Type.element(last));
  List form = _method_form(name, declared.len() - 1 - options, options);
  return form ? %($unit $form) : $(unit);
}

/** Defines the `Ui` method for the CUI function `$target`. */
macro Unit $cui.method(Name $target) { @cui_method($target) }

/*  Method forms

    A component whose last parameter is CUI's option record has a method
    form that takes the options as `name: value` arguments:

      ui.button("Add", variant: primary, icon: plus)
      ui.row (gap: 8, align: center) { ... }

    The form of a component is an Expression macro `$Ui.NAME`; the form of
    a block component, whose C functions are `cui_NAME_begin` and
    `cui_NAME_end`, is a decorator `$Ui.NAME`. Written in its own template,
    `ui.NAME(...)` is the method the form wraps. Each form is one of the
    templates below, one for each count of ordinary arguments, which takes
    its name from the method. A component's form calls its method with
    the arguments `cui_arguments` returns, and a block's form calls its
    begin method through `cui_begin`; both read the method's parameter
    types and lower each value by its type; see x2cui-options.x.
*/

/* CUI's own block macros, `cui_NAME(ui, ...) { ... }`, which run their
   block between `cui_NAME_begin` and `cui_NAME_end`. Each has a block
   form. Those that CUI writes with `CUI__SCOPE_IF` run the block only
   while the begin call reports the block open. A table has its own form,
   with a template of columns, a data grid keeps `$cui.data_grid`, and a
   virtual list keeps `$cui.virtual_list`. */
meta static List _scopes = %("node_content" "dockspace" "box" "row" "column"
  "card" "scroll" "split" "dialog_footer" "button_group" "reorder_item"
  "spotlight" "dock" "carousel" "carousel_slide" "card_stack_item"
  "menu_bar" "toolbar" "status_bar");
meta static List _openings = %("dock_panel" "popover" "menu" "context_menu"
  "dialog" "sheet" "accordion" "reasoning" "hover_card" "expandable_card"
  "user_menu" "menu_bar_menu" "inspector" "tree");

/** Returns the begin call of a block, `ui.NAME_begin(...)` with the
    arguments `cui_arguments` returns, as a test that is true while the
    block is open.
*/
meta List cui_begin(List ui, String block, List options, List @args) {
  List call = cui_call(ui, %"$(block)_begin", options, @args);
  return block in _openings ? call : $!( ($call, 1) );
}

/* The component templates. */

macro Unit $cui.widget0(Name $method) {
  macro Expression $Ui.$method(Expr $ui, Entry @options) =>
    $ui.$method(@cui_arguments($ui, $method, $options));
}

macro Unit $cui.widget1(Name $method) {
  macro Expression $Ui.$method(Expr $ui, Expr $a, Entry @options) =>
    $ui.$method(@cui_arguments($ui, $method, $options, $a));
}

macro Unit $cui.widget2(Name $method) {
  macro Expression $Ui.$method(Expr $ui, Expr $a, Expr $b, Entry @options) =>
    $ui.$method(@cui_arguments($ui, $method, $options, $a, $b));
}

macro Unit $cui.widget3(Name $method) {
  macro Expression $Ui.$method(
    Expr $ui, Expr $a, Expr $b, Expr $c, Entry @options) =>
    $ui.$method(@cui_arguments($ui, $method, $options, $a, $b, $c));
}

macro Unit $cui.widget4(Name $method) {
  macro Expression $Ui.$method(
    Expr $ui, Expr $a, Expr $b, Expr $c, Expr $d, Entry @options) =>
    $ui.$method(@cui_arguments($ui, $method, $options, $a, $b, $c, $d));
}

macro Unit $cui.widget5(Name $method) {
  macro Expression $Ui.$method(
    Expr $ui, Expr $a, Expr $b, Expr $c, Expr $d, Expr $e, Entry @options) =>
    $ui.$method(@cui_arguments($ui, $method, $options, $a, $b, $c, $d, $e));
}

macro Unit $cui.widget6(Name $method) {
  macro Expression $Ui.$method(
    Expr $ui, Expr $a, Expr $b, Expr $c, Expr $d, Expr $e, Expr $f,
    Entry @options) =>
    $ui.$method(@cui_arguments($ui, $method, $options, $a, $b, $c, $d, $e, $f));
}

macro Unit $cui.widget7(Name $method) {
  macro Expression $Ui.$method(
    Expr $ui, Expr $a, Expr $b, Expr $c, Expr $d, Expr $e, Expr $f, Expr $g,
    Entry @options) =>
    $ui.$method(
      @cui_arguments($ui, $method, $options, $a, $b, $c, $d, $e, $f, $g));
}

macro Unit $cui.widget8(Name $method) {
  macro Expression $Ui.$method(
    Expr $ui, Expr $a, Expr $b, Expr $c, Expr $d, Expr $e, Expr $f, Expr $g,
    Expr $h, Entry @options) =>
    $ui.$method(@cui_arguments(
      $ui, $method, $options, $a, $b, $c, $d, $e, $f, $g, $h));
}

/* The block templates. The receiver is evaluated once; the end call is
   deferred, so it also runs when the block leaves early; a block whose
   begin call reports whether it is open runs only while it is open. */

macro Unit $cui.block0(Name $block, Name $end) {
  macro Decorator $Ui.$block(Stmt $body, Expr $ui, Entry @options) {
    {
      typeof($ui) ui = $ui;
      if ($cui_begin(ui, $block, $options)) {
        defer ui.$end();
        $body
      }
    }
  }
}

macro Unit $cui.block1(Name $block, Name $end) {
  macro Decorator $Ui.$block(Stmt $body, Expr $ui, Expr $a, Entry @options) {
    {
      typeof($ui) ui = $ui;
      if ($cui_begin(ui, $block, $options, $a)) {
        defer ui.$end();
        $body
      }
    }
  }
}

macro Unit $cui.block2(Name $block, Name $end) {
  macro Decorator $Ui.$block(
    Stmt $body, Expr $ui, Expr $a, Expr $b, Entry @options) {
    {
      typeof($ui) ui = $ui;
      if ($cui_begin(ui, $block, $options, $a, $b)) {
        defer ui.$end();
        $body
      }
    }
  }
}

macro Unit $cui.block3(Name $block, Name $end) {
  macro Decorator $Ui.$block(
    Stmt $body, Expr $ui, Expr $a, Expr $b, Expr $c, Entry @options) {
    {
      typeof($ui) ui = $ui;
      if ($cui_begin(ui, $block, $options, $a, $b, $c)) {
        defer ui.$end();
        $body
      }
    }
  }
}

macro Unit $cui.block4(Name $block, Name $end) {
  macro Decorator $Ui.$block(
    Stmt $body, Expr $ui, Expr $a, Expr $b, Expr $c, Expr $d,
    Entry @options) {
    {
      typeof($ui) ui = $ui;
      if ($cui_begin(ui, $block, $options, $a, $b, $c, $d)) {
        defer ui.$end();
        $body
      }
    }
  }
}

meta static Macro _widget_form(int count) {
  switch (count) {
    case 0: return $cui.widget0;
    case 1: return $cui.widget1;
    case 2: return $cui.widget2;
    case 3: return $cui.widget3;
    case 4: return $cui.widget4;
    case 5: return $cui.widget5;
    case 6: return $cui.widget6;
    case 7: return $cui.widget7;
    case 8: return $cui.widget8;
  }
  return NULL;
}

meta static Macro _block_form(int count) {
  switch (count) {
    case 0: return $cui.block0;
    case 1: return $cui.block1;
    case 2: return $cui.block2;
    case 3: return $cui.block3;
    case 4: return $cui.block4;
  }
  return NULL;
}

/* A row and a column end as a box does. */
meta static String _end_method(String block) =>
  block == "row" || block == "column" ? "box_end" : %"$(block)_end";

/* The method form of `method`, which takes `count` ordinary arguments and,
   when `options` is set, an option record; NULL when it has none. */
meta static List _method_form(String method, int count, int options) {
  String block = method.endswith("_begin") ? method[:method.len() - 6] : NULL;
  if (block && (block in _scopes || block in _openings))
    return Macro_apply(_block_form(count), %($block $(_end_method(block))));
  Macro form = options && !block ? _widget_form(count) : NULL;
  return form ? Macro_apply(form, %($method)) : NULL;
}

/** Returns the method form of `method`, a `Ui` method written in x2c
    rather than generated, when it takes an option record last.
*/
meta List cui_form(String method) {
  Type ui = $!Type{ Ui };
  List types = Type.parameters(Type.resolve_member(ui, method, 1)[2]);
  int options = _option_record(types[types.len() - 1]);
  List form = _method_form(method, types.len() - 1 - options, options);
  return form ? $(form) : %();
}

/** Defines the method form of the `Ui` method `$method`. */
macro Unit $cui.form(Name $method) { @cui_form($method) }
