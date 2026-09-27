#include "x2c.x"
#include "datum.x"

int main(void) {
  List external = %(binding 912 "helper");
  List body = %(block
    (declare (int) (bindings (bind (local-slot 0 "tmp") ())))
    (return () (expr () (op +
      (expr () (ident (local-slot 0 "tmp")))
      (expr () (ident $external))))));
  List template = %(syntax-template
    (kind block) (parameters ()) (body $body)
    (locals (0 "tmp")) (boundary $external)
    (capture ("x2c.template" $external ()))) ;
  Buffer encoded = Buffer.new(0);
  if (datum_result_problem(template, {})) return 1;
  if (!datum_write(encoded, template, 1)) return 2;
  unsigned cursor = 0;
  Var restored = void;
  if (!datum_read(encoded, cursor, restored)) return 3;
  if (!template.equal(restored)) return 4;
  List rows = (List) restored;
  if (!rows.assoc(<body>).equal(body)) return 5;
  printf("descriptor roundtrip: structural equality; local/free references retained\n");
  return 0;
}
