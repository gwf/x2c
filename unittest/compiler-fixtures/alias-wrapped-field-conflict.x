#include "x2c.x"

/* A wrapper adds no field scope to the containing aggregate. */
struct Sized {
  alias 5 as size;
  alias 1 {
    alias 2 {
      int size;
    }
  }
};

int main(void) { return 0; }
