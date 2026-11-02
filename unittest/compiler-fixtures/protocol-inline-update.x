#include "x2c.x"
#include "protocol-inline-update-cash.x"

/* Calls the public inline functions of `protocol-inline-update-cash`,
   whose bodies reach that unit's generated helpers. */
int main(void) {
  Cash cash = doubled(Cash.new(21));
  Cash total = sum3(Cash.new(1), Cash.new(2), Cash.new(3));
  printf("%ld %ld %d\n", cash.cents, total.cents, cash_discards());
  return 0;
}
