#include "x2c.x"

typedef struct Before { int value; } Before;
typedef struct Opaque *Opaque;

int before_size(Before value) => value.value;

/* A typedef after a function definition is source-private unless a public
   prototype names it; the header must then be able to spell it. */
typedef struct After { int value; } After;
typedef struct Hidden { int value; } Hidden;
typedef struct Item { int value; } Item, *ItemPtr;
typedef struct Opaque { int value; } *Opaque;

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
