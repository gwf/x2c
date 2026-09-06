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

static void box_null_array(void) {
  Var.new(<array>, NULL);
}

static void box_null_map(void) {
  Var.new(<map>, NULL);
}

int main(void) {
  Scope.retain();
  Array first_array = %[], second_array = %[];
  Map first_map = %{}, second_map = %{};
  Var boxed_array = first_array, boxed_map = first_map;
  first_array.push(7);
  first_map[<key>] = 9;

  int arrays = (void *) first_array != NULL &&
               (void *) second_array != NULL &&
               first_array != second_array &&
               first_array.len() == 1 && second_array.len() == 0;
  int maps = (void *) first_map != NULL &&
             (void *) second_map != NULL &&
             first_map != second_map &&
             first_map.len() == 1 && second_map.len() == 0;
  int boxes = boxed_array.array() == first_array &&
              boxed_map.map() == first_map;
  int rejects = rejected(box_null_array) && rejected(box_null_map);
  printf("%d %d %d %d\n", arrays, maps, boxes, rejects);
  Scope.release();
  return arrays && maps && boxes && rejects ? 0 : 1;
}
