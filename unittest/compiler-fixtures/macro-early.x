#include "x2c.x"
#include "meta.x"

/* A producer pairs `new-name` with `early`: the first application under a
   key declares the named global early, and later applications under the
   same key reuse that binding. */
meta static List tally(String key, int amount) {
  Atom token = Atom.intern("?__early_tally");
  String digits = %"$amount";
  return %(code-value "source"
    (stmnt (expr (int) (op += (expr (int) (ident $token))
      (expr (int) (literal (int) $digits)))))
    ((new-name $token "tally")
     (early (tally $key) $token
       (declare (static int) (bindings (bind $token ()))))));
}
macro Stmt $add_one() { @tally("a", 1) }
macro Stmt $add_ten() { @tally("b", 10) }

meta static List run_macro(Macro m) { return m(); }
macro Stmt $one() { @run_macro($add_one) }
macro Stmt $ten() { @run_macro($add_ten) }

int main(void) {
  $one();
  $one();
  $ten();
  return 0;
}
