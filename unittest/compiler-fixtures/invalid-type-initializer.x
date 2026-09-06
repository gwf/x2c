#include "x2c.x"

typedef struct BadInitializer *BadInitializer;

int BadInitializer.initialize(void) {
  return 1;
}
