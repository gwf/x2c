#include "x2c.x"
#include "meta.x"

/* A Param quotation binds nothing, so it may not declare a name of its
   own. Its name comes from a hole: `$!Param{ double $x }`. */
meta static List named(void) => $!Param{ double x };

int main(void) { return 0; }
