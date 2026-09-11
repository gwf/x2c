#pragma private

static int answer(void) { return NATIVE_LATE; }

#define NATIVE_LATE 42
#include <stdio.h>

int main(void) {
  printf("%d\n", answer());
  return 0;
}
