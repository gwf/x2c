#include "x2c.x"

/* A public directive that follows an item the source holds must not change
   what that item sees, although the source includes the header first. A C
   include stays in the source at its place, so `saved` is a macro only
   after it. A public `#define` goes to the header, and the source repeats
   it in order; function bodies still follow the file's directives. */
static int saved = 7;
#include "header-include-after-source-macros.h"

static int value = 5;
int read_value(void) => value;
#define value 42

int main(void) {
  printf("%d %d\n", saved, read_value());
  return 0;
}
