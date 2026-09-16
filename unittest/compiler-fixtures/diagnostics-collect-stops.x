#include "x2c.x"

/* Symbol collection has no per-declaration recovery, so its first error ends
   the translation before later declarations are parsed. */
typedef struct Broken {
  int value +;
} *Broken;

int parse_error(void) {
  int sum = 42 +;
  return sum;
}

int type_error(int value) {
  return value is int;
}
