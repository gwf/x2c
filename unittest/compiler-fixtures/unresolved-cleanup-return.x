#include "x2c.x"
#include <stdio.h>

FILE *open_with_cleanup(void) {
  try {
    return fopen("/tmp/x2c-unresolved-cleanup-return.tmp", "w");
  }
  finally {
  }
}

int main(void) {
  FILE *file = open_with_cleanup();
  if (!file) return 1;
  fclose(file);
  return 0;
}
