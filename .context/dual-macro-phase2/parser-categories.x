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
      rows = cons(%($key ${sequence ? %($selected).var() : selected}), rows);
    }
    rows = cons(%(${Atom.intern(%"?__macro_member_$name")} $selected), rows);
    rows = cons(%(${Atom.intern(%"*__macro_splice_$name")} ($selected)), rows);
  }
  List body = t.assoc(<template>);
  return Macro_pattern_view(Macro_inline(t.assoc(<env>), body.replace(rows)));
}

macro Expression $sum(Expr $left, Expr $right) => $left + $right;
macro Expression $twice(Expr $value) => $value + $value;
macro Expression $call(Expr $callee, Expr $items...) => $callee($items...);
macro Expression $size(Type $type) => sizeof($type);
macro Expression $member(Expr $object, Name $name) => $object.$name;
macro Statement $returned(Expr $value) { return $value; }

int repeated(Macro pattern, List code) {
  match (code) {
    case pattern(?value): return 1;
    default: return 0;
  }
}
int sequence_count(Macro pattern, List code) {
  match (code) {
    case pattern(?callee, *items): return items.len();
    default: return -1;
  }
}
int type_match(Macro pattern, List code) {
  match (code) {
    case pattern(*type): return List.compare(type, %(int)) == 0;
    default: return 0;
  }
}
int member_match(Macro pattern, List code) {
  match (code) {
    case pattern(?object, ?name): return name.str().equal("total");
    default: return 0;
  }
}
int statement_match(Macro pattern, List code) {
  match (code) {
    case pattern(?value): return 1;
    default: return 0;
  }
}

int main(void) {
  List a = %(expr (int) (ident (binding 1 "a")));
  List b = %(expr (int) (ident (binding 2 "b")));
  List same = %(expr (int) (op + $a $a));
  List different = %(expr (int) (op + $a $b));
  int repeated_hit = repeated($twice,same), repeated_miss = repeated($twice,different);
  printf("repeated %d %d\n",repeated_hit,repeated_miss);
  Macro call = $call;
  List callee = %(expr () (ident "f"));
  List empty = %(expr () (call $callee (args)));
  List three = %(expr () (call $callee (args $a $b $a)));
  int zero = sequence_count(call,empty), count = sequence_count(call,three);
  List rebuilt_empty = call(callee), rebuilt_three = call(callee,a,b,a);
  int rz = sequence_count(call,rebuilt_empty), rt = sequence_count(call,rebuilt_three);
  printf("sequence %d %d rebuild %d %d\n",zero,count,rz,rt);
  List size = %(expr (ulong) (sizeof (int)));
  int type_hit = type_match($size,size);
  Macro type_template = $size;
  List type_built = type_template(%(int));
  int type_rebuilt = type_match(type_template,type_built);
  printf("Type %d %d body %s built %s\n",type_hit,type_rebuilt,((List) type_template.assoc(<template>)).repr().str(),type_built.repr().str());
  List member = %(expr (int) (op . $a ("total")));
  int name_hit = member_match($member,member);
  Macro name_template = $member;
  List name_built = name_template(a,"total");
  int name_rebuilt = member_match(name_template,name_built);
  printf("Name %d %d\n",name_hit,name_rebuilt);
  List returned = %(return (int) $a);
  int statement_hit = statement_match($returned,returned);
  Macro statement_template = $returned;
  List statement_built = statement_template(a);
  int statement_rebuilt = statement_match(statement_template,statement_built);
  printf("Statement %d %d\n",statement_hit,statement_rebuilt);
  return repeated_hit != 1 || repeated_miss != 0 || zero != 0 || count != 3 || rz != 0 || rt != 3 || type_hit != 1 || type_rebuilt != 1 || name_hit != 1 || name_rebuilt != 1 || statement_hit != 1 || statement_rebuilt != 1;
}
