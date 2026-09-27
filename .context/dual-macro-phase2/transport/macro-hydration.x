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

#include <assert.h>
static int helper(int x) => x + 1;
static int other(int x) => x + 100;
macro Expression $with_helper(Expr $argument) => helper($argument);

meta static Macro macro_relay(Macro t) => t;

meta static Macro macro_hydrate(Macro template, List rigid) {
  List body = template.assoc(<template>), rows;
  if (!body.try_match(%(expr ?type (call ?old ?args)), rows))
    x2c_diagnostic_fail("unexpected source body", %(${body.repr()}));
  x2c_diagnostic_warn("Macro hydration",
    %(${rows.assoc(<?old>).repr()} ${rigid.repr()}));
  List updated = %(expr ${rows.assoc(<?type>)}
    (call $rigid ${rows.assoc(<?args>)}));
  Array parts = [];
  foreach (List field, template.cdr())
    parts.push(field.car() == <template> ? %(template $updated) : field);
  return cons(template.car(), parts.list_free());
}

meta static List macro_pipeline(List rigid, List subject) {
  Macro original = $with_helper;
  Macro hydrated = macro_hydrate(macro_relay(original), rigid);
  List rows;
  if (!subject.try_match(Macro_pattern(hydrated, %(?argument)), rows))
    return x2c_literal_int(0);
  List argument = rows.assoc(<?argument>);
  return hydrated(argument);
}
macro Expression $macro_bridge(Expr $rigid, Expr $subject) =>
  $macro_pipeline($rigid, $subject);

int main(void) {
  int shift_a = 1, shift_b = 2, shift_c = 3;
  (void) shift_a, (void) shift_b, (void) shift_c;
  int price = 20;
  assert($macro_bridge(helper, helper(price)) == 21);
  {
    int (*helper)(int) = other;
    assert($macro_bridge(helper, helper(price)) == 120);
    assert($macro_bridge(other, helper(price)) == 0);
  }
  puts("actual Macro hydration: getter, relay, shared pattern/application pass");
  return 0;
}
