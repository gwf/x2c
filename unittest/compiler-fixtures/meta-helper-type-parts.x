/* A project meta body that inspects a builder's result sees the syntax the
   compiler builds, not a placeholder for it. */
#include "x2c.x"
#include "meta.x"
#include <stdio.h>

meta static int parts(void) { return Type.parts(%(int)).len(); }

meta static int pointer(void) =>
  Type.parts(%(* const char)).equal(%((const char) (*)));

meta static int function(void) =>
  Type.parts(%(* (func ((int) (* char))) int)).equal(
    %((int) (* (fnmod (params (param (int) (bind () ()))
                              (param (char) (bind () (*))))))));

meta static int array(void) =>
  Type.parts(%((dim 4) const long)).equal(%((const long) ((dim 4))));

int main(void) {
  printf("%d %d %d %d\n", $parts(), $pointer(), $function(), $array());
  return 0;
}
