#include "x2c.x"
#include "meta.x"

/* A producer whose carrier code keeps a binder no effect replaced is
   rejected at the application instead of reaching the emitter. */
meta static List stray(void) {
  Atom token = Atom.intern("?__stray");
  return %(code-value "source"
    (stmnt (expr (int) (ident $token))) ());
}
macro Statement $stray_slot() { $stray()... }

meta static List apply_stray(void) {
  Macro slot = $stray_slot;
  return slot();
}
macro Statement $use_stray() { $apply_stray()... }

int main(void) {
  $use_stray();
  return 0;
}
