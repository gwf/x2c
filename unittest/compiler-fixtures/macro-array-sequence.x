#include "x2c.x"

macro Expression $values(Expr $items...) =>
  %[${10}, $items..., ${40}];

macro Entry $named_value(Expr $value) {
  result: $value
}

macro Expression $description(Expr $value) => %"result=${$value}";

int main(void) {
  Array full = $values(20, 30);
  Array empty = $values();
  Map row = %{${$named_value(42)}};
  String text = $description(42);
  if (full.len() != 4 || full[0].integer() != 10 ||
      full[1].integer() != 20 || full[2].integer() != 30 ||
      full[3].integer() != 40)
    return 1;
  if (empty.len() != 2 || empty[0].integer() != 10 ||
      empty[1].integer() != 40)
    return 2;
  if (row[<result>].integer() != 42 || text != %"result=42")
    return 3;
  printf("macro collections and string ok\n");
  return 0;
}
