#include "x2c.x"

/* A `meta` adoption that relies on a base default exposes the forwarding
   function the conformance generates for its participant. */
typedef struct Sized { size_t n; } *Sized;
protocol Sized(T) {
  size_t T.size(T);
}
size_t Sized.size(Sized s) => s.n;

typedef struct Crate { struct Sized sized; } *Crate;
Sized Crate.sized(Crate crate) => &crate.sized;
meta protocol Sized(Crate);

$(defun probe.row (name rows)
   (cond ((null? rows) nil)
         ((equal? (car (car rows)) name) (car rows))
         (true (probe.row name (cdr rows)))))
macro Expression $target(Expr $name) =>
  $(repr (probe.row (x2c.literal.value $name)
                          (_x2c.native-meta.targets)));

int main(void) {
  struct Crate storage = {{3}};
  Crate crate = &storage;
  printf("%s\n%s\n%zu\n", $target("Crate_size"), $target("Sized_size"),
         crate.size());
  return 0;
}
