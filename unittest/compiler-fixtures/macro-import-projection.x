#include <stdlib.h>

int answer(void) { return 42; }
$(import "macro-import-projection.xmacro")
class Projected { int value; };

int main(void) {
  int answer = 3, abs = 5;
  printf("%d %d %d %d\n", answer, abs,
    $project.global_answer(), $project.native_abs(-7));
  return 0;
}
