// Same-spelled template declarations follow lexical scope and each expansion
// receives private value, typedef, enumerator, and tag identities.
#include "x2c.x"

struct Public { int value; };

macro Unit $lexical(name $read, Type $number) {
  struct Node { int value; };
  enum Choice { Option = 1 };
  typedef int Scalar;

  int $read(void) {
    struct Node outside = {3};
    struct Public retained = {2};
    int Node = 1;
    int value = 4;
    int total = 0;
    {
      struct Node { String value; };
      struct Node inside = {"hello"};
      String value = "hello";
      total = inside.value.len() + value.len();
    }
    {
      typedef $number Scalar;
      Scalar value = (Scalar) 5;
      enum Choice { Option = 2 };
      total += (int) value + Option;
    }
    return total + outside.value + retained.value + Node + value + Option;
  }
}

$lexical(first, int);
$lexical(second, long);

int main(void) {
  int a = first(), b = second();
  printf("%d %d\n", a, b);
  return a == 28 && b == 28 ? 0 : 1;
}
