#include "system-macros.x"

/* Dynamic values cross typed boundaries; native types still matter. is
   tests an exact tag. Conversion can succeed without that tag matching. */
int main(void) {
  Var value = 42;
  double converted = value;
  printf("Int tag: %d\nDouble tag: %d\nConverted to double: %.1f\n",
         value is int, value is double, converted);
  Var wide = 42L;
  puts($dedent(%"
    Numeric equality: $(value == wide)
    Identity: $(value === wide)"));
  return 0;
}
