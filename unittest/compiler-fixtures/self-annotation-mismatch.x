#include "x2c.x"

typedef List Marked;

Self Marked.next(Self value);

Marked Marked.next(Marked value) {
  return value.cdr();
}

int main(void) { return 0; }
