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

meta static List Macro_apply(Macro t, List values) =>
  _macro_instantiate(t, values);

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


static Atom _hygiene_local(int index) => Atom.intern(%"?__fixed_$index");

static Var _hygiene_view(Var value) {
  if (value is not <list>) return value;
  List node = value;
  match (node) {
    case %(at ? ?body): return _hygiene_view(body);
    case %(src ? ?body): return _hygiene_view(body);
    case %(literal *): return value;
    case %(binding ? ?): return value;
  }
  Array parts = [];
  foreach (Var child, node) parts.push(_hygiene_view(child));
  return parts.list_free();
}

static List _hygiene_pattern(Macro t, List names) {
  List pattern = Macro_pattern(t, names), replacements = NULL;
  int ordinal = 0;
  foreach (List fresh, t.assoc(<fresh>).list()) {
    Atom identity = _hygiene_local(ordinal++);
    replacements = cons(%(${fresh.car()} (binding (!and $identity $identity) ?)), replacements);
  }
  pattern = pattern.replace(replacements);
  match (pattern) case %(seq *parts): pattern = %(!or (seq @parts) (block @parts));
  return _hygiene_view(pattern);
}

typedef struct FixedIdentityPolicy { int count; int slots[MACHINE_BINDER_MAX]; } FixedIdentityPolicy;

static int _hygiene_identity_equal(void *raw_machine, int slot, Var left,
                                   Var right, void *raw_policy) {
  if (left != right) return 0;
  MatchMachine machine = raw_machine;
  FixedIdentityPolicy *policy = raw_policy;
  int local = 0;
  for (int i = 0; i < policy.count; i++) if (policy.slots[i] == slot) local = 1;
  if (!local) return 1;
  for (int i = 0; i < policy.count; i++) {
    int other = policy.slots[i];
    if (other != slot && machine.slots[other].kind == MACHINE_SLOT_VALUE &&
        machine.slots[other].value == right) return 0;
  }
  return 1;
}

static int _hygiene_capture(List code, Macro t, List pattern,
                            MatchCaptureBuffer *captured) {
  MatchPlan plan = MatchPlan.prepare(pattern);
  if (plan.status != MACHINE_PREPARED) {
    int result = plan.execute_capture(code, *captured, NULL);
    plan.free();
    return result == 1;
  }
  FixedIdentityPolicy policy; policy.count = 0;
  int ordinal = 0;
  foreach (List fresh, t.assoc(<fresh>).list()) {
    int slot = plan.layout.index(_hygiene_local(ordinal++));
    if (slot >= 0) policy.slots[policy.count++] = slot;
  }
  struct MatchMachine storage;
  MatchMachine machine = &storage;
  machine.open(); machine.relation = _hygiene_identity_equal;
  machine.relation_context = &policy;
  machine.begin(plan.program.view(), _hygiene_view(code)); machine.run();
  int matched = machine.status == <ok>;
  if (matched) {
    for (int i = 0; i < machine.slot_count; i++) {
      MachineSlot *slot = &machine.slots[i];
      if (slot.kind == MACHINE_SLOT_INVALID) continue;
      captured->values[i] = slot.kind == MACHINE_SLOT_SPAN
        ? machine.materialize_span(slot.span) : slot.value;
      captured->present |= 1UL << i;
    }
    matched = machine.status == <ok>;
  }
  machine.finish(); machine.dispose(); plan.free();
  return matched;
}

static int _macro_capture(List code, Macro t, List names,
  MatchCaptureBuffer *published) {
  List pattern = _hygiene_pattern(t, names);
  MatchCaptureLayout actual = MatchCaptureLayout.analyze(pattern);
  MatchCaptureLayout logical = MatchCaptureLayout.analyze(%(!and @names));
  Var values[MACHINE_BINDER_MAX], ordered[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  int matched = _hygiene_capture(code, t, pattern, &captured);
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

int observed = 0;
void audit(int value) { observed = value; }
macro Statement $audited(Expr $value, Expr $observer) {
  int saved = $value;
  $observer(saved);
  return saved;
}
int external = 5;
macro Statement $nested(Expr $value, Expr $observer) {
  int x = $value;
  { int x = 1; $observer(x); }
  $observer(x + external);
}
macro Expression $code(Statement $value) => $(_x2c.literal.list $value);
static int recognize_audit(List code) {
  Macro selected = $audited;
  match (code) case selected(?value, ?observer): {
    assert(value is <list> && observer is <list>);
    List captured = observer.list().search(%(binding ? "audit"));
    List original = code.search(%(binding ? "audit"));
    assert(captured && original);
    List captured_record = captured.car().list().assoc(<*>);
    List original_record = original.car().list().assoc(<*>);
    assert(captured_record.equal(original_record));
    return 1;
  }
  return 0;
}
static int recognize_nested(List code) {
  Macro selected = $nested;
  match (code) case selected(?value, ?observer): return 1;
  return 0;
}
static Var merge_identity(Var code, Var from, Var to) {
  if (code is not <list>) return code;
  match (code) case %(binding ?id ?name):
    if (id == from) return %(binding $to $name);
  Array parts = [];
  foreach (Var child, code.list()) parts.push(merge_identity(child, from, to));
  return parts.list_free();
}
int main(void) {
  List actual = $code({ int subtotal = 7; audit(subtotal); return subtotal; });
  assert(recognize_audit(actual));
  assert(!recognize_audit($code({ int subtotal = 7; audit(observed); return subtotal; })));
  List nested = $code({ int outer = 3; { int inner = 1; audit(inner); } audit(outer + external); });
  assert(recognize_nested(nested));
  assert(!recognize_nested($code({ int outer = 3; { int inner = 1; audit(outer); } audit(outer + external); })));
  { int external = 99;
    assert(!recognize_nested($code({ int outer = 3; { int inner = 1; audit(inner); } audit(outer + external); })));
  }
  Macro selected = $nested;
  List rows;
  assert(_hygiene_view(nested).list().try_match(_hygiene_pattern(selected, %(?value ?observer)), rows));
  Var outer = rows.assoc(_hygiene_local(0)), inner = rows.assoc(_hygiene_local(1));
  List merged = merge_identity(nested, inner, outer);
  assert(!recognize_nested(merged));
  puts("source-case-hygiene: actual derived fresh slots, renamed locals, nested shadow/free mismatch, raw binding captures, injectivity checkpoint PASS");
  return 0;
}
