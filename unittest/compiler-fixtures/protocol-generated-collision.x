#include "x2c.x"

typedef struct FirstTruth {
  int value;
} *FirstTruth;

typedef struct SecondTruth {
  int value;
} *SecondTruth;

typedef struct Choice {
  int value;
} *Choice;

protocol FirstTruth(T) {
  int T.truth(T);
}

protocol SecondTruth(T) {
  int T.truth(T);
}

FirstTruth Choice.firsttruth(Choice value) {
  return (FirstTruth) value;
}

SecondTruth Choice.secondtruth(Choice value) {
  return (SecondTruth) value;
}

int FirstTruth.truth(FirstTruth value) {
  return value.value != 0;
}

int SecondTruth.truth(SecondTruth value) {
  return value.value > 0;
}

protocol FirstTruth(Choice);
protocol SecondTruth(Choice);

int main(void) {
  return 0;
}
