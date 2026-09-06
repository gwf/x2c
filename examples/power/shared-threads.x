/*  threads.x -- isolated workers with shared coordinated state */

#include <stdio.h>

typedef struct Work {
  String name;
  int iterations;
  int *counter;
  Mutex mutex;
} Work;

static Var count(const void *input, size_t input_size) {
  const Work *work = input;
  if (input_size != sizeof(Work))
    raise %(bad-arg (owner "count worker"));

  for (int i = 0; i < work.iterations; i++) {
    String scratch = %"${work.name}-$i";
    List garbage = %(iteration $i scratch $scratch);
    (void) garbage;

    work.mutex.lock();
    (*work.counter)++;
    work.mutex.unlock();
  }

  String message = %"${work.name} complete";
  log_info(<worker>, %((message $message)));
  Map result = %{
    name: ${work.name},
    message: $message
  };
  return result;
}

int main(void) {
  int counter = 0;
  Mutex mutex = Mutex.new();

  List events = nil;
  Logger logger = Logger.new(<info>);
  logger.add_memory_sink(&events);
  Logger previous = log_set_global_logger(logger);

  Work alpha = { "alpha", 1000, &counter, mutex };
  Work beta = { "beta", 1000, &counter, mutex };
  Thread alpha_thread = Thread.start(count, &alpha, sizeof(alpha));
  Thread beta_thread = Thread.start(count, &beta, sizeof(beta));

  Map alpha_result = alpha_thread.join();
  Map beta_result = beta_thread.join();

  printf("counter: %d\n", counter);
  printf("events: %zu\n", events.len());
  printf("alpha: %s\n", alpha_result[<message>].string());
  printf("beta: %s\n", beta_result[<message>].string());
  printf("parent strings reused: %s\n",
         alpha_result[<name>].string() == alpha.name &&
         beta_result[<name>].string() == beta.name ? "yes" : "no");

  log_set_global_logger(previous);
  alpha_thread.free();
  beta_thread.free();
  logger.free();
  mutex.free();
  return 0;
}
