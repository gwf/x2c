#include "x2c.x"
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

static int rejected(void (*action)(void)) {
  pid_t pid = fork();
  if (pid < 0) return 0;
  if (pid == 0) {
    action();
    _exit(0);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) != pid) return 0;
  return WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT;
}

static void update_void(void) {
  Var one = 1, two = 2;
  Array.update_n(%[], 3, one, void, two);
}

static void literal_void(void) {
  Var middle = void;
  Array values = %[1, $middle, 2];
  (void) values;
}

int main(void) {
  Var null = (Var) { .u64 = 0 };
  Array values = %[1, $null, 2];
  int valid = values.len() == 3 && values[1].is_null();
  int direct = rejected(update_void);
  int literal = rejected(literal_void);
  printf("%d %d %d\n", valid, direct, literal);
  return valid && direct && literal ? 0 : 1;
}
