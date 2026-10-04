#include "x2c.x"
#include "meta.x"

/* Inside an expansion a meta call written as a whole statement may return
   a statement, in an arrow body or a braced one. */
meta static List same_of(List code) { return code; }
meta static void nothing(void) { }
macro Stmt $same(Stmt $code) => $same_of($code);
macro Stmt $braced(Stmt $code) { $same_of($code); }
macro Stmt $quiet() => $nothing();

int main(void) {
  int total = 0;
  $same(try total += 1; finally total += 10;);
  if (total == 11)
    $same(try raise %(bad-arg (value 7));
          catch %(bad-arg (value ?value)): total += value.int(););
  $braced(defer printf("%d\n", total););
  $braced(if (total == 18) total += 100;);
  $same(total += 1000;);
  $quiet();
  return total != 1118;
}
