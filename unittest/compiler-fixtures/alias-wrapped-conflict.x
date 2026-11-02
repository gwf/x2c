#include "x2c.x"

/* A braced alias at file scope wraps declarations that keep their file
   scope, so a wrapped declaration of a file-scope alias's name conflicts
   with that alias. */
alias 5 as size;
alias 1 as unit {
  int size = 3;
}

int main(void) { return size; }
