#include "x2c.x"

typedef struct UnregisteredType { int value; } UnregisteredType;

int invalid_aggregate(Var value) {
  return value is UnregisteredType;
}
