#include "x2c.x"

/* The existing Var->Iter protocol keeps the caller's destination; this is
   deliberately not a parallel iterator construction path. */
meta int protocol_adoption_probe(int offset) {
  List input = %(1 2 3);
  struct Iter storage;
  Iter values = Var.iter(input, &storage);
  Var first, second, third, extra;
  if (!values.try_next(&first) || !values.try_next(&second) ||
      !values.try_next(&third) || values.try_next(&extra)) return -1;
  return first.int() + second.int() + third.int() + offset;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $protocol_adoption_probe(0),
         protocol_adoption_probe(argc - 1));
  return 0;
}
