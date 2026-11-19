/* Var carries a runtime tag. Typed destinations request conversions;
   ordinary int arithmetic remains native C arithmetic. */
int main(void) {
  Var value = 42;
  value += 1;
  int count = value;
  double half = count / 2.0;
  printf("Var value: %s\nNative int: %d\nHalf: %.1f\n", value, count, half);
  value = "ready";
  printf("New Var value: %s\nString tag: %d\n", value, value is String);
  return 0;
}
