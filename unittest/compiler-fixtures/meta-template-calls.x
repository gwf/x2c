#include "x2c.x"

$(import "meta-template-calls.xmacro")

$make_answer();

macro Unit $build_echo() { $template_build()... }
$build_echo();

int main(int argc, char **argv) {
  (void) argv;
  $template_noop();
  $template_void();
  int x = argc + 5;
  List values = %(4 5);
  List same = $identity(values);
  printf("%d %d %d\n", $twice(3 + 4), $identity(x + 2), $nested(5));
  printf("%d %d %d\n", $collision(1), collision(1), $expression_macro(1));
  printf("%d %d %d %d\n", answer(), echo(42),
    $count_values(%(1 2 3)), same.len());
  return 0;
}
