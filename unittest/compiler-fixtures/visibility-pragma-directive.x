/* Only a `#pragma private` or `#pragma public` directive changes
   visibility, and a comment in one reads as a blank, as it does in C. A
   directive that merely spells the words, such as the string macro below,
   keeps its place in the header. The included file returns to public
   output under a commented `#pragma public`, so its greeting stays visible
   here. */
#include "visibility-pragma-directive/source.x"

#define VISIBILITY_NOTE "pragma private"
int shown_value = 1;

#pragma private /* not pragma public */
int hidden_value = 3;

int greeting_length(void) { return (int) greeting.len(); }
