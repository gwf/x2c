// Translated alone, so protocol-recorded-conformance-shapes.x has no
// interface and collection walks its source. The walk resolves Var(Disk)
// as that unit's own translation does, so this unit's Disk.truth does not
// change the conformance: the truth test stays a pointer test.
#include "x2c.x"
#include "protocol-recorded-conformance-shapes.x"

int Disk.truth(Disk value) {
  return value.radius > 5;
}

int disk_test(Disk disk) {
  return disk ? 1 : 0;
}
