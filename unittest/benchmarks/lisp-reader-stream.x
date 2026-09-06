/*  lisp-reader-stream.x -- fixed-source Lisp reader scaling */


#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>


static uint64_t _now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}


static String _single_form(int count) {
  return String.new("'(") + String.new("1 ").repeat(count) + ")";
}


static String _many_forms(int count) {
  return String.new("1 ").repeat(count);
}


static void _run(const char *lane, int count, String source) {
  Lisp lisp = Lisp.new_bare();
  Lisp.eval_string(lisp, "0");
  uint64_t start = _now_ns();
  Var result = Lisp.eval_string(lisp, source);
  uint64_t elapsed = _now_ns() - start;
  if (result is void) {
    fprintf(stderr, "benchmark produced void\n");
    exit(1);
  }
  printf("%s,%d,%llu\n", lane, count, (unsigned long long) elapsed);
  Lisp.destroy(lisp);
}


int main(void) {
  _run("single", 4000, _single_form(4000));
  _run("many", 2000, _many_forms(2000));
  _run("many", 4000, _many_forms(4000));
  return 0;
}
