/* Advertised file-static values have separate compile-time and runtime
   instances. Calls that reach either const or mutable state stay unfolded;
   an explicit meta call may read or mutate the compile-time instance. */

#include "x2c.x"

meta static const double mg_pi = 3.25;
meta static int mg_counter = 10;

/* `meta` remains an identifier outside the forms it marks. */
typedef int meta;
meta ordinary_meta = 7;

meta double mg_read_pi(void) => mg_pi;
meta int mg_next(void) { mg_counter += 1; return mg_counter; }
meta int mg_pointer_next(void) {
  int *cell = &mg_counter;
  *cell = *cell + 1;
  return *cell;
}
meta double mg_pointer_pi(void) {
  const double *cell = &mg_pi;
  return *cell;
}

int main(void) {
  printf("%.2f %d %d %d %.2f %d %d\n",
    $(mg_read_pi), $(mg_next), $(mg_next), $(mg_pointer_next),
    $(mg_pointer_pi), mg_next(), ordinary_meta);
  return 0;
}
