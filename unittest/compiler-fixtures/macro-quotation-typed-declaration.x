#include "x2c.x"
#include "meta.x"

/* A typed quotation binds nothing, so it has no expansion to keep a name
   it declares private. A name it needs comes from a hole. */
meta static List counted(List value) =>
  $!(int)( ({ int total = $value; total + 1; }) );

int main(void) { return 0; }
