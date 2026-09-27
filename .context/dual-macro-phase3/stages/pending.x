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
macro Statement $audited(Expr $value, Expr $observer) {
  int saved = $value;
  $observer(saved);
  return saved;
}
macro Expression $sum(Expr $left, Expr $right) => $left + $right;

meta static Var build_audited(List value, List observer) {
  Macro template = $audited;
  List pending = template(value, observer);
  List rows;
  if (!pending.try_match(%("x2c.template" ?def ?values), rows))
    x2c_diagnostic_fail("application was not retained", NULL);
  if (!((List) rows.assoc(<?def>)).assoc(<fresh>).list())
    x2c_diagnostic_fail("fresh interface was lost", NULL);
  List values = rows.assoc(<?values>);
  if (values.len() != 2 || !values.car().list().equal(value) ||
      !values.cadr().list().equal(observer))
    x2c_diagnostic_fail("pending captures changed", NULL);
  return pending;
}
macro Statement $rewrite(Expr $value, Expr $observer) {
  $build_audited($value, $observer)...
}

static int observed = 0;
static int evaluate(int value) {
  observed++;
  return value;
}
static void audit(int value) { observed += value; }
int rewritten(int price, int tax) {
  int saved = 900;
  (void) saved;
  $rewrite(evaluate(price + tax), audit);
}
int rewritten_again(int other_price, int other_tax) {
  int saved = 700;
  (void) saved;
  $rewrite(evaluate(other_price + other_tax), audit);
}

meta static List sum_pipeline(List left, List right, List expanded) {
  Macro sum = $sum;
  List pending = sum(left, right), rows;
  if (!pending.try_match(%("x2c.template" ?def ?values), rows))
    x2c_diagnostic_fail("sum invocation was not retained", NULL);
  if (pending.try_match(Macro_pattern(sum, %(?a ?b)), rows))
    x2c_diagnostic_fail("pending invocation matched sum body", NULL);
  if (!expanded.try_match(Macro_pattern(sum, %(?a ?b)), rows))
    x2c_diagnostic_fail("expanded sum body did not match", NULL);
  return pending;
}
macro Expression $retained_sum(Expr $left, Expr $right, Expr $expanded) =>
  $sum_pipeline($left, $right, $expanded);

int main(void) {
  int a = 19, b = 23;
  assert($retained_sum(a,b,$sum(a,b)) == 42);
  assert(rewritten(19,23) == 42);
  assert(observed == 43);
  assert(rewritten_again(20,22) == 42);
  assert(observed == 86);
  puts("pending Macro: staged recognition and ordinary fresh audit insertion pass");
  return 0;
}
