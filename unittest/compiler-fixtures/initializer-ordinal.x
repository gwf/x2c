#include "x2c.x"

#define ROWS 2
#define COLS 3

typedef int Score;
Var Score.var(Score value) { return (int)value + 100; }
struct Matrix { Score values[ROWS][COLS]; Var tail; };
struct Record { String name; Var tail; };
struct Cell { String names[COLS]; Var tail; };
struct Bits { String names[ROWS]; unsigned int tag:3; };

static int calls;
static Score next(int n) { calls++; return n; }
static struct Matrix saved = {
  next(1), next(2), next(3), next(4), next(5), next(6), next(7)
};
static struct Record records[ROWS] = {"a", "bb", "ccc", "dddd"};
static struct Cell cells[ROWS] = {
  "a", "bb", "ccc", "dddd", "eeeee", "ffffff", "ggggggg", "hhhhhhhh"
};

static int valid(struct Matrix *m) {
  return m.values[0][0] == 1 && m.values[0][1] == 2 &&
    m.values[0][2] == 3 && m.values[1][0] == 4 &&
    m.values[1][1] == 5 && m.values[1][2] == 6 && m.tail.int() == 107;
}

int main(void) {
  int before = calls;
  struct Matrix local = {
    next(1), next(2), next(3), next(4), next(5), next(6), next(7)
  };
  struct Matrix compound = (struct Matrix) {
    next(1), next(2), next(3), next(4), next(5), next(6), next(7)
  };
  printf("%d %d %d %d %d\n", valid(&saved), valid(&local), valid(&compound),
    before, calls);

  String first = records[0].tail, second = records[1].tail;
  printf("%d %d %d %d\n", records[0].name.len(), first.len(),
    records[1].name.len(), second.len());

  struct Bits bits = {"a", "bb", 3};
  printf("%d %d %u\n", bits.names[0].len(), bits.names[1].len(), bits.tag);

  String row_first = cells[0].tail, row_second = cells[1].tail;
  printf("%d %d %d %d %d\n", cells[0].names[2].len(), row_first.len(),
    cells[1].names[0].len(), cells[1].names[2].len(), row_second.len());
  return 0;
}
