#include "protocol-owner.x"

int main(void) {
  Vec value = Scope.malloc(sizeof(struct Vec));
  value.x = 7;
  Var boxed = value;
  printf("%s\n", boxed.str());
  return 0;
}
