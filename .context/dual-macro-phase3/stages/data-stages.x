#pragma once
#include "x2c.x"
#include "meta.x"

static Var Macro_inline(List environment, Var tree);
meta static Macro Macro_close(Macro value, List captures) =>
  value.append(%((env $captures)));

meta static Var Macro_expr_value(Var value) {
  if (value.is_integer()) return x2c_literal_int(value.integer());
  return value;
}

meta static List Macro_apply(Macro t, List values) =>
  %("x2c.template" $t $values);

static Var Macro_inline(List environment, Var tree) {
  if (tree is not <list>) return tree;
  match (tree) {
    case %(tpl-call (expr ? (ident ?binding)) (args *arguments)): {
      Macro child = NULL;
      foreach (List row, environment)
        if (List.compare(row.car().list(), binding) == 0) {
          child = row.cadr();
          break;
        }
      return Macro_apply(child, arguments);
    }
    case %(literal *): return tree;
  }
  Array parts = [];
  foreach (Var part, tree.list()) parts.push(Macro_inline(environment, part));
  return parts.list_free();
}

meta static Var Macro_pattern_view(Var value) {
  if (value is not <list>)
    return value == <*> || value == <?> ? %(!quote $value).var() : value;
  List node = value;
  match (node) {
    case %(expr ?type ?body): {
      if (type === %(<macro-expr>) && body.is_binder()) return body;
      if (type === %(<macro-expr>) && body is <list> && body.list().car() == <expr>)
        return Macro_pattern_view(body);
      return %(expr ? ${Macro_pattern_view(body)});
    }
    case %(literal *): return %(!quote $node);
    case %(op ?operator *operands): {
      Array parts = [];
      foreach (Var operand, operands) parts.push(Macro_pattern_view(operand));
      return %(op (!quote $operator) @{parts.list_free()});
    }
    case %(seq ?one): return Macro_pattern_view(one);
    case %(return ?type ?body): return %(return ? ${Macro_pattern_view(body)});
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
      rows = cons(%($key ${sequence ? %($selected).var() : selected}), rows);
    }
    rows = cons(%(${Atom.intern(%"?__macro_member_$name")} $selected), rows);
    rows = cons(%(${Atom.intern(%"*__macro_splice_$name")} ($selected)), rows);
  }
  List body = t.assoc(<template>);
  return Macro_pattern_view(Macro_inline(t.assoc(<env>), body.replace(rows)));
}

#include <assert.h>
macro Expression $sum(Expr $left, Expr $right) => $left + $right;

meta static Var marker_data(void) =>
  %("x2c.template" "not_a_visible_macro" ());
meta static Macro descriptor_data(void) {
  Macro sum = $sum;
  return sum.append(%((held ("x2c.template" "not_a_visible_macro" ()))));
}
meta static int observe_data(Var value) {
  List rows;
  return value.list().try_match(%("x2c.template" ?name ()), rows);
}

int main(void) {
  Var raw = $marker_data();
  assert(raw.list().car().str() == "x2c.template");
  Macro descriptor = $descriptor_data();
  List retained = descriptor.assoc(<held>);
  assert(retained.car().str() == "x2c.template");
  assert(retained.cadr().str() == "not_a_visible_macro");
  puts("declared data stages: marker-shaped payloads remain inspectable");
  return 0;
}
