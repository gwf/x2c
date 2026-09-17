#include "x2c.x"
#include <unistd.h>

static void exit_terminal(void) {
  exit(1);
}

static int exit_caller(void) {
  exit_terminal();
}

void posix_exit_terminal(void) {
  _exit(1);
}

static int posix_exit_caller(void) {
  posix_exit_terminal();
}

int main(void) {
  exit(0);
}
