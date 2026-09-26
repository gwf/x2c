#include "x2c.x"

meta Var twice_value(Var value) => value * 2;

meta int local_storage_probe(int offset) {
  struct Iter source_storage, map_storage;
  Iter values = range(1 + offset, 3 + offset, 1, &source_storage).map(
    twice_value, &map_storage);
  List result = values.list();
  return result.car().integer() + result.cadr().integer() +
         result.caddr().integer();
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $local_storage_probe(0),
         local_storage_probe(argc - 1));
  return 0;
}
