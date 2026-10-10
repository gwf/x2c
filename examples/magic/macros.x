#include <assert.h>
macro Stmt $swap(Expr $left, Expr $right) {
  $(Code.type $left) temporary = $left;
  $left = $right;
  $right = temporary;
}

int main(void) {
// The same macro works with different types.
int left = 20, right = 22;
$swap(left, right);

String first = "hello", last = "world";
$swap(first, last);
printf("%d %d; %s %s\n", left, right, first, last);
assert(left == 22 && right == 20);
assert(first == "world" && last == "hello");
return 0;
}
