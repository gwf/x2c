#include "x2c.x"

/*  A catch arm is its own protected region, so a jump from the try body into
    an arm would enter past the handler setup and is rejected. */

int main(void) {
  int value = 0;
  try {
    value = 1;
    goto handler;
  }
  catch %(bad-arg *): {
handler:
    value = 2;
  }
  return value;
}
