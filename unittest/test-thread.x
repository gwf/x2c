/*  test-thread.x -- Context-backed Thread tests */

#include "typed-array.x"
#include "typed-map.x"
#include "test-support.x"
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>

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
    raise %(bad-arg (owner "thread test worker"));
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

  Map result = %{};
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
    raise %(bad-arg (owner "private result worker"));
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

  Array graph = %[];
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
  Array nested = %[];
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
    raise %(bad-arg (owner "private error worker"));
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
  try Thread.start(_thread_aligned_input_worker, &input, SIZE_MAX);
  catch %(size-limit): selected = 1;
  catch %(alloc-fail): selected = 2;
  EXPECT_INT_EQ(selected, 1);
}

static void thread_copies_input_at_maximum_alignment(void) {
  ThreadAlignedInput input = {
    UINT64_C(0x0123456789abcdef), 1234.5L
  };
  Thread thread = Thread.start(
    _thread_aligned_input_worker, &input, sizeof(input)
  );
  EXPECT_INT_EQ(thread.join().integer(), 1);
  thread.free();
}

static void thread_rejects_one_of_two_concurrent_joins(void) {
  ThreadJoinProbe probe = { 0 };
  ThreadJoinInput input = { &probe };
  probe.target = Thread.start(
    _thread_join_target_worker, &input, sizeof(input)
  );
  Thread first = Thread.start(
    _thread_join_competitor_worker, &input, sizeof(input)
  );
  Thread second = Thread.start(
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
  Map ancestor_map = %{};
  ancestor_map[<number>] = 47;
  ThreadTestInput first = {
    11, 250, &counter, mutex, ancestor_string, ancestor_list, ancestor_map
  };
  ThreadTestInput second = {
    22, 250, &counter, mutex, ancestor_string, ancestor_list, ancestor_map
  };
  Thread a = Thread.start(_thread_test_worker, &first, sizeof(first));
  Thread b = Thread.start(_thread_test_worker, &second, sizeof(second));
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
  Thread thread = Thread.start(_thread_error_worker, NULL, 0);
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

  Thread message = Thread.start(_thread_memory_log_worker, NULL, 0);
  EXPECT_INT_EQ(message.join().integer(), 73);
  List message_entry = entries.car();
  EXPECT_TRUE(message_entry[4].symbol() == <thread-mem>);
  EXPECT_STR_EQ(
    message_entry[5].list().assoc(<text>).string(),
    "worker-private log value"
  );

  Thread failure = Thread.start(_thread_logged_error_worker, NULL, 0);
  int caught = 0;
  try failure.join();
  catch %(join-fail *): caught = 1;
  EXPECT_TRUE(caught);
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
  Pool string_root = String.pool_current();
  Pool list_root = List.pool_current();
  size_t strings_before = Pool.stats(string_root).interned;
  size_t lists_before = Pool.stats(list_root).interned;

  Context destination = Context.open_isolated_named("Thread join target");
  int value = 8675309;
  Thread thread = Thread.start(
    _thread_private_result_worker, &value, sizeof(value)
  );
  List result = thread.join();
  EXPECT_INT_EQ(result.assoc(<value>).integer(), value);
  EXPECT_STR_EQ(
    result.assoc(<text>).string(), "sealed-worker-result-8675309"
  );
  thread.free();
  destination.close();

  EXPECT_INT_EQ(Pool.stats(string_root).interned, strings_before);
  EXPECT_INT_EQ(Pool.stats(list_root).interned, lists_before);
}

static void thread_join_returns_void_worker_result(void) {
  Thread thread = Thread.start(_thread_void_result_worker, NULL, 0);
  EXPECT_TRUE(thread.join() is void);
  thread.free();
}

static void thread_joins_nested_packed_containers(void) {
  Thread thread = Thread.start(_thread_packed_result_worker, NULL, 0);
  Array graph = thread.join();
  ArrayChar chars = graph[0].arraychar();
  ArrayShort shorts = graph[1].arrayshort();
  ArrayInt ints = graph[2].arrayint();
  ArrayLong longs = graph[3].arraylong();
  ArrayFloat floats = graph[4].arrayfloat();
  ArrayDbl doubles = graph[5].arraydbl();
  MapIntInt integer_map = graph[6].mapintint();
  MapLongDouble double_map = graph[7].maplongdouble();
  MapStringString string_map = graph[8].mapstringstring();

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
  Thread thread = Thread.start(_thread_recursive_export_worker, NULL, 0);
  ContextProbe probe = thread.join();
  EXPECT_INT_EQ(probe.exports, 2);
  Array nested = probe.value;
  EXPECT_PTR_EQ(nested[0].string(), String.new("recursive-worker-51"));
  nested.push(52);
  EXPECT_INT_EQ(nested[1].integer(), 52);
  thread.free();
}

static void thread_errors_stay_private_until_join(void) {
  Pool string_root = String.pool_current();
  Pool list_root = List.pool_current();
  size_t strings_before = Pool.stats(string_root).interned;
  size_t lists_before = Pool.stats(list_root).interned;

  Context destination = Context.open_isolated_named("Thread error target");
  int value = 424242;
  Thread thread = Thread.start(
    _thread_private_error_worker, &value, sizeof(value)
  );
  int caught = 0;
  try thread.join();
  catch %(join-fail *): caught = 1;
  EXPECT_TRUE(caught);
  thread.free();
  destination.close();

  EXPECT_INT_EQ(Pool.stats(string_root).interned, strings_before);
  EXPECT_INT_EQ(Pool.stats(list_root).interned, lists_before);
}

static void thread_error_wide_values_survive_until_join(void) {
  Thread thread = Thread.start(_thread_wide_error_worker, NULL, 0);
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
  Thread thread = Thread.start(
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
  Map map = %{};
  map[<number>] = 47;
  ThreadTestInput input = {
    3, 0, NULL, NULL, %"parent", %(parent), map
  };
  Thread thread = Thread.start(
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
  try x2c_register_type(%"too-late-thread-type");
  catch %(bad-state *): caught = 1;
  try Var.register_object_tag(<too-late>);
  catch %(bad-state *): tag_caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(tag_caught);
}

static Var _thread_render_shared(const void *input, size_t input_size) {
  if (input_size != sizeof(Array)) return 0;
  Array shared = *(Array *) input;
  for (int i = 0; i < 20; i++)
    if (shared.repr() != %"[ 1, 2 ]") return 0;
  return 1;
}

static void thread_rendering_paths_are_independent(void) {
  Array shared = %[1, 2];
  RenderPath path;
  EXPECT_TRUE(path.enter(shared));
  defer path.leave();
  Thread first = Thread.start(_thread_render_shared, &shared, sizeof(shared));
  Thread second = Thread.start(_thread_render_shared, &shared, sizeof(shared));
  EXPECT_INT_EQ(first.join().integer(), 1);
  EXPECT_INT_EQ(second.join().integer(), 1);
  first.free();
  second.free();
}

$(import "test-macros.xmacro")

void thread_suite(void) {
  $test.run(thread_failed_start_does_not_freeze_registration);
  $test.run(thread_input_size_overflow_is_size_limit);
  $test.run(thread_copies_input_at_maximum_alignment);
  $test.run(thread_rendering_paths_are_independent);
  $test.run(thread_rejects_one_of_two_concurrent_joins);
  $test.run(thread_rejects_free_before_join_and_double_join);
  $test.run(thread_workers_isolate_and_join_results);
  $test.run(thread_join_raises_worker_errors);
  $test.run(thread_memory_sink_retains_worker_events);
  $test.run(thread_results_stay_private_until_join);
  $test.run(thread_join_returns_void_worker_result);
  $test.run(thread_joins_nested_packed_containers);
  $test.run(thread_join_runs_recursive_custom_exporter);
  $test.run(thread_errors_stay_private_until_join);
  $test.run(thread_error_wide_values_survive_until_join);
  $test.run(thread_failed_join_export_releases_storage);
  $test.run(thread_freezes_late_descriptor_registration);
}
