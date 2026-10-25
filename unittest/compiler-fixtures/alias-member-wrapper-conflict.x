#include "x2c.x"

/* A braced alias in a struct body is one scope with the members it wraps,
   so another alias of its name among them conflicts. */
typedef struct Sized {
  alias 5 as size {
    alias 6 as size;
    int cells[size];
  }
} Sized;

int main(void) { return 0; }
