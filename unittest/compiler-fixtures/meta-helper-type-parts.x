/* A project meta body that inspects a builder's result sees the syntax the
   compiler builds, not a placeholder for it. */
#include "x2c.x"
#include "meta.x"
#include <stdio.h>

meta static int parts(void) { return x2c_type_parts(%(int)).len(); }

meta static int cast(void) =>
  x2c_expr_cast(%(* const char), %(expr (int) (literal (int) "0"))).equal(
    %(expr (* const char)
      (cast (decl (const char) (bindings (bind () (*))))
        (expr (int) (literal (int) "0")))));

meta static int declared(void) =>
  x2c_decl_make(%(* (func ((int) (* char))) int), "f", NULL).equal(
    %(declare (int) (bindings (bind ("f")
      (* (fnmod (params (param (int) (bind () ()))
                        (param (char) (bind () (*))))))))));

meta static int parameter(void) =>
  x2c_param_make(%((dim 4) const long), "a").equal(
    %(param (const long) (bind ("a") ((dim 4)))));

int main(void) {
  printf("%d %d %d %d\n", $parts(), $cast(), $declared(), $parameter());
  return 0;
}
