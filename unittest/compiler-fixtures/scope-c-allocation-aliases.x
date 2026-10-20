#include "x2c.x"

meta int allocation_aliases(void) {
  Scope.retain();
  char *copy = xmemdup("copy", 5);
  char *buffer = xmalloc(8);
  memcpy(buffer, copy, 5);
  buffer = xrealloc(buffer, 32);
  int *zeroes = xcalloc(3, sizeof(int));
  int result = strcmp(buffer, "copy") == 0 && zeroes[2] == 0;
  void *empty = xrealloc(NULL, 0);
  result += empty != NULL && xrealloc(empty, 0) == NULL;
  result += xmemdup(NULL, 4) == NULL && xmemdup(copy, 0) == NULL;
  xfree(copy);
  xfree(buffer);
  xfree(NULL);
  Scope.release();
  return result;
}

int main(void) {
  printf("%d %d\n", $allocation_aliases(), allocation_aliases());
  return 0;
}
