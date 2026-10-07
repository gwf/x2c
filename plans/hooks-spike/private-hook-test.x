#include "private-hook.x"

/* Not hooked: a static hook stays in its declaring file. */
int outside(int n) {
  switch (n) { case 1: return 1; }
  return 0;
}

int main(void) {
  return inside(1) + outside(1) == 2 ? 0 : 1;
}
