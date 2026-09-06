#include "x2c.x"

typedef struct TruthView {
  int value;
} *TruthView;

typedef struct Reading {
  TruthView view;
} *Reading;

static int truth_calls;
static int equal_calls;

protocol TruthView(T) {
  int T.truth(T);
  int T.equal(T, T);
}

TruthView Reading.truthview(Reading reading) {
  return reading.view;
}

int TruthView.truth(TruthView view) {
  truth_calls++;
  return view.value != 0;
}

int TruthView.equal(TruthView left, TruthView right) {
  equal_calls++;
  return left.value == right.value;
}

protocol TruthView(Reading);

static Reading reading(int value) {
  Reading result = Scope.malloc(sizeof(struct Reading));
  result.view = Scope.malloc(sizeof(struct TruthView));
  result.view.value = value;
  return result;
}

int main(void) {
  Reading zero = reading(0), also_zero = reading(0), one = reading(1);
  int dot = zero.truth(), branch = 0;
  if (zero) branch++;
  int equal = zero == also_zero;
  int short_false = zero && one;
  int short_true = one && zero;
  int not_zero = !zero;
  printf(
    "%d %d %d %d %d %d %d %d\n",
    dot, branch, equal, short_false, short_true, not_zero,
    truth_calls, equal_calls
  );
  return 0;
}
