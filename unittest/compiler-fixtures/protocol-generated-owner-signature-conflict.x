#include "x2c.x"

typedef struct TruthBase {
  int value;
} *TruthBase;

typedef struct Item {
  TruthBase base;
} *Item;

protocol TruthBase(T) {
  int T.truth(T, int threshold);
}

TruthBase Item.truthbase(Item item) {
  return item.base;
}

int TruthBase.truth(TruthBase base, int threshold) {
  return base.value > threshold;
}

Var Item.var(Item item) {
  return Var.new(<item>, item);
}

Item Var.item(Var value) {
  return (Item) value.pointer();
}

protocol TruthBase(Item);
protocol Var(Item);

int main(void) {
  return 0;
}
