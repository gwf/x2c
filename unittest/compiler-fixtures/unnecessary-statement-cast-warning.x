#include "x2c.x"

// A cast that begins a statement is typed and checked like any other cast.
int main(void) {
  int n = 3;
  char *p = NULL;
  (int)n;
  (char *)p;
  (void)n;
  (long)n;
  return 0;
}
