#include "declaration-macro-include-scope/provider.x"

// An included unit's macro import stays in that unit, whether the includer
// walks it or replays it, so the includer must import the macros it uses.
$answer(includer_answer);

int main(void) {
  printf("%d %d\n", provider_answer, includer_answer);
  return 0;
}
