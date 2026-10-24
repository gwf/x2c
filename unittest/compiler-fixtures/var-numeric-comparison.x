/* Two numeric Vars compare as their native values do in C. `===` on numbers
   requires the same type and the same bits. Map keys and sorting keep the
   numeric types apart. */
#include "x2c.x"

static void row(const char *label, Var a, Var b) {
  printf(
    "%-14s == %d  != %d  < %d  <= %d  > %d  >= %d  === %d  !== %d\n",
    label, a == b, a != b, a < b, a <= b, a > b, a >= b, a === b, a !== b);
}

int main(void) {
  auto {
    double negative_zero = -0.0;
    Var nan = 0.0 / 0.0;
    row("3 3L", 3, 3L);
    row("3 3.0", 3, 3.0);
    row("'a' 97", 'a', 97);
    row("-1 1u", -1, 1u);
    row("-1 4294967295u", -1, 4294967295u);
    row("2^53+1L 2^53", 9007199254740993L, 9007199254740992.0);
    row("NaN NaN", nan, nan);
    row("0.0 -0.0", 0.0, negative_zero);
    row("3L 3L boxes", Var.box_long(3L), Var.box_long(3L));
    row("\"3\" 3", "3", 3);

    Map keys = {};
    keys[3] = "int";
    keys[3L] = "long";
    printf("keys %d %s %s\n", keys.len(), keys[3].repr(), keys[3L].repr());
    Array sorted = [3, 3L, 2.5];
    printf("sorted %s\n", sorted.sort().repr());
  }
  return 0;
}
