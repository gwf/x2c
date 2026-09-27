#pragma once
#include "x2c.x"
#include "meta.x"

meta static List Macro_apply(Macro t, List values) {
  List rows = NULL;
  List holes = t.assoc(<parameters>);
  for (; holes; holes = holes.cdr(), values = values.cdr()) {
    List hole = holes.car();
    String name = hole.assoc(<binder>).str()[1:];
    Var value = values.car();
    if (hole.assoc(<kind>) == <expr> && value.is_integer())
      value = x2c_literal_int(value.integer());
    foreach (String projection, %("expression" "value" "source")) {
      Atom key = Atom.intern(%"?__macro_${projection}_$name");
      rows = cons(%($key $value), rows);
    }
    Atom splice = Atom.intern(%"*__macro_splice_$name");
    rows = cons(%($splice $value), rows);
  }
  List body = t.assoc(<template>);
  return body.replace(rows);
}

meta static Var Macro_pattern_view(Var value) {
  if (value is not <list>) return value;
  List node = value;
  match (node) {
    case %(expr ?type ?body): {
      if (type === %(<macro-expr>) && body.is_binder()) return body;
      return %(expr ? ${Macro_pattern_view(body)});
    }
    case %(literal *): return %(!quote $node);
  }
  Array parts = [];
  foreach (Var part, node) parts.push(Macro_pattern_view(part));
  return parts.list_free();
}

meta static List Macro_pattern(Macro t, List names) {
  List rows = NULL;
  List holes = t.assoc(<parameters>);
  for (; holes; holes = holes.cdr(), names = names.cdr()) {
    List hole = holes.car();
    String name = hole.assoc(<binder>).str()[1:];
    Var selected = names.car();
    int sequence = hole.assoc(<sequence>);
    foreach (String projection, %("expression" "value" "source")) {
      Atom key = Atom.intern(%"${sequence ? "*" : "?"}__macro_${projection}_$name");
      rows = cons(%($key $selected), rows);
    }
    rows = cons(%(${Atom.intern(%"*__macro_splice_$name")} $selected), rows);
  }
  List body = t.assoc(<template>);
  return Macro_pattern_view(body.replace(rows));
}
