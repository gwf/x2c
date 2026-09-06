/*  lisp-auto-benchmark.x -- Lisp AUTO acceptance benchmark

    Measures second-call AUTO at the real private _apply boundary.
    Both arms evaluate the identical pre-read `(brancher 7)` expression
    through public `Lisp.eval` and cross the identical installed native
    `add` Func exactly once per iteration; the evaluator arm uses the
    runtime-internal forced-evaluator control, and the prepared arm
    includes AUTO lookup, guards, machine setup, execution, and
    cleanup.  The retained gate is the median paired
    prepared_hit / evaluator_hit at most 0.90 across 21 fresh
    processes.  Transition, third-call, and nil lanes stay visible
    without reweighting the gate. */


#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile uint64_t benchmark_sink;
static long native_add_calls;

static void _fail(const char *what) {
  fprintf(stderr, "LISP-AUTO-BENCHMARK-FAIL,%s\n", what);
  exit(1);
}

static void _check(int ok, const char *what) {
  if (!ok) _fail(what);
}

static uint64_t _now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

static Var _native_add(Var a, Var b) {
  native_add_calls++;
  return Var.binary(a, <+>, b);
}

static Lisp _session(void) {
  Lisp lisp = Lisp.new_bare();
  Func add = Func.new(_native_add,
                      %((func (("Var") ("Var"))) "Var"));
  _check(add != NULL, "native-add");
  Lisp.set_global(lisp, "add", Func.var(add));
  Lisp.eval_string(lisp, "(def helper (lambda (x bias) (add x bias)))");
  Lisp.eval_string(lisp,
    "(def make-brancher (lambda (bias) (lambda (x) (cond (x (helper x bias)) (1 bias)))))");
  Lisp.eval_string(lisp, "(def brancher (make-brancher 5))");
  return lisp;
}

static Var _read_form(Lisp lisp, const char *text) {
  unsigned cursor = 0;
  Var form = void;
  _check(Lisp.read(lisp, String.new(text), &cursor, &form) ==
         <value>, "read-form");
  return form;
}

static uint64_t _time_lane(
  Lisp lisp, Var form, int iterations, long expected, const char *what) {
  long before = native_add_calls;
  uint64_t hash = 0x4c414e45ULL, start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    Var result = Lisp.eval(lisp, form);
    hash ^= result.u64;
  }
  uint64_t elapsed = _now_ns() - start;
  benchmark_sink ^= hash;
  if (expected >= 0) _check(native_add_calls - before == expected, what);
  return elapsed;
}

static void _check_mode(void) {
  Lisp lisp = _session();
  Var hit = _read_form(lisp, "(brancher 7)");
  Var nil_call = _read_form(lisp, "(brancher ())");
  for (int i = 0; i < 3; i++)
    _check(Var.integer(Lisp.eval(lisp, hit)) == 12, "hit-result");
  for (int i = 0; i < 3; i++)
    _check(Var.integer(Lisp.eval(lisp, nil_call)) == 5, "nil-result");
  LispAutoStats stats = Lisp.auto_stats(lisp);
  _check(stats.machine_entries >= 4, "machine-entries");
  _check(stats.published == 2, "published-programs");
  _check(stats.machine_errors == 0, "machine-errors");
  printf("check,auto-program-bytes,%ld\n", stats.program_bytes);
  Lisp.destroy(lisp);

  // The forced-evaluator arm is semantically identical and machine
  // free, and both arms cross the same native exactly once per call.
  Lisp forced = _session();
  Lisp.auto_disable(forced, 1);
  Var forced_hit = _read_form(forced, "(brancher 7)");
  long before = native_add_calls;
  for (int i = 0; i < 3; i++)
    _check(Var.integer(Lisp.eval(forced, forced_hit)) == 12, "forced-result");
  _check(native_add_calls - before == 3, "forced-native-parity");
  _check(Lisp.auto_stats(forced).machine_entries == 0, "forced-machine-free");
  Lisp.destroy(forced);
  printf("check,ok\n");
}

static void _time_mode(int sample) {
  int iterations = 10000, evaluator_first = sample % 2 == 1;
  printf("sample,%d\n", sample);

  Lisp evaluator = _session();
  Lisp.auto_disable(evaluator, 1);
  Var evaluator_hit = _read_form(evaluator, "(brancher 7)");
  Var evaluator_nil = _read_form(evaluator, "(brancher ())");

  Lisp prepared = _session();
  Var prepared_hit = _read_form(prepared, "(brancher 7)");
  Var prepared_nil = _read_form(prepared, "(brancher ())");

  // First evaluator call, AUTO transition, and third prepared call
  // stay visible; none of them reweights the steady gate.
  uint64_t start = _now_ns();
  _check(Var.integer(Lisp.eval(prepared, prepared_hit)) == 12, "first-call");
  uint64_t first_ns = _now_ns() - start;
  start = _now_ns();
  _check(Var.integer(Lisp.eval(prepared, prepared_hit)) == 12,
         "transition-call");
  uint64_t transition_ns = _now_ns() - start;
  start = _now_ns();
  _check(Var.integer(Lisp.eval(prepared, prepared_hit)) == 12, "third-call");
  uint64_t third_ns = _now_ns() - start;
  _check(Lisp.auto_stats(prepared).machine_entries == 3, "prepared-warmup");

  uint64_t evaluator_ns, prepared_ns;
  if (evaluator_first) {
    evaluator_ns = _time_lane(evaluator, evaluator_hit, iterations,
                              iterations, "evaluator-native-count");
    prepared_ns = _time_lane(prepared, prepared_hit, iterations,
                             iterations, "prepared-native-count");
  }
  else {
    prepared_ns = _time_lane(prepared, prepared_hit, iterations,
                             iterations, "prepared-native-count");
    evaluator_ns = _time_lane(evaluator, evaluator_hit, iterations,
                              iterations, "evaluator-native-count");
  }
  uint64_t evaluator_nil_ns =
    _time_lane(evaluator, evaluator_nil, iterations, 0,
               "evaluator-nil-natives");
  uint64_t prepared_nil_ns =
    _time_lane(prepared, prepared_nil, iterations, 0, "prepared-nil-natives");
  _check(Lisp.auto_stats(prepared).machine_errors == 0, "prepared-clean");
  _check(Lisp.auto_stats(evaluator).machine_entries == 0, "evaluator-forced");

  printf("lane,first-evaluator,1,%llu\n", (unsigned long long) first_ns);
  printf("lane,auto-transition,1,%llu\n", (unsigned long long) transition_ns);
  printf("lane,third-prepared,1,%llu\n", (unsigned long long) third_ns);
  printf("lane,evaluator-hit,%d,%llu\n", iterations,
         (unsigned long long) evaluator_ns);
  printf("lane,prepared-hit,%d,%llu\n", iterations,
         (unsigned long long) prepared_ns);
  printf("lane,evaluator-nil,%d,%llu\n", iterations,
         (unsigned long long) evaluator_nil_ns);
  printf("lane,prepared-nil,%d,%llu\n", iterations,
         (unsigned long long) prepared_nil_ns);

  Lisp forced_check = prepared;
  (void) forced_check;
  Lisp.destroy(prepared);
  Lisp.destroy(evaluator);
}

int main(int argc, char **argv) {
  if (argc >= 2 && !strcmp(argv[1], "--check")) {
    _check_mode();
    return 0;
  }
  if (argc >= 3 && !strcmp(argv[1], "--time")) {
    _time_mode(atoi(argv[2]));
    return 0;
  }
  fprintf(stderr, "usage: %s --check | --time SAMPLE\n", argv[0]);
  return 2;
}
