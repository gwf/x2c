/*  channel.x -- non-owning Var transport and explicit stream completion

    Copyright (c) 2026 Gary William Flake.

    Queue commitment and cooperative stop share Thread's internal monitor.
    Allocation, Error dispatch, and payload destruction stay outside it.
*/

#pragma once

#include "common.x"
#include "cleanup.x"
#include "thread.x"
#include "iter.x"
#include "protocols.x"
#include "rewrite.x"

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/** A synchronized non-void Var stream with explicitly managed payload
    lifetimes. Sending copies representation bits, never storage ownership.
    Close ends sends and lets accepted values drain. Every user and waiter
    must finish before the Channel's storage scope is destroyed. */
typedef struct Channel *Channel;

static typedef struct ChannelMessage {
  Var value;
  struct ChannelMessage *next;
} ChannelMessage;

/* Rendezvous records live on their blocked callers' stacks. Only the shared
   monitor reads links, owner tokens, and commitment flags. */
static typedef struct ChannelWait {
  Var value;
  Thread owner;
  struct ChannelWait *previous, *next;
  int committed;
} ChannelWait;

static typedef struct ChannelWaits {
  ChannelWait *first, *last;
} ChannelWaits;

static struct Channel {
  Scope lifetime;
  Symbol type;
  size_t capacity, count;
  ChannelMessage *first, *last;
  ChannelWaits senders, receivers;
  pthread_cond_t changed;
  int initialized, closed;
};

// native resources and construction

static void _native_check(int error) {
  if (!error) return;
  fprintf(stderr, "Channel: native synchronization failed (%d)\n", error);
  abort();
}

static void _drop(void *bytes) {
  Channel channel = bytes;
  if (channel.initialized) _native_check(pthread_cond_destroy(&channel.changed));
}

static size_t _capacity(Var value) {
  if (value == <unbounded>) return SIZE_MAX;
  if (value.is_integer()) {
    long capacity = -1;
    try capacity = value.convert(<long>).long_value();
    catch %(conv-range *): capacity = -1;
    if (capacity >= 0) return (size_t) capacity;
  }
  raise %(bad-arg (operation "Channel.new") (argument capacity));
}

/** Creates a Channel constrained to an exact Var tag, with capacity zero
    for rendezvous, a nonnegative integer for bounded buffering, or
    <unbounded>. The <var> tag permits every non-void Var without conversion.
    Short forms are new(), new(capacity), and new(tag); omitted capacity
    means rendezvous. Queuing does not intern or export message contents.
    Raises: <bad-arg> for an unknown tag or invalid capacity, <alloc-fail>
    for storage, or <io-fail> for native condition initialization. */
Channel Channel.new(Var type, Var capacity) {
  if (capacity is void) {
    if (type == <unbounded> || type is not <symbol>) {
      capacity = type;
      type = <var>;
    }
    else capacity = 0;
  }
  if (type is not <symbol> ||
      (type != <var> && !Var.known_tag(type.symbol())))
    raise %(bad-arg (operation "Channel.new") (argument type));
  size_t limit = _capacity(capacity);
  Scope lifetime = Scope.child();
  int ready = 0;
  defer if (!ready) lifetime.destroy();
  Channel channel = Scope.malloc_finalized_in(
    &lifetime, sizeof(struct Channel), _drop);
  memset(channel, 0, sizeof(struct Channel));
  channel.lifetime = lifetime;
  channel.type = type;
  channel.capacity = limit;
  int error = pthread_cond_init(&channel.changed, NULL);
  if (error) raise %(io-fail (operation "pthread_cond_init") (errno $error));
  channel.initialized = 1;
  ready = 1;
  return channel;
}

macro Expression $channel.new.empty() => Channel.new();
macro Expression $channel.new.one(Expr $value) => Channel.new($value);

$rewrite($channel.new.empty)
meta static Code _new_empty(Code code) {
  match (code) case $channel.new.empty():
    return $!Channel{ Channel.new(<var>, 0) };
  return code;
}

$rewrite($channel.new.one)
meta static Code _new_one(Code code) {
  match (code) case $channel.new.one(?value):
    return $!Channel{ Channel.new($value, void) };
  return code;
}

/** Returns the Channel's complete storage scope, including explicitly
    adopted child scopes. It does not follow references in queued Vars.
    A null Channel returns NULL. */
Scope Channel.scope(Channel channel) => channel ? channel.lifetime : NULL;

// rendezvous queues

static void _append_wait(ChannelWaits *queue, ChannelWait *wait) {
  wait.previous = queue.last;
  if (queue.last) queue.last.next = wait;
  else queue.first = wait;
  queue.last = wait;
}

static void _remove_wait(ChannelWaits *queue, ChannelWait *wait) {
  if (wait.previous) wait.previous.next = wait.next;
  else queue.first = wait.next;
  if (wait.next) wait.next.previous = wait.previous;
  else queue.last = wait.previous;
}

static ChannelWait *_live_wait(ChannelWaits *queue) {
  for (ChannelWait *wait = queue.first; wait; wait = wait.next)
    if (!x2c_thread_wait_stopped(wait.owner)) return wait;
  return NULL;
}

static void _notify(Channel channel) =>
  _native_check(pthread_cond_broadcast(&channel.changed));

/* A positive status means committed, zero means closed, and negative means
   stopped. Callers unlock before dispatching either failure. */
static int _rendezvous_send(Channel channel, Var value) {
  if (x2c_thread_stopping()) return -1;
  if (channel.closed) return 0;
  ChannelWait *receiver = _live_wait(&channel.receivers);
  if (receiver) {
    receiver.value = value;
    receiver.committed = 1;
    _remove_wait(&channel.receivers, receiver);
    _notify(channel);
    return 1;
  }
  ChannelWait wait = { .value = value, .owner = x2c_thread_wait_owner() };
  _append_wait(&channel.senders, &wait);
  while (!wait.committed && !channel.closed && !x2c_thread_stopping())
    x2c_thread_wait(&channel.changed);
  if (wait.committed) return 1;
  _remove_wait(&channel.senders, &wait);
  return x2c_thread_stopping() ? -1 : 0;
}

static int _rendezvous_receive(Channel channel, Var *out) {
  if (x2c_thread_stopping()) return -1;
  ChannelWait *sender = _live_wait(&channel.senders);
  if (sender && !channel.closed) {
    *out = sender.value;
    sender.committed = 1;
    _remove_wait(&channel.senders, sender);
    _notify(channel);
    return 1;
  }
  if (channel.closed) return 0;
  ChannelWait wait = { .owner = x2c_thread_wait_owner() };
  _append_wait(&channel.receivers, &wait);
  while (!wait.committed && !channel.closed && !x2c_thread_stopping())
    x2c_thread_wait(&channel.changed);
  if (wait.committed) { *out = wait.value; return 1; }
  _remove_wait(&channel.receivers, &wait);
  return x2c_thread_stopping() ? -1 : 0;
}

// buffered queues

static int _buffer_send(Channel channel, ChannelMessage *message) {
  while (channel.count == channel.capacity && !channel.closed &&
         !x2c_thread_stopping())
    x2c_thread_wait(&channel.changed);
  if (x2c_thread_stopping()) return -1;
  if (channel.closed) return 0;
  if (channel.last) channel.last.next = message;
  else channel.first = message;
  channel.last = message;
  channel.count++;
  _notify(channel);
  return 1;
}

static int _buffer_receive(Channel channel, ChannelMessage **out) {
  while (!channel.count && !channel.closed && !x2c_thread_stopping())
    x2c_thread_wait(&channel.changed);
  if (x2c_thread_stopping()) return -1;
  if (!channel.count) return 0;
  ChannelMessage *message = channel.first;
  channel.first = message.next;
  if (!channel.first) channel.last = NULL;
  channel.count--;
  *out = message;
  _notify(channel);
  return 1;
}

// communication

/** Sends non-void representation bits without changing referenced storage
    ownership. Waits for queue capacity or a rendezvous match. Acceptance
    commits under synchronization; later stop cannot retract that send.
    Raises: <bad-arg> for NULL, <void-op> for void, <bad-types> for a tag
    mismatch, <bad-state> for closure or cooperative stop, or <alloc-fail>
    for buffered queue storage. No failure dispatch holds the queue lock. */
void Channel.send(Channel channel, Var value) {
  if (!channel) raise %(bad-arg (operation "Channel.send"));
  if (value is void) raise %(void-op (operation "Channel.send"));
  if (channel.type != <var> && value.tag() != channel.type)
    raise %(bad-types (operation "Channel.send"));
  ChannelMessage *message = NULL;
  int status = 0;
  defer if (message && status != 1) Scope.free(message);
  if (channel.capacity) {
    message = Scope.malloc_in(&channel.lifetime, sizeof(ChannelMessage));
    *message = (ChannelMessage) { .value = value };
  }
  x2c_thread_wait_lock();
  status = channel.capacity ? _buffer_send(channel, message)
                            : _rendezvous_send(channel, value);
  x2c_thread_wait_unlock();
  if (status < 0) x2c_thread_cancel();
  if (!status) raise %(bad-state (operation "Channel.send") (closed 1));
}

/** Receives one accepted Var without adopting or exporting its storage.
    Returns void only after normal close and draining. Null remains data.
    A committed delivery succeeds despite a later stop request.
    Raises: <bad-arg> for NULL or <bad-state> for cooperative stop. */
Var Channel.receive(Channel channel) {
  if (!channel) raise %(bad-arg (operation "Channel.receive"));
  Var value = void;
  ChannelMessage *message = NULL;
  x2c_thread_wait_lock();
  int status = channel.capacity ? _buffer_receive(channel, &message)
                               : _rendezvous_receive(channel, &value);
  if (message) value = message.value;
  x2c_thread_wait_unlock();
  if (message) Scope.free(message);
  if (status < 0) x2c_thread_cancel();
  return value;
}

/** Ends sends and wakes waiters; accepted messages remain available to drain.
    Repeated close is harmless. Closing does not stop Thread users, free
    payloads, or acknowledge completion of a borrow.
    Raises: <bad-arg> for NULL. */
void Channel.close(Channel channel) {
  if (!channel) raise %(bad-arg (operation "Channel.close"));
  x2c_thread_wait_lock();
  channel.closed = 1;
  _notify(channel);
  x2c_thread_wait_unlock();
}

/** Closes and destroys an unused Channel's complete storage scope. Every
    user and waiter must already have finished. Adopted child scopes are
    reclaimed; arbitrary referenced payloads are not followed. NULL does
    nothing. Automatic owner destruction also releases native resources. */
void Channel.free(Channel channel) {
  if (channel) { channel.close(); channel.lifetime.destroy(); }
}

$cleanup.by(Channel, free);

// boxing and iteration

/** Boxes the borrowed Channel handle without changing its lifetime. */
Var Channel.var(Channel channel) => Var.new(<channel>, channel);

/** Reads a Channel handle with its exact tag. Ownership is unchanged.
    Raises: <bad-types> for another tag. */
Channel Var.channel(Var value) {
  if (value is not <channel>) raise %(bad-types (operation "Var.channel"));
  return value.pointer();
}

protocol Var(Channel);

static int _next(Iter iter, Var *out) {
  Channel channel = iter.obj;
  Var value = channel.receive();
  if (value is void) { iter.next = NULL; return 0; }
  *out = value;
  return 1;
}

/** Initializes a borrowed iterator that blocks for each received message.
    Normal close and draining end iteration; cooperative stop raises instead.
    The Channel must outlive traversal. */
Iter Channel.iter(Channel channel, Iter dest) =>
  dest.init(channel, _next, void);

protocol Iter(Channel);
