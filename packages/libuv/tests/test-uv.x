/*  test-uv.x -- focused loop, process, callback, and watch tests */

import "libuv" with UvAsync, UvCheck, UvIdle, UvLoop, UvPrepare,
  UvProcess, UvSignal, UvTimer, UvWatch;

#include "test-support.x"
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

$(import "../../../unittest/test-macros.xmacro")

static String _scratch(String name) {
  String path = %"/tmp/x2c-libuv-$name";
  mkdir(path, 0700);
  return path;
}

static void process_captures_stdout_stderr_and_exit(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess child = loop.spawn(%(
    "/bin/sh" "-c"
    "printf 'ordinary output'; printf 'diagnostic' >&2; exit 7"
  ));
  defer child.free();
  child.close_stdin();

  EXPECT_TRUE(child.pid() > 0);
  EXPECT_FALSE(child.exited());
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_TRUE(child.exited());
  EXPECT_STR_EQ(child.stdout(), %"ordinary output");
  EXPECT_STR_EQ(child.stderr(), %"diagnostic");
  Bytes diagnostic = child.stderr_bytes();
  defer diagnostic.free();
  EXPECT_INT_EQ(diagnostic.len(), 10);
  EXPECT_INT_EQ(child.exit_status(), 7);
  EXPECT_INT_EQ(child.term_signal(), 0);
  EXPECT_FALSE(child.timed_out());
}

static void process_stdin_and_concurrent_children(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();

  UvProcess upper = loop.spawn(%("/usr/bin/tr" "[:lower:]" "[:upper:]"));
  defer upper.free();
  upper.write(%"one\n").write(%"two\n").close_stdin();

  UvProcess lines = loop.spawn(%("/usr/bin/wc" "-l"));
  defer lines.free();
  lines.write(%"one\ntwo\n").close_stdin();

  EXPECT_TRUE(loop.alive());
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_FALSE(loop.alive());
  EXPECT_STR_EQ(upper.stdout(), %"ONE\nTWO\n");
  EXPECT_TRUE(lines.stdout().contains(%"2"));
  EXPECT_INT_EQ(upper.exit_status(), 0);
  EXPECT_INT_EQ(lines.exit_status(), 0);

  int count = 0;
  foreach(String line, upper.stdout().lines()) count++;
  EXPECT_INT_EQ(count, 2);
}

static void process_binary_output_uses_bytes(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess child = loop.spawn(%("/usr/bin/printf" "a\\0b"));
  defer child.free();
  child.close_stdin();
  loop.run(UV_RUN_DEFAULT);

  Bytes output = child.stdout_bytes();
  defer output.free();
  EXPECT_INT_EQ(output.len(), 3);
  EXPECT_INT_EQ(((unsigned char *) output)[0], 'a');
  EXPECT_INT_EQ(((unsigned char *) output)[1], 0);
  EXPECT_INT_EQ(((unsigned char *) output)[2], 'b');

  int caught = 0;
  try child.stdout();
  catch %(bad-enc *): caught = 1;
  EXPECT_TRUE(caught);
}

static void process_output_limit_reports_libuv_error(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess child = loop.command(%("/usr/bin/printf" "four"))
    .max_output(2).start();
  defer child.free();
  child.close_stdin();
  loop.run(UV_RUN_DEFAULT);

  int caught = 0;
  try child.stdout();
  catch %(io-fail (library ?library) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"libuv");
    EXPECT_STR_EQ(operation.string(), %"stdout");
  }
  EXPECT_TRUE(caught);
}

static void process_free_waits_for_every_close_callback(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess child = loop.spawn(%("/usr/bin/printf" "done"));
  child.close_stdin();

  int caught = 0;
  try child.free();
  catch %(bad-state *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_NULL(child.free());
  EXPECT_NULL(child.free());

  caught = 0;
  try child.exit_status();
  catch %(bad-state (library *) (operation ?operation) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"exit_status");
    EXPECT_STR_EQ(reason.string(), %"process has been released");
  }
  EXPECT_TRUE(caught);
}

static void command_sets_directory_and_environment(void) {
  String work = _scratch(%"cwd");
  UvLoop loop = UvLoop.new();
  defer loop.free();

  UvProcess child = loop.command(%("/bin/sh" "-c" "pwd; printenv MODE"))
    .directory(work)
    .environment(%{"MODE": "strict", "PATH": "/usr/bin:/bin"})
    .start();
  defer child.free();
  child.close_stdin();
  loop.run(UV_RUN_DEFAULT);

  EXPECT_TRUE(child.stdout().contains(%"x2c-libuv-cwd"));
  EXPECT_TRUE(child.stdout().contains(%"strict"));
  EXPECT_INT_EQ(child.exit_status(), 0);
}

static void command_rejects_options_after_it_starts(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess child = loop.spawn(%("/usr/bin/printf" "x"));
  defer child.free();
  child.close_stdin();

  int caught = 0;
  try child.deadline(50);
  catch %(bad-state (library ?library) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"deadline");
  }
  EXPECT_TRUE(caught);
  loop.run(UV_RUN_DEFAULT);
}

static void command_rejects_bad_argv_environment_and_stdio(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  int caught = 0;

  try loop.command(%("/usr/bin/printf" 7));
  catch %(bad-types (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"command");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try loop.command(%("/usr/bin/printf" "x")).environment(%{"MODE": 7});
  catch %(bad-types (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"environment");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try loop.command(%("/usr/bin/printf" "x"))
    .stdio(<pipe>, <pipe>, <invalid>);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"stdio");
  }
  EXPECT_TRUE(caught);
}

static void process_stdio_can_be_captured_inherited_or_ignored(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess child = loop.command(%("/bin/sh" "-c" "printf captured"))
    .stdio(<ignore>, <pipe>, <ignore>).start();
  defer child.free();
  child.close_stdin();
  loop.run(UV_RUN_DEFAULT);
  EXPECT_STR_EQ(child.stdout(), %"captured");

  int caught = 0;
  try child.stderr();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"stderr");
  }
  EXPECT_TRUE(caught);

  UvProcess inherited = loop.command(%("/usr/bin/true"))
    .stdio(<ignore>, <inherit>, <inherit>).start();
  defer inherited.free();
  loop.run(UV_RUN_DEFAULT);
  EXPECT_INT_EQ(inherited.exit_status(), 0);
}

static void deadline_kills_a_child_that_overruns(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess slow = loop.command(%("/bin/sh" "-c" "exec sleep 30"))
    .deadline(150).start();
  defer slow.free();
  slow.close_stdin();

  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_TRUE(slow.exited());
  EXPECT_TRUE(slow.timed_out());
  EXPECT_INT_EQ(slow.term_signal(), SIGKILL);
}

static void deadline_leaves_a_prompt_child_alone(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess quick = loop.command(%("/usr/bin/printf" "quick"))
    .deadline(30000).start();
  defer quick.free();
  quick.close_stdin();

  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_FALSE(quick.timed_out());
  EXPECT_STR_EQ(quick.stdout(), %"quick");
  EXPECT_INT_EQ(quick.exit_status(), 0);

  int caught = 0;
  try quick.kill(SIGTERM);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"process_kill");
  }
  EXPECT_TRUE(caught);
}

static void _record_async(UvAsync async, Var value) {
  Array calls = value;
  calls.push((int) calls.len() + 1);
  async.stop();
}

static void async_sends_coalesce_and_stop_is_idempotent(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  Array calls = %[];
  UvAsync async = loop.async(calls, _record_async);

  EXPECT_PTR_EQ(async.loop(), loop);
  EXPECT_PTR_EQ(async.native()->data, async);
  EXPECT_PTR_EQ(async.send(), async);
  async.send().send();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(calls.len(), 1);
  EXPECT_NULL(async.stop());
  EXPECT_NULL(async.stop());
}

typedef struct AsyncNotifyInput {
  UvAsync async;
  int answer;
} AsyncNotifyInput;

typedef struct AsyncNotifyState {
  Thread sender;
  List result;
  uv_thread_t loop_thread;
  uv_thread_t callback_thread;
  int calls;
} AsyncNotifyState;

static Var _notify_loop(const void *input, size_t size) {
  if (size != sizeof(AsyncNotifyInput)) {
    raise %(bad-arg (owner "libuv async test worker"));
  }
  const AsyncNotifyInput *notify = input;
  int answer = notify.answer;
  notify.async.send();
  return %((answer $answer) (source thread));
}

static void _join_async_sender(UvAsync async, Var value) {
  AsyncNotifyState *state = value.pointer();
  state.callback_thread = uv_thread_self();
  state.calls++;
  state.result = state.sender.join();
  state.sender.free();
  state.sender = NULL;
  async.stop();
}

static void async_thread_wakes_the_loop_and_exports_its_result(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  AsyncNotifyState state = { 0 };
  state.loop_thread = uv_thread_self();
  UvAsync async = loop.async(
    Var.new(<p48>, &state), _join_async_sender
  );
  AsyncNotifyInput input = { async, 42 };
  state.sender = Thread.start(_notify_loop, &input, sizeof(input));

  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.calls, 1);
  EXPECT_NULL(state.sender);
  EXPECT_INT_EQ(state.result.assoc(<answer>).integer(), 42);
  EXPECT_TRUE(state.result.assoc(<source>).symbol() == <thread>);
  EXPECT_TRUE(uv_thread_equal(
    &state.loop_thread, &state.callback_thread
  ));
}

static void _record_tick(UvTimer timer, Var value) {
  Array ticks = value;
  ticks.push((int) ticks.len() + 1);
  if (ticks.len() == 3) timer.stop();
}

static void timer_fires_once_and_repeats(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  Array once = Array.new();
  Array repeated = Array.new();

  loop.timer(1, 0, once, _record_tick);
  loop.timer(1, 1, repeated, _record_tick);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);

  EXPECT_INT_EQ(once.len(), 1);
  EXPECT_INT_EQ(repeated.len(), 3);
  EXPECT_INT_EQ(((Var) repeated[2]).int(), 3);
}

static void _stop_the_loop(UvTimer timer, Var value) {
  Array reached = value;
  reached.push(%"budget");
  timer.loop().stop();
}

typedef struct PhaseState {
  UvIdle idle;
  UvPrepare prepare;
  UvCheck check;
  Array order;
  uv_thread_t loop_thread;
  int same_thread;
} PhaseState;

static void _record_idle(UvIdle idle, Var value) {
  PhaseState *state = value.pointer();
  uv_thread_t current = uv_thread_self();
  state.same_thread += uv_thread_equal(&state.loop_thread, &current);
  state.order.push(<idle>);
}

static void _record_prepare(UvPrepare prepare, Var value) {
  PhaseState *state = value.pointer();
  uv_thread_t current = uv_thread_self();
  state.same_thread += uv_thread_equal(&state.loop_thread, &current);
  state.order.push(<prepare>);
}

static void _record_poll(UvAsync async, Var value) {
  PhaseState *state = value.pointer();
  state.order.push(<poll>);
  async.stop();
}

static void _record_check(UvCheck check, Var value) {
  PhaseState *state = value.pointer();
  uv_thread_t current = uv_thread_self();
  state.same_thread += uv_thread_equal(&state.loop_thread, &current);
  state.order.push(<check>);
  state.idle.stop();
  state.prepare.stop();
  check.stop();
}

static void loop_phases_keep_their_order_and_native_handles(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  PhaseState state = { 0 };
  state.order = %[];
  state.loop_thread = uv_thread_self();
  Var value = Var.new(<p48>, &state);
  state.prepare = loop.prepare(value, _record_prepare);
  state.check = loop.check(value, _record_check);
  state.idle = loop.idle(value, _record_idle);
  UvAsync poll = loop.async(value, _record_poll);

  EXPECT_PTR_EQ(state.idle.loop(), loop);
  EXPECT_PTR_EQ(state.prepare.loop(), loop);
  EXPECT_PTR_EQ(state.check.loop(), loop);
  EXPECT_PTR_EQ(state.idle.native()->data, state.idle);
  EXPECT_PTR_EQ(state.prepare.native()->data, state.prepare);
  EXPECT_PTR_EQ(state.check.native()->data, state.check);
  poll.send();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);

  EXPECT_INT_EQ(state.order.len(), 4);
  EXPECT_TRUE(((Var) state.order[0]).symbol() == <idle>);
  EXPECT_TRUE(((Var) state.order[1]).symbol() == <prepare>);
  EXPECT_TRUE(((Var) state.order[2]).symbol() == <poll>);
  EXPECT_TRUE(((Var) state.order[3]).symbol() == <check>);
  EXPECT_INT_EQ(state.same_thread, 3);
  EXPECT_NULL(state.idle.stop());
  EXPECT_NULL(state.prepare.stop());
  EXPECT_NULL(state.check.stop());
  EXPECT_INT_EQ(loop.run(UV_RUN_NOWAIT), 0);
}

static void _ignore_prepare(UvPrepare prepare, Var value) {
  (void) prepare;
  (void) value;
}

static void _ignore_check(UvCheck check, Var value) {
  (void) check;
  (void) value;
}

static void _ignore_idle(UvIdle idle, Var value) {
  (void) idle;
  (void) value;
}

static void idle_forces_a_zero_timeout_poll(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvPrepare prepare = loop.prepare(void, _ignore_prepare);
  UvCheck check = loop.check(void, _ignore_check);
  loop.run(UV_RUN_NOWAIT);
  EXPECT_INT_EQ(uv_backend_timeout(loop.native()), -1);

  UvIdle idle = loop.idle(void, _ignore_idle);
  EXPECT_INT_EQ(uv_backend_timeout(loop.native()), 0);
  idle.stop();
  prepare.stop();
  check.stop();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
}

static void _raise_inside_idle(UvIdle idle, Var value) {
  (void) idle;
  (void) value;
  raise %(malformed (library "test") (reason "an idle callback failed"));
}

static void _raise_inside_prepare(UvPrepare prepare, Var value) {
  (void) prepare;
  (void) value;
  raise %(malformed (library "test")
          (reason "a prepare callback failed"));
}

static void _raise_inside_check(UvCheck check, Var value) {
  (void) check;
  (void) value;
  raise %(malformed (library "test") (reason "a check callback failed"));
}

static void _close_async(UvAsync async, Var value) {
  (void) value;
  async.stop();
}

static void phase_callback_errors_are_independent_and_resumable(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  Array guard = %[];
  UvTimer guard_timer = loop.timer(250, 0, guard, _stop_the_loop);
  loop.idle(void, _raise_inside_idle);

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library *) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"an idle callback failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(guard.len(), 0);
  guard_timer.stop();
  loop.run(UV_RUN_NOWAIT);

  guard = %[];
  guard_timer = loop.timer(250, 0, guard, _stop_the_loop);
  loop.prepare(void, _raise_inside_prepare);
  caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library *) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"a prepare callback failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(guard.len(), 0);
  guard_timer.stop();
  loop.run(UV_RUN_NOWAIT);

  guard = %[];
  guard_timer = loop.timer(250, 0, guard, _stop_the_loop);
  UvAsync wake = loop.async(void, _close_async);
  loop.check(void, _raise_inside_check);
  wake.send();
  caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library *) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"a check callback failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(guard.len(), 0);
  guard_timer.stop();

  Array resumed = %[];
  loop.timer(0, 0, resumed, _record_tick);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(resumed.len(), 1);
}

static void loop_phases_reject_bad_arguments(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  int caught = 0;

  try loop.idle(void, NULL);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"idle");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try loop.prepare(void, NULL);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"prepare");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try loop.check(void, NULL);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"check");
  }
  EXPECT_TRUE(caught);
}

static void timer_deadline_stops_a_running_loop(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess slow = loop.spawn(%("/bin/sh" "-c" "exec sleep 30"));
  defer slow.free();
  slow.close_stdin();

  Array reached = Array.new();
  loop.timer(100, 0, reached, _stop_the_loop);
  loop.run(UV_RUN_DEFAULT);

  EXPECT_INT_EQ(reached.len(), 1);
  EXPECT_FALSE(slow.exited());
  slow.kill(SIGTERM);
  loop.run(UV_RUN_DEFAULT);
  EXPECT_TRUE(slow.exited());
  EXPECT_INT_EQ(slow.term_signal(), SIGTERM);
}

static void _handle_interrupt(UvSignal signal, Var value) {
  Array seen = value;
  seen.push(signal.number());
  signal.loop().stop();
  signal.stop();
}

static void signal_handler_runs_inside_the_loop(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess slow = loop.spawn(%("/bin/sh" "-c" "exec sleep 30"));
  defer slow.free();
  slow.close_stdin();

  Array seen = Array.new();
  loop.signal(SIGUSR1, seen, _handle_interrupt);
  uv_kill(uv_os_getpid(), SIGUSR1);
  loop.run(UV_RUN_DEFAULT);

  EXPECT_INT_EQ(seen.len(), 1);
  EXPECT_INT_EQ(((Var) seen[0]).int(), SIGUSR1);
  slow.kill(SIGTERM);
  loop.run(UV_RUN_DEFAULT);
  EXPECT_TRUE(slow.exited());
}

static void _record_entry(UvWatch watch, Var value) {
  Array seen = value;
  if (!watch.entry()) return;
  seen.push(watch.entry());
  watch.loop().stop();
  watch.stop();
}

static void _abandon_watch(UvTimer timer, Var value) {
  (void) value;
  timer.loop().stop();
}

static void watch_reports_an_entry_a_child_creates(void) {
  String work = _scratch(%"same-name");
  UvLoop loop = UvLoop.new();
  defer loop.free();

  unlink(%"$work/x2c-libuv-same-name");
  Array seen = Array.new();
  UvWatch watch = loop.watch(work, seen, _record_entry);
  EXPECT_NULL(watch.entry());
  loop.timer(5000, 0, seen, _abandon_watch);

  UvProcess touch = loop.command(%("/usr/bin/touch" "x2c-libuv-same-name"))
    .directory(work).start();
  defer touch.free();
  touch.close_stdin();
  loop.run(UV_RUN_DEFAULT);

  EXPECT_TRUE(seen.len() > 0);
  EXPECT_STR_EQ(
    ((Var) seen[seen.len() - 1]).string(), %"x2c-libuv-same-name"
  );
}

static void _record_change(UvWatch watch, Var value) {
  Array seen = value;
  seen.push(watch.entry() ? watch.entry() : %"<absent>");
  seen.push(watch.kind());
  watch.loop().stop();
  watch.stop();
}

static void watch_distinguishes_content_changes(void) {
  String work = _scratch(%"watch-change");
  String path = %"$work/content.txt";
  File seed = File.open(path, %"w");
  seed.puts(%"before\n");
  seed.close();

  UvLoop loop = UvLoop.new();
  defer loop.free();
  Array seen = %[];
  loop.watch(path, seen, _record_change);
  loop.timer(5000, 0, seen, _abandon_watch);
  UvProcess append = loop.command(%(
    "/bin/sh" "-c" "printf 'after\\n' >> content.txt"
  )).directory(work).start();
  defer append.free();
  append.close_stdin();
  loop.run(UV_RUN_DEFAULT);
  if (!append.exited()) loop.run(UV_RUN_DEFAULT);

  EXPECT_INT_EQ(seen.len(), 2);
  EXPECT_TRUE(((Var) seen[1]).symbol() == <change>);
}

static void native_handles_reach_the_pinned_api(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess child = loop.spawn(%("/usr/bin/printf" "native"));
  defer child.free();
  child.close_stdin();

  EXPECT_NOT_NULL(loop.native());
  EXPECT_INT_EQ(uv_process_get_pid(child.native()), child.pid());

  uv_timer_t extra;
  EXPECT_INT_EQ(uv_timer_init(loop.native(), &extra), 0);
  uv_close((uv_handle_t *) &extra, NULL);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(child.exit_status(), 0);
}

static void _raise_inside_a_timer(UvTimer timer, Var value) {
  (void) timer;
  (void) value;
  raise %(malformed (library "test") (reason "a callback body failed"));
}

static void a_failed_callback_reaches_the_caller(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  loop.timer(1, 1, 0, _raise_inside_a_timer);

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library ?library) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"a callback body failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(loop.run(UV_RUN_NOWAIT), 0);
}

static void _raise_inside_a_signal(UvSignal signal, Var value) {
  (void) signal;
  (void) value;
  raise %(malformed (library "test") (reason "a signal callback failed"));
}

static void a_failed_signal_callback_reaches_the_caller_once(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess slow = loop.spawn(%("/bin/sh" "-c" "exec sleep 30"));
  defer slow.free();
  slow.close_stdin();
  loop.signal(SIGUSR2, 0, _raise_inside_a_signal);
  Array guard = %[];
  UvTimer guard_timer = loop.timer(250, 0, guard, _stop_the_loop);
  uv_kill(uv_os_getpid(), SIGUSR2);

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library *) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"a signal callback failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(guard.len(), 0);
  guard_timer.stop();
  slow.kill(SIGTERM);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
}

static void _raise_inside_a_watch(UvWatch watch, Var value) {
  (void) watch;
  (void) value;
  raise %(malformed (library "test") (reason "a watch callback failed"));
}

static void _raise_inside_async(UvAsync async, Var value) {
  (void) async;
  (void) value;
  raise %(malformed (library "test")
          (reason "an async callback failed"));
}

static void a_failed_async_callback_stops_and_resumes_the_loop(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvProcess slow = loop.spawn(%("/bin/sh" "-c" "exec sleep 30"));
  defer slow.free();
  slow.close_stdin();
  UvAsync async = loop.async(void, _raise_inside_async);
  Array guard = %[];
  UvTimer guard_timer = loop.timer(250, 0, guard, _stop_the_loop);
  async.send();

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library ?library) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"test");
    EXPECT_STR_EQ(reason.string(), %"an async callback failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_FALSE(slow.exited());
  EXPECT_INT_EQ(guard.len(), 0);
  guard_timer.stop();
  EXPECT_NULL(async.stop());
  EXPECT_NULL(async.stop());

  slow.kill(SIGTERM);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_TRUE(slow.exited());
}

static void _write_watched_file(UvTimer timer, Var value) {
  (void) timer;
  String path = value.string();
  File file = File.open(path, "w");
  file.puts(%"changed\n");
  file.close();
}

static void a_failed_watch_callback_reaches_the_caller(void) {
  String work = _scratch(%"failed-watch");
  String path = %"$work/watched.txt";
  UvLoop loop = UvLoop.new();
  defer loop.free();
  loop.watch(work, void, _raise_inside_a_watch);
  UvTimer writer = loop.timer(1, 10, path, _write_watched_file);
  UvTimer timeout = loop.timer(5000, 0, void, _abandon_watch);

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library *) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"a watch callback failed");
  }
  writer.stop();
  timeout.stop();
  EXPECT_TRUE(caught);
  loop.run(UV_RUN_NOWAIT);
}

static void loop_free_closes_active_handles(void) {
  UvLoop loop = UvLoop.new();
  loop.idle(void, _ignore_idle);
  loop.prepare(void, _ignore_prepare);
  loop.check(void, _ignore_check);
  loop.timer(30000, 30000, 0, _stop_the_loop);
  EXPECT_NULL(loop.free());
}

static void async_watch_and_timer_reject_bad_arguments(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();

  int caught = 0;
  try loop.async(void, NULL);
  catch %(bad-arg (library ?library) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"async");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try loop.timer(-1, 0, 0, _stop_the_loop);
  catch %(bad-arg (library ?library) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"timer");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try loop.watch(%"/no/such/directory/here", 0, _record_entry);
  catch %(io-fail (library ?library) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"fs_event_start");
  }
  EXPECT_TRUE(caught);
}

void uv_suite(void) {
  $test.run(process_captures_stdout_stderr_and_exit);
  $test.run(process_stdin_and_concurrent_children);
  $test.run(process_binary_output_uses_bytes);
  $test.run(process_output_limit_reports_libuv_error);
  $test.run(process_free_waits_for_every_close_callback);
  $test.run(command_sets_directory_and_environment);
  $test.run(command_rejects_options_after_it_starts);
  $test.run(command_rejects_bad_argv_environment_and_stdio);
  $test.run(process_stdio_can_be_captured_inherited_or_ignored);
  $test.run(deadline_kills_a_child_that_overruns);
  $test.run(deadline_leaves_a_prompt_child_alone);
  $test.run(async_sends_coalesce_and_stop_is_idempotent);
  $test.run(async_thread_wakes_the_loop_and_exports_its_result);
  $test.run(timer_fires_once_and_repeats);
  $test.run(loop_phases_keep_their_order_and_native_handles);
  $test.run(idle_forces_a_zero_timeout_poll);
  $test.run(phase_callback_errors_are_independent_and_resumable);
  $test.run(loop_phases_reject_bad_arguments);
  $test.run(timer_deadline_stops_a_running_loop);
  $test.run(signal_handler_runs_inside_the_loop);
  $test.run(watch_reports_an_entry_a_child_creates);
  $test.run(watch_distinguishes_content_changes);
  $test.run(native_handles_reach_the_pinned_api);
  $test.run(a_failed_callback_reaches_the_caller);
  $test.run(a_failed_signal_callback_reaches_the_caller_once);
  $test.run(a_failed_watch_callback_reaches_the_caller);
  $test.run(a_failed_async_callback_stops_and_resumes_the_loop);
  $test.run(loop_free_closes_active_handles);
  $test.run(async_watch_and_timer_reject_bad_arguments);
}

int main(void) {
  TestHarness_begin();
  $test.suite(uv_suite);
  return TestHarness_finish();
}
