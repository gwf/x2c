#include "x2c.x"

macro Expression $nested_text(Expr $value) => %"${%"${$value}"}";
macro Expression $grouped(Expr $value) =>
  %(${%{value: $value}} @{%(tail)});

static String punctuation = %"}";

static int local_value(void) {
  int meta = 3;
  Map values = %{value: $meta};
  List items = %(${values[<value>]} @{%(tail)});
  return items[0].integer();
}

#include "defs.x"

meta static int seven(void) => 7;
macro Expression $seven_value() => $seven();

int main(void) {
  List items = %(${%{value: 5}} @{%(tail)});
  if (items[0].map()[<value>].integer() != 5 ||
      items[1] != <tail>) return 1;
  if ($nested_text("seven") != %"seven" || punctuation != %"}") return 2;
  printf("%d %d %d\n", $seven_value(), $twice(7), local_value());
  return 0;
}
