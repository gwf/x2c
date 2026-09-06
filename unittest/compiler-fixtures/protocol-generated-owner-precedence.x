#include "x2c.x"

typedef struct SemanticTruth {
  int value;
} *SemanticTruth;

typedef struct Packet {
  SemanticTruth view;
} *Packet;

static int truth_calls;

protocol SemanticTruth(T) {
  int T.truth(T);
}

SemanticTruth Packet.semantictruth(Packet packet) {
  return packet.view;
}

int SemanticTruth.truth(SemanticTruth view) {
  truth_calls++;
  return view.value != 0;
}

Var Packet.var(Packet packet) {
  return Var.new(<packet>, packet);
}

Packet Var.packet(Var value) {
  return (Packet) value.pointer();
}

protocol Var(Packet);
protocol SemanticTruth(Packet);

static Packet packet(int value) {
  Packet result = Scope.malloc(sizeof(struct Packet));
  result.view = Scope.malloc(sizeof(struct SemanticTruth));
  result.view.value = value;
  return result;
}

int main(void) {
  Packet zero = packet(0), one = packet(1);
  Var boxed_zero = zero, boxed_one = one;
  int branch = 0;
  if (zero) branch++;
  if (one) branch += 2;
  int zero_dot = zero.truth();
  int one_dot = one.truth();
  int zero_boxed = boxed_zero.truth();
  int one_boxed = boxed_one.truth();
  int zero_not = !zero;
  printf(
    "%d %d %d %d %d %d %d\n",
    zero_dot, one_dot, branch, zero_boxed, one_boxed, zero_not,
    truth_calls
  );
  return 0;
}
