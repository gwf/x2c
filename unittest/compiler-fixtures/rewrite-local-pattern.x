#include "x2c.x"
#include "rewrite.x"

macro Expression $local_sum(Expr $left, Expr $value) =>
  $left + ({ int temporary = $value; temporary; });

$rewrite($local_sum)
meta Code recognize_local(Code code) => $!int{99};

int main(void) {
  int base = 1;
  int same = base + ({ int renamed = 4; renamed; });
  int different = base + ({ int renamed = 4; renamed + 1; });
  printf("local %d %d\n", same, different);
  return 0;
}
