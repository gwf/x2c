#include "x2c.x"
#include "process.x"
#include <errno.h>
#include <signal.h>

/* A Job that a compile-time call starts ends when that call returns, even
   when it starts inside an inner `$scope` block, so the process is gone
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

int main(void) {
  long pid = $started();
  int gone = pid > 0 && kill((pid_t) pid, 0) == -1 && errno == ESRCH;
  printf("%d\n", gone);
  return 0;
}
