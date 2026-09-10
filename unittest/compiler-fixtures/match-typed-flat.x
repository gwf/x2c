#include "x2c.x"

// A literal head followed by typed and untyped captures emits direct checks.
static int classify(List form) {
  match (form) {
    case %(call ?(String callee) ?args): return 1;
    case %(call ?callee ?args): return 2;
    case %(pair (!is ?left type symbol) ?(int right)): return 3;
  }
  return 0;
}

int main(void) {
  printf("%d %d %d %d %d\n",
    classify(%(call "f" (1))), classify(%(call f (1))),
    classify(%(pair x 2)), classify(%(pair "x" 2)), classify(%(call "f")));
  return 0;
}
