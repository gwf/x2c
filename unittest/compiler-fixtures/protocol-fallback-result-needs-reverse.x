#include "x2c.x"

typedef struct View {
  int value;
} *View;

typedef struct Item {
  View view;
} *Item;

protocol View(T) {
  T T.clone(T);
}

View Item.view(Item item) {
  return item.view;
}

View View.clone(View view) {
  return view;
}

protocol View(Item);

int main(void) {
  return 0;
}
