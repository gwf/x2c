/*  varops-fatal.x -- process-isolated terminal Var probes */

#include "x2c.x"

#include <string.h>

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  Var one = 1;
  Var value = void;
  struct Iter iter_storage;

  if (!strcmp(argv[1], "convert")) void.convert(<i32>);
  if (!strcmp(argv[1], "truth")) void.truthy();
  if (!strcmp(argv[1], "hash")) void.hash();
  if (!strcmp(argv[1], "compare")) void.compare(one);
  if (!strcmp(argv[1], "iter")) void.iter(&iter_storage);
  if (!strcmp(argv[1], "binary")) void.binary(<+>, one);
  if (!strcmp(argv[1], "update")) Var.update(&value, <+>, one);
  if (!strcmp(argv[1], "postfix")) Var.postfix(&value, <++>);
  return 2;
}
