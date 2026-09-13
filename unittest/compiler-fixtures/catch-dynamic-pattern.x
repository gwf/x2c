#include "x2c.x"
static int selected(Symbol code) {
  int result = 0;
  try { Error.raise(<invariant>, %((value $code))); }
  catch %(invariant (value $code)): result = 1;
  catch: result = 2;
  return result;
}
int main(void) {
  int first = selected(<first>), second = selected(<second>);
  printf("%d %d\n", first, second);
  return 0;
}
