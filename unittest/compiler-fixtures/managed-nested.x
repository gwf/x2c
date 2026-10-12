/* A managed initializer cannot manage another managed initializer. */

#include "x2c.x"

#include <stdlib.h>

typedef struct Handle { int id; } *Handle;
void Handle.cleanup(Handle h) { free(h); }
protocol Cleanup(Handle);

static Handle acquire(void) => calloc(1, sizeof(struct Handle));

int main(void) {
  Handle h = $auto($auto(acquire()));
  return h.id;
}
