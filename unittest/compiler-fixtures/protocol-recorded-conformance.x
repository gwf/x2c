// Translated after protocol-recorded-conformance-shapes.x, which declares
// Var(Disk). This unit's own Disk.truth does not change that conformance:
// the truth test and the boxed call both use Var's inherited truth.
#include "x2c.x"
#include "protocol-recorded-conformance-shapes.x"

int Disk.truth(Disk value) {
  return value.radius > 5;
}

int main(void) {
  Disk disk = xmalloc(sizeof(struct Disk));
  disk.radius = 3;
  Var boxed = disk;
  printf("test %d\n", disk ? 1 : 0);
  printf("boxed %d\n", boxed.truth());
  return 0;
}
