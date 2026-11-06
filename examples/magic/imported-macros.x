/*  imported-macros.x -- use a macro and meta function from another file

    The provider is a second source file, so name it on the command line:

      x2c run -q examples/magic/imported-macros.x examples/magic/support/answer.x
*/

#include "support/answer.x"

int main(void) {
  printf("%d\n", $example.answer(40));
  return 0;
}
