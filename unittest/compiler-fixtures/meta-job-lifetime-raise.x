#include "x2c.x"
#include "meta.x"
#include "process.x"

/* A Job that a compile-time call starts ends when that call raises. The
   failure in `starts` leaves it with the job running; the job is
   terminated and reaped, and translation continues to the next call. */

meta void starts(void) {
  List command = %(sleep 30);
  Job job = List.job(command);
  job.start();
  x2c_diagnostic_fail("failed with a job running", %());
}

meta void after(void) {
  x2c_diagnostic_fail("translation continued", %());
}

void first(void) { $starts(); }
void second(void) { $after(); }
