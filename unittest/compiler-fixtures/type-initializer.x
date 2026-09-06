#include "x2c.x"

typedef struct InitializerFixture *InitializerFixture;

static int calls = 0;
static int ready = 0;
static String label = NULL;

static int setup(void) {
  return 42;
}

void InitializerFixture.initialize(void) {
  calls++;
  ready = setup();
  label = %"ready";
}

int main(void) {
  InitializerFixture.initialize();
  printf("%d %d %s\n", calls, ready, label);
  return calls == 1 && ready == 42 && label == %"ready" ? 0 : 1;
}
