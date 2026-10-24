#include "x2c.x"

/* A Split from String.lines lives in the active Scope, so returning it out
   of the region `auto` that holds it gives the ordinary region finding. */

meta Split leak(String text) {
  auto { return text.lines(); }
}

int main(void) { return 0; }
