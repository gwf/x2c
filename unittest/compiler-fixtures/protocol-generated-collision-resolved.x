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

int Choice.truth(Choice value) {
  return value.value == 7;
}

protocol FirstTruth(Choice);
protocol SecondTruth(Choice);

int main(void) {
  Choice value = Scope.malloc(sizeof(struct Choice));
  value.value = 7;
  printf("%d\n", value.truth());
  return 0;
}
