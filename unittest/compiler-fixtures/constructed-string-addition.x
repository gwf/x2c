#include "x2c.x"

macro Expression $built() => $(x2c.literal.string "a");
macro Expression $joined(Expr $value) => %"${$value}" + "|";

int main(void) {
  if ($built() + "|" != %"a|" || "|" + $built() != %"|a") return 1;
  if ($built() + $built() != %"aa" || %"a" + %"b" != %"ab") return 2;
  String name = %"x";
  if ($built() + %"$name" != %"ax" || %"$name" + $built() != %"xa")
    return 3;
  if ($joined("one") != %"one|" || $joined("two") != %"two|") return 4;
  printf("constructed String addition ok\n");
  return 0;
}
