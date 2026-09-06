#include "x2c.x"

static int cleanup = 0;

static void record_cleanup(void) {
  cleanup++;
}

static void raise_from_callee(void) {
  raise %(invariant (value 17));
}

static int preserve_parameter(int value) {
  try {
    value = 23;
    raise %(invariant);
  }
  catch %(invariant): {}
  return value;
}

int main(void) {
  int caught = 0, inner_handled = 0;
  try {
    try {
      {
        defer record_cleanup();
        // The defer frame must intercept transfer originating below it.
        raise_from_callee();
      }
    }
    catch %(invariant (value ?value)): {
      caught = value.int();
      inner_handled = 1;
      raise %(bad-state);
    }
  }
  catch %(bad-state): {}
  int parameter = preserve_parameter(0);
  printf("%d %d %d %d\n", caught, cleanup, inner_handled, parameter);
  return caught == 17 && cleanup == 1 && inner_handled && parameter == 23
       ? 0 : 1;
}
