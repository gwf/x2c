#include <assert.h>
// Compile-time Lisp builds one cons expression at a time.
$(defun cons-expr (n tail)
  `(expr ("List") (cons ,(x2c.literal.int n) ,tail)))
int main(void) {
List early = $(cons-expr 1 (cons-expr 4 (cons-expr 9 '(nil))));

// Spell out the same List.
List obvious = %(1 4 9);

// Build its cells directly.
List handmade = cons(1, cons(4, cons(9, NULL)));

// Runtime Lisp evaluates a quoted List.
Lisp lisp = Lisp.new(); defer lisp.destroy();
List late = lisp.eval(%('(1 4 9)));

List ways = %($early $obvious $handmade $late);
foreach (List left, ways)
  foreach (List right, ways) assert(left == right);
puts(%"$early: Four different ways to agree.");
return 0;
}
