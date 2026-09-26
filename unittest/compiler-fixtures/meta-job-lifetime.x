#include "x2c.x"
#include "process.x"
#include <errno.h>
#include <signal.h>

$(import "meta-job-lifetime.xmacro")

int main(void) {
  long pid = $started();
  int gone = pid > 0 && kill((pid_t) pid, 0) == -1 && errno == ESRCH;
  printf("%d\n", gone);
  return 0;
}
