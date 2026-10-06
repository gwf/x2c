/* A native macro spelling "pragma private" is ordinary source data.
   Nonstatic declarations remain public across includes and definitions. */
#include "visibility-pragma-directive/source.x"

#define VISIBILITY_NOTE "pragma private"
int shown_value = 1;

int hidden_value = 3;

int greeting_length(void) { return (int) greeting.len(); }
