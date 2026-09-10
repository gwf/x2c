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

Mat Mat.matmul(Mat lhs, Mat rhs) => Mat.new(lhs.value * 10 + rhs.value);

protocol Var(Mat);

int main(void) {
  Mat a = Mat.new(2), b = Mat.new(3), c = Mat.new(4);
  Mat product = a @ b;
  Mat chain = a @ b @ c;
  Var va = a, vb = b;
  Var boxed = va @ vb;
  a @= b;
  va @= vb;
  int shape = 0;
  match (%(op @ x y)) {
    case %(op @ ?left ?right): shape = 1;
  }
  printf("%d %d %d %d %d %d\n", product.value, chain.value,
         boxed.mat().value, a.value, va.mat().value, shape);
  return 0;
}
