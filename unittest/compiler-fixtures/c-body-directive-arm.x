#include "x2c.x"

// A governed statement ends its conditional arm's share of the statement; a
// later statement in the same arm follows it, as in C.
int main(void) {
  int flag = 0, a = 0, b = 0;
  if (flag)
#if 1
    a += 1;
  defer printf("deferred a=%d\n", a);
#endif
  printf("if a=%d\n", a);
  for (int i = 0; i < 3; i++)
#if 1
    a += 1;
  b += 1;
#endif
  printf("for a=%d b=%d\n", a, b);
  foreach (Var item, [1, 2, 3])
#if 1
    a += item.int();
  b += 1;
#endif
  printf("foreach a=%d b=%d\n", a, b);
  if (flag)
#if 1
    a = 1;
  else
    a = 2;
#endif
  int n = 0;
  do
#if 1
    n++;
  while (n < 3);
#endif
  printf("else a=%d do n=%d\n", a, n);
  return 0;
}
