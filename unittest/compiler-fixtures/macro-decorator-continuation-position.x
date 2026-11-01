macro Decorator $unit(Expr $ignored) =>
  macro Decorator(Unit $declaration) { $declaration };

int main(void) {
  $unit() 0
  int value = 1;
  return value;
}
