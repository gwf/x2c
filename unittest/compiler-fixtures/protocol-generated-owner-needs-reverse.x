#include "x2c.x"

typedef struct SemanticTruth {
  int value;
} *SemanticTruth;

typedef struct Packet {
  SemanticTruth view;
} *Packet;

protocol SemanticTruth(T) {
  int T.truth(T);
}

SemanticTruth Packet.semantictruth(Packet packet) {
  return packet.view;
}

int SemanticTruth.truth(SemanticTruth view) {
  return view.value != 0;
}

Var Packet.var(Packet packet) {
  return Var.new(<packet>, packet);
}

protocol SemanticTruth(Packet);
protocol Var(Packet);

int main(void) {
  return 0;
}
