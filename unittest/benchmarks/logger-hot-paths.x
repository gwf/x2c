/*  logger-hot-paths.x -- focused Logger timings */


#include <stdint.h>
#include <time.h>

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void result(const char *name, uint64_t elapsed, long operations) {
  printf("%s,%.3f\n", name, (double) elapsed / operations);
}

static void discard_emit(Logger logger, const LogEvent *event, Var data) {
  (void) logger;
  (void) event;
  (void) data;
}

static void rejected_dynamic(Logger logger, int value) {
  if (!logger.should_log(<debug>, <bench>)) return;
  logger.debug(<bench>, %((value $value) (guard ${value + 1})));
}

int main(void) {
  uint64_t start;
  volatile unsigned long guard = 0;
  List fields = %((value 17) (message "benchmark"));

  Logger filtered = Logger.new(<info>);
  filtered.add_sink(discard_emit, NULL, nil);
  int filtered_count = 200000;
  start = now_ns();
  for (int i = 0; i < filtered_count; i++) {
    rejected_dynamic(filtered, i);
    guard += i;
  }
  result("filtered-dynamic", now_ns() - start, filtered_count);

  Logger direct = Logger.new(<trace>);
  direct.add_sink(discard_emit, NULL, nil);
  int direct_count = 200000;
  start = now_ns();
  for (int i = 0; i < direct_count; i++) {
    direct.info(<bench>, fields);
    guard += i & 1;
  }
  result("noop-sink", now_ns() - start, direct_count);

  direct.add_sink(discard_emit, NULL, nil);
  int fanout_count = 100000;
  start = now_ns();
  for (int i = 0; i < fanout_count; i++) {
    direct.info(<bench>, fields);
    guard += i & 1;
  }
  result("two-sink-fanout", now_ns() - start, fanout_count);

  File file = tmpfile();
  Logger text = Logger.new(<trace>);
  text.add_file_sink(file);
  text.info(<bench>, fields);
  int text_count = 2000;
  start = now_ns();
  for (int i = 0; i < text_count; i++) {
    text.info(<bench>, fields);
    guard += i & 1;
  }
  result("file-text", now_ns() - start, text_count);

  filtered.free();
  direct.free();
  text.free();
  fclose(file);
  return guard == 0;
}
