/* Dynamic values cross typed boundaries; native types still matter. is
   tests an exact tag. Conversion can succeed without that tag matching. */
int main(void) {
  auto {
    Var value = 42;
    double converted = value;
    printf("values: int tag %d, double tag %d, converted %.1f\n",
           value is int, value is double, converted);
    Var wide = 42L;
    printf("   numeric equality %d, identity %d\n", value == wide, value === wide);
  }
  return 0;
}
