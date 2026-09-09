/*  inline-lisp.x -- Query SQLite and inspect rows through ordinary Lisp. */

import "sqlite" with SqliteLisp;

int main(void) {
  Scope.retain();
  defer Scope.release();
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  SqliteLisp.install(lisp);

  List report = lisp.eval(%(
    sqlite-query ":memory:"
      "SELECT ? AS name, ? AS payload, ? AS missing"
      (list "archive" (sqlite-bytes '(0 127 255)) (sqlite-null))
  ));
  lisp.set_global("report", report);
  printf("%s\n", lisp.eval(%(car (car report))).string());
  puts(lisp.eval(%(sqlite-bytes-list (cadr (car report)))).repr());
  Var missing = lisp.eval(%(sqlite-null? (car (cdr (cdr (car report))))));
  printf("null: %d\n", !missing.is_nil());
  return 0;
}
