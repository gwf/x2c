#include <stdio.h>

#if 0
module { "module-block-trivia/missing.x" }
#endif
#ifdef __cplusplus
module { "module-block-trivia/also-missing.x" }
#endif

module /* The token scan skips comments before the brace. */ {
  "module-block-trivia/value.x",
}

int main(void) {
  printf("%d\n", answer());
  return 0;
}
