/* Optional native layout probe; run with run-task-backend.sh. */
#include "../../lib/task/stack.c"
#include <assert.h>
#include <signal.h>
#include <sys/wait.h>

static void entry(void *value) {
  TaskStack *stack = *(TaskStack **)value;
  volatile unsigned char local = 0;
  uintptr_t address = (uintptr_t)&local;
  uintptr_t low = x2c_task_stack_low(stack);
  assert(address >= low && address < low + stack->coroutine->stack_size);
  x2c_task_stack_yield(stack);
  local = 1;
  assert(local == 1);
}

int main(void) {
  assert(x2c_task_stack_supported());
  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  size_t sizes[] = {32768, 65536, 65537, 1048576, 8u << 20};
  for (size_t i = 0; i < sizeof(sizes) / sizeof(*sizes); i++) {
    TaskStack *stack = x2c_task_stack_new(entry, &stack, sizes[i]);
    assert(stack);
    size_t rounded = (sizes[i] + page - 1) / page * page;
    assert(stack->coroutine->stack_size == rounded);
    assert(stack->mapping_size == rounded + page);
    assert(x2c_task_stack_low(stack) == (uintptr_t)stack->mapping + page);
    x2c_task_stack_resume(stack);
    assert(mco_status(stack->coroutine) == MCO_SUSPENDED);
    x2c_task_stack_resume(stack);
    assert(mco_status(stack->coroutine) == MCO_DEAD);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
      *(volatile unsigned char *)stack->mapping = 1;
      _exit(0);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status));
    assert(WTERMSIG(status) == SIGSEGV || WTERMSIG(status) == SIGBUS);
    uintptr_t mapping = (uintptr_t)stack->mapping;
    x2c_task_stack_free(stack);
    for (size_t offset = 0; offset < rounded + page; offset += page) {
      errno = 0;
      assert(mprotect((void *)(mapping + offset), page,
                      PROT_READ | PROT_WRITE) == -1);
      assert(errno == ENOMEM);
    }
  }
  return 0;
}
