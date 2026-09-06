/* error-fatal-preinit.c -- error floor before x2c runtime initialization */

#include "common.h"
#include "error.h"

int main(void) {
  x2c_error_raise((Symbol) 1, NULL);
  return 2;
}
