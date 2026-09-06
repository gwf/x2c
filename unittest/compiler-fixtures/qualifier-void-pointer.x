#include "x2c.x"

/* A pointer to void hands the same address on, so it must promise every
   qualifier the source declares. It was the one conversion that silently
   laundered const, because its base type differs from the source's and the
   same-canonical-type test could not see it. */
int main(void) {
  const char *readonly = "text";
  void *laundered = readonly;
  printf("%p\n", laundered);
  return 0;
}
