#pragma once

#include "x2c.x"
#include "meta.x"

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

/** Returns the `Ui` method that forwards to the C function `target`. */
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
  List method = x2c_ident(_method_name(function));
  List unit = _spelled(result, "(void)")
    ? $!Unit{ inline void Ui.$method(@declared) { $target(@passed); } }
    : $!Unit{ inline $result Ui.$method(@declared) =>
                $target(@passed); };
  return $(unit);
}

/** Defines the `Ui` method for the CUI function `$target`. */
macro Unit $cui.method(Name $target) { @cui_method($target) }
