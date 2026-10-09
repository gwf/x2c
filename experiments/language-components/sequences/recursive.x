#include "statements.x"
int main(void) {
  $trace();
  $trace(puts("one");, puts("two");, printf("other\n"););
  return 0;
}
