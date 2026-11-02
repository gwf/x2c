#include "x2c.x"
#include <stdlib.h>
#include <string.h>

extern size_t strlen(const char *text);
extern int puts(const char *text);
typedef int (*Compare)(const void *, const void *);

macro Expression $boxed(Expr $value) => ({ Var result = $value; result; });

int main(void) {
  Func length = strlen;
  printf("%ld\n", length("abcd").integer());
  int values[2] = {2, 1};
  qsort(values, 2, sizeof(int), (Compare) (%!(const void *a, const void *b) =>
    *(const int *) a - *(const int *) b));
  printf("%d %d\n", values[0], values[1]);
  Var printed = (puts("typed"));
  printf("typed=%d\n", printed.integer() >= 0);
  Var known = 9;
  Var generic = _Generic(1, int: known, default: known);
  Var grouped_generic = (_Generic(1, int: known, default: known));
  Var native = $boxed(strlen("abcd")), boxed = $boxed(known);
  printf("%ld %ld %ld %ld\n", generic.integer(), grouped_generic.integer(),
         native.integer(), boxed.integer());
  Func null = NULL, grouped = ((NULL)), grouped_zero = ((0));
  Func cast = (Func) (NULL), grouped_cast = ((Func) (NULL));
  Func conditional = 1 ? NULL : NULL;
  Func grouped_conditional = ((1 ? NULL : NULL));
  printf("%d %d %d %d %d %d %d\n", null == NULL, grouped == NULL,
         grouped_zero == NULL, cast == NULL, grouped_cast == NULL,
         conditional == NULL, grouped_conditional == NULL);
  return 0;
}
