#include "x2c.x"

typedef struct Rec {
  int n;
} Rec;

int main(void) {
  Rec rec = { 1 };
  List items = List.append(&rec, NULL);
  (void) items;
  return 0;
}
