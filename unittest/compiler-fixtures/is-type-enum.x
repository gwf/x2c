#include "x2c.x"

enum Choice { CHOICE_A };

int invalid_enum(Var value) {
  return value is enum Choice;
}
