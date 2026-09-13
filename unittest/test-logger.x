/*  test-logger.x -- unit tests for logger filtering and delivery */

#include "test-support.x"
$(import "test-macros.xmacro")
#include "logger.x"

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct CapturedEvent {
  unsigned long sequence;
  long long wall_time_us;
  long long elapsed_us;
  Symbol level;
  Symbol category;
  List fields;
} CapturedEvent;

typedef struct CaptureState {
  CapturedEvent events[16];
  int count;
} CaptureState;

typedef struct OrderState {
  int id;
  int *order;
  int *count;
} OrderState;

typedef struct FlushState {
  int emits;
  int flushes;
} FlushState;

typedef struct MutationState {
  Logger logger;
  OrderState added;
  Symbol action;
  int mutated;
} MutationState;

static void free_during_emit(Logger logger, const LogEvent *event, Var data) {
  (void) event;
  (void) data;
  logger.free();
}

static void logger_free_stops_during_emission(void) {
  $test.scoped();
  Logger logger = Logger.new(<trace>);
  logger.add_sink(free_during_emit, NULL, void);
  int caught = 0;
  try logger.info(<free-test>, nil);
  catch %(bad-state *): caught = 1;
  EXPECT_TRUE(caught);
  logger.free();
}


static void capture_emit(Logger logger, const LogEvent *event, Var data) {
  (void) logger;
  CaptureState *state = data;
  if (!state || state->count >= 16) return;
  CapturedEvent *copy = &state->events[state->count++];
  copy->sequence = event->sequence;
  copy->wall_time_us = event->wall_time_us;
  copy->elapsed_us = event->elapsed_us;
  copy->level = event->level;
  copy->category = event->category;
  copy->fields = event->fields;
}

static void order_emit(Logger logger, const LogEvent *event, Var data) {
  (void) logger;
  (void) event;
  OrderState *state = data;
  if (!state) return;
  state->order[(*state->count)++] = state->id;
}

static void flush_emit(Logger logger, const LogEvent *event, Var data) {
  (void) logger;
  (void) event;
  FlushState *state = data;
  if (state) state->emits++;
}

static void flush_sink(Logger logger, Var data) {
  (void) logger;
  FlushState *state = data;
  if (state) state->flushes++;
}

static MutationState mutation;

static void recursive_emit(Logger logger, const LogEvent *event, Var data) {
  order_emit(logger, event, data);
  if (mutation.mutated) return;
  mutation.mutated = 1;
  if (mutation.action == <add>)
    logger.add_sink(order_emit, NULL, Var.new(<p48>, &mutation.added));
  else if (mutation.action == <clear>) logger.clear_sinks();
  else logger.info(<recursive>, nil);
}

static void guarded_dynamic_event(Logger logger, int value) {
  if (!logger.should_log(<debug>, <hot>)) return;
  logger.debug(<hot>, %(
    (message ${String.printf("value=%d", value)})
    (value $value)
  ));
}

static void logger_creation_levels_and_queries(void) {
  $test.scoped();
  Logger logger = Logger.new(<info>);
  EXPECT_NOT_NULL(logger);
  EXPECT_TRUE(Logger.min_level(logger) == <info>);
  EXPECT_INT_EQ(Logger.sink_count(logger), 0);
  EXPECT_FALSE(logger.should_log(<info>, <test>));
  EXPECT_INT_EQ(Logger.level_priority(<trace>), 0);
  EXPECT_INT_EQ(Logger.level_priority(<fatal>), 5);
  EXPECT_INT_EQ(Logger.level_priority(<off>), 6);
  EXPECT_INT_EQ(Logger.level_priority(<unknown>), -1);
  EXPECT_NULL(Logger.new(<unknown>));

  CaptureState capture = { 0 };
  logger.add_sink(capture_emit, NULL, Var.new(<p48>, &capture));
  EXPECT_TRUE(logger.should_log(<info>, <test>));
  EXPECT_FALSE(logger.should_log(<debug>, <test>));
  EXPECT_FALSE(logger.should_log(<off>, <test>));
  EXPECT_FALSE(logger.should_log(<unknown>, <test>));
  EXPECT_FALSE(logger.should_log(<info>, 0));
  EXPECT_TRUE(logger.set_min_level(<off>));
  EXPECT_FALSE(logger.should_log(<fatal>, <test>));
  EXPECT_FALSE(logger.set_min_level(<unknown>));
  EXPECT_TRUE(Logger.min_level(logger) == <off>);
  logger.free();
}

static void logger_threshold_and_metadata(void) {
  $test.scoped();
  Logger logger = Logger.new(<warn>);
  CaptureState first = { 0 }, second = { 0 };
  List fields = %((message "same event"));
  logger.add_sink(capture_emit, NULL, Var.new(<p48>, &first));
  logger.add_sink(capture_emit, NULL, Var.new(<p48>, &second));
  logger.log(<info>, <test>, fields);
  logger.log(<unknown>, <test>, fields);
  logger.log(<off>, <test>, fields);
  logger.log(<warn>, <test>, fields);
  logger.log(<error>, <test>, fields);
  EXPECT_INT_EQ(first.count, 2);
  EXPECT_INT_EQ(second.count, 2);
  EXPECT_INT_EQ(first.events[0].sequence, 0);
  EXPECT_INT_EQ(first.events[1].sequence, 1);
  EXPECT_TRUE(first.events[0].wall_time_us > 0);
  EXPECT_TRUE(first.events[0].elapsed_us >= 0);
  EXPECT_TRUE(first.events[1].elapsed_us >= first.events[0].elapsed_us);
  EXPECT_TRUE(first.events[0].wall_time_us == second.events[0].wall_time_us);
  EXPECT_TRUE(first.events[0].elapsed_us == second.events[0].elapsed_us);
  EXPECT_TRUE(first.events[0].level == second.events[0].level);
  EXPECT_TRUE(first.events[0].category == second.events[0].category);
  EXPECT_PTR_EQ(first.events[0].fields, fields);
  EXPECT_PTR_EQ(second.events[0].fields, fields);
  logger.free();
}

static void logger_fifo_removal_and_clear(void) {
  $test.scoped();
  Logger logger = Logger.new(<trace>);
  int order[16] = { 0 }, count = 0;
  OrderState one = { 1, order, &count };
  OrderState two = { 2, order, &count };
  OrderState three = { 3, order, &count };
  LogSink first = logger.add_sink(order_emit, NULL, Var.new(<p48>, &one));
  LogSink middle = logger.add_sink(order_emit, NULL, Var.new(<p48>, &two));
  LogSink last = logger.add_sink(order_emit, NULL, Var.new(<p48>, &three));
  EXPECT_NOT_NULL(first);
  EXPECT_NOT_NULL(last);
  logger.info(<test>, nil);
  EXPECT_INT_EQ(count, 3);
  EXPECT_INT_EQ(order[0], 1);
  EXPECT_INT_EQ(order[1], 2);
  EXPECT_INT_EQ(order[2], 3);
  EXPECT_TRUE(logger.remove_sink(middle));
  EXPECT_FALSE(logger.remove_sink(middle));
  logger.info(<test>, nil);
  EXPECT_INT_EQ(count, 5);
  EXPECT_INT_EQ(order[3], 1);
  EXPECT_INT_EQ(order[4], 3);
  logger.clear_sinks();
  EXPECT_INT_EQ(logger.sink_count(), 0);
  EXPECT_FALSE(logger.should_log(<info>, <test>));
  EXPECT_FALSE(logger.remove_sink(first));
  EXPECT_FALSE(logger.remove_sink(last));
  logger.free();
}

static void logger_recursion_and_locked_sink_list(void) {
  $test.scoped();
  Logger logger = Logger.new(<trace>);
  int order[16] = { 0 }, count = 0;
  OrderState one = { 1, order, &count }, two = { 2, order, &count };
  mutation = (MutationState) { .logger = logger };
  logger.add_sink(recursive_emit, NULL, Var.new(<p48>, &one));
  logger.add_sink(order_emit, NULL, Var.new(<p48>, &two));

  // An emitter may log again; the inner event finishes inside the outer one.
  logger.info(<outer>, nil);
  EXPECT_INT_EQ(count, 4);
  EXPECT_INT_EQ(order[0], 1);
  EXPECT_INT_EQ(order[1], 1);
  EXPECT_INT_EQ(order[2], 2);
  EXPECT_INT_EQ(order[3], 2);

  // An emitter may not change the sink list it is being walked from.
  mutation.mutated = 0;
  mutation.action = <add>;
  int caught = 0;
  try logger.info(<add-test>, nil);
  catch %(bad-state *): caught = 1;
  EXPECT_TRUE(caught);

  mutation.mutated = 0;
  mutation.action = <clear>;
  caught = 0;
  try logger.info(<clear-test>, nil);
  catch %(bad-state *): caught = 1;
  EXPECT_TRUE(caught);

  logger.clear_sinks();
  logger.free();
}

static void logger_flush_and_borrowed_file(void) {
  $test.scoped();
  Logger logger = Logger.new(<trace>);
  FlushState state = { 0 };
  logger.add_sink(flush_emit, flush_sink, Var.new(<p48>, &state));
  logger.info(<test>, nil);
  EXPECT_INT_EQ(state.emits, 1);
  EXPECT_INT_EQ(state.flushes, 0);
  logger.flush();
  EXPECT_INT_EQ(state.flushes, 1);
  logger.fatal(<test>, nil);
  EXPECT_INT_EQ(state.emits, 2);
  EXPECT_INT_EQ(state.flushes, 2);
  logger.free();
  EXPECT_INT_EQ(state.flushes, 3);

  File file = tmpfile();
  char file_buffer[4096];
  struct stat before = { 0 }, explicit = { 0 }, fatal = { 0 };
  file.setvbuf(file_buffer, _IOFBF, sizeof file_buffer);
  Logger text = Logger.new(<trace>);
  text.add_file_sink(file);
  text.info(<test>, %((value 7)));
  file.stat(&before);
  EXPECT_TRUE(before.st_size == 0);
  text.flush();
  file.stat(&explicit);
  EXPECT_TRUE(explicit.st_size > before.st_size);
  text.fatal(<test>, %((value 8)));
  file.stat(&fatal);
  EXPECT_TRUE(fatal.st_size > explicit.st_size);
  text.free();
  EXPECT_TRUE(file.puts("tail") >= 0);
  file.close();
}

static void logger_plain_text_and_per_logger_origin(void) {
  $test.scoped();
  File first_file = tmpfile(), second_file = tmpfile();
  Logger first = Logger.new(<trace>), second = Logger.new(<trace>);
  first.add_file_sink(first_file);
  second.add_file_sink(second_file);
  first.info(<test>, %((message "hello") (answer 42)));
  first.warn(<test>, %((message "again")));
  second.info(<other>, nil);
  first.flush();
  second.flush();
  first_file.rewind();
  second_file.rewind();
  String first_text = first_file.string(), second_text = second_file.string();
  EXPECT_TRUE(first_text.contains(%"0:00.000 info/test start_time=\""));
  EXPECT_TRUE(first_text.contains(%" message=\"hello\" answer=42\n"));
  EXPECT_TRUE(first_text.contains(%" warn/test message=\"again\"\n"));
  EXPECT_FALSE(first_text.contains(%"\x1b["));
  int origin = first_text.find(%"start_time=");
  EXPECT_TRUE(origin >= 0);
  EXPECT_INT_EQ(first_text.find_within(%"start_time=", origin + 1, -1), -1);
  EXPECT_TRUE(second_text.contains(%"0:00.000 info/other start_time=\""));
  first.free();
  second.free();
  first_file.close();
  second_file.close();
}

static void logger_stderr_uses_color_on_a_tty(void) {
  $test.scoped();
  int master = posix_openpt(O_RDWR | O_NOCTTY);
  int saved = -1, slave = -1, captured = -1;
  char bytes[1024] = { 0 };
  if (master >= 0) {
    int flags = fcntl(master, F_GETFL, 0);
    if (flags >= 0) fcntl(master, F_SETFL, flags | O_NONBLOCK);
  }
  if (master >= 0 && grantpt(master) == 0 && unlockpt(master) == 0) {
    char *name = ptsname(master);
    if (name) slave = open(name, O_RDWR | O_NOCTTY);
  }
  if (slave >= 0) saved = dup(STDERR_FILENO);
  if (saved >= 0 && dup2(slave, STDERR_FILENO) >= 0) {
    Logger logger = Logger.new(<trace>);
    logger.add_stderr_sink();
    logger.info(<color>, %((value 7)));
    logger.free();
    fflush(stderr);
    dup2(saved, STDERR_FILENO);
    close(saved);
    saved = -1;
    captured = read(master, bytes, sizeof bytes - 1);
    close(slave);
    slave = -1;
  }
  if (saved >= 0) {
    dup2(saved, STDERR_FILENO);
    close(saved);
  }
  if (slave >= 0) close(slave);
  if (master >= 0) close(master);
  EXPECT_TRUE(captured > 0);
  EXPECT_TRUE(captured > 0 && strstr(bytes, "\x1b[") != NULL);
  EXPECT_TRUE(captured > 0 && strstr(bytes, "info") != NULL);
}

static void logger_memory_sink_shape(void) {
  $test.scoped();
  ScopeStats before = Scope.stats();
  List entries = nil;
  List first_fields = %((value 1));
  List second_fields = %((value 2));
  Logger logger = Logger.new(<trace>);
  logger.add_memory_sink(&entries);
  logger.info(<memory>, first_fields);
  logger.warn(<memory>, second_fields);
  EXPECT_INT_EQ(entries.len(), 2);
  List (newest, oldest) = entries;
  EXPECT_INT_EQ(newest.len(), 6);
  EXPECT_TRUE(newest.getindex(0).ulong_value() == 1);
  EXPECT_TRUE(oldest.getindex(0).ulong_value() == 0);
  EXPECT_TRUE(newest.getindex(1).long_long_value() > 0);
  EXPECT_TRUE(newest.getindex(2).long_long_value() >= 0);
  EXPECT_TRUE(newest.getindex(3).symbol() == <warn>);
  EXPECT_TRUE(newest.getindex(4).symbol() == <memory>);
  EXPECT_PTR_EQ(newest.getindex(5).list(), second_fields);
  EXPECT_PTR_EQ(oldest.getindex(5).list(), first_fields);
  logger.free();
  ScopeStats after = Scope.stats();
  EXPECT_TRUE(after.live_scopes == before.live_scopes);
}

static void logger_memory_sink_outlives_registration_context(void) {
  $test.scoped();
  ScopeStats before = Scope.stats();
  List entries = nil;
  Logger logger = Logger.new(<trace>);
  Context context = Context.open_isolated_named("sink registration");
  logger.add_memory_sink(&entries);
  context.close();

  logger.info(<memory>, %((message "after Context close")));
  EXPECT_INT_EQ(entries.len(), 1);
  List entry = entries.car();
  EXPECT_STR_EQ(
    entry[5].list().assoc(<message>).string(), "after Context close"
  );
  logger.free();
  ScopeStats after = Scope.stats();
  EXPECT_TRUE(after.live_scopes == before.live_scopes);
}


static List _logger_error_entry(Symbol code) {
  return %((code $code));
}


static void logger_error_handler_renders_only_selected_newest(void) {
  $test.scoped();
  Logger logger = Logger.new(<trace>);
  CaptureState capture = { 0 };
  logger.add_sink(capture_emit, NULL, Var.new(<p48>, &capture));
  Logger previous = log_set_global_logger(logger);
  Error.initialize();

  Symbol collected_code = <collected>;
  Error.policy_set(collected_code, <collect>);
  List collected = _logger_error_entry(collected_code);
  EXPECT_TRUE(Logger.error_handler(%($collected), void) == <declined>);
  EXPECT_INT_EQ(capture.count, 0);

  Symbol logged_code = <logged-err>;
  Error.policy_set(logged_code, <log>);
  List logged = _logger_error_entry(logged_code);
  EXPECT_TRUE(Logger.error_handler(%($collected $logged), void) == <declined>);
  EXPECT_INT_EQ(capture.count, 1);
  EXPECT_TRUE(capture.events[0].category == <err-report>);
  EXPECT_PTR_EQ(capture.events[0].fields, logged);

  log_set_global_logger(previous);
  logger.free();
}


static void logger_global_replacement_and_shutdown(void) {
  $test.scoped();
  Logger custom = Logger.new(<trace>);
  FlushState state = { 0 };
  custom.add_sink(flush_emit, flush_sink, Var.new(<p48>, &state));
  Logger previous = log_set_global_logger(custom);
  EXPECT_PTR_EQ(log_get_global_logger(), custom);
  EXPECT_PTR_EQ(log_set_global_logger(previous), custom);
  EXPECT_PTR_EQ(log_set_global_logger(custom), previous);
  log_info(<global>, nil);
  EXPECT_INT_EQ(state.emits, 1);
  Logger.shutdown();
  EXPECT_NULL(log_get_global_logger());
  EXPECT_INT_EQ(state.flushes, 1);
  EXPECT_INT_EQ(custom.sink_count(), 1);
  int after_shutdown = state.emits;
  EXPECT_TRUE(after_shutdown >= 1);
  custom.info(<direct>, nil);
  EXPECT_INT_EQ(state.emits, after_shutdown + 1);
  custom.free();
}

static void logger_rejected_and_warmed_paths_allocate_nothing(void) {
  $test.scoped();
  Logger filtered = Logger.new(<info>);
  CaptureState capture = { 0 };
  filtered.add_sink(capture_emit, NULL, Var.new(<p48>, &capture));
  ScopeStats before_rejected = Scope.stats();
  for (int i = 0; i < 1000; i++) guarded_dynamic_event(filtered, i);
  ScopeStats after_rejected = Scope.stats();
  EXPECT_TRUE(after_rejected.allocation_calls ==
              before_rejected.allocation_calls);
  EXPECT_TRUE(after_rejected.reallocation_calls ==
              before_rejected.reallocation_calls);
  EXPECT_INT_EQ(capture.count, 0);

  File file = tmpfile();
  Logger text = Logger.new(<trace>);
  List fields = %((message "fixed") (value 17));
  text.add_file_sink(file);
  text.info(<warm>, fields);
  ScopeStats before_warm = Scope.stats();
  for (int i = 0; i < 1000; i++) text.info(<warm>, fields);
  ScopeStats after_warm = Scope.stats();
  EXPECT_TRUE(after_warm.allocation_calls == before_warm.allocation_calls);
  EXPECT_TRUE(after_warm.reallocation_calls == before_warm.reallocation_calls);
  text.free();
  file.close();
  filtered.free();
}


void logger_suite(void) {
  $test.run(logger_creation_levels_and_queries);
  $test.run(logger_free_stops_during_emission);
  $test.run(logger_threshold_and_metadata);
  $test.run(logger_fifo_removal_and_clear);
  $test.run(logger_recursion_and_locked_sink_list);
  $test.run(logger_flush_and_borrowed_file);
  $test.run(logger_plain_text_and_per_logger_origin);
  $test.run(logger_stderr_uses_color_on_a_tty);
  $test.run(logger_memory_sink_shape);
  $test.run(logger_memory_sink_outlives_registration_context);
  $test.run(logger_error_handler_renders_only_selected_newest);
  $test.run(logger_rejected_and_warmed_paths_allocate_nothing);
  $test.run(logger_global_replacement_and_shutdown);
}
