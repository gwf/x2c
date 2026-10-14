/* A program's definitions keep their own names apart from the shipped
   components': a meta function spelled like a shipped translator or helper
   is a separate function, and the components lower their forms as they
   always do, through the copies the compiler links. */

#include "x2c.x"
#include "meta.x"

#include <stdio.h>

/* Spelled like the interpolation component's translator. */
meta Code interpolation_lowering(Code code) => $!String{ String.new("program's") };

/* Spelled like the try component's landing helper. */
meta List _x2c_try_landing(List frame, List clause, List exits) => frame;

/* Spelled like the access component's read translator. */
meta Code access_read(Code code) => code;

static int risky(int n) {
  int r = 0;
  try {
    if (n > 1) raise %(big);
    r = n;
  }
  catch %(big): r = -1;
  return r;
}

int main(void) {
  int n = 4;
  String text = %"n is $n";
  Array items = [1, 2, 3];
  items[1] = 20;
  printf("%s %ld %d %d\n", text, items[1].integer(), risky(1), risky(5));
  return 0;
}
