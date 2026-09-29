#include "x2c.x"

meta static List atom_data(List value) { return value; }

int main(void) {
  List expected = %(?type ?callee_type ?foo_bar ?calleeType
                    (?type_name ?abcdefgh));
  List actual = $atom_data(%(?type ?callee_type ?foo_bar ?calleeType
                            (?type_name ?abcdefgh)));
  assert(actual === expected);
  assert(actual.car() is <symbol>);
  assert(actual.cadr() is <lsym>);
  printf("meta atom data passed\n");
  return 0;
}
