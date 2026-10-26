#include "lib.x"
#include "meta.x"
#include "rewrite.x"
int count(int fixed, .... items) => fixed + items.len();
macro Expression $counted(Expr @args) => count(@args);
$rewrite($counted)
meta Code ordered_count(Code call) {
  match (call) case %(expr ? (call ?target (args *arguments))): {
    List fixed = %(expr (int) (literal (int) "100"));
    return Code.call_in_order(target, cons(fixed, arguments.cdr()), %(int));
  }
  return call;
}
int main(void) {
  List values = %(1 2);
  int result = count(10, @values, 3);
  printf("%d\n", result);
  return 0;
}
