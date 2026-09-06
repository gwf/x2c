#include "x2c.x"

static void exit_terminal(void) {
  exit(1);
}

static int exit_caller(void) {
  exit_terminal();
}

int main(void) {
  return 0;
}
