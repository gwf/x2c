#include "x2c.x"

meta int keys(int prefix, Map @options) => prefix + options.len();
meta int dynamic(void) {
  Func f = keys;
  Map extra = {c: 3};
  return f(10, d: 4, @extra, c: 5).int();
}

int main(void) {
  printf("meta %d %d %d %d\n", $keys(1), $keys(1, x: 1, y: 2),
    $keys(1, "s": 1, "s": 2), $dynamic());
  return 0;
}
