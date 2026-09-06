#include "x2c.x"

typedef struct Vec {
  int x;
} *Vec;

Var tag_scope_box(Vec value) {
  return value;
}
