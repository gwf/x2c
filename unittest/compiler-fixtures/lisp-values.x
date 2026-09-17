#include "x2c.x"

/* The compile-time value operations build a Map, a List, an Array and a
   String during translation, and the results reach the program as
   literals. */

$(defun tally (words)
  (let ((counts (Map.new)))
    (begin
      (map (lambda (word)
             (Map.setindex counts word
               (+ 1 (Map.getdefault counts word 0))))
           words)
      (List.sort (Map.list counts)))))

$(defun render (pairs)
  (String.join ", "
    (map (lambda (pair)
           (String.add (String.upper (car pair))
                       (String.add "=" (str (cadr pair)))))
         pairs)))

$(defun stack (values)
  (let ((items (Array.new)))
    (begin
      (map (lambda (value) (Array.push items value)) values)
      (Array.remove items 0)
      (Array.join items "|"))))

int main(void) {
  printf("%s\n",
    $(x2c.literal.string (render (tally (String.split "fig pear fig" " ")))));
  printf("%s\n", $(x2c.literal.string (stack '("a" "b" "c"))));
  printf("%s\n",
    $(x2c.literal.string (Symbol.str (Var.parse "answer" 'symbol))));
  printf("%d\n", $(x2c.literal.int (Var.convert 42.75 'i32)));
  printf("%d\n", $(x2c.literal.int (List.index '(a b c) 'c)));
  return 0;
}
