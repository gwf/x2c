/*  test-channel.x -- ownership-neutral transport and stop commitment */

#include "test-support.x"
#include "test-macros.x"
#include "channel.x"
#include "typed-array.x"
#include <sched.h>
#include <stdatomic.h>

static void channel_constructor_forms_and_boxing(void) {
  $test.scoped();
  Channel rendezvous = auto Channel.new();
  Channel bounded = auto Channel.new(2);
  Channel typed = auto Channel.new(<map>);
  Channel typed_buffer = auto Channel.new(<i32>, 2);
  Channel unbounded = auto Channel.new(<unbounded>);
  Var boxed = bounded;
  EXPECT_TRUE(boxed is <channel>);
  EXPECT_PTR_EQ(boxed.channel(), bounded);
  EXPECT_NOT_NULL(rendezvous.scope());
  EXPECT_NOT_NULL(typed.scope().parent());
  typed_buffer.send(17);
  EXPECT_INT_EQ(typed_buffer.receive().integer(), 17);
  unbounded.close();
  EXPECT_TRUE(unbounded.receive() is void);
}

static void channel_close_drains_and_preserves_null_data(void) {
  $test.scoped();
  Channel channel = auto Channel.new(3);
  channel.send(11);
  channel.send(NULL);
  channel.send(nil);
  channel.close();
  channel.close();
  EXPECT_INT_EQ(channel.receive().integer(), 11);
  EXPECT_TRUE(channel.receive().is_null());
  EXPECT_TRUE(channel.receive().is_nil());
  EXPECT_TRUE(channel.receive() is void);
  EXPECT_TRUE(channel.receive() is void);
  int rejected = 0;
  try channel.send(12);
  catch %(bad-state (operation "Channel.send") (closed 1)): rejected = 1;
  EXPECT_TRUE(rejected);
}

static void channel_rejects_void_and_exact_tag_mismatch(void) {
  $test.scoped();
  Channel channel = auto Channel.new(<i32>, 1);
  int no_void = 0, no_wrong_type = 0;
  try channel.send(void);
  catch %(void-op *): no_void = 1;
  try channel.send((long) 3);
  catch %(bad-types *): no_wrong_type = 1;
  EXPECT_TRUE(no_void);
  EXPECT_TRUE(no_wrong_type);
  channel.send(3);
  EXPECT_INT_EQ(channel.receive().integer(), 3);
  Channel lists = auto Channel.new(<list>, 1);
  lists.send(nil);
  EXPECT_TRUE(lists.receive().is_nil());
  Channel handles = auto Channel.new(<channel>, 1);
  handles.send(Channel.var(NULL));
  EXPECT_NULL(handles.receive().channel());
}

static void channel_rejects_invalid_construction(void) {
  int negative = 0, unknown = 0, fractional = 0;
  try Channel.new(-1);
  catch %(bad-arg *): negative = 1;
  try Channel.new(<int>);
  catch %(bad-arg *): unknown = 1;
  try Channel.new(1.5);
  catch %(bad-arg *): fractional = 1;
  EXPECT_TRUE(negative);
  EXPECT_TRUE(unknown);
  EXPECT_TRUE(fractional);
}

static void channel_unbounded_fifo(void) {
  $test.scoped();
  Channel channel = auto Channel.new(<i32>, <unbounded>);
  for (int i = 0; i < 128; ++i) channel.send(i);
  channel.close();
  for (int i = 0; i < 128; ++i)
    EXPECT_INT_EQ(channel.receive().integer(), i);
  EXPECT_TRUE(channel.receive() is void);
}

static void channel_rendezvous_iteration(void) {
  $test.scoped();
  Channel channel = auto Channel.new();
  int sum = 0, count = 0;
  Thread.run([
    %!(void) => {
      for (int i = 0; i < 32; ++i) channel.send(i);
      channel.close();
    },
    %!(void) using &sum, &count => {
      foreach (int value in channel) { sum += value; count++; }
    }
  ]);
  EXPECT_INT_EQ(sum, 496);
  EXPECT_INT_EQ(count, 32);
}

static void channel_many_senders_share_bounded_queue(void) {
  $test.scoped();
  Channel channel = auto Channel.new(2);
  Array jobs = [];
  int remaining = 4, total = 0;
  for (int worker = 0; worker < 4; ++worker)
    jobs.push(%!(void) => {
      for (int i = 0; i < 100; ++i) channel.send(1);
      return <sender>;
    });
  jobs.push(%!(void) using &total => {
    foreach (int value in channel) total += value;
    return <reader>;
  });
  Thread.run(jobs, %!(Var completed) using &remaining => {
    if (completed == <sender> && !--remaining) channel.close();
  });
  EXPECT_INT_EQ(total, 400);
}

static void _channel_many_producers_and_consumers(Var capacity) {
  Channel channel = auto Channel.new(capacity);
  Array jobs = auto [];
  atomic_int count = 0;
  int remaining = 4, total = 0;
  for (int worker = 0; worker < 4; ++worker) {
    jobs.push(%!(void) => {
      for (int i = 1; i <= 256; ++i) channel.send(i);
      return <sender>;
    });
    jobs.push(%!(void) using &count => {
      int sum = 0;
      foreach (int value in channel) {
        sum += value;
        atomic_fetch_add(&count, 1);
      }
      return sum;
    });
  }
  Thread.run(jobs, %!(Var completed) using &remaining, &total => {
    if (completed == <sender>) {
      if (!--remaining) channel.close();
    }
    else total += completed.integer();
  });
  EXPECT_INT_EQ(atomic_load(&count), 1024);
  EXPECT_INT_EQ(total, 4 * 256 * 257 / 2);
}

static void channel_buffer_transitions_wake_all_waiter_classes(void) {
  $test.scoped();
  _channel_many_producers_and_consumers(1);
  _channel_many_producers_and_consumers(8);
  _channel_many_producers_and_consumers(<unbounded>);
}

static atomic_int channel_probe_ready;

static Var _channel_sender(const void *bytes, size_t size) {
  (void) size;
  Channel channel = *(Channel const *) bytes;
  atomic_store(&channel_probe_ready, 1);
  channel.send(71);
  return 1;
}

static Var _channel_receiver(const void *bytes, size_t size) {
  (void) size;
  Channel channel = *(Channel const *) bytes;
  atomic_store(&channel_probe_ready, 1);
  return channel.receive();
}

static void _channel_expect_stopped(Thread thread) {
  int caught = 0;
  try thread.join();
  catch %(join-fail (errors ?errors)): {
    List error = errors.list().car();
    caught = error.assoc(<code>) == <bad-state> &&
             error.assoc(<detail>).list().assoc(<cancelled>) == 1;
  }
  thread.free();
  EXPECT_TRUE(caught);
}

static void channel_stopped_sender_does_not_enqueue(void) {
  $test.scoped();
  Channel channel = auto Channel.new(1);
  channel.send(12);
  atomic_store(&channel_probe_ready, 0);
  Thread sender = Thread.start_raw(_channel_sender, &channel, sizeof(channel));
  while (!atomic_load(&channel_probe_ready)) sched_yield();
  sender.stop();
  _channel_expect_stopped(sender);
  channel.close();
  EXPECT_INT_EQ(channel.receive().integer(), 12);
  EXPECT_TRUE(channel.receive() is void);
}

static void channel_stopped_receiver_does_not_consume(void) {
  $test.scoped();
  Channel channel = auto Channel.new(1);
  atomic_store(&channel_probe_ready, 0);
  Thread receiver = Thread.start_raw(
    _channel_receiver, &channel, sizeof(channel));
  while (!atomic_load(&channel_probe_ready)) sched_yield();
  receiver.stop();
  _channel_expect_stopped(receiver);
  channel.send(19);
  EXPECT_INT_EQ(channel.receive().integer(), 19);
}

static void channel_rendezvous_commit_survives_later_stop(void) {
  $test.scoped();
  Channel channel = auto Channel.new();
  for (int i = 0; i < 32; ++i) {
    Thread sender = Thread.start_raw(_channel_sender, &channel, sizeof(channel));
    EXPECT_INT_EQ(channel.receive().integer(), 71);
    sender.stop();
    EXPECT_INT_EQ(sender.join().integer(), 1);
    sender.free();
    Thread receiver = Thread.start_raw(
      _channel_receiver, &channel, sizeof(channel));
    channel.send(73);
    receiver.stop();
    EXPECT_INT_EQ(receiver.join().integer(), 73);
    receiver.free();
  }
}

static void channel_stopped_rendezvous_peer_is_not_matched(void) {
  $test.scoped();
  Channel channel = auto Channel.new();
  Thread stopped = Thread.start_raw(_channel_receiver, &channel, sizeof(channel));
  stopped.stop();
  Thread live = Thread.start_raw(_channel_receiver, &channel, sizeof(channel));
  channel.send(79);
  EXPECT_INT_EQ(live.join().integer(), 79);
  live.free();
  _channel_expect_stopped(stopped);
}

static void channel_close_rejects_unaccepted_rendezvous_send(void) {
  $test.scoped();
  Channel channel = auto Channel.new();
  Thread sender = Thread.start_raw(_channel_sender, &channel, sizeof(channel));
  channel.close();
  int rejected = 0;
  try sender.join();
  catch %(join-fail *): rejected = 1;
  sender.free();
  EXPECT_TRUE(rejected);
  EXPECT_TRUE(channel.receive() is void);
}

static void channel_close_rejects_blocked_bounded_send(void) {
  $test.scoped();
  Channel channel = auto Channel.new(1);
  channel.send(12);
  atomic_store(&channel_probe_ready, 0);
  Thread sender = Thread.start_raw(_channel_sender, &channel, sizeof(channel));
  while (!atomic_load(&channel_probe_ready)) sched_yield();
  channel.close();
  int rejected = 0;
  try sender.join();
  catch %(join-fail (errors ?errors)): {
    List error = errors.list().car();
    rejected = error.assoc(<code>) == <bad-state> &&
               error.assoc(<detail>).list().assoc(<closed>) == 1;
  }
  sender.free();
  EXPECT_TRUE(rejected);
  EXPECT_INT_EQ(channel.receive().integer(), 12);
  EXPECT_TRUE(channel.receive() is void);
}

static void channel_payload_ownership_is_unchanged(void) {
  $test.scoped();
  Channel channel = auto Channel.new(2);
  Map payload = {};
  payload[<value>] = 83;
  Scope parent = payload.scope().parent();
  channel.send(payload);
  channel.send(payload);
  Map first = channel.receive(), second = channel.receive();
  EXPECT_PTR_EQ(first, payload);
  EXPECT_PTR_EQ(second, payload);
  EXPECT_PTR_EQ(payload.scope().parent(), parent);
  payload[<value>] = 89;
  EXPECT_INT_EQ(first[<value>].integer(), 89);
}

static atomic_int channel_payload_drops;

static void _channel_drop_payload(void *bytes) {
  (void) bytes;
  atomic_fetch_add(&channel_payload_drops, 1);
}

static void _channel_queue_owned_result(Channel channel) {
  Map part = {};
  Scope storage = part;
  Scope.malloc_finalized_in(&storage, sizeof(int), _channel_drop_payload);
  channel.send_owned(part);
}

static void channel_cleanup_reclaims_only_owned_storage(void) {
  $test.scoped();
  atomic_store(&channel_payload_drops, 0);
  Channel explicit = Channel.new(1);
  _channel_queue_owned_result(explicit);
  explicit.free();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 1);

  Scope owner = Scope.child();
  Scope.push(&owner);
  Channel inherited = Channel.new(1);
  Scope.pop();
  _channel_queue_owned_result(inherited);
  owner.destroy();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 2);

  Map borrowed = {};
  borrowed[<value>] = 97;
  Channel references = Channel.new(1);
  references.send(borrowed);
  references.free();
  EXPECT_INT_EQ(borrowed[<value>].integer(), 97);
}

static void channel_close_wakes_exhausted_receivers(void) {
  $test.scoped();
  for (int capacity = 0; capacity < 2; ++capacity) {
    Channel channel = auto Channel.new(capacity);
    atomic_store(&channel_probe_ready, 0);
    Thread receiver = Thread.start_raw(
      _channel_receiver, &channel, sizeof(channel));
    while (!atomic_load(&channel_probe_ready)) sched_yield();
    channel.close();
    EXPECT_TRUE(receiver.join() is void);
    receiver.free();
  }
}

static Map _channel_owned_result(void) {
  Map part = {};
  part[<value>] = 107;
  Scope storage = part;
  Scope.malloc_finalized_in(&storage, sizeof(int), _channel_drop_payload);
  return part;
}

static void channel_owned_receive_joins_receiver_scope(void) {
  $test.scoped();
  atomic_store(&channel_payload_drops, 0);
  Channel channel = auto Channel.new(1);
  Scope source = Scope.child();
  Scope.push(&source);
  Map part = _channel_owned_result();
  Scope.pop();
  channel.send_owned(part);
  source.destroy();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 0);
  Map received = channel.receive();
  EXPECT_PTR_EQ(Scope.owner(received), *Scope.top());
  EXPECT_INT_EQ(received[<value>].integer(), 107);
  received.cleanup();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 1);
}

static void channel_owned_closed_send_restores_parent(void) {
  $test.scoped();
  atomic_store(&channel_payload_drops, 0);
  Channel channel = auto Channel.new(1);
  channel.close();
  Map part = _channel_owned_result();
  Scope original = Scope.owner(part);
  int rejected = 0;
  try channel.send_owned(part);
  catch %(bad-state (operation "Channel.send") (closed 1)): rejected = 1;
  EXPECT_TRUE(rejected);
  EXPECT_PTR_EQ(Scope.owner(part), original);
  part.cleanup();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 1);

  Map detached = _channel_owned_result();
  Scope detached_storage = Scope.new();
  detached.move_to(&detached_storage);
  rejected = 0;
  try channel.send_owned(detached);
  catch %(bad-state (operation "Channel.send") (closed 1)): rejected = 1;
  EXPECT_TRUE(rejected);
  EXPECT_PTR_EQ(Scope.owner(detached), detached_storage);
  EXPECT_NULL(detached_storage.parent());
  detached.cleanup();
  detached_storage.destroy();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 2);
}

static void channel_owned_type_failure_keeps_sender_ownership(void) {
  $test.scoped();
  Channel channel = auto Channel.new(<i32>, 1);
  Map part = {};
  Scope original = Scope.owner(part);
  int rejected = 0;
  try channel.send_owned(part);
  catch %(bad-types *): rejected = 1;
  EXPECT_TRUE(rejected);
  EXPECT_PTR_EQ(Scope.owner(part), original);
}

static Var _channel_owned_stopped_sender(const void *bytes, size_t size) {
  (void) size;
  Channel channel = *(Channel const *) bytes;
  Map part = _channel_owned_result();
  Scope original = Scope.owner(part);
  atomic_store(&channel_probe_ready, 1);
  int restored = 0;
  try channel.send_owned(part);
  catch %(bad-state (operation "Thread.stop") (cancelled 1)):
    restored = Scope.owner(part) == original;
  return restored;
}

static void channel_owned_stopped_send_restores_parent(void) {
  $test.scoped();
  for (int capacity = 0; capacity < 2; ++capacity) {
    atomic_store(&channel_payload_drops, 0);
    Channel channel = auto Channel.new(capacity);
    if (capacity) channel.send(109);
    atomic_store(&channel_probe_ready, 0);
    Thread sender = Thread.start_raw(
      _channel_owned_stopped_sender, &channel, sizeof(channel));
    while (!atomic_load(&channel_probe_ready)) sched_yield();
    sender.stop();
    EXPECT_INT_EQ(sender.join().integer(), 1);
    sender.free();
    EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 1);
    channel.close();
    if (capacity) EXPECT_INT_EQ(channel.receive().integer(), 109);
    EXPECT_TRUE(channel.receive() is void);
  }
}

static Var _channel_owned_sender(const void *bytes, size_t size) {
  (void) size;
  Channel channel = *(Channel const *) bytes;
  channel.send_owned(_channel_owned_result());
  return 1;
}

static Var _channel_owned_failing_receiver(const void *bytes, size_t size) {
  (void) size;
  Channel channel = *(Channel const *) bytes;
  Map received = channel.receive();
  if (received[<value>] != 107) raise %(bad-state);
  raise %(recv-fail);
  return void;
}

static void channel_owned_queue_survives_sender_exit(void) {
  $test.scoped();
  atomic_store(&channel_payload_drops, 0);
  Channel channel = Channel.new(1);
  Thread sender = Thread.start_raw(
    _channel_owned_sender, &channel, sizeof(channel));
  EXPECT_INT_EQ(sender.join().integer(), 1);
  sender.free();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 0);
  channel.free();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 1);
}

static void channel_owned_receive_failure_reclaims_payload(void) {
  $test.scoped();
  atomic_store(&channel_payload_drops, 0);
  Channel channel = Channel.new(1);
  channel.send_owned(_channel_owned_result());
  Thread receiver = Thread.start_raw(
    _channel_owned_failing_receiver, &channel, sizeof(channel));
  int failed = 0;
  try receiver.join();
  catch %(join-fail (errors ?errors)):
    failed = errors.list().car().list().assoc(<code>) == <recv-fail>;
  receiver.free();
  EXPECT_TRUE(failed);
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 1);
  channel.free();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 1);
}

static Var _channel_owned_return(Var input) {
  Array args = input;
  Channel channel = args[0];
  Scope output = args[1];
  Map received = channel.receive();
  received.move_to(&output);
  return received;
}

static void channel_owned_rendezvous_commit_survives_stop(void) {
  $test.scoped();
  atomic_store(&channel_payload_drops, 0);
  Channel channel = auto Channel.new();
  for (int i = 0; i < 16; ++i) {
    Thread sender = Thread.start_raw(
      _channel_owned_sender, &channel, sizeof(channel));
    Map received = channel.receive();
    sender.stop();
    EXPECT_INT_EQ(sender.join().integer(), 1);
    sender.free();
    EXPECT_INT_EQ(received[<value>].integer(), 107);
    received.cleanup();
    EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 2 * i + 1);

    Scope output = Scope.child();
    Thread receiver = Thread.start(_channel_owned_return, [channel, output]);
    channel.send_owned(_channel_owned_result());
    receiver.stop();
    Map joined = receiver.join();
    receiver.free();
    EXPECT_INT_EQ(joined[<value>].integer(), 107);
    joined.cleanup();
    output.destroy();
    EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 2 * i + 2);
  }
}

static void channel_owned_plain_map_moves_and_grows(void) {
  $test.scoped();
  Channel channel = auto Channel.new(1);
  Scope source = Scope.child();
  Scope.push(&source);
  Map part = {};
  part[<first>] = 1;
  Scope.pop();
  channel.send_owned(part);
  source.destroy();
  Map received = channel.receive();
  EXPECT_INT_EQ(received[<first>].integer(), 1);
  for (int i = 0; i < 256; ++i) received[i] = i + 1;
  EXPECT_INT_EQ(received.len(), 257);
  EXPECT_INT_EQ(received[255].integer(), 256);
  received.cleanup();
}

static void channel_owned_plain_array_moves_and_grows(void) {
  $test.scoped();
  Channel channel = auto Channel.new(1);
  Scope source = Scope.child();
  Scope.push(&source);
  Array part = [3];
  Scope.pop();
  channel.send_owned(part);
  source.destroy();
  Array received = channel.receive();
  for (int i = 0; i < 256; ++i) received.push(i);
  EXPECT_INT_EQ(received.len(), 257);
  EXPECT_INT_EQ(received[0].integer(), 3);
  EXPECT_INT_EQ(received[256].integer(), 255);
  received.free();
}

static void channel_owned_nested_contents_move_with_record(void) {
  $test.scoped();
  atomic_store(&channel_payload_drops, 0);
  Channel channel = auto Channel.new(1);
  Scope source = Scope.child();
  Scope.push(&source);
  Map part = _channel_owned_result();
  Array child = [7];
  Scope contents = part;
  child.move_to(&contents);
  part[<child>] = child;
  Scope.pop();
  channel.send_owned(part);
  source.destroy();
  Map received = channel.receive();
  Array nested = received[<child>];
  for (int i = 0; i < 128; ++i) {
    received[i] = i;
    nested.push(i);
  }
  EXPECT_INT_EQ(received[127].integer(), 127);
  EXPECT_INT_EQ(nested.len(), 129);
  received.cleanup();
  EXPECT_INT_EQ(atomic_load(&channel_payload_drops), 1);
}

static void channel_owned_failure_restores_contents_parent(void) {
  $test.scoped();
  atomic_store(&channel_payload_drops, 0);
  Channel channel = auto Channel.new(1);
  channel.close();
  for (int detached = 0; detached < 2; ++detached) {
    Map part = _channel_owned_result();
    Scope original = Scope.owner(part), contents = part;
    Scope separate = detached ? NULL : Scope.child();
    contents.transfer(separate);
    int rejected = 0;
    try channel.send_owned(part);
    catch %(bad-state (operation "Channel.send") (closed 1)): rejected = 1;
    EXPECT_TRUE(rejected);
    EXPECT_PTR_EQ(Scope.owner(part), original);
    EXPECT_PTR_EQ(contents.parent(), separate);
    EXPECT_INT_EQ(part[<value>].integer(), 107);
    part.cleanup();
    EXPECT_INT_EQ(atomic_load(&channel_payload_drops), detached + 1);
    if (separate) separate.destroy();
  }
}

static void channel_owned_typed_array_uses_explicit_group(void) {
  $test.scoped();
  Channel channel = auto Channel.new(1);
  Scope source = Scope.child();
  Scope.push(&source);
  ArrayInt part = ArrayInt.new();
  part.push(11);
  Scope transport = Scope.new();
  part.move_to(&transport);
  Scope.pop();
  channel.send_owned(part);
  source.destroy();
  ArrayInt received = channel.receive();
  for (int i = 0; i < 256; ++i) received.push(i);
  EXPECT_INT_EQ(received.len(), 257);
  EXPECT_INT_EQ(received[0], 11);
  EXPECT_INT_EQ(received[256], 255);
  received.free();
}

static void channel_owned_receive_releases_transport_scope(void) {
  $test.scoped();
  Channel channel = auto Channel.new(1);
  size_t scopes = Scope.stats().live_scopes;
  for (int i = 0; i < 32; ++i) {
    Map map = _channel_owned_result();
    channel.send_owned(map);
    Map received_map = channel.receive();
    received_map.cleanup();
    Array array = [i];
    channel.send_owned(array);
    Array received_array = channel.receive();
    received_array.free();
    EXPECT_INT_EQ(Scope.stats().live_scopes, scopes);
  }
}

/* An unmanaged pthread has no Thread token or native-thread cleanup hook.
   Repeated blocking calls must unlink and destroy their temporary resources. */
static void *_channel_unmanaged_exchange(void *bytes) {
  Channel channel = bytes;
  Pool.thread_initialize();
  for (int i = 0; i < 64; ++i) {
    channel.send(i);
    channel.receive();
  }
  x2c_thread_state_release();
  return NULL;
}

static void channel_unmanaged_blocking_calls(void) {
  $test.scoped();
  Channel channel = auto Channel.new();
  pthread_t native;
  Pool.thread_start();
  EXPECT_INT_EQ(pthread_create(
    &native, NULL, _channel_unmanaged_exchange, channel), 0);
  for (int i = 0; i < 64; ++i) {
    EXPECT_INT_EQ(channel.receive().integer(), i);
    channel.send(i);
  }
  EXPECT_INT_EQ(pthread_join(native, NULL), 0);
}

static void channel_cancelled_waiters_pass_buffered_opportunities(void) {
  $test.scoped();
  for (int sending = 0; sending < 2; ++sending) {
    Channel channel = auto Channel.new(1);
    if (sending) channel.send(12);
    Thread stopped[8];
    for (int i = 0; i < 8; ++i)
      stopped[i] = Thread.start_raw(
        sending ? _channel_sender : _channel_receiver, &channel, sizeof(channel));
    for (int i = 0; i < 8; ++i) stopped[i].stop();
    Thread live = Thread.start_raw(
      sending ? _channel_sender : _channel_receiver, &channel, sizeof(channel));
    if (sending) {
      EXPECT_INT_EQ(channel.receive().integer(), 12);
      EXPECT_INT_EQ(channel.receive().integer(), 71);
      EXPECT_INT_EQ(live.join().integer(), 1);
    }
    else {
      channel.send(73);
      EXPECT_INT_EQ(live.join().integer(), 73);
    }
    live.free();
    for (int i = 0; i < 8; ++i) _channel_expect_stopped(stopped[i]);
  }
}

void channel_suite(void) {
  $test.run(channel_unmanaged_blocking_calls);
  $test.run(channel_cancelled_waiters_pass_buffered_opportunities);
  $test.run(channel_owned_receive_releases_transport_scope);
  $test.run(channel_owned_plain_map_moves_and_grows);
  $test.run(channel_owned_plain_array_moves_and_grows);
  $test.run(channel_owned_nested_contents_move_with_record);
  $test.run(channel_owned_failure_restores_contents_parent);
  $test.run(channel_owned_typed_array_uses_explicit_group);
  $test.run(channel_owned_receive_joins_receiver_scope);
  $test.run(channel_owned_closed_send_restores_parent);
  $test.run(channel_owned_type_failure_keeps_sender_ownership);
  $test.run(channel_owned_stopped_send_restores_parent);
  $test.run(channel_owned_queue_survives_sender_exit);
  $test.run(channel_owned_receive_failure_reclaims_payload);
  $test.run(channel_owned_rendezvous_commit_survives_stop);
  $test.run(channel_cleanup_reclaims_only_owned_storage);
  $test.run(channel_close_wakes_exhausted_receivers);
  $test.run(channel_constructor_forms_and_boxing);
  $test.run(channel_close_drains_and_preserves_null_data);
  $test.run(channel_rejects_void_and_exact_tag_mismatch);
  $test.run(channel_rejects_invalid_construction);
  $test.run(channel_unbounded_fifo);
  $test.run(channel_rendezvous_iteration);
  $test.run(channel_many_senders_share_bounded_queue);
  $test.run(channel_buffer_transitions_wake_all_waiter_classes);
  $test.run(channel_stopped_sender_does_not_enqueue);
  $test.run(channel_stopped_receiver_does_not_consume);
  $test.run(channel_rendezvous_commit_survives_later_stop);
  $test.run(channel_stopped_rendezvous_peer_is_not_matched);
  $test.run(channel_close_rejects_unaccepted_rendezvous_send);
  $test.run(channel_close_rejects_blocked_bounded_send);
  $test.run(channel_payload_ownership_is_unchanged);
}
