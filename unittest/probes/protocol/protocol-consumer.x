#include "protocol-owner.x"

int main(void) {
  Vec value = xmalloc(sizeof(struct Vec));
  value.x = 7;
  Var boxed = value;
  printf("%s\n", boxed);
  return 0;
}
