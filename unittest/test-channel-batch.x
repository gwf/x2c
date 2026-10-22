/*  test-channel-batch.x -- failure cleanup across Channel and Thread.run */

#include "channel.x"
#include "test-support.x"
#include "test-macros.x"
#include <stdatomic.h>

static atomic_int batch_payload_drops;

static void _batch_payload_drop(void *value) {
  (void) value;
  atomic_fetch_add(&batch_payload_drops, 1);
}

static Map _batch_payload(void) {
  Map payload = {};
  Scope owner = payload;
  Scope.malloc_finalized_in(&owner, 1, _batch_payload_drop);
  payload["value"] = 37;
  return payload;
}

static void channel_batch_failure_reclaims_queued_owned_payload(void) {
  $test.scoped();
  Channel results = Channel.new(1);
  Channel ready = $auto(Channel.new());
  atomic_store(&batch_payload_drops, 0);
  int caught = 0;
  try Thread.run([
    %!(void) => {
      results.send_owned(_batch_payload());
      ready.send(<ready>);
      return void;
    },
    %!(void) => {
      ready.receive();
      raise %(bad-arg (primary 81));
      return void;
    }
  ]);
  catch %(join-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(atomic_load(&batch_payload_drops), 0);
  results.cleanup();
  EXPECT_INT_EQ(atomic_load(&batch_payload_drops), 1);
}

static void channel_batch_receiver_failure_reclaims_owned_payload(void) {
  $test.scoped();
  Channel results = $auto(Channel.new());
  atomic_store(&batch_payload_drops, 0);
  int caught = 0;
  try Thread.run([
    %!(void) => {
      results.send_owned(_batch_payload());
      return void;
    },
    %!(void) => {
      Map payload = results.receive();
      if (payload["value"] != 37) raise %(bad-state);
      raise %(bad-arg (primary 82));
      return void;
    }
  ]);
  catch %(join-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(atomic_load(&batch_payload_drops), 1);
}

static void channel_batch_transfers_nested_storage_after_worker_exit(void) {
  $test.scoped();
  Channel results = $auto(Channel.new(1));
  atomic_store(&batch_payload_drops, 0);
  Thread.run([
    %!(void) => {
      Map payload = _batch_payload();
      Array child = [19];
      Scope contents = payload.scope();
      child.block().move_to(&contents);
      payload["child"] = child;
      results.send_owned(payload);
      return void;
    }
  ]);
  EXPECT_INT_EQ(atomic_load(&batch_payload_drops), 0);
  Map payload = results.receive();
  Array child = payload["child"];
  EXPECT_INT_EQ(child[0].integer(), 19);
  for (int i = 0; i < 128; ++i) {
    child.push(i);
    payload[i] = i;
  }
  EXPECT_INT_EQ(child[128].integer(), 127);
  EXPECT_INT_EQ(payload[127].integer(), 127);
  EXPECT_PTR_EQ(Scope.owner(child), payload.scope());
  payload.cleanup();
  EXPECT_INT_EQ(atomic_load(&batch_payload_drops), 1);
}

static void channel_batch_worker_failure_stops_both_directions(void) {
  $test.scoped();
  Channel files = $auto(Channel.new());
  Channel results = $auto(Channel.new());
  Channel ready = $auto(Channel.new(2));
  Array jobs = $auto([]);
  atomic_int finished = 0;
  int callbacks = 0, caught = 0;

  jobs.push(%!(void) using &finished => {
    defer atomic_fetch_add(&finished, 1);
    ready.send(<producer>);
    files.send("never consumed");
    return <unexpected>;
  });
  jobs.push(%!(void) using &finished => {
    defer atomic_fetch_add(&finished, 1);
    ready.send(<consumer>);
    results.receive();
    return <unexpected>;
  });
  jobs.push(%!(void) using &finished => {
    defer atomic_fetch_add(&finished, 1);
    ready.receive();
    ready.receive();
    raise %(bad-arg (primary 73));
    return void;
  });

  try Thread.run(jobs, %!(Var result) using &callbacks => {
    (void) result;
    callbacks++;
  });
  catch %(join-fail (errors ?errors)): {
    caught++;
    List entry = errors.list().car();
    EXPECT_INT_EQ(entry.assoc(<detail>).list().assoc(<primary>).int(), 73);
  }
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(callbacks, 0);
  EXPECT_INT_EQ(atomic_load(&finished), 3);
}

static void channel_batch_service_failure_stops_reply_wait(void) {
  $test.scoped();
  Channel requests = $auto(Channel.new());
  Channel reply = $auto(Channel.new());
  Array jobs = $auto([]);
  atomic_int finished = 0;
  int callbacks = 0, caught = 0;

  jobs.push(%!(void) using &finished => {
    defer atomic_fetch_add(&finished, 1);
    requests.receive();
    raise %(bad-arg (primary 91));
    return void;
  });
  jobs.push(%!(void) using &finished => {
    defer atomic_fetch_add(&finished, 1);
    requests.send("request");
    return reply.receive();
  });

  try Thread.run(jobs, %!(Var result) using &callbacks => {
    (void) result;
    callbacks++;
  });
  catch %(join-fail (errors ?errors)): {
    caught++;
    List entry = errors.list().car();
    EXPECT_INT_EQ(entry.assoc(<detail>).list().assoc(<primary>).int(), 91);
  }
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(callbacks, 0);
  EXPECT_INT_EQ(atomic_load(&finished), 2);
}

void channel_batch_suite(void) {
  $test.run(channel_batch_failure_reclaims_queued_owned_payload);
  $test.run(channel_batch_receiver_failure_reclaims_owned_payload);
  $test.run(channel_batch_transfers_nested_storage_after_worker_exit);
  $test.run(channel_batch_worker_failure_stops_both_directions);
  $test.run(channel_batch_service_failure_stops_reply_wait);
}
