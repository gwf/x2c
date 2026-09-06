#include "x2c.x"

typedef struct ParseBase *ParseBase;

protocol ParseBase(T) {
  String T.str(T);
  int    T.equal(T, T);
}

int main(void) {
  printf("ok\n");
  return 0;
}
