#include "x2c.x"

// A variable is never a permitted operand of an integer constant
// expression, so an integral one can never spell a null pointer -- not
// even when it holds zero, as this one does.  That makes the conversion
// below an unconditional C constraint violation, decidable without
// folding anything, and it is the form most likely to appear in real
// code.  Before it was diagnosed the compiler exited 0 and emitted
// `List x = n;`, which the C compiler rejects.
int main(void) {
  int n = 0;
  List x = n;
  (void) x;
  return 0;
}
