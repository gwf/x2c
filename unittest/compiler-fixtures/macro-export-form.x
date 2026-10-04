// `export` marks only a file-scope macro import. Elsewhere it is an
// ordinary identifier.
#include "x2c.x"

int twice(int export) { return export * 2; }

export $(defun f () 1)
