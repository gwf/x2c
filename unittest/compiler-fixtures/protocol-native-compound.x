#include "x2c.x"

typedef void *Handle;

static void clear_slot(void **slot) { *slot = NULL; }

protocol void *(T) {
  void T.clear(T *) = clear_slot;
}

protocol void *(Handle);

int main(void) {
  Handle h = &h;
  Handle_clear(&h);
  printf("%d\n", h == NULL);
  return 0;
}
