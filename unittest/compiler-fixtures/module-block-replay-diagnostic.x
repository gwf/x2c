/* An including unit reports a member's misplaced evaluated collection
   at the member's own line and column. */
#include "module-block-replay-diagnostic/library.x"

int main(void) => library_value();
