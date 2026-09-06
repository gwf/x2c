/*  thread-notify.x -- wake one libuv loop from an x2c Thread */

import "libuv" with UvAsync, UvLoop;

#include <stdio.h>

typedef struct NotifyWork {
  UvAsync async;
  int left;
  int right;
} NotifyWork;

typedef struct NotifyState {
  Thread worker;
  String result;
} NotifyState;

static Var add(const void *input, size_t input_size) {
  if (input_size != sizeof(NotifyWork)) {
    raise %(bad-arg (owner "thread-notify worker"));
  }
  const NotifyWork *work = input;
  String result = %"${work.left} + ${work.right} = ${work.left + work.right}";
  work.async.send();
  return result;
}

static void receive(UvAsync async, Var value) {
  NotifyState *state = value.pointer();
  state.result = state.worker.join();
  state.worker.free();
  state.worker = NULL;
  async.stop();
}

int main(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  NotifyState state = { 0 };
  UvAsync async = loop.async(Var.new(<p48>, &state), receive);
  NotifyWork work = { async, 19, 23 };
  state.worker = Thread.start(add, &work, sizeof(work));

  loop.run(UV_RUN_DEFAULT);
  printf("worker result: %s\n", state.result);
  return 0;
}
