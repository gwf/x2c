#include "x2c.x"

typedef struct PointerReceiverRec { int x; } PointerReceiverRec;
typedef struct PointerReceiverBox { PointerReceiverRec inner; }
  PointerReceiverBox;

void PointerReceiverRec.bump(PointerReceiverRec *rec, int by) {
  rec->x += by;
}

int PointerReceiverRec.get(PointerReceiverRec *rec) {
  return rec->x;
}

int main(void) {
  PointerReceiverRec rec = { 1 };
  PointerReceiverRec *pointer = &rec;
  PointerReceiverRec row[2] = { { 10 }, { 20 } };
  PointerReceiverBox box = { { 100 } };

  rec.bump(2);
  (&rec).bump(4);
  pointer.bump(8);
  row[1].bump(1);
  box.inner.bump(1);

  printf("%d %d %d %d\n",
    rec.get(), row[1].get(), box.inner.get(), pointer.get());
  return 0;
}
