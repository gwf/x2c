#include "x2c.x"

typedef struct RvalueReceiverRec { int x; } RvalueReceiverRec;

int RvalueReceiverRec.get(RvalueReceiverRec *rec) {
  return rec->x;
}

RvalueReceiverRec make_rec(void) {
  return (RvalueReceiverRec) { 7 };
}

int main(void) {
  return make_rec().get();
}
