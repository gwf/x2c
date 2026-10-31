/*  test-task.x -- cooperative batch execution with ordinary Channels */

#include "task.x"
#include "test-support.x"
#include "test-macros.x"
#include <stdatomic.h>

static void task_empty_batch_has_no_completion(void) {
  Array completed = auto [];
  Task.run([], %!(Var result) => completed.push(result));
  EXPECT_INT_EQ(completed.len(), 0);
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

void task_suite(void) {
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
}
