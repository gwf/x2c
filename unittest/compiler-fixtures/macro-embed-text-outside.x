#include "x2c.x"

/* Outside an expansion the String literal is rejected as an argument before
   the outside-expansion check is reached; unittest/STATUS.md tracks it. */
String value = $x2c_embed_text("macro-embed-text-data.txt");
