/*  test-task.x -- cooperative batch execution with ordinary Channels */

#include "task.x"
#include "json.x"
#include "regex.x"
#include "test-support.x"
#include "test-macros.x"
#include <stdatomic.h>
#include <sys/mman.h>
#include <unistd.h>
#ifdef __APPLE__
#include <malloc/malloc.h>
#endif

class TaskRenderProbe { Channel gate; int calls; } *;

void TaskRenderProbe.init(TaskRenderProbe probe, Channel gate) {
  probe.gate = gate;
  probe.calls = 0;
}

String TaskRenderProbe.repr(TaskRenderProbe probe) {
  if (++probe.calls == 1) {
    probe.gate.receive();
  }
  return "item";
}

static void task_empty_batch_has_no_completion(void) {
  Array completed = auto [];
  Task.run([], %!(Var result) => completed.push(result));
  EXPECT_INT_EQ(completed.len(), 0);
  int nested = 0;
  Func inner = %!(void) => 1;
  Task.run([%!(void) using &nested, &inner => {
    try Task.run([inner]);
    catch %(bad-state (operation "Task.run")
                      (reason "nested task batches are unsupported")):
      nested = 1;
    return void;
  }], NULL);
  EXPECT_INT_EQ(nested, 1);
}

static void task_request_reply_closes_after_clients_finish(void) {
  $test.scoped();
  Channel requests = auto Channel.new(2);
  Channel first = auto Channel.new();
  Channel second = auto Channel.new();
  Array answers = auto [], jobs = auto [];
  jobs.push(%!(void) => {
    foreach (List request in requests) {
      String text = request[0];
      Channel reply = request[1];
      reply.send(text.upper());
    }
    return <service>;
  });
  jobs.push(%!(void) => {
    requests.send($("first", first));
    return first.receive();
  });
  jobs.push(%!(void) => {
    requests.send($("second", second));
    return second.receive();
  });
  Task.run(jobs, %!(Var result) => {
    if (result is <string>) {
      answers.push(result);
      if (answers.len() == 2) requests.close();
    }
  });
  EXPECT_INT_EQ(answers.len(), 2);
  answers.sort();
  EXPECT_STR_EQ(answers[0].string(), "FIRST");
  EXPECT_STR_EQ(answers[1].string(), "SECOND");
}

static void task_rendezvous_and_buffered_channels_drain(void) {
  $test.scoped();
  Channel values = auto Channel.new();
  Channel results = auto Channel.new(2);
  Task.run([
    %!(void) => {
      values.send(NULL);
      values.send(41);
      values.close();
      return void;
    },
    %!(void) => {
      results.send(values.receive());
      results.send(values.receive());
      if (values.receive() is not void) raise %(invariant);
      results.close();
      return void;
    }
  ]);
  EXPECT_TRUE(results.receive().is_null());
  EXPECT_INT_EQ(results.receive().int(), 41);
  EXPECT_TRUE(results.receive() is void);
}

static void task_array_return_preserves_identity_and_owner(void) {
  $test.scoped();
  Scope owner = *Scope.top();
  Array alias = NULL, result = NULL;
  Task.run([
    %!(void) using &alias => {
      Array value = [17, 29];
      alias = value;
      return value;
    }
  ], %!(Var value) using &result => result = value.array());
  EXPECT_PTR_EQ(result, alias);
  EXPECT_PTR_EQ(Scope.owner(result), owner);
  EXPECT_INT_EQ(result[1].int(), 29);
  alias[0] = 31;
  EXPECT_INT_EQ(result[0].int(), 31);
}

static void task_service_failure_stops_waiting_client(void) {
  $test.scoped();
  Channel ready = auto Channel.new();
  Channel reply = auto Channel.new();
  Array cleanup = auto [0, 0];
  int caught = 0, original = 0;
  try Task.run([
    %!(void) => {
      defer cleanup[0] = cleanup[0].int() + 1;
      ready.receive();
      raise %(bad-arg (primary 47));
      return void;
    },
    %!(void) => {
      defer cleanup[1] = cleanup[1].int() + 1;
      ready.send(<ready>);
      return reply.receive();
    }
  ], NULL);
  catch %(join-fail (errors ?errors)): {
    caught++;
    foreach (List entry in errors.list())
      if (entry.assoc(<code>) == <bad-arg>)
        original = entry.assoc(<detail>).list().assoc(<primary>).int();
  }
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(original, 47);
  EXPECT_INT_EQ(cleanup[0].int(), 1);
  EXPECT_INT_EQ(cleanup[1].int(), 1);
}

static void task_callback_failure_preserves_primary_error(void) {
  $test.scoped();
  Channel blocked = auto Channel.new(), release = auto Channel.new();
  Array cleanup = auto [0];
  int caught = 0;
  try Task.run([
    %!(void) => {
      release.receive();
      return 11;
    },
    %!(void) => {
      defer cleanup[0] = cleanup[0].int() + 1;
      release.send(<go>);
      return blocked.receive();
    }
  ], %!(Var value) => {
    (void) value;
    raise %(bad-arg (primary 53));
  });
  catch %(bad-arg (primary ?value)): caught = value.int();
  EXPECT_INT_EQ(caught, 53);
  EXPECT_INT_EQ(cleanup[0].int(), 1);
}

static void task_context_export_keeps_its_base_destination(void) {
  $test.scoped();
  Scope owner = *Scope.top();
  Channel ready = auto Channel.new(1), resume = auto Channel.new();
  Channel done = auto Channel.new();
  Array results = auto [];
  Task.run([
    %!(void) => {
      auto Context context = Context.open();
      ready.send(<ready>);
      resume.receive();
      Array result = context.export([67]);
      done.send(<done>);
      return result;
    },
    %!(void) => {
      ready.receive();
      auto Context context = Context.open();
      resume.send(<resume>);
      done.receive();
      return void;
    }
  ], %!(Var value) => {
    if (value is <array>) results.push(value);
  });
  EXPECT_INT_EQ(results.len(), 1);
  Array result = results[0];
  EXPECT_INT_EQ(result[0].int(), 67);
  EXPECT_PTR_EQ(Scope.owner(result), owner);
}

static Symbol _task_observe_parent(List errors, Var data) {
  (void) errors;
  Array seen = data;
  seen[0] = seen[0].int() + 1;
  return <declined>;
}

static void task_inherits_owners_and_policy_without_activations(void) {
  $test.scoped();
  auto Context caller = Context.open_isolated();
  Scope owner = *Scope.top();
  Pool pool = Pool.current();
  MatchCache cache = MatchCache.current();
  Error.policy_set(<task-prob>, <collect>);
  Error.bound_set(79);
  Error.raise(<task-prob>, %((where "caller")));
  int count = Error.count();
  Channel gate = auto Channel.new(1);
  Array observed = auto [0], facts = auto [], completed = auto [];
  ErrorHandler handler = Error.push(_task_observe_parent, observed);
  defer Error.pop(handler);
  Func first = %!(void) => 0;
  Task.run([
    first,
    %!(void) using &owner, &pool, &cache => {
      gate.receive();
      facts.push(Context.current() == NULL);
      facts.push(*Scope.top() == owner);
      facts.push(Pool.current() == pool);
      facts.push(Error.policy_get(<task-prob>) == <collect>);
      facts.push(Error.bound() == 79);
      facts.push(Error.count() == 0);
      facts.push(MatchCache.current() != cache);
      Error.raise(<task-prob>, %((where "task")));
      facts.push(Error.count() == 1);
      Error.policy_set(<task-prob>, <ignore>);
      return 1;
    }
  ], %!(Var result) using &caller, &owner, &pool => {
    EXPECT_PTR_EQ(Context.current(), caller);
    EXPECT_PTR_EQ(*Scope.top(), owner);
    EXPECT_PTR_EQ(Pool.current(), pool);
    completed.push(result);
    if (result.int() == 0) {
      Error.policy_set(<task-prob>, <ignore>);
      gate.send(<go>);
    }
  });
  EXPECT_INT_EQ(facts.len(), 8);
  foreach (Var fact in facts) EXPECT_TRUE(fact.int());
  EXPECT_INT_EQ(completed.len(), 2);
  EXPECT_INT_EQ(observed[0].int(), 0);
  EXPECT_INT_EQ(Error.count(), count);
  EXPECT_PTR_EQ(MatchCache.current(), cache);
}

static int _task_nested_cleanup(Channel gate, Array cleanup) {
  defer cleanup[0] = cleanup[0].int() + 1;
  defer {
    try cleanup[3] = cleanup[3].int() + 1;
    finally cleanup[4] = cleanup[4].int() + 1;
  }
  try {
    try {
      gate.receive();
      return 83;
    }
    finally cleanup[1] = cleanup[1].int() + 1;
  }
  finally cleanup[2] = cleanup[2].int() + 1;
  return -1;
}

static void task_resumed_return_runs_nested_cleanup_once(void) {
  $test.scoped();
  Channel gate = auto Channel.new();
  Array cleanup = auto [0, 0, 0, 0, 0], results = auto [];
  Task.run([
    %!(void) => { return _task_nested_cleanup(gate, cleanup); },
    %!(void) => {
      gate.send(<go>);
      return void;
    }
  ], %!(Var value) => {
    if (value is not void) results.push(value);
  });
  EXPECT_INT_EQ(results.len(), 1);
  EXPECT_INT_EQ(results[0].int(), 83);
  foreach (Var count in cleanup) EXPECT_INT_EQ(count.int(), 1);
}

typedef struct TaskCancelInput {
  Channel ready, blocked, payloads;
  atomic_int *cleaned;
} TaskCancelInput;

static Var _task_cancel_owner(const void *bytes, size_t size) {
  (void) size;
  TaskCancelInput input = *(const TaskCancelInput *) bytes;
  Task.run([
    %!(void) => {
      defer atomic_fetch_add(input.cleaned, 1);
      if (input.payloads) input.payloads.send_owned([89]);
      input.ready.send(<ready>);
      return input.blocked.receive();
    }
  ], NULL);
  return void;
}

static void task_owner_stop_finishes_parked_cleanup(void) {
  $test.scoped();
  Channel ready = auto Channel.new(), blocked = auto Channel.new();
  atomic_int cleaned = 0;
  TaskCancelInput input = {ready, blocked, NULL, &cleaned};
  Thread owner = Thread.start_raw(_task_cancel_owner, &input, sizeof(input));
  ready.receive();
  owner.stop();
  int caught = 0;
  try owner.join();
  catch %(join-fail *): caught++;
  owner.free();
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(atomic_load(&cleaned), 1);
}

static void task_owner_stop_keeps_committed_owned_payload(void) {
  $test.scoped();
  Channel ready = auto Channel.new(), blocked = auto Channel.new();
  Channel payloads = auto Channel.new(1);
  atomic_int cleaned = 0;
  TaskCancelInput input = {ready, blocked, payloads, &cleaned};
  Thread owner = Thread.start_raw(_task_cancel_owner, &input, sizeof(input));
  ready.receive();
  owner.stop();
  int caught = 0;
  try owner.join();
  catch %(join-fail *): caught++;
  owner.free();
  payloads.close();
  Array payload = payloads.receive();
  EXPECT_INT_EQ(payload[0].int(), 89);
  EXPECT_TRUE(payloads.receive() is void);
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(atomic_load(&cleaned), 1);
}

static Var _task_native_producer(const void *bytes, size_t size) {
  (void) size;
  Channel values = *(const Channel *)bytes;
  for (int i = 1; i <= 4000; i++) values.send(i);
  values.close();
  return void;
}

static void task_native_notifications_do_not_repeat_completions(void) {
  $test.scoped();
  Channel values = auto Channel.new(1);
  Thread producer = Thread.start_raw(
    _task_native_producer, &values, sizeof(values));
  Array jobs = auto [], totals = auto [];
  for (int i = 0; i < 4; i++)
    jobs.push(%!(void) => {
      int total = 0;
      foreach (int value in values) total += value;
      return total;
    });
  Task.run(jobs, %!(Var result) => totals.push(result));
  producer.join();
  producer.free();
  int total = 0;
  foreach (int value in totals) total += value;
  EXPECT_INT_EQ(totals.len(), 4);
  EXPECT_INT_EQ(total, 4000 * 4001 / 2);
}

static void task_stop_rolls_back_uncommitted_owned_send(void) {
  $test.scoped();
  Channel ready = auto Channel.new(1), pending = auto Channel.new();
  Array payload = [97];
  Scope owner = Scope.owner(payload);
  int caught = 0;
  try Task.run([
    %!(void) => {
      ready.send(<ready>);
      pending.send_owned(payload);
      return void;
    },
    %!(void) => {
      ready.receive();
      raise %(bad-arg (primary 101));
      return void;
    }
  ], NULL);
  catch %(join-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_PTR_EQ(Scope.owner(payload), owner);
  EXPECT_INT_EQ(payload[0].int(), 97);
}

static Lisp _task_lisp_session(Channel gate, int fail) {
  Lisp session = Lisp.kernel();
  Var expected = Var.new(<p48>, session);
  session.set_global("pause", Func.var(%!(void) => {
    EXPECT_PTR_EQ(Lisp.active(), expected.pointer());
    defer EXPECT_PTR_EQ(Lisp.active(), expected.pointer());
    gate.receive();
    EXPECT_PTR_EQ(Lisp.active(), expected.pointer());
    if (fail) raise %(bad-arg (operation "task Lisp callback"));
    return void;
  }));
  return session;
}

static void task_lisp_activations_restore_after_suspension_and_failure(void) {
  $test.scoped();
  for (int fail = 0; fail < 2; fail++) {
    Channel a = auto Channel.new(1);
    Channel b = auto Channel.new(1);
    Lisp left_session = _task_lisp_session(a, fail);
    defer left_session.destroy();
    Lisp right_session = _task_lisp_session(b, 0);
    defer right_session.destroy();
    Var left = Var.new(<p48>, left_session);
    Var right = Var.new(<p48>, right_session);
    Lisp outer = Lisp.kernel();
    defer outer.destroy();
    Var caller = Var.new(<p48>, outer);
    outer.set_global("batch", Func.var(%!(void) => {
      int caught = 0;
      try Task.run([
        %!(void) => {
          ((Lisp)left.pointer()).eval_string("(pause)");
          return void;
        },
        %!(void) => {
          ((Lisp)right.pointer()).eval_string("(pause)");
          return void;
        },
        %!(void) => {
          EXPECT_PTR_EQ(Lisp.active(), NULL);
          a.send(1); b.send(1);
          return void;
        }
      ], %!(Var result) => {
        EXPECT_PTR_EQ(Lisp.active(), caller.pointer());
        return void;
      });
      catch %(join-fail *): caught = 1;
      EXPECT_INT_EQ(caught, fail);
      EXPECT_PTR_EQ(Lisp.active(), caller.pointer());
      return void;
    }));
    outer.eval_string("(batch)");
    EXPECT_PTR_EQ(Lisp.active(), NULL);
  }
}

static void _task_expect_caller_render_path(Var shared) {
  RenderPath duplicate;
  int entered = duplicate.enter(shared.pointer());
  if (entered) duplicate.leave();
  EXPECT_FALSE(entered);
}

static void task_render_paths_restore_after_suspension_and_failure(void) {
  $test.scoped();
  for (int fail = 0; fail < 2; fail++) {
    Channel gate = auto Channel.new(1);
    TaskRenderProbe probe = TaskRenderProbe.new(gate);
    Array array = [probe], outputs = [];
    Map map = {1: probe};
    Var shared = fail ? map.var() : array.var();
    String expected = fail ? "{ 1: item }" : "[ item ]";
    RenderPath caller;
    EXPECT_TRUE(caller.enter(shared.pointer()));
    int caught = 0;
    try {
      try Task.run([
        %!(void) => shared.repr(),
        %!(void) => shared.repr(),
        %!(void) => {
          if (fail) raise %(bad-arg (operation "task renderer"));
          gate.send(1);
          return void;
        }
      ], %!(Var value) => {
        if (value is <string>) outputs.push(value);
        _task_expect_caller_render_path(shared);
      });
      catch %(join-fail *): caught = 1;
      EXPECT_INT_EQ(caught, fail);
      _task_expect_caller_render_path(shared);
    }
    finally caller.leave();
    if (!fail) EXPECT_INT_EQ(outputs.len(), 2);
    foreach (String output in outputs) EXPECT_STR_EQ(output, expected);
    EXPECT_STR_EQ(shared.repr(), expected);
  }
}

static void task_job_storage_obeys_page_boundary_and_zeroes(void) {
  size_t page = sysconf(_SC_PAGESIZE);
  size_t sizes[] = { page - 1, page, page + 1 };
  for (int sample = 0; sample < 3; sample++) {
    size_t size = sizes[sample];
    unsigned char *storage = x2c_task_jobs_new(size);
    if (!EXPECT_NOT_NULL(storage)) continue;
    int zeroed = 1;
    for (size_t i = 0; i < size; i++)
      if (storage[i]) zeroed = 0;
    EXPECT_TRUE(zeroed);
#ifdef __APPLE__
    EXPECT_INT_EQ(malloc_zone_from_ptr(storage) == NULL, size > page);
#endif
    memset(storage, 0xa5, size);
    uintptr_t address = (uintptr_t)storage;
    x2c_task_jobs_free(storage, size);
    if (size > page)
      for (size_t offset = 0; offset < size; offset += page) {
        errno = 0;
        EXPECT_INT_EQ(mprotect((void *)(address + offset), page,
                              PROT_READ | PROT_WRITE), -1);
        EXPECT_INT_EQ(errno, ENOMEM);
      }
  }
}

static void task_large_batch_completes_and_cleans_partial_startup(void) {
  $test.scoped();
  Array jobs = [];
  Func job = %!(void) => 1;
  for (int i = 0; i < 1025; i++) jobs.push(job);
  int completed = 0, caught = 0;
  Task.run(jobs, %!(Var result) using &completed => {
    if (result == 1) completed++;
    return void;
  });
  EXPECT_INT_EQ(completed, 1025);
  jobs[1] = Func.var(NULL);
  try Task.run(jobs, NULL);
  catch %(bad-arg *): caught = 1;
  EXPECT_INT_EQ(caught, 1);
  Task.run([job], %!(Var result) using &completed => {
    if (result == 1) completed++;
    return void;
  });
  EXPECT_INT_EQ(completed, 1026);
}

static void task_configured_stack_sizes_and_invalid_settings(void) {
  $test.scoped();
  const char *previous = getenv("X2C_TASK_STACK_BYTES");
  char *saved = previous ? strdup(previous) : NULL;
  const char *valid[] = { NULL, "32768", "65536", "65537", "1048576" };
  const char *invalid[] = {
    "", "0", "32767", "-32768", "65536x", "18446744073709551615",
    "18446744073709551616"
  };
  try {
    for (int i = 0; i < 5; i++) {
      if (valid[i]) setenv("X2C_TASK_STACK_BYTES", valid[i], 1);
      else unsetenv("X2C_TASK_STACK_BYTES");
      Channel gate = auto Channel.new();
      int completed = 0;
      Task.run([
        %!(void) => gate.receive(),
        %!(void) => { gate.send(42); return 7; }
      ], %!(Var result) using &completed => {
        if (result == 42 || result == 7) completed++;
        return void;
      });
      EXPECT_INT_EQ(completed, 2);
    }
    for (int i = 0; i < 7; i++) {
      setenv("X2C_TASK_STACK_BYTES", invalid[i], 1);
      int caught = 0, entered = 0;
      try Task.run([%!(void) using &entered => { entered++; return void; }]);
      catch %(bad-arg (operation "Task stack capacity")): caught = 1;
      EXPECT_INT_EQ(caught, 1);
      EXPECT_INT_EQ(entered, 0);
    }
    setenv("X2C_TASK_STACK_BYTES", "65536", 1);
    int completed = 0;
    Func job = %!(void) => 1;
    Task.run([job], %!(Var value) using &completed => {
      completed += value.int();
      return void;
    });
    EXPECT_INT_EQ(completed, 1);
  } finally {
    if (saved) setenv("X2C_TASK_STACK_BYTES", saved, 1);
    else unsetenv("X2C_TASK_STACK_BYTES");
    free(saved);
  }
}

/* Regex, JSON, and the Lisp reader size their nesting limits for an 8 MiB
   stack. On the smallest task stack each stops at the stack floor and
   raises its own cause instead of overflowing. */
static void task_small_stack_bounds_library_recursion(void) {
  $test.scoped();
  String pairs = "ab".repeat(1990);
  String arrays = %"$("[".repeat(512))$("]".repeat(512))";
  String lists = %"$("(".repeat(1000))x$(")".repeat(1000))";
  Var nested = Json.parse(arrays);
  int matched = 0, parsed = 0, written = 0, read = 0;
  Func job = %!(void) using &matched, &parsed, &written, &read => {
    try Regex.compile("^(?:ab)*$").match(pairs);
    catch %(size-limit (operation "Regex.match") *): matched = 1;
    try Json.parse(arrays);
    catch %(malformed (operation "Json.parse")
                      (reason "nesting exceeds the stack") *): parsed = 1;
    try nested.json();
    catch %(size-limit (operation "Var.json")
                       (reason "nesting exceeds the stack")): written = 1;
    unsigned cursor = 0;
    try lists.read_lisp_form(cursor, NULL);
    catch %(size-limit (operation "Lisp.read") *): read = 1;
    return void;
  };
  const char *previous = getenv("X2C_TASK_STACK_BYTES");
  char *saved = previous ? strdup(previous) : NULL;
  try {
    setenv("X2C_TASK_STACK_BYTES", "32768", 1);
    Task.run([job]);
  } finally {
    if (saved) setenv("X2C_TASK_STACK_BYTES", saved, 1);
    else unsetenv("X2C_TASK_STACK_BYTES");
    free(saved);
  }
  EXPECT_INT_EQ(matched, 1);
  EXPECT_INT_EQ(parsed, 1);
  EXPECT_INT_EQ(written, 1);
  EXPECT_INT_EQ(read, 1);
}

void task_suite(void) {
  $test.run(task_configured_stack_sizes_and_invalid_settings);
  $test.run(task_small_stack_bounds_library_recursion);
  $test.run(task_empty_batch_has_no_completion);
  $test.run(task_request_reply_closes_after_clients_finish);
  $test.run(task_rendezvous_and_buffered_channels_drain);
  $test.run(task_array_return_preserves_identity_and_owner);
  $test.run(task_service_failure_stops_waiting_client);
  $test.run(task_callback_failure_preserves_primary_error);
  $test.run(task_context_export_keeps_its_base_destination);
  $test.run(task_inherits_owners_and_policy_without_activations);
  $test.run(task_resumed_return_runs_nested_cleanup_once);
  $test.run(task_owner_stop_finishes_parked_cleanup);
  $test.run(task_owner_stop_keeps_committed_owned_payload);
  $test.run(task_native_notifications_do_not_repeat_completions);
  $test.run(task_stop_rolls_back_uncommitted_owned_send);
  $test.run(task_lisp_activations_restore_after_suspension_and_failure);
  $test.run(task_render_paths_restore_after_suspension_and_failure);
  $test.run(task_job_storage_obeys_page_boundary_and_zeroes);
  $test.run(task_large_batch_completes_and_cleans_partial_startup);
}
