#include "x2c.x"

import "geo" as g;

macro Unit $check_imported(Type $type) => {
  $(let ((actual (x2c.type.fields $type)))
     (if (equal? actual
           '(("a" (struct "geo__VecData"))
             ("b" (struct "geo__VecData"))))
         nil
         (x2c.diagnostic.fail "imported fields differ"
                              (list (repr actual)))))...
}

$check_imported(g.VecPair);
