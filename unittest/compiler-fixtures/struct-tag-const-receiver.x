#include "x2c.x"

typedef struct TagReceiverRec { int x; } TagReceiverRec;

void TagReceiverRec.bump(TagReceiverRec *rec, int by) {
  rec->x += by;
}

int main(void) {
  const struct TagReceiverRec rec = { 1 };
  rec.bump(4);
  return 0;
}
