/*  outer-decorator.x -- a decorator outside $cstar.verify rewrites the body
    after the record was taken. cstar-verify must refuse the file.
*/

#include "x2c.x"
$(import "../src/cstar.xmacro")

macro Decorator $demo.append(Function $function) using $unused => {
  $(x2c.function.body $function)...
  int $unused = 0;
  (void) $unused;
}

$demo.append()
$cstar.verify("fact(true)", "fact(true)")
static int identity(int x) {
  return x;
}
