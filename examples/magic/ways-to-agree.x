#include <assert.h>
// Wrap one expression node; keep the cons cells explicit.
$(defun node (type body) `(expr (,type) ,body))
int main(void) {
List early = $(node "List" `(cons ,(x2c.literal.int 1)
  ,(node "List" `(cons ,(x2c.literal.int 4)
    ,(node "List" `(cons ,(x2c.literal.int 9) (nil)))))));

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
