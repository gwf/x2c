#include "x2c.x"

typedef struct Before { int value; } Before;
typedef struct Opaque *Opaque;

int before_size(Before value) => value.value;

/* A static typedef stays private unless a public declaration needs it.
   A public opaque pointer declaration can retain a private layout. */
static typedef struct After { int value; } After;
static typedef struct Hidden { int value; } Hidden;
static typedef struct Item { int value; } Item, *ItemPtr;
static typedef struct Opaque { int value; } *Opaque;

int after_size(After value) => value.value;

ItemPtr item_identity(ItemPtr value) => value;

int opaque_size(Opaque value) => value.value;

static int hidden_size(Hidden value) => value.value;

int main(void) {
  After after = { 2 };
  Hidden hidden = { 3 };
  Item item = { 4 };
  struct Opaque opaque = { 5 };
  return after_size(after) + hidden_size(hidden) == 5 &&
         item_identity(&item).value == 4 && opaque_size(&opaque) == 5 ? 0 : 1;
}
