#pragma once
#include "x2c.x"
#include "meta.x"

static Var Macro_inline(List environment, Var tree);
static List _macro_instantiate(Macro t, List values);
meta static Macro Macro_close(Macro value, List captures) =>
  value.append(%((env $captures)));

meta static Var Macro_expr_value(Var value) {
  if (value.is_integer()) return x2c_literal_int(value.integer());
  return value;
}

static List _macro_instantiate(Macro t, List values) {
  List rows = NULL;
  List holes = t.assoc(<parameters>);
  for (; holes; holes = holes.cdr()) {
    List hole = holes.car();
    String name = hole.assoc(<binder>).str()[1:];
    int sequence = hole.assoc(<sequence>);
    Var value = sequence ? values.var() : values.car();
    if (sequence && hole.assoc(<kind>) == <expr>) {
      Array lifted = [];
      foreach (Var item, values) lifted.push(Macro_expr_value(item));
      value = lifted.list_free();
    }
    else if (hole.assoc(<kind>) == <expr>) value = Macro_expr_value(value);
    Var expression = value;
    if (!sequence && hole.assoc(<kind>) == <name>)
      expression = %(expr () (ident $value));
    foreach (String projection, %("expression" "value" "source")) {
      Atom key = Atom.intern(%"${sequence ? "*" : "?"}__macro_${projection}_$name");
      rows = cons(%($key ${projection == "expression" ? expression : value}), rows);
    }
    if (hole.assoc(<kind>) == <name>)
      rows = cons(%(${Atom.intern(%"?__macro_member_$name")} $value), rows);
    Atom splice = Atom.intern(%"*__macro_splice_$name");
    rows = cons(%($splice $value), rows);
    values = sequence ? NULL : values.cdr();
  }
  List body = t.assoc(<template>);
  return Macro_inline(t.assoc(<env>), body.replace(rows));
}

meta static List Macro_apply(Macro t, List values) {
  Array grouped = [];
  foreach (List hole, t.assoc(<parameters>).list()) {
    int sequence = hole.assoc(<sequence>);
    grouped.push(sequence ? values.var() : values.car());
    values = sequence ? NULL : values.cdr();
  }
  return %("x2c.template" $t ${grouped.list_free()});
}

static Var Macro_inline(List environment, Var tree) {
  if (tree is not <list>) return tree;
  match (tree) {
    case %(expr (<macro-expr>) (expr ?type ?body)):
      return Macro_inline(environment, %(expr $type $body));
    case %(tpl-call (expr ? (ident ?binding)) (args *arguments)): {
      Macro child = NULL;
      foreach (List row, environment)
        if (List.compare(row.car(), binding) == 0) {
          child = row.cadr();
          break;
        }
      return _macro_instantiate(child, arguments);
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
    if (hole.assoc(<kind>) == <type>)
      selected = Atom.intern("*" + selected.str()[1:]);
    int sequence = hole.assoc(<sequence>);
    foreach (String projection, %("expression" "value" "source")) {
      Atom key = Atom.intern(%"${sequence ? "*" : "?"}__macro_${projection}_$name");
      rows = cons(%($key ${sequence ? %($selected).var() : selected}), rows);
    }
    rows = cons(%(${Atom.intern(%"?__macro_member_$name")} $selected), rows);
    rows = cons(%(${Atom.intern(%"*__macro_splice_$name")} ($selected)), rows);
  }
  List body = t.assoc(<template>);
  List pattern = Macro_pattern_view(
    Macro_inline(t.assoc(<env>), body.replace(rows)));
  if (t.assoc(<kind>) == <block-item> && body.car() == <seq>
    && body.cdr().len() == 1)
    return %(!or $pattern (seq $pattern));
  return pattern;
}


static int _macro_capture(List code, Macro t, List names,
  MatchCaptureBuffer *published) {
  List stored = NULL, grouped = NULL;
  int pending = 0;
  match (code) {
    case %("x2c.template" ?descriptor ?arguments): {
      pending = 1;
      if (descriptor is not <list>) return 0;
      stored = descriptor;
      grouped = arguments;
      break;
    }
    case %(macro-invoke ?descriptor (args *rows) ?): {
      pending = 1;
      if (descriptor is not <list>) return 0;
      stored = descriptor;
      Array projected = [];
      List holes = t.assoc(<parameters>);
      foreach (List row, rows) {
        List hole = holes.car();
        Var value = hole.assoc(<kind>) == <expr>
          ? row.assoc(<expression>) : row.assoc(<value>);
        if (hole.assoc(<sequence>)) {
          match (row) case %(capture ? (value *items) *): value = items;
        }
        projected.push(value);
        holes = holes.cdr();
      }
      grouped = projected.list_free();
      break;
    }
  }
  if (pending) {
    if (List.compare(stored, t) != 0) return 0;
    Array patterns = [];
    List labels = names;
    foreach (List hole, t.assoc(<parameters>).list()) {
      Var label = labels.car();
      patterns.push(hole.assoc(<sequence>)
        ? Atom.intern("?" + label.str()[1:]) : label);
      labels = labels.cdr();
    }
    List pending_pattern = patterns.list_free();
    MatchCaptureLayout actual = MatchCaptureLayout.analyze(pending_pattern);
    MatchCaptureLayout logical = MatchCaptureLayout.analyze(%(!and @names));
    Var values[MACHINE_BINDER_MAX];
    MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
    int matched = x2c_match_try_capture(grouped, pending_pattern, &captured);
    if (matched) {
      List holes = t.assoc(<parameters>), labels = names;
      for (; holes; holes = holes.cdr(), labels = labels.cdr()) {
        Atom label = labels.car();
        Atom internal = holes.car().list().assoc(<sequence>)
          ? Atom.intern("?" + label.str()[1:]) : label;
        published->values[logical.index(label)] = values[actual.index(internal)];
      }
      published->present = logical.definite;
    }
    actual.free();
    logical.free();
    return matched;
  }
  List pattern = Macro_pattern(t, names);
  MatchCaptureLayout actual = MatchCaptureLayout.analyze(pattern);
  MatchCaptureLayout logical = MatchCaptureLayout.analyze(%(!and @names));
  Var values[MACHINE_BINDER_MAX], ordered[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  int matched = x2c_match_try_capture(code, pattern, &captured);
  if (matched) {
    List holes = t.assoc(<parameters>), labels = names;
    for (; holes; holes = holes.cdr(), labels = labels.cdr()) {
      List hole = holes.car();
      Atom label = labels.car();
      Atom internal = hole.assoc(<kind>) == <type>
        ? Atom.intern("*" + label.str()[1:]) : label;
      int from = actual.index(internal), to = logical.index(label);
      if (from < 0 || to < 0 || !captured.has(from)) {
        matched = 0;
        break;
      }
      ordered[to] = values[from];
    }
    if (matched) {
      for (int i = 0; i < logical.binder_count; i++)
        published->values[i] = ordered[i];
      published->present = logical.definite;
    }
  }
  actual.free();
  logical.free();
  return matched;
}

static List _macro_case_pattern(Macro t, List names,
  int (*capture)(List, Macro, List, MatchCaptureBuffer *)) =>
  Macro_pattern(t, names);

#include <assert.h>
macro Expression $sum(Expr $left, Expr $right) => $left + $right;
macro Expression $product(Expr $left, Expr $right) => $left * $right;

meta static Var recognize_stages(Macro sum, Macro product,
                           List left, List right, List expanded) {
  List pending = sum(left, right);
  List wrong = product(left, right);
  int pending_hit = 0, body_hit = 0, wrong_hit = 0;
  match (pending) {
    case sum(?a, ?b):
      pending_hit = List.compare(a, left) == 0 &&
                    List.compare(b, right) == 0;
  }
  match (expanded) {
    case sum(?a, ?b):
      body_hit = List.compare(a, left) == 0 &&
                 List.compare(b, right) == 0;
  }
  match (wrong) {
    case sum(?a, ?b): wrong_hit = 1;
  }
  if (!pending_hit || !body_hit || wrong_hit)
    x2c_diagnostic_fail("stage-selected source cases failed",
      %(${%"hits: $pending_hit $body_hit $wrong_hit"} ${pending.repr()} ${expanded.repr()}));
  return pending;
}
macro Expression $stage_cases(Expr $left, Expr $right, Expr $expanded) =>
  $recognize_stages($sum, $product, $left, $right, $expanded);

int main(void) {
  int price = 19, tax = 23;
  assert($stage_cases(price, tax, $sum(price, tax)) == 42);
  puts("same source Macro case recognizes retained and expanded inputs; product fails");
  return 0;
}
