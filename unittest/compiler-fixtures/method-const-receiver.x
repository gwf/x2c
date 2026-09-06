#include "x2c.x"

typedef struct ConstReceiverRec { int x; } ConstReceiverRec;

void ConstReceiverRec.bump(ConstReceiverRec *rec, int by) {
  rec->x += by;
}

int main(void) {
  const ConstReceiverRec rec = { 1 };
  rec.bump(4);
  return 0;
}
