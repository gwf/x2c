#include "x2c.x"
#include "meta.x"

typedef struct MixedRecord { int subtotal, total; } MixedRecord;
static int sink;

macro Stmt $mixed(Name $name, Expr $record) {
  int $name = $record.$name;
  sink += $name;
}
macro Stmt $fresh(Expr $record) {
  int subtotal = $record.subtotal;
  sink += subtotal;
}
macro Stmt $member_first(Name $name, Expr $record) {
  sink += $record.$name;
  int $name = 1;
  sink += $name;
}
macro Expression $read_name(Name $name) => $name;
macro Expression $read_member(Expr $record, Name $name) =>
  $record.$name;

meta static List mixed_hit(List code) {
  Macro mixed = $mixed;
  List declared = NULL, receiver = NULL;
  match (code) {
    case %(block (at ? (declare ?
           (bindings (op = (bind ?name ?)
             (expr ? (op . ?record ?)))))) *): {
      declared = name;
      receiver = record;
    }
    case %(seq (declare ?
           (bindings (op = (bind ?name ?)
             (expr ? (op . ?record ?))))) *): {
      declared = name;
      receiver = record;
    }
  }
  match (code) {
    case mixed(?name, ?record): {
      if (!declared || !receiver ||
          List.compare(name, declared) != 0 ||
          List.compare(record, receiver) != 0)
        x2c_diagnostic_fail("mixed Name capture lost source subtree", %());
      return $!int{ 1 };
    }
  }
  return $!int{ 0 };
}
macro Expression $is_mixed(Stmt $code) => $mixed_hit($code);

meta static List member_first_hit(List code) {
  Macro shape = $member_first;
  match (code) case shape(?name, ?record): return $!int{ 1 };
  return $!int{ 0 };
}
macro Expression $is_member_first(Stmt $code) =>
  $member_first_hit($code);

meta static List pending_hit(Var name, List record) {
  Macro shape = $mixed;
  List pending = shape(name, record);
  match (pending) case shape(?same, ?receiver):
    return $!int{ ${same == name &&
                           List.compare(receiver, record) == 0} };
  return $!int{ 0 };
}
macro Expression $is_pending(Name $name, Expr $record) =>
  $pending_hit($name, $record);

meta static List single_role_hits(List reference, List member) {
  Macro read_name = $read_name, read_member = $read_member;
  int binding_hit = 0, member_hit = 0;
  match (reference) case read_name(?name): binding_hit = name is <list>;
  match (member) case read_member(?record, ?name):
    member_hit = name == "subtotal";
  return $!int{ ${binding_hit + member_hit} };
}
macro Expression $single_roles(Expr $reference, Expr $member) =>
  $single_role_hits($reference, $member);

meta static List wrong_reference_case(List code, List other) {
  List original = NULL, replacement = NULL;
  match (code)
    case %(block (at ? (declare ?
           (bindings (op = (bind ?name ?) ?)))) *): original = name;
  match (other)
    case %(block (at ? (declare ?
           (bindings (op = (bind ?name ?) ?)))) *): replacement = name;
  if (!original || !replacement ||
      List.compare(original, replacement) == 0 ||
      original.caddr() != replacement.caddr())
    x2c_diagnostic_fail("wrong-reference setup failed", %());
  List changed = code.search_replace(
    %(ident (!quote $original)), %(ident $replacement));
  if (List.compare(changed, code) == 0)
    x2c_diagnostic_fail("wrong-reference substitution failed", %());
  return mixed_hit(changed);
}
macro Expression $wrong_reference(Stmt $code, Stmt $other) =>
  $wrong_reference_case($code, $other);

int main(void) {
  MixedRecord record = { .subtotal = 4, .total = 7 };
  int hit = $is_mixed({ int subtotal = record.subtotal; sink += subtotal; });
  int wrong_member = $is_mixed({
    int subtotal = record.total;
    sink += subtotal;
  });
  int renamed = $is_mixed($fresh(record););
  int first = $is_member_first({
    sink += record.subtotal;
    int subtotal = 1;
    sink += subtotal;
  });
  int first_wrong = $is_member_first({
    sink += record.total;
    int subtotal = 1;
    sink += subtotal;
  });
  int pending = $is_pending(subtotal, record);
  int wrong_ref = $wrong_reference(
    { int subtotal = record.subtotal; sink += subtotal; },
    { int subtotal = record.subtotal; sink += subtotal; });
  int subtotal = 3;
  int single_roles = $single_roles(subtotal, record.subtotal);
  printf("%d %d %d %d %d %d %d %d\n", hit, wrong_member, renamed,
         first, first_wrong, pending, wrong_ref, single_roles);
  return 0;
}
