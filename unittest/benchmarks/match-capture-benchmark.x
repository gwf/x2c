/*  match-capture-benchmark.x -- positional Match acceptance timings */


#include "match-recursive.x"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

typedef uint64_t (*DispatchFn)(List);

static volatile uint64_t benchmark_sink;
static DispatchFn volatile dispatch_target;

static uint64_t _now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

static uint64_t _mix(uint64_t hash, uint64_t value) {
  hash ^= value + 0x9e3779b97f4a7c15ULL + (hash << 6) + (hash >> 2);
  return hash;
}

static uint64_t _capture_hash(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  uint64_t hash = 0x63617074757265ULL;
  for (int i = 0; i < layout.binder_count; i++)
    if (captures.has(i))
      hash = _mix(hash, captures.values[i].u64);
  return hash;
}

static uint64_t _binding_hash(MatchCaptureLayout layout, List bindings) {
  uint64_t hash = 0x63617074757265ULL;
  for (int i = 0; i < layout.binder_count; i++)
    hash = _mix(hash, bindings.assoc(layout.binders[i]).u64);
  return hash;
}

static uint64_t _local_hash(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  Var b0 = layout.binder_count > 0 ? captures.values[0] : void;
  Var b1 = layout.binder_count > 1 ? captures.values[1] : void;
  Var b2 = layout.binder_count > 2 ? captures.values[2] : void;
  Var b3 = layout.binder_count > 3 ? captures.values[3] : void;
  Var b4 = layout.binder_count > 4 ? captures.values[4] : void;
  Var b5 = layout.binder_count > 5 ? captures.values[5] : void;
  Var b6 = layout.binder_count > 6 ? captures.values[6] : void;
  Var b7 = layout.binder_count > 7 ? captures.values[7] : void;
  Var locals[8] = { b0, b1, b2, b3, b4, b5, b6, b7 };
  uint64_t hash = 0x63617074757265ULL;
  for (int i = 0; i < layout.binder_count; i++)
    hash = _mix(hash, locals[i].u64);
  return hash;
}

static void _result(
  const char *route, int binders, const char *outcome, const char *consumer,
  int iterations, uint64_t elapsed) {
  printf("%s,%d,%s,%s,%d,%llu\n",
         route, binders, outcome, consumer, iterations,
         (unsigned long long) elapsed);
}

static uint64_t _time_prepared_list(
  MatchPlan plan, MatchCaptureLayout layout, List input, int iterations,
  uint64_t *receipt) {
  uint64_t hash = 1, start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    List bindings = NULL;
    uint64_t value = plan.try_match(input, &bindings)
                   ? _binding_hash(layout, bindings) : 0xfeedULL;
    hash = _mix(hash, value);
  }
  *receipt = hash;
  benchmark_sink ^= hash;
  return _now_ns() - start;
}

static uint64_t _time_prepared_capture(
  MatchPlan plan, MatchCaptureLayout layout, List input, int iterations,
  int named_local, uint64_t *receipt) {
  Var values[8];
  MatchCaptureBuffer captures = { values, 0, 8 };
  uint64_t hash = 1, start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    int matched = plan.try_capture(input, &captures);
    uint64_t value = matched == 1
                   ? (named_local
                      ? _local_hash(layout, &captures)
                      : _capture_hash(layout, &captures))
                   : 0xfeedULL;
    hash = _mix(hash, value);
  }
  *receipt = hash;
  benchmark_sink ^= hash;
  return _now_ns() - start;
}

static uint64_t _time_recursive_capture(
  MatchCaptureLayout layout, Var pattern, List input, int iterations,
  uint64_t *receipt) {
  Var values[8];
  MatchCaptureBuffer captures = { values, 0, 8 };
  uint64_t hash = 1, start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    int matched = match_recursive_try_capture(
      layout, input, &captures
    );
    uint64_t value = matched == 1
                   ? _capture_hash(layout, &captures) : 0xfeedULL;
    hash = _mix(hash, value);
  }
  *receipt = hash;
  benchmark_sink ^= hash;
  return _now_ns() - start;
}

static void _match_lane(
  int binders, Var pattern, List hit, List miss, int iterations, int reverse) {
  MatchPlan plan = MatchPlan.prepare(pattern);
  MatchCaptureLayout layout = MatchCaptureLayout.analyze(pattern);
  if (!plan || plan.status != MACHINE_PREPARED || !layout) exit(2);
  List inputs[2] = { hit, miss };
  const char *outcomes[2] = { "hit", "miss" };
  for (int lane = 0; lane < 2; lane++) {
    List input = inputs[lane];
    uint64_t list_receipt, capture_receipt;
    uint64_t local_receipt, recursive_receipt;
    uint64_t list_ns, capture_ns, local_ns, recursive_ns;
    if (reverse) {
      recursive_ns = _time_recursive_capture(
        layout, pattern, input, iterations, &recursive_receipt
      );
      local_ns = _time_prepared_capture(
        plan, layout, input, iterations, 1, &local_receipt
      );
      capture_ns = _time_prepared_capture(
        plan, layout, input, iterations, 0, &capture_receipt
      );
      list_ns = _time_prepared_list(
        plan, layout, input, iterations, &list_receipt
      );
    }
    else {
      list_ns = _time_prepared_list(
        plan, layout, input, iterations, &list_receipt
      );
      capture_ns = _time_prepared_capture(
        plan, layout, input, iterations, 0, &capture_receipt
      );
      local_ns = _time_prepared_capture(
        plan, layout, input, iterations, 1, &local_receipt
      );
      recursive_ns = _time_recursive_capture(
        layout, pattern, input, iterations, &recursive_receipt
      );
    }
    if (list_receipt != capture_receipt ||
        list_receipt != local_receipt ||
        list_receipt != recursive_receipt)
      exit(3);
    _result("prepared", binders, outcomes[lane], "list-assoc",
            iterations, list_ns);
    _result("prepared", binders, outcomes[lane], "capture-index",
            iterations, capture_ns);
    _result("prepared", binders, outcomes[lane], "named-local",
            iterations, local_ns);
    _result("recursive", binders, outcomes[lane], "capture-index",
            iterations, recursive_ns);
    reverse = !reverse;
  }
  plan.free();
  layout.free();
}

static uint64_t _dispatch_if(List input) {
  Var (tag, value) = input;
  if (tag == <t0> && input.len() == 3) return value.u64;
  if (tag == <t1> && input.len() == 3) return value.u64;
  if (tag == <t2> && input.len() == 3) return value.u64;
  if (tag == <t3> && input.len() == 3) return value.u64;
  if (tag == <t4> && input.len() == 3) return value.u64;
  if (tag == <t5> && input.len() == 3) return value.u64;
  if (tag == <t6> && input.len() == 3) return value.u64;
  if (tag == <t7> && input.len() == 3) return value.u64;
  return 0xfeedULL;
}

static uint64_t _dispatch_match(List input) {
  match (input) {
    case %((!set t0 t1 t2 t3 t4 t5 t6 t7) ?value ?): return value.u64;
  }
  return 0xfeedULL;
}

static uint64_t _time_dispatch(
  DispatchFn fn, List *inputs, int input_count, int iterations,
  uint64_t *receipt) {
  uint64_t hash = 1;
  dispatch_target = fn;
  DispatchFn target = dispatch_target;
  uint64_t start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    List input = inputs[i % input_count];
    hash = _mix(hash, target(input));
  }
  *receipt = hash;
  benchmark_sink ^= hash;
  return _now_ns() - start;
}

static void _dispatch_lane(
  const char *outcome, List *inputs, int input_count, int iterations,
  int reverse) {
  uint64_t if_receipt, match_receipt, if_ns, match_ns;
  if (reverse) {
    match_ns = _time_dispatch(
      _dispatch_match, inputs, input_count, iterations, &match_receipt
    );
    if_ns = _time_dispatch(
      _dispatch_if, inputs, input_count, iterations, &if_receipt
    );
  }
  else {
    if_ns = _time_dispatch(
      _dispatch_if, inputs, input_count, iterations, &if_receipt
    );
    match_ns = _time_dispatch(
      _dispatch_match, inputs, input_count, iterations, &match_receipt
    );
  }
  if (if_receipt != match_receipt) exit(4);
  _result("dispatch", 8, outcome, "direct-if", iterations, if_ns);
  _result("dispatch", 8, outcome, "source-match", iterations, match_ns);
}

static void _check_captures(void) {
  MatchCaptureLayout repeated =
    MatchCaptureLayout.analyze(%(same ?x ?x));
  Var values[3] = { <old0>, <old1>, <old2> };
  MatchCaptureBuffer captures = { values, 0x55UL, 3 };
  if (match_recursive_try_capture(
        repeated, %(same 7 8), &captures) != 0 ||
      values[0] != <old0> || captures.present != 0x55UL)
    exit(5);
  repeated.free();

  MatchCaptureLayout star =
    MatchCaptureLayout.analyze(%(*prefix pivot ?last));
  if (match_recursive_try_capture(
        star, %(a b pivot c), &captures) != 1 ||
      values[0].list() != %(a b) || values[1] != <c>)
    exit(5);
  star.free();

  MatchCaptureLayout alternatives = MatchCaptureLayout.analyze(
    %(!or (left ?left) (right ?right))
  );
  if (match_recursive_try_capture(
        alternatives, %(right 9), &captures) != 1 ||
      MatchCaptureBuffer.has(&captures, 0) ||
      !MatchCaptureBuffer.has(&captures, 1) || values[1] != 9)
    exit(5);
  alternatives.free();
}

int main(int argc, char **argv) {
  int iterations = argc > 1 ? atoi(argv[1]) : 100000;
  int sample = argc > 2 ? atoi(argv[2]) : 0;
  _check_captures();

  List miss = %(miss 10 20 30 40 50 60 70 80);
  _match_lane(0, %(tag), %(tag), miss, iterations, sample & 1);
  _match_lane(1, %(tag ?b0), %(tag 10), miss, iterations, !(sample & 1));
  _match_lane(2, %(tag ?b0 ?b1), %(tag 10 20), miss,
              iterations, sample & 1);
  _match_lane(4, %(tag ?b0 ?b1 ?b2 ?b3),
              %(tag 10 20 30 40), miss, iterations, !(sample & 1));
  _match_lane(
    8, %(tag ?b0 ?b1 ?b2 ?b3 ?b4 ?b5 ?b6 ?b7),
    %(tag 10 20 30 40 50 60 70 80), miss,
    iterations, sample & 1
  );

  List first[1] = { %(t0 42 payload) };
  List last[1] = { %(t7 42 payload) };
  List absent[1] = { %(miss 42 payload) };
  List mixed[16] = {
    %(t0 42 payload), %(t7 42 payload),
    %(t3 42 payload), %(t4 42 payload),
    %(t6 42 payload), %(t1 42 payload),
    %(t5 42 payload), %(t2 42 payload),
    %(miss 42 payload), %(miss 42 payload),
    %(miss 42 payload), %(miss 42 payload),
    %(miss 42 payload), %(miss 42 payload),
    %(miss 42 payload), %(miss 42 payload)
  };
  _dispatch_lane("first", first, 1, iterations, sample & 1);
  _dispatch_lane("last", last, 1, iterations, !(sample & 1));
  _dispatch_lane("miss", absent, 1, iterations, sample & 1);
  _dispatch_lane("mixed", mixed, 16, iterations, !(sample & 1));
  return benchmark_sink == UINT64_MAX;
}
