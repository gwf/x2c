#include "x2c.x"

$(def compile_answer 40)

int main(void) {
  printf("%d\n", $(+ compile_answer 2));
  return 0;
}
