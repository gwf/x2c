/*  comptime-declines-fallthrough.x -- a switch arm that runs into the next

    C runs on into the arm below when one does not transfer control. The
    comptime lowering refuses that by decision: reordering the arms into a
    state machine would be machinery with no caller, and accepting the
    switch as written would run the wrong arms. A refusal stops translation
    at the first function, so this decline needs its own fixture. See
    `plans/comptime-x2c-generalization.md`.
*/

#include "x2c.x"

meta int ct_fallthrough(int n) {
  int s = 0;
  switch (n) {
    case 1:
      s = 1;
    case 2:
      s = s + 2;
      break;
  }
  return s;
}

int main(void) { return 0; }
