#include "x2c.x"

macro Expression $counter() => ({
  int count = 0;
  Func f = %!() using &count => ++count;
  f;
});

int main(void) {
  int result = ({ int t = 0; Func f = %!() using &t => ++t; f(); t; });
  int nested = ({
    int t = 4;
    { Func f = %!() using &t => ++t; f(); }
    t;
  });
  Func counter = $counter();
  long first = counter().integer(), second = counter().integer();
  printf("%d %d %ld %ld\n", result, nested, first, second);
  char text[4] = "ab";
  Func snapshot = %!() => text;
  text[0] = 'z';
  printf("%s\n", snapshot().repr());
  const char fixed[4] = "cd";
  Func read_fixed = %!() => fixed;
  printf("%s\n", read_fixed().repr());
  const int read_only = 6;
  Func read = %!() using &read_only => read_only;
  printf("%ld\n", read().integer());
  int n = 1;
  int *const pointer = &n;
  const Array values = [1];
  Func assign = %!() using &pointer => *pointer = 2;
  Func mutate = %!() using &values => values[0] = 2;
  assign();
  mutate();
  printf("%d %ld\n", n, values[0].integer());
  return 0;
}
