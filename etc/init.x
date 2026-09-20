/* Standard Lisp algorithms; generate with tools/gen-lisp-init.py. */
#include "x2c.x"
$(def write-file (bind "lisp_write_file" nil))
$(defun init.emit (fn)
  (begin (write-file "init-generated.xlisp"
    (foldl string-append "" (map repr (x2c.comptime.lower fn)))) (list fn)))
macro Decorator $init.emit(Unit $fn) => {
  $(init.emit $fn)...
}
$init.emit()
List filter(Func keep, List values) {
  if (values.equal(%())) return values;
  Var value = values.car();
  if (keep(value).equal(%())) return filter(keep, values.cdr());
  return value.cons(filter(keep, values.cdr()));
}

