#include "x2c.x"
#include "process.x"
#include <errno.h>
#include <signal.h>

/* A Job that a compile-time call starts ends when that call returns, with
   or without an inner `$scope` block around it, so the process is gone
   before the program runs. */

meta long started(void) {
  long pid = 0;
  $scope() {
    List command = %(sleep 30);
    Job job = List.job(command);
    job.start();
    pid = job.pids[0];
  }
  return pid;
}

meta long started_plain(void) {
  List command = %(sleep 30);
  Job job = List.job(command);
  job.start();
  return job.pids[0];
}

static int gone(long pid) =>
  pid > 0 && kill((pid_t) pid, 0) == -1 && errno == ESRCH;

int main(void) {
  printf("%d %d\n", gone($started()), gone($started_plain()));
  return 0;
}
