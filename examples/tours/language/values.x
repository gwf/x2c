/* Var carries a runtime tag. Typed destinations request conversions;
   ordinary int arithmetic remains native C arithmetic. */
int main(void) {
  auto {
    Var value = 42;
    value += 1;
    int count = value;
    double half = count / 2.0;
    printf("values: %s, native %d, half %.1f\n", value, count, half);
    value = "ready";
    printf("   now %s, String tag %d\n", value, value is String);
  }
  return 0;
}
