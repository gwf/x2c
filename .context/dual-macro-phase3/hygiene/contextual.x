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

meta static List Macro_apply(Macro t, List values) {
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

static Var Macro_inline(List environment, Var tree) {
  if (tree is not <list>) return tree;
  match (tree) {
    case %(tpl-call (expr ? (ident ?binding)) (args *arguments)): {
      Macro child = NULL;
      foreach (List row, environment)
        if (List.compare(row.car(), binding) == 0) {
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

int observed = 0;
int audits = 0;
void audit(int value) { observed = value; audits++; }
macro Statement $audited(Expr $value) {
  int saved = $value;
  audit(saved);
  return saved;
}
meta static List pending(Macro t, List value) =>
  %(("x2c.template" $t ($value)));
macro Statement $insert(Expr $value) { $pending($audited, $value)... }
meta static Var hygiene_view(Var value) {
  if (value is not <list>) return value;
  match (value) {
    case %(at ? ?body): return hygiene_view(body);
    case %(src ? ?body): return hygiene_view(body);
    case %(literal *): return value;
  }
  Array parts = [];
  foreach (Var child, value.list()) parts.push(hygiene_view(child));
  return parts.list_free();
}
meta static List hygiene_pattern(Macro t, List names) {
  List pattern = Macro_pattern(t, names), replacements = NULL;
  int ordinal = 0;
  foreach (List row, t.assoc(<fresh>).list()) {
    Atom binder = row.car();
    Atom identity = Atom.intern(%"?__identity_${ordinal++}");
    replacements = cons(%($binder (binding $identity ?)), replacements);
  }
  pattern = hygiene_view(pattern.replace(replacements));
  match (pattern) case %(seq *parts): return %(!or (seq @parts) (block @parts));
  return pattern;
}
meta static List inspect(Macro t, List value) {
  List pattern = hygiene_pattern(t, %(?value)), rows;
  List subject = hygiene_view(value);
  int result = subject.try_match(pattern, rows);

  return x2c_literal_int(result);
}
macro Expression $show(Statement $value) => $inspect($audited, $value);
int external = 5;
macro Statement $nested(Expr $value) {
  int x = $value;
  { int x = 1; audit(x); }
  audit(x + external);
}
meta static List match_macro(Macro t, List value) {
  List pattern = hygiene_pattern(t, %(?value)), rows;
  List subject = hygiene_view(value);
  int hit = subject.try_match(pattern, rows);

  return x2c_literal_int(hit);
}
macro Expression $nested_match(Statement $code) => $match_macro($nested, $code);
macro Statement $returned(Expr $value) { return $value; }
meta static List audit_transform(Macro input, Macro output, List statement) {
  List pattern = hygiene_pattern(input, %(?value)), rows;
  List subject = hygiene_view(statement);
  if (!subject.try_match(pattern, rows)) return %($statement);
  Var value = rows.assoc(<?value>);
  return %(("x2c.template" $output ($value)));
}
macro Statement $audit_return(Statement $code) {
  $audit_transform($returned, $audited, $code)...
}
macro Statement $cross(Decl $prefix, Expr $value) { $prefix return $value; }
meta static Var replace_binding(Var tree, List owned, Var replacement) {
  if (tree is not <list>) return tree;
  if (tree.list().compare(owned) == 0) return replacement;
  Array parts = [];
  foreach (Var child, tree.list()) parts.push(replace_binding(child, owned, replacement));
  return parts.list_free();
}
meta static List cross_rebuild(Macro t, List code) {
  List pattern = hygiene_pattern(t, %(?prefix ?value)), rows;
  List subject = hygiene_view(code);
  if (!subject.try_match(pattern, rows)) return %((return (int) ${x2c_literal_int(-1)}));
  List prefix = rows.assoc(<?prefix>), value = rows.assoc(<?value>);
  List owned = NULL;
  match (prefix) {
    case %(declare ? (bindings (op = (bind ?binding ?) ?))): owned = binding;
    case %(declare ? (bindings (bind ?binding ?))): owned = binding;
  }
  if (!owned) return %((return (int) ${x2c_literal_int(-2)}));
  String label = owned.caddr();
  Atom fresh = Atom.intern("?__captured_local");
  List body = Macro_apply(t, %($prefix $value));
  body = replace_binding(body, owned, fresh);
  Array fields = []; fields.push(<macrodef>);
  foreach (List field, t.cdr()) {
    Var key = field.car();
    if (key == <template>) fields.push(%(template $body));
    else if (key == <parameters>) fields.push(%(parameters ()));
    else if (key == <pattern>) fields.push(%(pattern (args)));
    else if (key == <fresh>) fields.push(%(fresh (($fresh $label 0) @{field.cadr().list()})));
    else fields.push(field);
  }
  Macro closed = fields.list_free();
  return %(("x2c.template" $closed ()));
}
macro Statement $cross_copy(Statement $code) { $cross_rebuild($cross, $code)... }
int cross_demo(void) { $cross_copy({ int carried = 9; return carried; }); }
macro Statement $decl_record(Decl $prefix, Expr $value) { $prefix audit($value); }
meta static List cross_rebuild_twice(Macro t, List code) {
  List once = cross_rebuild(t, code);
  return %(@once @once);
}
macro Statement $cross_twice(Statement $code) { $cross_rebuild_twice($decl_record, $code)... }
int cross_copies(void) {
  int carried = 999;
  $cross_twice({ int carried = 9; audit(carried); });
  return carried;
}
macro Statement $recorded(Expr $value) { int saved = $value; audit(saved); }
meta static List pending_twice(Macro t, List value) =>
  %(("x2c.template" $t ($value)) ("x2c.template" $t ($value)));
macro Statement $insert_twice(Expr $value) { $pending_twice($recorded, $value)... }
int copies(int price) { int saved = 999; $insert_twice(price); return saved; }
int foo(int price) { int saved = 999; $insert(price); }
int transformed(int price) { $audit_return(return price + 1;); }
macro Expression $code(Statement $value) => $(_x2c.literal.list $value);
macro Statement $repeated(Statement $item, Statement $between...) {
  $item $between... $item
}
typedef struct ActualPolicy { int same_slot, calls, rejected; Macro item; } ActualPolicy;
static int actual_relation(void *raw, int slot, Var left, Var right, void *context) {
  ActualPolicy *policy = context;
  if (slot != policy.same_slot) return left == right;
  policy.calls++;
  List pattern = hygiene_pattern(policy.item, %(?value)), a, b;
  List left_code = hygiene_view(left), right_code = hygiene_view(right);
  if (!left_code.try_match(pattern, a) || !right_code.try_match(pattern, b)) {
    policy.rejected++; return 0;
  }
  List av = a.assoc(<?value>), bv = b.assoc(<?value>);
  int result = av.compare(bv) == 0;
  if (!result) policy.rejected++;
  return result;
}
int main(void) {
  Macro item = $nested, repeated = $repeated;
  List source = $code({
    { int outer = 3; { int inner = 1; audit(inner); } audit(outer + external); }
    { int outer = 3; { int inner = 1; audit(outer); } audit(outer + external); }
    { int renamed = 3; { int other = 1; audit(other); } audit(renamed + external); }
  });
  List pattern = hygiene_pattern(repeated, %(?same *between));
  List subject = hygiene_view(source);
  MatchPlan plan = MatchPlan.prepare(pattern);
  ActualPolicy policy = { .same_slot = plan.layout.index(<?same>),
                          .calls = 0, .rejected = 0, .item = item };
  struct MatchMachine storage;
  MatchMachine machine = &storage;
  machine.open(); machine.relation = actual_relation; machine.relation_context = &policy;
  machine.begin(plan.program.view(), subject); machine.run();
  assert(machine.status == <ok>);
  assert(policy.calls >= 2 && policy.rejected >= 1);
  MachineSlot *between = &machine.slots[plan.layout.index(<*between>)];
  List taken = between.kind == MACHINE_SLOT_SPAN
    ? machine.materialize_span(between.span) : between.value.list();
  assert(taken.len() == 1);
  machine.finish(); assert(machine.clean());
  machine.dispose(); plan.free();
  puts("hygiene-context: actual parsed repeated+nested bodies, actual captured local identities, contextual retry PASS");
  return 0;
}
