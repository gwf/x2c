#include "x2c.x"
#include "process.x"

/* A Job that a compile-time call starts is finalized when the call
   returns, so returning it is an error. */

meta Var start(void) {
  List command = %(sleep 1);
  Var job = command.job();
  return job;
}

int main(void) { return 0; }
