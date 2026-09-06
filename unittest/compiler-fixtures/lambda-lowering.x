#include "x2c.x"

int main(void) {
  List values = %(1 2 3);
  List doubled = values.map(%!(value) => value.int() * 2);
  List nested = %((4) (5));
  List heads = nested.map(%!(value) => value.list()[0]);
  printf("%d %d %d\n", doubled.getindex(0).int(),
         doubled.getindex(1).int(), doubled.getindex(2).int());
  printf("%d %d\n", heads.getindex(0).int(), heads.getindex(1).int());
  return 0;
}
