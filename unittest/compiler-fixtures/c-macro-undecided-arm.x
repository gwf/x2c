#include "x2c.x"

// x2c cannot decide `__APPLE__`, so both arms parse. A macro an arm
// defines expands in the rest of that arm; after the group it is
// conditionally defined, so its uses stay for the C compiler.
#ifdef __APPLE__
#define HOST_WORD 1
int arm_word(void) { return HOST_WORD; }
#else
#define HOST_WORD 1
int arm_word(void) { return HOST_WORD; }
#endif

int main(void) {
  printf("%d %d\n", arm_word(), HOST_WORD);
  return 0;
}
