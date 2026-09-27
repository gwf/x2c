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
      rows = cons(%($key $selected), rows);
    }
    rows = cons(%(${Atom.intern(%"?__macro_member_$name")} $selected), rows);
    rows = cons(%(${Atom.intern(%"*__macro_splice_$name")} ($selected)), rows);
  }
  List body = t.assoc(<template>);
  return Macro_pattern_view(Macro_inline(t.assoc(<env>), body.replace(rows)));
}

macro Expression $sum(Expr $left, Expr $right) => $left + $right;
macro Expression $product(Expr $left, Expr $right) => $left * $right;
macro Expression $cast(Type $type, Expr $value) => ($type) ($value);
macro Expression $call(Expr $callee, Expr $items...) => $callee($items...);
macro Expression $member(Expr $object, Name $name) => $object.$name;
macro Statement $returned(Expr $value) { return $value; }

int sum(int a, int b) => 100 + a + b;
int ordinary_collision(void) {
  int ordinary = sum(1,2);
  macro Expression sum(Expr $a, Expr $b) => $a + $b + 20;
  int local = sum(1,2);
  int global = $sum(1,2);
  int escaped = (sum)(1,2);
  int (*reference)(int,int) = sum;
  printf("collision %d %d %d %d %d\n", ordinary,local,global,escaped,reference(1,2));
  return ordinary != 103 || local != 23 || global != 3 || escaped != 103 || reference(1,2) != 103;
}

meta static List applied(Macro t) => t(3,4);
meta static int direct(void) => $sum(3,4);
meta static Macro factory(void) => macro Expression(Expr $left, Expr $right) => $left + $right;
meta static Macro relay(Macro t) => t;
meta static Macro composed(Macro inner) {
  Macro outer = macro Expression(Expr $inside) => ($inside);
  List child_body = inner.assoc(<template>);
  List result_body = outer(child_body);
  Macro result = outer.search_replace(%(template ?old), %(template $result_body));
  return result.search_replace(%(parameters ?old), %(parameters ${inner.assoc(<parameters>)}));
}
macro Expression $apply_sum() => $applied($sum);
macro Expression $direct_sum() => $direct();
macro Expression $factory_sum() => $applied($relay($factory()));

Macro choose(int flag, Macro a, Macro b) => flag ? a : b;
int recognizes(Macro pattern, List code) {
  match (code) {
    case pattern(?a, ?b): return 1;
    default: return 0;
  }
}

meta static Macro lexical_wrap(Macro inner) =>
  macro Expression(Expr $left, Expr $right) => (inner($left, $right));
macro Expression $lexical_sum() => $applied($lexical_wrap($factory()));

int main(int argc, char **argv) {
  (void) argv;
  int bad = ordinary_collision();
  int bound = $apply_sum(), named = $direct_sum(), anonymous = $factory_sum();
  printf("bound %d %d %d\n", bound,named,anonymous);
  bad |= bound != 7 || named != 7 || anonymous != 7;
  Macro plus = $sum, times = $product;
  List code = %(expr (int) (op + (expr (int) (literal (int) "9")) (expr (int) (literal (int) "10"))));
  Macro selected = choose(argc == 1,plus,times);
  int hit = recognizes(selected,code), miss = recognizes(choose(argc != 1,plus,times),code);
  printf("dynamic %d %d\n", hit,miss);
  bad |= hit != 1 || miss != 0;
  Macro wrapped = $composed($factory());
  List parens = %(expr (int) (parens $code));
  Macro lexical = $lexical_wrap($factory());
  int lexical_hit = recognizes(lexical,parens);
  int lexical_value = $lexical_sum();
  printf("lexical composed %d %d\n", lexical_hit,lexical_value);
  bad |= lexical_hit != 1 || lexical_value != 7;
  int composed_hit = recognizes(wrapped,parens);
  printf("anonymous composed %d\n", composed_hit);
  bad |= composed_hit != 1;
  Macro sum = $sum;
  List built = sum(code, code);
  printf("runtime constructed %s\n", built.repr().str());
  return bad;
}
