#include "x2c.x"

struct CallValue { int value; int *borrowed; };

meta struct CallValue change_copy(struct CallValue argument) {
  argument.value += 7;
  *argument.borrowed += 3;
  return argument;
}

meta struct CallValue forward_copy(struct CallValue argument) {
  return change_copy(argument);
}

meta int call_value_probe(int offset) {
  int shared = 10 + offset;
  struct CallValue original = { .value = 2, .borrowed = &shared };
  struct CallValue result = forward_copy(original);
  int *stable_field = &result.value;
  result = change_copy(original);
  return original.value * 1000 + *stable_field * 100 + shared;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $call_value_probe(0),
         call_value_probe(argc - 1));
  return 0;
}
