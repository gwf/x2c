#include "declaration-macro-include-scope/provider.x"

// Public declaration macros reach the includer through ordinary includes.
$answer(includer_answer);

int main(void) {
  printf("%d %d\n", provider_answer, includer_answer);
  return 0;
}
