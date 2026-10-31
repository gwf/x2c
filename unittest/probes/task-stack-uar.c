/* Optional ASan use-after-return regression; run with run-task-backend.sh. */
#define MCO_LOG(message) ((void)0)
#include "../../lib/task/stack.c"
#include <assert.h>

typedef struct {
  TaskStack *stack;
  unsigned char *parked;
  int yields, finished;
} Probe;

static void entry(void *value) {
  Probe *probe = value;
  mco_coro *co = probe->stack->coroutine;
  void *base = co->stack_base;
  co->stack_base = (char *)base + co->stack_size;
  assert(mco_yield(co) == MCO_STACK_OVERFLOW);
  co->stack_base = base;
  size_t magic = co->magic_number;
  co->magic_number = 0;
  assert(mco_yield(co) == MCO_STACK_OVERFLOW);
  co->magic_number = magic;

  unsigned char local[32] = {17, 29};
  probe->parked = local;
  for (int i = 0; i < 3; i++) {
    probe->yields++;
    x2c_task_stack_yield(probe->stack);
    assert(local[0] == 18 + i && local[1] == 29);
  }
  probe->parked = NULL;
  probe->finished = 1;
}

int main(void) {
  size_t sizes[] = {32768, 65537, 8u << 20};
  for (size_t i = 0; i < sizeof(sizes) / sizeof(*sizes); i++) {
    Probe probe = {0};
    probe.stack = x2c_task_stack_new(entry, &probe, sizes[i]);
    assert(probe.stack);
    for (int turn = 0; turn < 3; turn++) {
      x2c_task_stack_resume(probe.stack);
      assert(mco_status(probe.stack->coroutine) == MCO_SUSPENDED);
      assert(probe.yields == turn + 1 && !probe.finished);
      assert(probe.parked && probe.parked[0] == 17 + turn);
      probe.parked[0]++;
    }
    x2c_task_stack_resume(probe.stack);
    assert(mco_status(probe.stack->coroutine) == MCO_DEAD);
    assert(probe.finished && !probe.parked);
    x2c_task_stack_free(probe.stack);
  }
  return 0;
}
