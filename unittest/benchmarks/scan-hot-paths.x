/*  scan-hot-paths.x -- focused scanner operation timings */


#include <stdint.h>
#include <time.h>

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}


static void result(const char *name, uint64_t elapsed, int count) {
  printf("%s,%.3f\n", name, (double) elapsed / count);
}


int main(void) {
  int fast_count = 2000000, mixed_count = 500000;
  volatile long sink = 0;
  char ident[] = "scanner_identifier ";
  char keyword[] = "continue ";
  char decimal[] = "123456789;";
  char hex[] = "0x1abcdefUL;";
  char segment[] = "scanner segment text$";
  char same_line[] = "scanner_identifier";
  char multi_line[] = "alpha\nbeta\ngamma\n";
  uint64_t start;

  scan_keyword(ident);
  scan_keyword(keyword);

  start = now_ns();
  for (int i = 0; i < fast_count; i++) sink += scan_identifier(ident);
  result("identifier", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < fast_count; i++) sink += scan_keyword(keyword);
  result("keyword-hit", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < fast_count; i++) sink += scan_keyword(ident);
  result("keyword-miss", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < fast_count; i++) sink += scan_number(decimal);
  result("number-decimal", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < fast_count; i++) sink += scan_number(hex);
  result("number-hex", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < fast_count; i++) sink += scan_string_segment(segment);
  result("string-segment", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < fast_count; i++) {
    int line = 1, col = 1;
    scan_next_line_col(same_line, 18, &line, &col);
    sink += line + col;
  }
  result("line-col-single", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < fast_count; i++) {
    int line = 1, col = 1;
    scan_next_line_col(multi_line, 17, &line, &col);
    sink += line + col;
  }
  result("line-col-multi", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < mixed_count; i++) {
    int line = 1, col = 1;
    sink += scan_identifier(ident);
    sink += scan_keyword(keyword);
    sink += scan_keyword(ident);
    sink += scan_number(decimal);
    sink += scan_number(hex);
    sink += scan_string_segment(segment);
    scan_next_line_col(same_line, 18, &line, &col);
    sink += line + col;
  }
  result("weighted-mix", now_ns() - start, mixed_count);

  return sink == 0;
}
