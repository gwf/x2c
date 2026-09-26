/* Advertised file-static values have separate compile-time and runtime
   instances. An explicit meta call reads or mutates the compile-time
   instance; an ordinary call uses the runtime one. */

#include "x2c.x"

meta static const double mg_pi = 3.25;
meta static int mg_counter = 10;

/* `meta` remains an identifier outside the forms it marks. */
typedef int meta;
meta ordinary_meta = 7;

$(import "meta-globals.xmacro")

int main(void) {
  printf("%.2f %d %d %d %.2f %d %d\n",
    $(mg_read_pi), $(mg_next), $(mg_next), $(mg_pointer_next),
    $(mg_pointer_pi), mg_next(), ordinary_meta);
  return 0;
}
