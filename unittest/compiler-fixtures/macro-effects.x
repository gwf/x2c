#include "x2c.x"
#include "meta.x"

/* A producer returns lowered code with an effect the compiler applies when
   the macro value application is bound: each `new-name` allocates one
   fresh local, shared by the declaration and the uses that name it. */
meta static List counter_slot(void) {
  Atom token = Atom.intern("?__effect_counter");
  return %(code-value "source"
    (declare (int) (bindings (op = (bind $token ()) (expr (int) (literal (int) "0")))))
    ((new-name $token "counter")));
}
macro Stmt $counted(Stmt $body) {
  @counter_slot()
  $body
}

meta static List count_twice(List body) {
  Macro counted = $counted;
  return counted(body);
}
macro Stmt $twice_counted(Stmt $body) { @count_twice($body) }

int main(void) {
  int total = 0;
  $twice_counted({ total += 1; });
  $twice_counted({ total += 2; });
  printf("%d\n", total);
  return 0;
}
