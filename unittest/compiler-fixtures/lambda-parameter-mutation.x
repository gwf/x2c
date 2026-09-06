#include "x2c.x"

int main(void) {
  int zero = 0;
  Func assign = %!(int value) => {
    value = 42;
    return value + zero;
  };
  Func compound = %!(int value) => {
    value += 3;
    return value + zero;
  };
  Func prefix = %!(int value) => {
    int result = ++value;
    return result * 100 + value + zero;
  };
  Func postfix = %!(int value) => {
    int result = value++;
    return result * 100 + value + zero;
  };
  Func address = %!(int value) => {
    int *alias = &value;
    *alias += 5;
    return value + zero;
  };
  Func factory = %!(int value) => {
    return %!() using &value => {
      int previous = value++;
      return previous * 100 + value + zero;
    };
  };
  Func nested = factory(4);
  long assigned = assign(0).integer();
  long compounded = compound(4).integer();
  long prefixed = prefix(3).integer();
  long postfixed = postfix(3).integer();
  long addressed = address(7).integer();
  long first_nested = nested().integer();
  long second_nested = nested().integer();

  printf("%ld %ld %ld %ld %ld %ld %ld\n",
         assigned, compounded, prefixed, postfixed,
         addressed, first_nested, second_nested);
  return 0;
}
