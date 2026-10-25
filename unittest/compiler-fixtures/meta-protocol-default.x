#include "x2c.x"
#include "compiler-meta.x"

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

meta static String probe_row(String name, List rows) {
  foreach (List row, rows)
    if (row.car().equal(name)) return row.repr();
  return "()";
}
macro Expression $target(Expr $name) =>
  $probe_row($Code.value($name), $_x2c_native_rows(<lisp>, %(), %()));

int main(void) {
  struct Crate storage = {{3}};
  Crate crate = &storage;
  printf("%s\n%s\n%zu\n", $target("Crate_size"), $target("Sized_size"),
         crate.size());
  return 0;
}
