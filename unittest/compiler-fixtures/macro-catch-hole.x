#include "x2c.x"
#include "meta.x"

/* A Catch sequence hole writes a try's catch arms, so one macro recognizes
   a try with catches: its body, its arms and its finalizer. */
macro Stmt $caught(Stmt $body, Stmt $finalizer,
    Catch @arms) {
  try $body catch @arms finally $finalizer
}
macro Stmt $tried(Stmt $body, Stmt $finalizer) {
  try $body finally $finalizer
}

meta static List shape_of(List code) {
  Macro caught = $caught, tried = $tried;
  match (code) {
    case caught(?body, ?finalizer, *arms):
      return x2c_literal_int(10 + arms.len());
    case tried(?body, ?finalizer): return x2c_literal_int(1);
  }
  return x2c_literal_int(0);
}
macro Expression $shape(Stmt $code) => $shape_of($code);

int main(void) {
  int x = 0;
  int arms = $shape(try { x++; } catch %(bad-arg *): { x = 2; }
                    catch: { x = 3; } finally { x += 4; });
  int plain = $shape(try { x++; } finally { x += 4; });
  printf("%d %d\n", arms, plain);
  return 0;
}
