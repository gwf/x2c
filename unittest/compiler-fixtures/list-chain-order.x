#include "x2c.x"

static int trail;

static int note(int value) {
  trail = trail * 10 + value;
  return value;
}

static List items(int value) => %(${note(value)} ${note(value + 1)});

int main(void) {
  List chain = %(fixed ${note(1)} @{items(2)} (${note(4)})
                 ${note(5)} @{items(6)});
  if (trail != 1234567 || chain.len() != 8) return 1;
  if (chain[0].symbol() != <fixed> || chain[1].integer() != 1 ||
      chain[2].integer() != 2 || chain[3].integer() != 3 ||
      chain[4].list()[0].integer() != 4 || chain[5].integer() != 5 ||
      chain[6].integer() != 6 || chain[7].integer() != 7) return 2;
  List first = %(constant (nested 3)), second = %(constant (nested 3));
  if (first != second) return 3;
  printf("List heads, splices, and final tails keep source order\n");
  return 0;
}
