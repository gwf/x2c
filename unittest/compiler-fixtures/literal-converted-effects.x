#include "x2c.x"

typedef int Score;
static int order, counter;

Var Score.var(Score value) {
  order = order * 10 + (int) value;
  return (int) value;
}

static int note(int value) {
  order = order * 10 + value;
  return value;
}

static int fail(int value) {
  note(value);
  raise %(probe (value $value));
  return 0;
}

#define NEXT (counter++)

int main(void) {
  Score one = 1, two = 2;
  Array values = [(Var) one, (Var) two];
  if (order != 12 || values[0] != 1 || values[1] != 2) return 1;
  order = 0;
  List items = %(${(Var) one} ${(Var) two});
  if (order != 12 || items != %(1 2)) return 2;
  order = 0;
  Map entries = {(Var) one: (Var) two};
  if (order != 12 || entries[1] != 2) return 3;
  order = 0;
  String text = %"${(Var) one}${(Var) two}";
  if (order != 12 || text != %"12") return 4;
  Array native = [(int) NEXT, (int) NEXT];
  if (counter != 2 || native[0] != 0 || native[1] != 1) return 5;
  List native_list = %(${(int) NEXT} ${(int) NEXT});
  if (counter != 4 || native_list != %(2 3)) return 6;
  Map native_map = {(int) NEXT: (int) NEXT};
  if (counter != 6 || native_map[4] != 5) return 7;
  String native_text = %"${(int) NEXT}${(int) NEXT}";
  if (counter != 8 || native_text != %"67") return 8;
  order = 0;
  match (%(k 1 2))
    case %(k ${note(1)} ${note(2)}): {}
  if (order != 12) return 9;
  order = 0;
  try { raise %(probe (a ${note(1)}) (b ${note(2)})); }
  catch %(probe (a ?a) (b ?b)):
    if (a != 1 || b != 2) return 10;
  if (order != 12) return 11;
  order = 0;
  try {
    List stopped = %(${fail(1)} ${note(2)});
    (void) stopped;
    return 12;
  }
  catch %(probe (value 1)): {}
  if (order != 1) return 13;
  order = 0;
  try { raise %(probe (a ${fail(1)}) (b ${note(2)})); }
  catch %(probe (value 1)): {}
  if (order != 1) return 14;
  printf("converted literal effects stay in source order\n");
  return 0;
}
