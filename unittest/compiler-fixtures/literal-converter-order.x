#include "x2c.x"

typedef int Score;
typedef Var Packed;
static int observed;

Var Score.var(Score value) {
  observed = observed * 10 + (int) value;
  return (int) value;
}

String Score.str(Score value) {
  observed = observed * 10 + (int) value;
  return ((int) value).str();
}

Packed int.packed(int value) {
  observed = observed * 10 + value;
  return value.var();
}

static Var shadowed(List value) {
  observed = observed * 10 + 1;
  return value;
}

int main(void) {
  Score first = 1, second = 2;
  List explicit = %(${first.var()} ${second.var()});
  printf("explicit %d %ld\n", observed, (long) explicit.len());
  observed = 0;
  List implicit = %($first $second);
  printf("list %d %ld\n", observed, (long) implicit.len());
  observed = 0;
  List nested = %(($first) ($second));
  printf("nested %d %ld\n", observed, (long) nested.len());
  observed = 0;
  Array values = [first, second];
  printf("array %d %ld\n", observed, (long) values.len());
  observed = 0;
  Map entry = %{${first}: ${second}};
  printf("map %d %ld\n", observed, (long) entry.len());
  observed = 0;
  String text = %"$first$second";
  printf("string %d %s\n", observed, (char *) text);
  observed = 0;
  List empty = NULL;
  Var (*List_var)(List) = shadowed;
  List calls = %(${List_var(empty)} $second);
  printf("shadow %d %ld\n", observed, (long) calls.len());
  observed = 0;
  List aliases = %(${((int) first).packed()} ${((int) second).packed()});
  printf("alias %d %ld\n", observed, (long) aliases.len());
  return 0;
}
