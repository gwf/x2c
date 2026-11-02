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
  const int read_only = 6;
  Func read = %!() using &read_only => read_only;
  printf("%ld\n", read().integer());
  return 0;
}
