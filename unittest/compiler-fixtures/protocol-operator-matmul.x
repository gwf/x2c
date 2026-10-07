#include "x2c.x"

typedef struct Mat {
  int value;
} *Mat;

Var Mat.var(Mat value) => Var.new(<mat>, value);

Mat Var.mat(Var value) => (Mat) value.pointer();

Mat Mat.new(int value) {
  Mat result = Scope.malloc(sizeof(struct Mat));
  result.value = value;
  return result;
}

Mat Mat.matmul(Mat lhs, Mat rhs) {
  if (rhs.value < 0) raise %(bad-arg);
  return Mat.new(lhs.value * 10 + rhs.value);
}

static int order;
static Mat *destination(Mat *slot) { order = order * 10 + 1; return slot; }
static Mat operand(Mat value) { order = order * 10 + 2; return value; }

protocol Var(Mat);

int main(void) {
  Mat a = Mat.new(2), b = Mat.new(3), c = Mat.new(4);
  Mat product = a.matmul(b);
  Mat chain = a.matmul(b).matmul(c);
  Var va = a, vb = b;
  Var boxed = va.matmul(vb);
  a = a.matmul(b);
  va = va.matmul(vb);
  Mat updated = Mat.new(2);
  Mat *slot = destination(&updated);
  Mat current = *slot, rhs = operand(b);
  *slot = current.matmul(rhs);
  if (order != 12 || updated.value != 23) return 1;
  int failed = 0;
  try { *slot = updated.matmul(Mat.new(-1)); }
  catch %(bad-arg *): failed = 1;
  if (!failed || updated.value != 23) return 2;
  int shape = 0;
  match (%(op @ x y)) {
    case %(op @ ?left ?right): shape = 1;
  }
  printf("%d %d %d %d %d %d\n", product.value, chain.value,
         boxed.mat().value, a.value, va.mat().value, shape);
  return 0;
}
