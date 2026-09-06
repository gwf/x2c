#include "x2c.x"

typedef int LocalTestCount;
Var LocalTestCount.var(LocalTestCount value) => value + 100;

int main(void) {
  typedef LocalTestCount Alias;
  Alias original = 3;
  {
    typedef double LocalTestCount;
    LocalTestCount fraction = 2.5;
    Alias same = 4;
    Var boxed = original;
    if (fraction != 2.5 || same != 4 || boxed != 103) return 1;
    if (sizeof(same) != sizeof(int)) return 2;
  }
  typedef LocalTestCount LocalTestCount;
  LocalTestCount count = 5;
  Var boxed = count;
  if (boxed != 105) return 3;
  {
    typedef double Alias;
    Alias fraction = 1.5;
    if (fraction != 1.5) return 4;
  }
  Alias restored = 6;
  boxed = restored;
  if (boxed != 106) return 5;
  puts("local aliases preserve file types and lexical scope");
  return 0;
}
