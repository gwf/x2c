#include "x2c.x"
#include "process.x"

/* A Job that a compile-time call starts is finalized when the call
   returns, so returning it is an error. The fixture marks `List.job`
   itself; the region walk rejects the body before anything binds it. */

meta Job List.job(List command);

meta Var start(void) {
  List command = %(sleep 1);
  Var job = command.job();
  return job;
}

int main(void) { return 0; }
