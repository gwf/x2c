#include "x2c.x"
#include <stdlib.h>

typedef struct Item { int value; } Item;
typedef struct Holder { Item *items; Item inline_items[2]; } Holder;

static Item *kept;
static void keep(Item *item) { kept = item; }
static Item *element(Holder *holder) => &holder.items[0];
static Item *inline_element(Holder *holder) => &holder.inline_items[0];

// A pointer field's pointee is separate from the local containing the field.
static void allocated_pointer_field(void) {
  Holder holder = {0};
  holder.items = calloc(2, sizeof(Item));
  keep(element(&holder));
  keep(&holder.items[1]);
  kept = NULL;
  free(holder.items);
}

// An inline array still belongs to its containing frame.
static Item *returned_inline_element(void) {
  Holder holder = {0};
  return inline_element(&holder);
}

static void stored_inline_element(void) {
  Holder holder = {0};
  keep(&holder.inline_items[1]);
}

// Taking the pointer field's own address still borrows the local record.
static Item **returned_field_address(void) {
  Holder holder = {0};
  return &holder.items;
}

int main(void) { return 0; }
