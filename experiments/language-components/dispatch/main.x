#include "x2c.x"
#include "components.x"

int main(void) {
  Distance a = {9}, b = {2};
  Distance sum = a + b;
  int x = 9, y = 2;
  printf("distance %d ordinary %d %d %d\n", sum.value, x + y, x * y, x - y);
  printf("candidates %d\n", $candidate_count());
  Choice choice = {7};
  switch (choice) { case 7: puts("selected"); break; }
  switch (2) { case 2: puts("ordinary"); break; }
  return 0;
}
