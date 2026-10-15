/* A tag declared in a `for` initializer, in a function or a macro, is
   local to the loop, so the later `struct Record` is the file's tag. A tag
   there is a clang extension that gcc rejects, so the fixture checks the
   generated C without compiling it. */
#include "x2c.x"

struct Record { int integer; };

macro Stmt $loop_scope() {
  for (struct Record { String text; } value = {"macro"}; 0;)
    (void)value;
}

static int loop_scope(void) {
  for (struct Record { String text; } value = {"loop"}; 0;)
    (void)value;
  $loop_scope();
  struct Record after = {7};
  return after.integer;
}
