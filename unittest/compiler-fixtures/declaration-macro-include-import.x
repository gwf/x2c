#include "declaration-macro-include-scope/provider.x"
$(import "declaration-macro-include-scope/answer.xmacro")

// An includer that imports the macros an included unit also imports uses
// them after a serial translation of that unit, which it then replays.
$answer(includer_answer);

int main(void) {
  printf("%d %d\n", provider_answer, includer_answer);
  return 0;
}
