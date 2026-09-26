/* Adopted structs keep C value-copy and address semantics in compile-time
   execution, where each lives in native bytes. */

#include "x2c.x"

struct MetaPoint { int x; int y; };

meta struct MetaPoint mr_make(int x, int y) {
  struct MetaPoint result = { .x = x, .y = y };
  return result;
}

meta int mr_sum(struct MetaPoint point) {
  point.x += 1;
  return point.x + point.y;
}

meta int mr_probe(int seed) {
  struct MetaPoint original = mr_make(seed, seed + 1);
  struct MetaPoint copy = original;
  copy.x = 20;
  int *field = &original.y;
  *field += 2;
  struct MetaPoint *address = &copy;
  address->y = 30;
  return original.x * 1000 + original.y * 100 + copy.x * 10 +
         copy.y + mr_sum(original);
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $(mr_probe 3), mr_probe(argc + 2));
  return 0;
}
