#include "x2c.x"
#include <stdlib.h>

static void borrow(int **out, int *value) { *out = value; }
static void borrow_again(int **out, int *value) { borrow(out, value); }
static void retain(Array out, void *value) { out.push(value); }
static void retain_again(Array out, void *value) { retain(out, value); }
static void retain_unknown(void *value) {
  Array out = malloc(sizeof(struct Array));
  retain_again(out, value);
}

// Raw stores alone do not establish retention beyond the call.
static void raw_stores(int **out) {
  int value = 1;
  *out = &value;
  borrow_again(out, &value);
  int **unknown = out + 1;
  *unknown = &value;
  borrow_again(unknown, &value);
}

// Known retention survives multiple helper summaries and an unknown target.
static void known_stores(Array out, Map map) {
  int value = 1;
  struct Array item = {0};
  out.push(&value);
  map.set("value", &value);
  retain_again(out, &value);
  retain_unknown(&value);
  out[0] = (Array) &item;
  map["item"] = (Array) &item;
}

// The raw-store boundary does not hide an already ended allocation region.
static void ended_store(int **out) {
  int *value = NULL;
  Scope.open();
  value = xmalloc(sizeof(int));
  Scope.close();
  borrow_again(out, value);
}

int main(void) { return 0; }
