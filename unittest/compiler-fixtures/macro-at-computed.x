#include "x2c.x"
#include "meta.x"

meta static List identity(List rows) => rows;
macro Expression $call(Expr $callee, Expr @args) => $callee(@identity($args));
macro Expression $lisp_call(Expr $callee, Expr @args) => $callee(@(identity $args));
macro Expression $array(Expr @args) => %[${@identity($args)}];
macro Expression $map(Entry @rows) => %{${@identity($rows)}};
macro Expression $lambda(Expr $body, Param @params) =>
  %!(@identity($params)) => $body;
macro Unit $fields(Name $name, Field @rows) {
  typedef struct $name { @identity($rows) } $name;
}
macro Unit $enums(Enumerator @rows) {
  enum GeneratedEnum { @(identity $rows) };
}
macro Unit $global_locals(DeclaratorRow @rows) { int @(identity $rows); }
macro Stmt $locals(DeclaratorRow @rows) { int @identity($rows); }
macro Stmt $block(Stmt @rows) { @identity($rows) }
meta static List catch_rows(void) {
  List pattern = $!( %(probe (value ?captured)) );
  List body = $!{ total = captured; };
  return %(($pattern $body));
}
macro Stmt $caught(Stmt $body) { try $body catch @catch_rows() }
macro Stmt $caught_lisp(Stmt $body) { try $body catch @(catch_rows) }
macro Stmt $matched(Expr $value, MatchRow @rows) { match ($value) { @(identity $rows) } }
macro Unit $units(Unit @rows) { @identity($rows) }
macro Stmt $fixture.for(Stmt @rows) { @rows }
macro Stmt $qualified(Stmt $row) { @fixture.for($row) }

$global_locals(global_left = 20, global_right = 22);
$fields(Generated, int value;);
$enums(ROW_A = 2, ROW_B = 3);
$units(static int total;,
       static int sum(int a, int b) => a + b;);

int main(void) {
  $locals(left = 20, right = 22);
  $block(total = $call(sum, left, right););
  Array full = $array(20, 22), empty = $array();
  Map map = $map("a": 20, "b": 22), no_rows = $map();
  Generated record = {.value = ROW_A + ROW_B};
  Func fn = $lambda(42, int unused);
  (void) fn;
  $caught(raise %(probe (value 43)););
  $caught_lisp(raise %(probe (value 44)););
  $matched(%(ready), case %(ready): total++;);
  $qualified(total++;);
  if (total != 46 || global_left + global_right != 42 || $lisp_call(sum, left, right) != 42 ||
      full.len() != 2 || empty.len() || full[0].int() != 20 ||
      full[1].int() != 22 || map["a"].int() != 20 ||
      map["b"].int() != 22 || no_rows.len() || record.value != 5)
    return 1;
  puts("computed sequence roles ok");
  return 0;
}
