#include "rewrite-stacked-defs.x"

int main(void) {
  Stacked left = {4}, right = {2};
  printf("%d %d %d\n", left + right, left - right, left * right);
  return 0;
}
