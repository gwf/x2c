expand %(("generated_answer" 42) ("generated_other" 7))
macro Declaration(Name $name, Expr $value) {
  int $name(void) { return $value; }
}

expand %(("unit_answer" 3) ("unit_other" 5))
macro Unit(Name $name, Expr $value) {
  static int $name(void) { return $value; }
}

typedef struct Generated {
  expand %("left" "right")
  macro Field(Name $name) { int $name; }
} Generated;

enum GeneratedValues {
  expand %(("GENERATED_A" 1) ("GENERATED_B" 2))
  macro Enumerator(Name $name, Expr $value) { $name = $value }
};

static int sum(int left, int right) { return left + right; }
static int sum_rows(int head, List @tail) {
  foreach (int value in tail) head += value;
  return head;
}

macro Expression $squares() =>
  sum(@expand (%(2 3)) macro Expression(Expr $n) => $n * $n);

macro Expression $empty_arguments() =>
  sum_rows(9, @expand (%()) macro Expression(Expr $n) => $n);

macro Stmt $nested(Expr $amount) {
  expand %(1 2)
  macro Stmt(Expr $n) { total += $amount * $n; }
}

macro Stmt $from_rows(Expr $rows) {
  expand $rows
  macro Stmt(Expr $n) { total += $n; }
}

int main(void) {
  int total = 0;
  expand %(1 2 3)
  macro Stmt(Expr $n) { int temporary = $n; total += temporary; }
  if (total != 6) return 1;

  expand %((2 3) (4 5))
  macro Stmt(Expr $left, Expr $right) { total += $left * $right; }
  if (total != 32) return 2;
  expand %()
  macro Stmt(Expr $n) { total += $n; }
  if (total != 32) return 3;

  int zero = 0;
  expand %(() ())
  macro Stmt() { zero++; }
  if (zero != 2) return 4;

  expand %(("first" 2) ("second" 3))
  macro Stmt(Name $name, Expr $value) { int $name = $value; }
  if (first + second != 5) return 5;

  int widths = 0;
  expand %(((int)) ((double)))
  macro Stmt(Type $type) { widths += sizeof($type); }
  if (widths != sizeof(int) + sizeof(double)) return 6;

  int tail = 0;
  expand %((1 2 3) (4))
  macro Stmt(Expr $head, Expr @rest) { tail += sum_rows($head, @rest); }
  if (tail != 10) return 7;

  $nested(3);
  if (total != 41) return 8;
  $from_rows(%(4 5));
  if (total != 50) return 10;

  Generated record = { 1, 2 };
  Map entries = ${
    expand %(("a" 1) ("b" 2))
    macro Entry(Expr $key, Expr $value) { $key: $value }
  };
  int square = expand %(4) macro Expression(Expr $n) => $n * $n;
  if (record.left + record.right != 3 || GENERATED_A + GENERATED_B != 3 ||
      entries.len() != 2 || square != 16 || $squares() != 13 ||
      $empty_arguments() != 9 || unit_answer() + unit_other() != 8 ||
      generated_answer() != 42 || generated_other() != 7)
    return 9;
  puts("macro mapping ok");
  return 0;
}
