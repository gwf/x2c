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

macro Expression $sum(Expr $left, Expr $right) => $left + $right;
meta static List inspect(Macro t) => x2c_literal_int(((List) t.assoc(<parameters>)).len());
meta static List applied(Macro t) => t(3, 4);
meta static List selected(int mode) {
  Macro sum = $sum;
  if (mode) return sum(5, 6);
  return sum(7, 8);
}
int main(void) {
  Macro sum = $sum;
  printf("body %s\n", ((List) sum.assoc(<template>)).repr().str());
  printf("inspect %s applied %s selected %s named %d\n",
    $inspect($sum).repr().str(), $applied($sum).repr().str(),
    $selected(1).repr().str(), $sum(1,2));
  List syntax = %(expr (int) (op + (expr (int) (literal (int) "9")) (expr (int) (literal (int) "10"))));
  match (syntax) {
    case sum(?a, ?b): printf("matched %s %s\n", a.repr().str(), b.repr().str());
    default: puts("miss");
  }
  return 0;
}

macro Expression $apply_sum() => $applied($sum);
macro Expression $count_sum() => $inspect($sum);
int bound_values(void) {
  return $apply_sum() + $count_sum();
}
