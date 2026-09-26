#include "x2c.x"
#include "meta.x"
$(import "meta-capture-definition/helpers.xmacro")

$(import "meta-capture-calls.xmacro")

macro Expression $capture.text(Expr $value) => $capture_text($value);
macro Expression $capture.forward($value) => $capture.text($value);
macro Statement $capture.swap(Expr $left, Expr $right) {
  $capture_type($left) temporary = $left;
  $left = $right;
  $right = temporary;
}
macro Enumerator $capture.values() {
  base = 3,
  $capture_name("READY") = base + 1,
  $capture_name("DONE")
}
macro Decorator $capture.trace(Function $function) {
  printf("%s\n", $capture_function_name($function));
  $capture_function_body($function)...
}

enum Status { $capture.values() };
$capture.trace()
static int answer(void) { return 42; }

int main(void) {
  int a = 1, b = 2;
  printf("[%s]\n", $capture.forward(a /* kept */ + 2));
  $capture.swap(a, b);
  printf("%d %d %d %d\n", a, b, READY, DONE);
  printf("%d\n", answer());
  printf("%s", $capture.notice("macro-embed-text-data.txt"));
  return 0;
}
