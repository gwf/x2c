#include "meta.x"
#include <stdio.h>

meta static List descriptor(void) {
  List external = %(binding 912 "helper");
  List body = %(block
    (declare (int) (bindings (bind (local-slot 0 "tmp") ())))
    (return () (expr () (op +
      (expr () (ident (local-slot 0 "tmp")))
      (expr () (ident $external))))));
  return %(syntax-template
    (kind block) (parameters ()) (body $body)
    (locals (0 "tmp")) (boundary $external)
    (capture ("x2c.atom" $external ())));
}

meta static List relay(List value) => value;

meta static int inspect(List value) {
  List body = value.assoc(<body>);
  List external = value.assoc(<boundary>);
  if (!external.equal(%(binding 912 "helper"))) return 0;
  if (!value.assoc(<capture>).equal(
      %("x2c.atom" $external ()))) return 0;
  if (!body.equal(%(block
    (declare (int) (bindings (bind (local-slot 0 "tmp") ())))
    (return () (expr () (op +
      (expr () (ident (local-slot 0 "tmp")))
      (expr () (ident $external)))))))) return 0;
  return 1;
}

meta static int pipeline(void) => inspect(relay(descriptor()));

int main(void) {
  int result = $pipeline();
  printf("helper descriptor inspection: %d\n", result);
  return result == 1 ? 0 : 1;
}
