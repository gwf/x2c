/*  test-thread.x -- Context-backed Thread tests */

#include "typed-array.x"
#include "typed-map.x"
#include "regex.x"
#include "test-support.x"
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <pthread.h>

typedef struct ThreadTestInput {
  int value;
  int iterations;
  int *counter;
  Mutex mutex;
  String ancestor_string;
  List ancestor_list;
  Map ancestor_map;
} ThreadTestInput;

typedef struct ThreadAlignedInput {
  uint64_t first;
  long double second;
} ThreadAlignedInput;

typedef struct ThreadJoinProbe {
  Thread target;
  atomic_int ready;
  atomic_int go;
  atomic_int release_target;
  atomic_int successes;
  atomic_int rejections;
} ThreadJoinProbe;

typedef struct ThreadJoinInput {
  ThreadJoinProbe *probe;
} ThreadJoinInput;

static Var _thread_aligned_input_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(ThreadAlignedInput)) return 0;
  if ((uintptr_t) input % _Alignof(max_align_t)) return 0;
  const ThreadAlignedInput *aligned = input;
  return aligned.first == UINT64_C(0x0123456789abcdef) &&
         aligned.second == 1234.5L;
}

static Var _thread_join_target_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(ThreadJoinInput)) return 0;
  const ThreadJoinInput *join_input = input;
  while (!atomic_load(&join_input.probe.release_target)) sched_yield();
  return 89;
}

static Var _thread_join_competitor_worker(
  const void *input, size_t input_size) {
  if (input_size != sizeof(ThreadJoinInput)) return 0;
  const ThreadJoinInput *join_input = input;
  ThreadJoinProbe *probe = join_input.probe;
  atomic_fetch_add(&probe.ready, 1);
  while (!atomic_load(&probe.go)) sched_yield();
  int rejected = 0;
  try {
    Var result = probe.target.join();
    if (result.integer() == 89) atomic_fetch_add(&probe.successes, 1);
  }
  catch %(bad-state *): rejected = 1;
  if (rejected) atomic_fetch_add(&probe.rejections, 1);
  return rejected ? 0 : 1;
}

static Var _thread_test_worker(const void *input, size_t input_size) {
  const ThreadTestInput *data = input;
  if (input_size != sizeof(ThreadTestInput))
    raise %(bad-arg (operation "thread test worker"));
  int caught = 0;
  try raise %(worker-loc);
  catch %(worker-loc): caught = 1;
  int matched = 0;
  List match_input = %(worker ${data.value});
  match (match_input) {
    case %(worker ?number): matched = number.int() == data.value;
  }
  if (data.mutex)
    log_info(<thread-tes>, %((value ${data.value})));

  for (int i = 0; i < data.iterations; i++) {
    String garbage = String.printf("worker-%d-%d", data.value, i);
    List cells = %(garbage $garbage value ${data.value});
    (void) cells;
    data.mutex.lock();
    (*data.counter)++;
    data.mutex.unlock();
  }

  Map result = {};
  result[<value>] = data.value;
  result[<caught>] = caught;
  result[<matched>] = matched;
  result[<ancestor-s>] = data.ancestor_string;
  result[<ancestor-l>] = data.ancestor_list;
  result[<ancestor-m>] = data.ancestor_map[<number>];
  result[<private-st>] = String.new("shared worker result");
  result[<wide>] = Var.box_long(0x123456789L);
  return result;
}

static Var _thread_error_worker(const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  raise %(worker-fai (detail "from worker"));
  return void;
}

static Var _thread_memory_log_worker(const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  String text = String.new("worker-private log value");
  log_info(<thread-mem>, %((text $text)));
  return 73;
}

static Var _thread_logged_error_worker(const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  Error.policy_set(<worker-log>, <log>);
  raise %(worker-log (detail "worker-private error value"));
  return 91;
}

static Var _thread_private_result_worker(
  const void *input, size_t input_size) {
  if (input_size != sizeof(int))
    raise %(bad-arg (operation "private result worker"));
  int value = *((const int *) input);
  String text = String.printf("sealed-worker-result-%d", value);
  return %((value $value) (text $text));
}

static Var _thread_packed_result_worker(const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  ArrayChar chars = ArrayChar.new();
  ArrayShort shorts = ArrayShort.new();
  ArrayInt ints = ArrayInt.new();
  ArrayLong longs = ArrayLong.new();
  ArrayFloat floats = ArrayFloat.new();
  ArrayDbl doubles = ArrayDbl.new();
  chars.push(4);
  shorts.push(40);
  ints.push(400);
  longs.push(4000000000L);
  floats.push(4.5f);
  doubles.push(40.25);

  MapIntInt integer_map = MapIntInt.new();
  MapLongDouble double_map = MapLongDouble.new();
  MapStringString string_map = MapStringString.new();
  integer_map.set(4, 16);
  double_map.set(4000000000L, 4.25);
  string_map.set(
    String.printf("thread-packed-key-%d", 41),
    String.printf("thread-packed-value-%d", 42)
  );
  string_map.set("", String.printf("thread-empty-key-%d", 43));
  string_map.set(String.printf("thread-empty-value-%d", 44), "");

  Array graph = [];
  graph.push(chars);
  graph.push(shorts);
  graph.push(ints);
  graph.push(longs);
  graph.push(floats);
  graph.push(doubles);
  graph.push(integer_map);
  graph.push(double_map);
  graph.push(string_map);
  graph.push(ints);
  return graph;
}

static Var _thread_recursive_export_worker(
  const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  ContextProbe probe = Scope.malloc(sizeof(struct ContextProbe));
  Array nested = [];
  nested.push(String.printf("recursive-worker-%d", 51));
  probe.value = nested;
  probe.exports = 0;
  probe.fail_at = 0;
  return Var.new(<ctxprobe>, probe);
}

static Var _thread_void_result_worker(const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  return void;
}

static Var _thread_private_error_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(int))
    raise %(bad-arg (operation "private error worker"));
  int value = *((const int *) input);
  String text = String.printf("sealed-worker-error-%d", value);
  List detail = %((text $text) (value $value));
  raise %(worker-pri (detail $detail));
  return void;
}

static Var _thread_wide_error_worker(const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  Var wide = Var.box_long(0x123456789L);
  raise %(worker-wid (value $wide));
  return void;
}

static Var _thread_failing_export_worker(
  const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  ContextProbe probe = Scope.malloc(sizeof(struct ContextProbe));
  probe.value = String.new("join export failure value");
  probe.exports = 0;
  probe.fail_at = 1;
  return Var.new(<ctxprobe>, probe);
}

static void thread_failed_start_does_not_freeze_registration(void) {
  x2c_descriptor_thread_start_begin();
  x2c_descriptor_thread_start_end(0);
  EXPECT_FALSE(x2c_descriptor_registration_frozen());
}

static void thread_input_size_overflow_is_size_limit(void) {
  char input = 0;
  int selected = 0;
  try Thread.start_raw(_thread_aligned_input_worker, &input, SIZE_MAX);
  catch %(size-limit): selected = 1;
  catch %(alloc-fail): selected = 2;
  EXPECT_INT_EQ(selected, 1);
}

static void thread_copies_input_at_maximum_alignment(void) {
  ThreadAlignedInput input = {
    UINT64_C(0x0123456789abcdef), 1234.5L
  };
  Thread thread = Thread.start_raw(
    _thread_aligned_input_worker, &input, sizeof(input)
  );
  EXPECT_INT_EQ(thread.join().integer(), 1);
  thread.free();
}

static void thread_rejects_one_of_two_concurrent_joins(void) {
  ThreadJoinProbe probe = { 0 };
  ThreadJoinInput input = { &probe };
  probe.target = Thread.start_raw(
    _thread_join_target_worker, &input, sizeof(input)
  );
  Thread first = Thread.start_raw(
    _thread_join_competitor_worker, &input, sizeof(input)
  );
  Thread second = Thread.start_raw(
    _thread_join_competitor_worker, &input, sizeof(input)
  );
  while (atomic_load(&probe.ready) != 2) sched_yield();
  atomic_store(&probe.go, 1);
  while (atomic_load(&probe.rejections) != 1) sched_yield();
  int early_free = 0;
  try probe.target.free();
  catch %(bad-state *): early_free = 1;
  EXPECT_TRUE(early_free);
  atomic_store(&probe.release_target, 1);
  int first_result = first.join().integer();
  int second_result = second.join().integer();
  EXPECT_INT_EQ(first_result + second_result, 1);
  EXPECT_INT_EQ(atomic_load(&probe.successes), 1);
  EXPECT_INT_EQ(atomic_load(&probe.rejections), 1);
  probe.target.free();
  first.free();
  second.free();
}

static void thread_workers_isolate_and_join_results(void) {
  int counter = 0;
  Mutex mutex = Mutex.new();
  File log_output = tmpfile();
  Logger logger = Logger.new(<info>);
  logger.add_file_sink(log_output);
  Logger previous_logger = log_set_global_logger(logger);
  String ancestor_string = String.new("parent immutable");
  List ancestor_list = %(parent immutable list);
  Map ancestor_map = {};
  ancestor_map[<number>] = 47;
  ThreadTestInput first = {
    11, 250, &counter, mutex, ancestor_string, ancestor_list, ancestor_map
  };
  ThreadTestInput second = {
    22, 250, &counter, mutex, ancestor_string, ancestor_list, ancestor_map
  };
  Thread a = Thread.start_raw(_thread_test_worker, &first, sizeof(first));
  Thread b = Thread.start_raw(_thread_test_worker, &second, sizeof(second));
  Map a_result = a.join();
  Map b_result = b.join();

  EXPECT_INT_EQ(counter, 500);
  EXPECT_INT_EQ(a_result[<value>].integer(), 11);
  EXPECT_INT_EQ(b_result[<value>].integer(), 22);
  EXPECT_INT_EQ(a_result[<caught>].integer(), 1);
  EXPECT_INT_EQ(b_result[<caught>].integer(), 1);
  EXPECT_INT_EQ(a_result[<matched>].integer(), 1);
  EXPECT_INT_EQ(b_result[<matched>].integer(), 1);
  EXPECT_PTR_EQ(a_result[<ancestor-s>].string(), ancestor_string);
  EXPECT_PTR_EQ(b_result[<ancestor-l>].list(), ancestor_list);
  EXPECT_INT_EQ(a_result[<ancestor-m>].integer(), 47);
  EXPECT_INT_EQ(b_result[<ancestor-m>].integer(), 47);
  EXPECT_PTR_EQ(
    a_result[<private-st>].string(),
    b_result[<private-st>].string()
  );
  EXPECT_INT_EQ(a_result[<wide>].long_value(), 0x123456789L);
  EXPECT_INT_EQ(b_result[<wide>].long_value(), 0x123456789L);
  logger.flush();
  EXPECT_TRUE(ftell(log_output) > 0);
  log_set_global_logger(previous_logger);
  a.free();
  b.free();
  logger.free();
  fclose(log_output);
  mutex.free();
}

static void thread_join_raises_worker_errors(void) {
  Thread thread = Thread.start_raw(_thread_error_worker, NULL, 0);
  int caught = 0, error_count = -1;
  try thread.join();
  catch %(join-fail (errors ?errors)): {
    caught = 1;
    if (errors is <list>) error_count = errors.list().len();
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(error_count, 1);
  thread.free();
}

static Var _thread_ignored_policy_worker(
  const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  Error.raise(<worker-ign>, NULL);
  return 42;
}

static void thread_ignored_policy_resumes_in_worker(void) {
  Error.policy_set(<worker-ign>, <ignore>);
  Thread thread = Thread.start_raw(_thread_ignored_policy_worker, NULL, 0);
  EXPECT_INT_EQ(thread.join().integer(), 42);
  thread.free();
}

/* Every shared cause transfers, so one raised in a worker leaves the callback
   whatever the starting thread's policy table says. */
static Var _thread_shared_cause_worker(const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  raise %(bad-state (operation "shared cause worker"));
  return 5;
}

static void thread_shared_cause_still_fails_join(void) {
  Thread thread = Thread.start_raw(_thread_shared_cause_worker, NULL, 0);
  int caught = 0, error_count = -1;
  try thread.join();
  catch %(join-fail (errors ?errors)): {
    caught = 1;
    if (errors is <list>) error_count = errors.list().len();
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(error_count, 1);
  thread.free();
}

static void thread_memory_sink_retains_worker_events(void) {
  List entries = nil;
  Logger logger = Logger.new(<trace>);
  logger.add_memory_sink(&entries);
  Logger previous = log_set_global_logger(logger);

  Thread message = Thread.start_raw(_thread_memory_log_worker, NULL, 0);
  EXPECT_INT_EQ(message.join().integer(), 73);
  List message_entry = entries.car();
  EXPECT_TRUE(message_entry[4].symbol() == <thread-mem>);
  EXPECT_STR_EQ(
    message_entry[5].list().assoc(<text>).string(),
    "worker-private log value"
  );

  /* A `<log>` policy resolves the cause inside the worker as it does here:
     the error is reported and the callback keeps its result. */
  Thread failure = Thread.start_raw(_thread_logged_error_worker, NULL, 0);
  EXPECT_INT_EQ(failure.join().integer(), 91);
  List error_entry = entries.car();
  EXPECT_TRUE(error_entry[4].symbol() == <err-report>);
  EXPECT_TRUE(
    error_entry[5].list().assoc(<code>).symbol() == <worker-log>
  );

  log_set_global_logger(previous);
  message.free();
  failure.free();
  logger.free();
}

static void thread_results_stay_private_until_join(void) {
  Pool root = Pool.current();
  size_t before = root.stats().interned;

  Context destination = Context.open_isolated_named("Thread join target");
  int value = 8675309;
  Thread thread = Thread.start_raw(
    _thread_private_result_worker, &value, sizeof(value)
  );
  List result = thread.join();
  EXPECT_INT_EQ(result.assoc(<value>).integer(), value);
  EXPECT_STR_EQ(
    result.assoc(<text>).string(), "sealed-worker-result-8675309"
  );
  thread.free();
  destination.close();

  EXPECT_INT_EQ(root.stats().interned, before);
}

static void thread_join_returns_void_worker_result(void) {
  Thread thread = Thread.start_raw(_thread_void_result_worker, NULL, 0);
  EXPECT_TRUE(thread.join() is void);
  thread.free();
}

static void thread_joins_nested_packed_containers(void) {
  Thread thread = Thread.start_raw(_thread_packed_result_worker, NULL, 0);
  Array graph = thread.join();
  ArrayChar chars = graph[0];
  ArrayShort shorts = graph[1];
  ArrayInt ints = graph[2];
  ArrayLong longs = graph[3];
  ArrayFloat floats = graph[4];
  ArrayDbl doubles = graph[5];
  MapIntInt integer_map = graph[6];
  MapLongDouble double_map = graph[7];
  MapStringString string_map = graph[8];

  EXPECT_PTR_EQ(graph[9].arrayint(), ints);
  EXPECT_INT_EQ(chars[0], 4);
  EXPECT_INT_EQ(shorts[0], 40);
  EXPECT_INT_EQ(ints[0], 400);
  EXPECT_TRUE(longs[0] == 4000000000L);
  EXPECT_TRUE(floats[0] == 4.5f);
  EXPECT_TRUE(doubles[0] == 40.25);
  EXPECT_INT_EQ(integer_map.get(4), 16);
  EXPECT_TRUE(double_map.get(4000000000L) == 4.25);
  String key = String.new("thread-packed-key-41");
  String value = string_map.get(key);
  EXPECT_PTR_EQ(value, String.new("thread-packed-value-42"));
  EXPECT_PTR_EQ(
    string_map.get(""), String.new("thread-empty-key-43")
  );
  EXPECT_NULL(string_map.get(String.new("thread-empty-value-44")));

  for (int i = 0; i < 80; i++) {
    chars.push((char) i);
    shorts.push((short) i);
    ints.push(i);
    longs.push(i);
    floats.push((float) i);
    doubles.push((double) i);
    integer_map.set(i + 100, i);
    double_map.set((long) i + 100, i * 0.25);
    string_map.set(
      String.printf("joined-key-%d", i),
      String.printf("joined-value-%d", i)
    );
  }
  EXPECT_TRUE(chars.capacity() >= 81);
  EXPECT_TRUE(shorts.capacity() >= 81);
  EXPECT_TRUE(ints.capacity() >= 81);
  EXPECT_TRUE(longs.capacity() >= 81);
  EXPECT_TRUE(floats.capacity() >= 81);
  EXPECT_TRUE(doubles.capacity() >= 81);
  EXPECT_TRUE(integer_map.capacity >= 128);
  EXPECT_TRUE(double_map.capacity >= 128);
  EXPECT_TRUE(string_map.capacity >= 128);
  EXPECT_STR_EQ(string_map.get("joined-key-79"), "joined-value-79");
  thread.free();
}

static void thread_join_runs_recursive_custom_exporter(void) {
  Thread thread = Thread.start_raw(_thread_recursive_export_worker, NULL, 0);
  ContextProbe probe = thread.join();
  EXPECT_INT_EQ(probe.exports, 2);
  Array nested = probe.value;
  EXPECT_PTR_EQ(nested[0].string(), String.new("recursive-worker-51"));
  nested.push(52);
  EXPECT_INT_EQ(nested[1].integer(), 52);
  thread.free();
}

static void thread_errors_stay_private_until_join(void) {
  Pool root = Pool.current();
  size_t before = root.stats().interned;

  Context destination = Context.open_isolated_named("Thread error target");
  int value = 424242;
  Thread thread = Thread.start_raw(
    _thread_private_error_worker, &value, sizeof(value)
  );
  int caught = 0;
  try thread.join();
  catch %(join-fail *): caught = 1;
  EXPECT_TRUE(caught);
  thread.free();
  destination.close();

  EXPECT_INT_EQ(root.stats().interned, before);
}

static void thread_error_wide_values_survive_until_join(void) {
  Thread thread = Thread.start_raw(_thread_wide_error_worker, NULL, 0);
  int caught = 0;
  int64_t value = 0;
  try thread.join();
  catch %(join-fail (errors ?errors)): {
    caught = 1;
    List entry = errors.list().car();
    value = entry.assoc(<detail>).list().assoc(<value>).long_value();
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(value, 0x123456789L);
  thread.free();
}

static void _failing_join_round(void) {
  Thread thread = Thread.start_raw(
    _thread_failing_export_worker, NULL, 0
  );
  int caught = 0;
  try thread.join();
  catch %(thread-exp *): caught = 1;
  EXPECT_TRUE(caught);
  thread.free();
}

/* The first round publishes the catch site's plans, which `Match` keeps for
   the life of the process; the second measures the steady state. */
static void thread_failed_join_export_releases_storage(void) {
  _failing_join_round();
  ScopeStats before = Scope.stats();
  _failing_join_round();
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
}

static void thread_rejects_free_before_join_and_double_join(void) {
  Map map = {};
  map[<number>] = 47;
  ThreadTestInput input = {
    3, 0, NULL, NULL, "parent", %(parent), map
  };
  Thread thread = Thread.start_raw(
    _thread_test_worker, &input, sizeof(input)
  );
  int early = 0, twice = 0;
  try thread.free();
  catch %(bad-state *): early = 1;
  thread.join();
  try thread.join();
  catch %(bad-state *): twice = 1;
  EXPECT_TRUE(early);
  EXPECT_TRUE(twice);
  thread.free();
}

static void thread_freezes_late_descriptor_registration(void) {
  int caught = 0, tag_caught = 0;
  try x2c_register_type("too-late-thread-type");
  catch %(bad-state *): caught = 1;
  try Var.register_object_tag(<too-late>);
  catch %(bad-state *): tag_caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(tag_caught);
}

/* Neither class is boxed before its worker boxes it. */
class ThreadBoxLeft struct { int x; } *;
class ThreadBoxRight struct { int x; } *;

typedef struct ThreadFirstBox {
  atomic_int *arrived;
  void *object;
  Var *mine, *other;
  int left;
} ThreadFirstBox;

static void _thread_first_box_arrive(atomic_int *arrived, int count) {
  atomic_fetch_add(arrived, 1);
  while (atomic_load(arrived) < count) sched_yield();
}

static Var _thread_first_box(const void *input, size_t input_size) {
  if (input_size != sizeof(ThreadFirstBox)) return 0;
  const ThreadFirstBox *box = input;
  if (box.left) *box.mine = (ThreadBoxLeft) box.object;
  else *box.mine = (ThreadBoxRight) box.object;
  _thread_first_box_arrive(box.arrived, 2);
  Var other = *box.other;
  int ok = box.left ? other is ThreadBoxRight && other.repr().len() > 0
                    : other is ThreadBoxLeft && other.repr().len() > 0;
  _thread_first_box_arrive(box.arrived, 4);
  return ok;
}

static void thread_workers_first_box_classes(void) {
  atomic_int arrived = 0;
  Var left = void, right = void;
  ThreadFirstBox inputs[] = {
    { &arrived, ThreadBoxLeft.new(1), &left, &right, 1 },
    { &arrived, ThreadBoxRight.new(2), &right, &left, 0 }
  };
  Thread first = Thread.start_raw(_thread_first_box, &inputs[0],
                              sizeof(inputs[0]));
  Thread second = Thread.start_raw(_thread_first_box, &inputs[1],
                               sizeof(inputs[1]));
  EXPECT_INT_EQ(first.join().integer(), 1);
  EXPECT_INT_EQ(second.join().integer(), 1);
  EXPECT_TRUE(left is ThreadBoxLeft && right is ThreadBoxRight);
  first.free();
  second.free();
}

static Var _thread_render_shared(const void *input, size_t input_size) {
  if (input_size != sizeof(Array)) return 0;
  Array shared = *(Array *) input;
  for (int i = 0; i < 20; i++)
    if (shared.repr() != "[ 1, 2 ]") return 0;
  return 1;
}

static void thread_rendering_paths_are_independent(void) {
  Array shared = [1, 2];
  RenderPath path;
  EXPECT_TRUE(path.enter(shared));
  defer path.leave();
  Thread first = Thread.start_raw(_thread_render_shared, &shared, sizeof(shared));
  Thread second = Thread.start_raw(_thread_render_shared, &shared, sizeof(shared));
  EXPECT_INT_EQ(first.join().integer(), 1);
  EXPECT_INT_EQ(second.join().integer(), 1);
  first.free();
  second.free();
}

typedef struct ThreadRaceInput {
  atomic_int *arrived;
  int index;
  List *promoted;
  int *proven;
} ThreadRaceInput;

enum { THREAD_RACERS = 8 };

static void _thread_race_arrive(atomic_int *arrived) {
  atomic_fetch_add(arrived, 1);
  while (atomic_load(arrived) < THREAD_RACERS) sched_yield();
}

/* This site is registered first by the racing workers below. */
static int _thread_race_classify(int which) {
  try {
    if (which == 0) raise %(bad-state (operation "race"));
    if (which == 1) raise %(conv-range (operation "race"));
    raise %(void-op (operation "race"));
  }
  catch %(bad-state *): return 10;
  catch %(conv-range *): return 11;
  catch %(void-op *): return 12;
  return -1;
}

static Var _thread_race_catch_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(ThreadRaceInput)) return -1;
  const ThreadRaceInput *race = input;
  int wrong = 0;
  Pool.open();
  _thread_race_arrive(race.arrived);
  for (int i = 0; i < 300; i++) {
    int which = (i + race.index) % 3;
    if (_thread_race_classify(which) != 10 + which) wrong++;
  }
  Pool.close();
  return wrong;
}

/* Every worker builds the site's patterns in its own nested Pool; one binds
   the site and the rest must see it bound. */
static void thread_workers_bind_one_catch_site(void) {
  atomic_int arrived = 0;
  ThreadRaceInput inputs[THREAD_RACERS];
  Thread threads[THREAD_RACERS];
  for (int i = 0; i < THREAD_RACERS; i++) {
    inputs[i] = (ThreadRaceInput) { &arrived, i, NULL, NULL };
    threads[i] = Thread.start_raw(
      _thread_race_catch_worker, &inputs[i], sizeof(inputs[i]));
  }
  int wrong = 0;
  for (int i = 0; i < THREAD_RACERS; i++) {
    wrong += threads[i].join().integer();
    threads[i].free();
  }
  EXPECT_INT_EQ(wrong, 0);
  for (int which = 0; which < 3; which++)
    EXPECT_INT_EQ(_thread_race_classify(which), 10 + which);
}

static Var _thread_race_promote_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(ThreadRaceInput)) return -1;
  const ThreadRaceInput *race = input;
  Pool.open();
  Var value = 500681;
  List list = %($value);
  _thread_race_arrive(race.arrived);
  race.proven[race.index] = List.try_own(list) && Pool.is_permanent(list);
  race.promoted[race.index] = list;
  Pool.close();
  return 0;
}

/* Workers intern equal Lists in their own nested Pools before any promotes
   one. The first promoted identity stays canonical in the shared root. */
static void thread_promotions_keep_the_first_canonical_identity(void) {
  atomic_int arrived = 0;
  List promoted[THREAD_RACERS];
  int proven[THREAD_RACERS];
  ThreadRaceInput inputs[THREAD_RACERS];
  Thread threads[THREAD_RACERS];
  for (int i = 0; i < THREAD_RACERS; i++) {
    inputs[i] = (ThreadRaceInput) { &arrived, i, promoted, proven };
    threads[i] = Thread.start_raw(
      _thread_race_promote_worker, &inputs[i], sizeof(inputs[i]));
  }
  for (int i = 0; i < THREAD_RACERS; i++) {
    threads[i].join();
    threads[i].free();
  }
  Var value = 500681;
  List canonical = %($value);
  int permanent = 0;
  for (int i = 0; i < THREAD_RACERS; i++) {
    if (!proven[i]) continue;
    permanent++;
    EXPECT_TRUE(Pool.is_permanent(promoted[i]));
    EXPECT_PTR_EQ((void *) promoted[i], (void *) canonical);
  }
  EXPECT_TRUE(permanent > 0);
}

typedef struct RegexDepthInput {
  int repetitions;
} RegexDepthInput;

static Var _thread_regex_depth_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(RegexDepthInput)) return 0;
  const RegexDepthInput *depth = input;
  Regex re = Regex.compile("(?:a|b)*");
  return re.match("a".repeat(depth.repetitions)) ? 1 : 0;
}

/* A worker's stack reaches the same recursion depth as the main thread's: a
   group repeated just under the `Regex` limit matches, and one over it raises
   rather than overflowing the stack. */
static void thread_stack_reaches_library_recursion_limits(void) {
  RegexDepthInput deep = { 1999 };
  Thread thread = Thread.start_raw(_thread_regex_depth_worker, &deep, sizeof deep);
  EXPECT_INT_EQ(thread.join().integer(), 1);
  thread.free();

  RegexDepthInput over_limit = { 2500 };
  Thread limited = Thread.start_raw(
    _thread_regex_depth_worker, &over_limit, sizeof over_limit);
  int caught = 0;
  try limited.join();
  catch %(join-fail *): caught = 1;
  EXPECT_INT_EQ(caught, 1);
  limited.free();
}

#include "test-macros.x"

typedef struct ThreadWaitInput { Mutex gate; int value; } ThreadWaitInput;

static Var _thread_wait_worker(const void *input, size_t size) {
  (void) size;
  const ThreadWaitInput *work = input;
  if (work.gate) {
    work.gate.lock();
    work.gate.unlock();
  }
  return work.value;
}

static void thread_wait_any_empty_ready_and_removal(void) {
  $test.scoped();
  Array pending = [];
  EXPECT_NULL(Thread.wait_any(NULL));
  EXPECT_NULL(Thread.wait_any(pending));
  ThreadWaitInput input = { NULL, 42 };
  pending.push(Thread.start_raw(_thread_wait_worker, &input, sizeof(input)));
  pending.push(Thread.start_raw(_thread_wait_worker, &input, sizeof(input)));
  Thread first = Thread.wait_any(pending), second = Thread.wait_any(pending);
  EXPECT_INT_EQ(pending.len(), 0);
  pending.push(second);
  pending.push(first);
  EXPECT_TRUE(Thread.wait_any(pending) == second);
  EXPECT_INT_EQ(second.join().int(), 42);
  second.free();
  EXPECT_TRUE(Thread.wait_any(pending) == first);
  EXPECT_INT_EQ(first.join().int(), 42);
  pending.push(first);
  int caught = 0;
  try Thread.wait_any(pending);
  catch %(bad-state *): caught++;
  pending.remove(0);
  first.free();
  pending.push(NULL);
  try Thread.wait_any(pending);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 2);
}

static void thread_wait_any_skips_unfinished_workers(void) {
  $test.scoped();
  Mutex gate = Mutex.new();
  gate.lock();
  ThreadWaitInput slow = { gate, 1 }, fast = { NULL, 2 };
  Thread first = Thread.start_raw(_thread_wait_worker, &slow, sizeof(slow));
  Thread second = Thread.start_raw(_thread_wait_worker, &fast, sizeof(fast));
  Array pending = [first, second];
  EXPECT_TRUE(Thread.wait_any(pending) == second);
  gate.unlock();
  EXPECT_INT_EQ(second.join().int(), 2);
  second.free();
  EXPECT_TRUE(Thread.wait_any(pending) == first);
  EXPECT_INT_EQ(first.join().int(), 1);
  first.free();
  gate.free();
}

static void thread_wait_any_leaves_errors_for_join(void) {
  $test.scoped();
  Thread worker = Thread.start_raw(_thread_error_worker, NULL, 0);
  Array pending = [worker];
  EXPECT_TRUE(Thread.wait_any(pending) == worker);
  EXPECT_INT_EQ(pending.len(), 0);
  int caught = 0;
  try worker.join();
  catch %(join-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
  worker.free();
}

void thread_wait_any_suite(void) {
  $test.run(thread_wait_any_empty_ready_and_removal);
  $test.run(thread_wait_any_skips_unfinished_workers);
  $test.run(thread_wait_any_leaves_errors_for_join);
}

static void thread_finish_all_empty_and_success(void) {
  $test.scoped();
  Thread.finish_all(NULL);
  Array pending = [];
  Thread.finish_all(pending);
  EXPECT_INT_EQ(pending.len(), 0);
  ThreadWaitInput input = { NULL, 42 };
  Thread joined = Thread.start_raw(_thread_wait_worker, &input, sizeof(input));
  EXPECT_INT_EQ(joined.join().int(), 42);
  pending.push(joined);
  pending.push(Thread.start_raw(_thread_wait_worker, &input, sizeof(input)));
  Thread.finish_all(pending);
  EXPECT_INT_EQ(pending.len(), 0);
}

static void thread_finish_all_cleans_before_reporting_failure(void) {
  $test.scoped();
  ThreadWaitInput input = { NULL, 42 };
  Array pending = [Thread.start_raw(_thread_error_worker, NULL, 0),
    Thread.start_raw(_thread_wait_worker, &input, sizeof(input))];
  int caught = 0;
  try Thread.finish_all(pending);
  catch %(join-fail *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<errors>) is <list>);
    EXPECT_INT_EQ(pending.len(), 0);
  }
  EXPECT_INT_EQ(caught, 1);
}

static void thread_finish_all_preserves_an_unwinding_error(void) {
  $test.scoped();
  ThreadWaitInput input = { NULL, 42 };
  Array pending = [Thread.start_raw(_thread_error_worker, NULL, 0),
    Thread.start_raw(_thread_wait_worker, &input, sizeof(input))];
  int caught = 0;
  try {
    defer Thread.finish_all(pending);
    raise %(bad-arg (primary 73));
  }
  catch %(bad-arg (primary ?value)): {
    caught++;
    EXPECT_INT_EQ(value.int(), 73);
    EXPECT_INT_EQ(pending.len(), 0);
  }
  EXPECT_INT_EQ(caught, 1);
}

void thread_finish_all_suite(void) {
  $test.run(thread_finish_all_empty_and_success);
  $test.run(thread_finish_all_cleans_before_reporting_failure);
  $test.run(thread_finish_all_preserves_an_unwinding_error);
}

static Var _thread_finish_map_worker(const void *input, size_t size) {
  (void) input;
  (void) size;
  Map result = {};
  result[String.new("worker-key")] = String.new("worker-value");
  return result;
}

static void thread_finish_any_exports_map_and_frees_handle(void) {
  $test.scoped();
  Array pending = [];
  EXPECT_TRUE(Thread.finish_any(NULL) is void);
  EXPECT_TRUE(Thread.finish_any(pending) is void);
  pending.push(Thread.start_raw(_thread_finish_map_worker, NULL, 0));
  Map result = Thread.finish_any(pending);
  EXPECT_INT_EQ(pending.len(), 0);
  EXPECT_INT_EQ(result.len(), 1);
  EXPECT_STR_EQ(result["worker-key"].string(), "worker-value");
  result["added-after-finish"] = 7;
  EXPECT_INT_EQ(result["added-after-finish"].int(), 7);
}

static void thread_finish_any_cleans_a_failed_worker(void) {
  $test.scoped();
  Array pending = [Thread.start_raw(_thread_error_worker, NULL, 0)];
  int caught = 0;
  try Thread.finish_any(pending);
  catch %(join-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(pending.len(), 0);
}

void thread_finish_any_suite(void) {
  $test.run(thread_finish_any_exports_map_and_frees_handle);
  $test.run(thread_finish_any_cleans_a_failed_worker);
}

static Var _thread_value_identity(Var input) => input;

static Var _thread_value_map(Var input) {
  Map source = input;
  Map result = {source: source, text: String.new("worker-created value")};
  return result;
}

static Var _thread_value_error(Var input) {
  (void) input;
  raise %(worker-fai (detail "value worker"));
  return void;
}

static void thread_start_copies_bits_and_borrows_strings(void) {
  $test.scoped();
  String text = String.new("caller-owned input");
  Array pending = [Thread.start(_thread_value_identity, 37)];
  EXPECT_INT_EQ(Thread.finish_any(pending).int(), 37);
  pending.push(Thread.start(_thread_value_identity, text));
  EXPECT_TRUE(Thread.finish_any(pending).string() == text);
  pending.push(Thread.start(_thread_value_identity, void));
  EXPECT_TRUE(Thread.finish_any(pending) is void);
  EXPECT_INT_EQ(pending.len(), 0);
}

static void thread_start_borrows_map_and_exports_fresh_result(void) {
  $test.scoped();
  Map source = {key: String.new("caller value")};
  Array pending = [Thread.start(_thread_value_map, source)];
  Map result = Thread.finish_any(pending);
  EXPECT_TRUE(result[<source>].map() === source);
  EXPECT_INT_EQ(source.len(), 1);
  EXPECT_STR_EQ(source[<key>].string(), "caller value");
  EXPECT_STR_EQ(result[<text>].string(), "worker-created value");
  result[<after>] = 42;
  EXPECT_INT_EQ(result[<after>].int(), 42);
}

static void thread_start_preserves_worker_errors(void) {
  $test.scoped();
  Array pending = [Thread.start(_thread_value_error, 1)];
  int caught = 0;
  try Thread.finish_any(pending);
  catch %(join-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(pending.len(), 0);
}

static void thread_start_raw_copies_the_input_bytes(void) {
  $test.scoped();
  ThreadWaitInput input = { NULL, 37 };
  Array pending = [Thread.start_raw(_thread_wait_worker, &input, sizeof(input))];
  input.value = 99;
  EXPECT_INT_EQ(Thread.finish_any(pending).int(), 37);
  EXPECT_INT_EQ(pending.len(), 0);
}

void thread_start_suite(void) {
  $test.run(thread_start_copies_bits_and_borrows_strings);
  $test.run(thread_start_borrows_map_and_exports_fresh_result);
  $test.run(thread_start_preserves_worker_errors);
  $test.run(thread_start_raw_copies_the_input_bytes);
}

static Mutex parallel_order_gate;
static atomic_int parallel_active, parallel_maximum, parallel_started;
static atomic_int parallel_finished;

static Var _parallel_count(Var input) {
  int active = atomic_fetch_add(&parallel_active, 1) + 1;
  atomic_fetch_add(&parallel_started, 1);
  int maximum = atomic_load(&parallel_maximum);
  while (maximum < active && !atomic_compare_exchange_weak(
    &parallel_maximum, &maximum, active)) {}
  defer atomic_fetch_sub(&parallel_active, 1);
  defer atomic_fetch_add(&parallel_finished, 1);
  if (input.int() == 0 && parallel_order_gate) {
    parallel_order_gate.lock();
    parallel_order_gate.unlock();
  }
  return input;
}

static int _parallel_order_source(Iter iter, Var *out) {
  int index = iter.state.int();
  if (index == 3) return 0;
  *out = index;
  iter.state = index + 1;
  return 1;
}

static void _parallel_reset(void) {
  atomic_store(&parallel_active, 0);
  atomic_store(&parallel_maximum, 0);
  atomic_store(&parallel_started, 0);
  atomic_store(&parallel_finished, 0);
}

static void parallel_map_bounds_and_completion_order(void) {
  $test.scoped();
  _parallel_reset();
  parallel_order_gate = Mutex.new();
  parallel_order_gate.lock();
  try {
    struct Iter storage;
    Iter source = Iter.init(&storage, void, _parallel_order_source, 0);
    int folded = 0;
    ParallelMap map = source.parallel_map(_parallel_count, 2);
    EXPECT_INT_EQ(atomic_load(&parallel_started), 0);
    Func collect = %!(Array values, Var item) using &folded => {
      if (!folded++) {
        EXPECT_INT_EQ(item.int(), 1);
        EXPECT_TRUE(atomic_load(&parallel_finished) < 3);
        parallel_order_gate.unlock();
      }
      values.push(item);
      return values;
    };
    Array results = map.foldl([], collect);
    EXPECT_INT_EQ(results.len(), 3);
    EXPECT_INT_EQ(results[0].int(), 1);
    EXPECT_TRUE(atomic_load(&parallel_maximum) <= 2);
    EXPECT_INT_EQ(atomic_load(&parallel_active), 0);
    EXPECT_INT_EQ(atomic_load(&parallel_finished), 3);
  }
  finally {
    parallel_order_gate.free();
    parallel_order_gate = NULL;
  }
}

static void parallel_map_results_outlive_workers(void) {
  $test.scoped();
  Map input = {key: "caller value"};
  Array inputs = [input, input];
  Array results = inputs.iter()
    .parallel_map(_thread_value_map, 2)
    .foldl([], %!(Array values, Var item) => {
      values.push(item);
      return values;
    });
  Map result = results[0];
  EXPECT_INT_EQ(results.len(), 2);
  EXPECT_TRUE(result[<source>].map() === input);
  EXPECT_STR_EQ(result[<text>].string(), "worker-created value");
  result[<after>] = 42;
  EXPECT_INT_EQ(result[<after>].int(), 42);
}

static Var _parallel_worker_error(Var input) {
  _parallel_count(input);
  if (input.int() == 0) raise %(worker-fai (detail "parallel map"));
  return input;
}

static int _parallel_source_error(Iter iter, Var *out) {
  int index = iter.state.int();
  if (index == 3) raise %(bad-arg (primary 73));
  *out = index;
  iter.state = index + 1;
  return 1;
}

static void parallel_map_cleans_worker_and_source_failures(void) {
  $test.scoped();
  _parallel_reset();
  Array inputs = [0, 1, 2, 3, 4, 5];
  struct Iter worker_source, failing_source;
  int caught = 0;
  Func sum = %!(int total, int item) => total + item;
  try inputs.iter(&worker_source).parallel_map(_parallel_worker_error, 4)
    .foldl(0, sum);
  catch %(join-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(atomic_load(&parallel_active), 0);
  EXPECT_INT_EQ(atomic_load(&parallel_finished),
                atomic_load(&parallel_started));
  _parallel_reset();
  Iter source = Iter.init(&failing_source, void, _parallel_source_error, 0);
  try source.parallel_map(_parallel_count, 4).foldl(0, sum);
  catch %(bad-arg (primary ?value)): {
    caught++;
    EXPECT_INT_EQ(value.int(), 73);
  }
  EXPECT_INT_EQ(caught, 2);
  EXPECT_INT_EQ(atomic_load(&parallel_active), 0);
  EXPECT_INT_EQ(atomic_load(&parallel_finished), 3);
  _parallel_reset();
  struct Iter stopped_source;
  try inputs.iter(&stopped_source).parallel_map(_parallel_count, 4)
    .foldl(0, %!(Var acc, Var item) => {
      (void) acc;
      (void) item;
      raise %(bad-arg (primary 99));
    });
  catch %(bad-arg (primary ?value)): {
    caught++;
    EXPECT_INT_EQ(value.int(), 99);
  }
  EXPECT_INT_EQ(caught, 3);
  EXPECT_INT_EQ(atomic_load(&parallel_active), 0);
  EXPECT_INT_EQ(atomic_load(&parallel_started), 4);
  EXPECT_INT_EQ(atomic_load(&parallel_finished), 4);
}

static threaded int parallel_reuse_jobs;

static Var _parallel_reuse_worker(Var input) {
  _parallel_count(input);
  int jobs = ++parallel_reuse_jobs;
  Map result = {
    id: Var.box_ulong((unsigned long) (uintptr_t) pthread_self()),
    jobs: jobs,
    text: String.printf("job-%d", input.int())
  };
  return result;
}

static void parallel_map_reuses_workers_and_exports_each_job(void) {
  $test.scoped();
  _parallel_reset();
  Array inputs = [];
  for (int i = 0; i < 16; i++) inputs.push(i);
  Array results = inputs.iter().parallel_map(_parallel_reuse_worker, 4)
    .foldl([], %!(Array values, Var item) => {
      values.push(item);
      return values;
    });
  Map ids = {}, texts = {};
  int maximum_jobs = 0;
  foreach (Map result, results) {
    ids[result[<id>]] += 1;
    texts[result[<text>]] = 1;
    int jobs = result[<jobs>];
    if (jobs > maximum_jobs) maximum_jobs = jobs;
  }
  EXPECT_INT_EQ(results.len(), 16);
  EXPECT_INT_EQ(ids.len(), 4);
  EXPECT_TRUE(maximum_jobs > 1);
  EXPECT_TRUE(atomic_load(&parallel_maximum) <= 4);
  EXPECT_INT_EQ(atomic_load(&parallel_active), 0);
  EXPECT_INT_EQ(atomic_load(&parallel_started), 16);
  EXPECT_INT_EQ(atomic_load(&parallel_finished), 16);
  for (int i = 0; i < 16; i++)
    EXPECT_TRUE(texts.contains(String.printf("job-%d", i)));
}

void thread_parallel_map_suite(void) {
  $test.run(parallel_map_bounds_and_completion_order);
  $test.run(parallel_map_results_outlive_workers);
  $test.run(parallel_map_cleans_worker_and_source_failures);
  $test.run(parallel_map_reuses_workers_and_exports_each_job);
}

void thread_suite(void) {
  $test.run(thread_failed_start_does_not_freeze_registration);
  $test.run(thread_input_size_overflow_is_size_limit);
  $test.run(thread_copies_input_at_maximum_alignment);
  $test.run(thread_rendering_paths_are_independent);
  $test.run(thread_rejects_one_of_two_concurrent_joins);
  $test.run(thread_rejects_free_before_join_and_double_join);
  $test.run(thread_workers_isolate_and_join_results);
  $test.run(thread_join_raises_worker_errors);
  $test.run(thread_ignored_policy_resumes_in_worker);
  $test.run(thread_shared_cause_still_fails_join);
  $test.run(thread_memory_sink_retains_worker_events);
  $test.run(thread_results_stay_private_until_join);
  $test.run(thread_join_returns_void_worker_result);
  $test.run(thread_joins_nested_packed_containers);
  $test.run(thread_join_runs_recursive_custom_exporter);
  $test.run(thread_errors_stay_private_until_join);
  $test.run(thread_error_wide_values_survive_until_join);
  $test.run(thread_failed_join_export_releases_storage);
  $test.run(thread_freezes_late_descriptor_registration);
  $test.run(thread_workers_first_box_classes);
  $test.run(thread_stack_reaches_library_recursion_limits);
  $test.run(thread_workers_bind_one_catch_site);
  $test.run(thread_promotions_keep_the_first_canonical_identity);
}
