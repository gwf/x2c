/* Native task storage and stack switching. Scheduling stays in task.x. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>

#if (defined(__APPLE__) || defined(__linux__)) && \
    (defined(__aarch64__) || defined(__x86_64__)) && !defined(__EMSCRIPTEN__)
#include <sys/mman.h>
#include <unistd.h>
#define MCO_USE_ASM
#define MCO_API static inline
#define MCO_EXTERNAL_ASAN
#define MCO_NO_DEFAULT_ALLOCATOR
#define MCO_DEFAULT_STORAGE_SIZE 0
#define MINICORO_IMPL
#include "minicoro.h"

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#define TASK_ASAN
#endif
#endif
#if defined(__SANITIZE_ADDRESS__)
#define TASK_ASAN
#endif
#ifdef TASK_ASAN
#include <sanitizer/common_interface_defs.h>
#endif

typedef struct TaskStack {
  mco_coro *coroutine;
  void *mapping;
  size_t mapping_size;
  void (*entry)(void *);
  void *argument;
#ifdef TASK_ASAN
  void *fake_stack, *caller_fake_stack;
  const void *caller_bottom;
  size_t caller_size;
#endif
} TaskStack;

static void task_stack_entry(mco_coro *co) {
  TaskStack *stack = mco_get_user_data(co);
#ifdef TASK_ASAN
  __sanitizer_finish_switch_fiber(stack->fake_stack,
    &stack->caller_bottom, &stack->caller_size);
#endif
  stack->entry(stack->argument);
#ifdef TASK_ASAN
  __sanitizer_start_switch_fiber(NULL,
    stack->caller_bottom, stack->caller_size);
#endif
}

int x2c_task_stack_supported(void) { return 1; }

/* Large batch arrays bypass malloc's retained medium regions. */
void *x2c_task_jobs_new(size_t size) {
  if (size <= (size_t)sysconf(_SC_PAGESIZE)) return calloc(1, size);
  void *jobs = mmap(NULL, size, PROT_READ | PROT_WRITE,
    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  return jobs == MAP_FAILED ? NULL : jobs;
}

void x2c_task_jobs_free(void *jobs, size_t size) {
  if (!jobs) return;
  if (size <= (size_t)sysconf(_SC_PAGESIZE)) free(jobs);
  else munmap(jobs, size);
}

void *x2c_task_stack_new(void (*entry)(void *), void *argument, size_t size) {
  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  size = (size + page - 1) / page * page;
  mco_desc desc = mco_desc_init(task_stack_entry, size);
  /* The stack is external; retain only minicoro's control-record prefix. */
  desc.coro_size -= desc.stack_size;
  TaskStack *stack = calloc(1, sizeof(*stack));
  if (!stack) return NULL;
  stack->coroutine = calloc(1, desc.coro_size);
  if (!stack->coroutine) { free(stack); return NULL; }
  stack->mapping_size = size + page;
  stack->mapping = mmap(NULL, stack->mapping_size, PROT_NONE,
    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (stack->mapping == MAP_FAILED) {
    free(stack->coroutine);
    free(stack);
    return NULL;
  }
  desc.stack_base = (char *)stack->mapping + page;
  if (mprotect(desc.stack_base, size, PROT_READ | PROT_WRITE)) {
    int saved = errno;
    munmap(stack->mapping, stack->mapping_size);
    free(stack->coroutine);
    free(stack);
    errno = saved;
    return NULL;
  }
  stack->entry = entry;
  stack->argument = argument;
  desc.user_data = stack;
  if (mco_init(stack->coroutine, &desc) != MCO_SUCCESS) abort();
  return stack;
}

void x2c_task_stack_resume(void *value) {
  TaskStack *stack = value;
#ifdef TASK_ASAN
  __sanitizer_start_switch_fiber(&stack->caller_fake_stack,
    stack->coroutine->stack_base, stack->coroutine->stack_size);
#endif
  if (mco_resume(stack->coroutine) != MCO_SUCCESS) abort();
#ifdef TASK_ASAN
  __sanitizer_finish_switch_fiber(stack->caller_fake_stack, NULL, NULL);
#endif
}

void x2c_task_stack_yield(void *value) {
  TaskStack *stack = value;
#ifdef TASK_ASAN
  __sanitizer_start_switch_fiber(&stack->fake_stack,
    stack->caller_bottom, stack->caller_size);
#endif
  if (mco_yield(stack->coroutine) != MCO_SUCCESS) abort();
#ifdef TASK_ASAN
  __sanitizer_finish_switch_fiber(stack->fake_stack,
    &stack->caller_bottom, &stack->caller_size);
#endif
}

unsigned long x2c_task_stack_low(void *value) {
  TaskStack *stack = value;
  return (unsigned long)stack->coroutine->stack_base;
}

void x2c_task_stack_free(void *value) {
  TaskStack *stack = value;
  if (!stack) return;
  if (mco_uninit(stack->coroutine) != MCO_SUCCESS) abort();
  munmap(stack->mapping, stack->mapping_size);
  free(stack->coroutine);
  free(stack);
}
#else
int x2c_task_stack_supported(void) { return 0; }
void *x2c_task_jobs_new(size_t size) { (void)size; return NULL; }
void x2c_task_jobs_free(void *jobs, size_t size) { (void)size; free(jobs); }
void *x2c_task_stack_new(void (*entry)(void *), void *argument, size_t size) {
  (void)entry; (void)argument; (void)size;
  return NULL;
}
void x2c_task_stack_resume(void *value) { (void)value; abort(); }
void x2c_task_stack_yield(void *value) { (void)value; abort(); }
unsigned long x2c_task_stack_low(void *value) { (void)value; return 0; }
void x2c_task_stack_free(void *value) { (void)value; }
#endif
