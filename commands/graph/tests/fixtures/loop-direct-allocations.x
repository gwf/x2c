#include "x2c.x"

static void *allocate(void) => xmalloc(8);

void direct_allocations(char *bytes, size_t size) {
  for (int i = 0; i < 2; i++) {
    void *scope = xmalloc(8);
    String pool = String.new_len(bytes, size);
    void *helper = allocate();
    (void) scope;
    (void) pool;
    (void) helper;
  }
}
