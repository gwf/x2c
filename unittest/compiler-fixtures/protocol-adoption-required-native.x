#include "x2c.x"

typedef void *Handle;

protocol void *(T) {
  void T.dispose(T) = free;
}

int main(void) {
  Handle handle = NULL;
  handle.dispose();
  return 0;
}
