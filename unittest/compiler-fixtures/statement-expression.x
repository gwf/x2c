#include "x2c.x"
#include <stdio.h>

/* A statement expression in a template: its local is renamed. */
macro Expression $plus_one(Expr $value) => ({ int t = $value; t + 1; });

/* Lisp-built syntax binds and takes its final statement's type. */
macro Expression $wrapped(Expr $value) =>
  $(list 'expr '() (list 'parens (list 'block (list 'stmnt $value))));

/* A return leaving a statement expression runs the cleanup it leaves. */
static int early(int bad) {
  defer printf("cleanup %d\n", bad);
  int value = ({ if (bad) return -1; 2; });
  return value;
}

/* So does a break, and a defer may stand in a nested block. */
static int loop_total(void) {
  int total = 0;
  for (int i = 0; i < 5; i++) {
    defer total += 100;
    total += ({ if (i == 2) break; int r = 0; { defer r += 10; r = i; } r; });
  }
  return total;
}

/* A local set before a raise inside one keeps its value in the catch. */
static int caught(void) {
  return ({
    int seen = 0;
    try { seen = 5; raise %(probe); }
    catch %(probe): seen++;
    seen;
  });
}

int main(void) {
  int t = 1;
  int area = ({ int width = 6; width * 7; });
  String name = ({ String first = "Ada"; first + " Lovelace"; });
  String raw = ({ "raw"; });
  Var boxed = ({ Var v = 4; v; });
  Var converted = ({ 5; });
  int nested = ({ int y = ({ int z = 5; z + 1; }); y * 2; });
  Var lisp = $wrapped(7);
  Map map = ({a: 1});
  int brace = ({1});
  ({ printf("statement %d\n", area); });
  printf("%d %s %s %s %s %d\n", area, name, raw, boxed.repr(),
         converted.repr(), nested);
  printf("%d %d %s %d %d\n", $plus_one(41), t, lisp.repr(), map.len(),
         brace);
  int kept = early(0), left = early(1);
  printf("%d %d %d %d\n", kept, left, loop_total(), caught());
  return 0;
}
