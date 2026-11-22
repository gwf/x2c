/* A resumed main return must keep its exit status. */
#include "task.x"
#include <stdlib.h>

static void _on_exit(void) { puts("Task WebAssembly exit hook ran"); }

int main(void) {
  atexit(_on_exit);
  Array jobs = auto [];
  Func job = %!(void) => <done>;
  jobs.push(job);
  Task.run(jobs, NULL);
  return 7;
}
