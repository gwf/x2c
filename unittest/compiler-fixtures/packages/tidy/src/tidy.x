#include "x2c.x"
#include "cleanup.x"
typedef struct Handle { int value; } *Handle;
void Handle.free(Handle h) { (void) h; }
$cleanup.by(Handle, free);
int exercise(void) {
  struct Handle storage = {0};
  Handle h = auto &storage;
  return h.value;
}
