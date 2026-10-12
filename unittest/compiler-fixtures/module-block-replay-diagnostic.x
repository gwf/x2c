/* An including unit replays a member's compile-time Lisp from the member's
   own file, so its failure is reported at the member's line and column. */
#include "module-block-replay-diagnostic/library.x"

int main(void) => library_value();
