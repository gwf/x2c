/* A bodied meta function may live in an ordinary program file. */

#include "x2c.x"

meta int program_meta(int x) => x + 1;

int main(void) {
  printf("%d\n", $program_meta(41));
  return 0;
}
