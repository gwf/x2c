#include "x2c.x"

/* A finalizer that raises with no matching handler terminates through the
   error floor rather than looping on its own landing. */
int main(void) {
  try {
    printf("body\n");
  }
  finally {
    raise %(fin-raise);
  }
  return 0;
}
