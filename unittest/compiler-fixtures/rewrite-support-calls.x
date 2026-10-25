#include "x2c.x"
#include "rewrite.x"

/* Program call rules see the calls a program writes, including those
   inside an interpolation hole or a literal's element, but not the support
   calls that shipped components write for interpolation, collection
   literals, and indexed stores and updates. Each count is the explicit
   calls only. */
static int joins = 0, news = 0, updates = 0, stores = 0;

macro Expression $join(Expr $sep, Expr $parts) => String.join($sep, $parts);
macro Expression $new_map() => Map.new();
macro Expression $update_map(Expr $m, Expr @items) => Map.update_n($m, @items);
macro Expression $store(Expr $m, Expr $k, Expr $v) =>
  Map.setindex($m, $k, $v);
macro Expression $update(Expr $m, Expr $k, Expr $op, Expr $v) =>
  Map.updateindex($m, $k, $op, $v);
macro Expression $postfix(Expr $m, Expr $k, Expr $op) =>
  Map.postfixindex($m, $k, $op);

$rewrite($join)
meta Code count_join(Code code) {
  match (code) case $join(?sep, ?parts):
    return $!String{ (joins++, String.join($sep, $parts)) };
  return code;
}

$rewrite($new_map)
meta Code count_new(Code code) => $!Map{ (news++, Map.new()) };

$rewrite($update_map)
meta Code count_update_map(Code code) {
  match (code) case $update_map(?m, *items):
    return $!Map{ (updates++, Map.update_n($m, @items)) };
  return code;
}

$rewrite($store)
meta Code count_store(Code code) {
  match (code) case $store(?m, ?k, ?v):
    return $!Var{ (stores++, Map.setindex($m, $k, $v)) };
  return code;
}

$rewrite($update)
meta Code count_update(Code code) {
  match (code) case $update(?m, ?k, ?op, ?v):
    return $!Var{ (stores++, Map.updateindex($m, $k, $op, $v)) };
  return code;
}

$rewrite($postfix)
meta Code count_postfix(Code code) {
  match (code) case $postfix(?m, ?k, ?op):
    return $!Var{ (stores++, Map.postfixindex($m, $k, $op)) };
  return code;
}

int main(void) {
  String who = "world";
  String hello = %"hello $(who) $(String.join("-", %("a" "b")))";
  Map m = {"k": String.join("+", %("p" "q"))}, empty = {};
  Array a = [1, String.join("*", %("u" "v"))];
  m["n"] = 1;
  m["n"] += 2;
  m["n"]++;
  Map made = Map.new();
  Map.setindex(made, "x", 1);
  Var one = 1;
  made = Map.update_n(made, 1, one, one);
  printf("%s %s %s %s %d %d\n", hello, m.repr(), a.repr(), empty.repr(),
         (int) m.len(), (int) made.len());
  printf("joins=%d news=%d updates=%d stores=%d\n", joins, news, updates,
         stores);
  return 0;
}
