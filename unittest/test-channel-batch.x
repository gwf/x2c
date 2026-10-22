/*  test-channel-batch.x -- failure cleanup across Channel and Thread.run */

#include "channel.x"
#include "test-support.x"
#include "test-macros.x"
#include <stdatomic.h>

static void channel_batch_worker_failure_stops_both_directions(void) {
  $test.scoped();
  Channel files = $auto(Channel.new());
  Channel results = $auto(Channel.new());
  Channel ready = $auto(Channel.new(2));
  Array jobs = $auto([]);
  atomic_int finished = 0;
  atomic_int *done = &finished;
  int callbacks = 0, caught = 0;

  jobs.push(%!(void) => {
    defer atomic_fetch_add(done, 1);
    ready.send(<producer>);
    files.send("never consumed");
    return <unexpected>;
  });
  jobs.push(%!(void) => {
    defer atomic_fetch_add(done, 1);
    ready.send(<consumer>);
    results.receive();
    return <unexpected>;
  });
  jobs.push(%!(void) => {
    defer atomic_fetch_add(done, 1);
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
  EXPECT_INT_EQ(atomic_load(done), 3);
}

static void channel_batch_service_failure_stops_reply_wait(void) {
  $test.scoped();
  Channel requests = $auto(Channel.new());
  Channel reply = $auto(Channel.new());
  Array jobs = $auto([]);
  atomic_int finished = 0;
  atomic_int *done = &finished;
  int callbacks = 0, caught = 0;

  jobs.push(%!(void) => {
    defer atomic_fetch_add(done, 1);
    requests.receive();
    raise %(bad-arg (primary 91));
    return void;
  });
  jobs.push(%!(void) => {
    defer atomic_fetch_add(done, 1);
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
  EXPECT_INT_EQ(atomic_load(done), 2);
}

void channel_batch_suite(void) {
  $test.run(channel_batch_worker_failure_stops_both_directions);
  $test.run(channel_batch_service_failure_stops_reply_wait);
}
