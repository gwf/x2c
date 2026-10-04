#include "x2c.x"
#include "meta.x"

/* A type error in a `meta` body is reported at the call with the body's
   own place and message. */

meta static List wrong(void) {
  List items = "abc";
  return items;
}

int main(void) {
  List items = $wrong();
  return items == NULL;
}
