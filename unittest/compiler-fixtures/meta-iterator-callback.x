#include "x2c.x"

meta Var twice_value(Var value) => value * 2;

meta Iter make_values(int offset) {
  return range(1 + offset, 3 + offset, 1, Iter.new()).map(
    twice_value, Iter.new());
}

meta int iterator_callback_probe(int offset) {
  Iter values = make_values(offset);
  List result = values.list();
  return result.car().integer() + result.cadr().integer() +
         result.caddr().integer();
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $iterator_callback_probe(0),
         iterator_callback_probe(argc - 1));
  return 0;
}
