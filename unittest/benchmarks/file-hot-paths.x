/*  file-hot-paths.x -- focused File read-path timings */


#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}


static void line_result(
  const char *name, uint64_t elapsed, int count, ScopeStats before,
  ScopeStats after) {
  printf("%s-ns-per-line,%.3f\n", name, (double) elapsed / count);
  printf("%s-allocs-per-line,%.3f\n", name,
         (double) (after.allocation_calls - before.allocation_calls) / count);
  printf("%s-reallocs-per-line,%.3f\n", name,
         (double) (after.reallocation_calls - before.reallocation_calls) /
           count);
  printf("%s-frees-per-line,%.3f\n", name,
         (double) (after.free_calls - before.free_calls) / count);
}


static void benchmark_lines(const char *name, File file, int count) {
  volatile unsigned long sink = 0;
  ScopeStats before = Scope.stats();
  uint64_t start = now_ns();
  foreach(String line, file) sink += line.len();
  uint64_t elapsed = now_ns() - start;
  ScopeStats after = Scope.stats();
  line_result(name, elapsed, count, before, after);
  if (!sink) abort();
}


static File short_lines(int count, int unique) {
  File file = tmpfile();
  if (!file) abort();
  for (int i = 0; i < count; i++)
    fprintf(file, unique ? "line-%08d-value\n" : "repeated-value\n", i);
  rewind(file);
  return file;
}


static File long_lines(int count) {
  File file = tmpfile();
  if (!file) abort();
  char line[2049];
  memset(line, 'x', sizeof(line) - 2);
  line[sizeof(line) - 2] = '\n';
  line[sizeof(line) - 1] = '\0';
  for (int i = 0; i < count; i++) fputs(line, file);
  rewind(file);
  return file;
}


static void benchmark_whole_file(void) {
  File file = tmpfile();
  if (!file) abort();
  int bytes = 1024 * 1024;
  char chunk[4096];
  memset(chunk, 'w', sizeof(chunk));
  for (int written = 0; written < bytes; written += sizeof(chunk))
    fwrite(chunk, 1, sizeof(chunk), file);
  rewind(file);
  ScopeStats before = Scope.stats();
  uint64_t start = now_ns();
  String result = file.string();
  uint64_t elapsed = now_ns() - start;
  ScopeStats after = Scope.stats();
  printf("whole-file-ns-per-byte,%.3f\n", (double) elapsed / bytes);
  printf("whole-file-allocs,%zu\n",
         after.allocation_calls - before.allocation_calls);
  printf("whole-file-reallocs,%zu\n",
         after.reallocation_calls - before.reallocation_calls);
  if (result.len() != bytes) abort();
  file.close();
}


int main(void) {
  int short_count = 20000;
  File unique = short_lines(short_count, 1);
  benchmark_lines("short-unique", unique, short_count);
  unique.close();

  File repeated = short_lines(short_count, 0);
  benchmark_lines("short-repeated", repeated, short_count);
  repeated.close();

  int long_count = 2000;
  File long_input = long_lines(long_count);
  benchmark_lines("long-repeated", long_input, long_count);
  long_input.close();

  benchmark_whole_file();
  return 0;
}
