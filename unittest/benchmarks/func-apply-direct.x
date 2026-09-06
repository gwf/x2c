#include "x2c.x"

#include <stdio.h>
#include <time.h>

static Var identity(Var value) {
  return value;
}

typedef struct CapturedIdentityContext {
  Var value;
} CapturedIdentityContext;

static Var captured_identity(Func fn, const FuncArg *argv) {
  (void) argv;
  const CapturedIdentityContext *context = fn.context();
  return context.value;
}

static long long elapsed_ns(struct timespec start, struct timespec stop) {
  return (stop.tv_sec - start.tv_sec) * 1000000000LL +
         stop.tv_nsec - start.tv_nsec;
}

int main(void) {
  Func uncaptured = identity;
  CapturedIdentityContext context = { Var.new(<i32>, 7) };
  Func captured = Func.new_context(
    captured_identity, %((func (("Var"))) "Var"),
    &context, sizeof context
  );
  FuncArg argv[1] = { FuncArg.value(Var.new(<i32>, 7)) };
  Var result = void;
  for (int i = 0; i < 10000; i++)
    result = Func.apply(uncaptured, 1, argv);
  struct timespec start, stop;
  clock_gettime(CLOCK_MONOTONIC, &start);
  for (int i = 0; i < 1000000; i++)
    result = Func.apply(uncaptured, 1, argv);
  clock_gettime(CLOCK_MONOTONIC, &stop);
  if (result.integer() != 7) return 1;
  printf("uncaptured,%lld\n", elapsed_ns(start, stop));
  for (int i = 0; i < 10000; i++)
    result = Func.apply(captured, 1, argv);
  clock_gettime(CLOCK_MONOTONIC, &start);
  for (int i = 0; i < 1000000; i++)
    result = Func.apply(captured, 1, argv);
  clock_gettime(CLOCK_MONOTONIC, &stop);
  if (result.integer() != 7) return 1;
  printf("captured,%lld\n", elapsed_ns(start, stop));
  return 0;
}
