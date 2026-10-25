#include "x2c.x"

meta static List protocol_rows(void) => %((protocol bogus));

macro Stmt $bad() {
  @protocol_rows()
}

static void use_bad(void) {
  $bad();
}
