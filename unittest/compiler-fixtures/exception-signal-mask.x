#include "x2c.x"

#include <signal.h>

int main(void) {
  Error.initialize();
  sigset_t original, working, blocked, current;
  if (sigprocmask(SIG_SETMASK, NULL, &original)) return 2;
  working = original;
  sigdelset(&working, SIGUSR1);
  if (sigprocmask(SIG_SETMASK, &working, NULL)) return 2;

  int retained = 0;
  try {
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGUSR1);
    if (sigprocmask(SIG_BLOCK, &blocked, NULL)) return 2;
    raise %(invariant);
  }
  catch %(invariant): {
    if (sigprocmask(SIG_SETMASK, NULL, &current)) return 2;
    retained = sigismember(&current, SIGUSR1) == 1;
  }

  if (sigprocmask(SIG_SETMASK, &original, NULL)) return 2;
  printf("%d\n", retained);
  return retained ? 0 : 1;
}
