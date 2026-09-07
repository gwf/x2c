#include <assert.h>

macro Expression $squares() => (%(1 4 9))

int main(void) {
  // An ordinary macro expands to the List literal.
  List expanded = $squares();

  // Compile-time Lisp returns the syntax for a List.
  List early = $(quote
    (expr ("List") (cons (expr (int) (literal (int) "1"))
      (expr ("List") (cons (expr (int) (literal (int) "4"))
        (expr ("List") (cons (expr (int) (literal (int) "9"))
          (nil))))))));

  // Sometimes you already know the answer.
  List obvious = %(1 4 9);

  // Build the three cells directly.
  List handmade = cons(1, cons(4, cons(9, NULL)));

  // Insert ordinary variables into a List literal.
  int a = 1, b = 4, c = 9;
  List inserted = %($a $b $c);

  // Runtime Lisp returns the quoted List itself.
  Lisp lisp = Lisp.new(); defer lisp.destroy();
  List late = lisp.eval(%('(1 4 9)));

  List ways = %($expanded $early $obvious $handmade $inserted $late);
  foreach (List left, ways)
    foreach (List right, ways) assert(left == right);
  puts(%"$early: Six different ways to agree.");
  return 0;
}
