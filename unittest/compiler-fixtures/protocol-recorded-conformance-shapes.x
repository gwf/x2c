// The declaring unit resolves Var(Disk) with no Disk.truth in sight, so the
// conformance and the descriptor it registers use Var's inherited truth.
// protocol-recorded-conformance.x includes this unit and defines its own
// Disk.truth; it reuses this unit's conformance instead of resolving the
// adoption again.
#include "x2c.x"

typedef struct Disk {
  int radius;
} *Disk;

Var Disk.var(Disk value) {
  return Var.new(<disk>, value);
}

Disk Var.disk(Var value) {
  return (Disk) value.pointer();
}

protocol Var(Disk);
