/*  channel.x -- Var transport and explicit storage handoff

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
    lifetimes. Ordinary send copies bits without ownership changes;
    send_owned explicitly hands off a detached, exclusively owned storage
    subtree. Close ends sends and lets accepted values drain. Every user
    and waiter must finish before the Channel's storage scope is destroyed.
*/
typedef struct Channel *Channel;

static typedef struct ChannelMessage {
  Var value;
  struct ChannelMessage *next;
  int owned;
} ChannelMessage;

/* Only the shared monitor reads links, owner tokens, and commitment flags. */
static typedef struct ChannelWait {
  Var value;
  Thread owner;
  struct ChannelWait *previous, *next;
  int committed, owned;
} ChannelWait;

/* A blocked native thread cannot reenter Channel code: no callback or Error
   dispatch runs while registered. Every exit unlinks before dispatching, so
   one native-thread record covers both managed workers and the main thread. */
static threaded ChannelWait rendezvous_wait;

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
  ChannelMessage *message = channel.first;
  channel.first = channel.last = NULL;
  channel.count = 0;
  channel.closed = 1;
  while (message) {
    ChannelMessage *next = message.next;
    if (message.owned) Scope.owner(message.value.pointer()).destroy();
    free(message);
    message = next;
  }
  if (channel.initialized)
    _native_check(pthread_cond_destroy(&channel.changed));
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
    for storage, or <io-fail> for native condition initialization.
*/
Channel Channel.new(Var type, Var capacity) {
  if (capacity is void) {
    if (type == <unbounded> || type is not <symbol>) {
      capacity = type;
      type = <var>;
    }
    else capacity = 0;
  }
  if (type is not <symbol> ||
      (type != <var> && !Var.known_tag(type)))
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
  if (code ~= $channel.new.empty())
    return $!Channel{ Channel.new(<var>, 0) };
  return code;
}

$rewrite($channel.new.one)
meta static Code _new_one(Code code) {
  if (code ~= $channel.new.one(?value))
    return $!Channel{ Channel.new($value, void) };
  return code;
}

/** Returns the Channel's own storage scope. Owned queued payloads stay
    detached; ordinary messages remain borrowed. This scope is not a shared
    adoption destination for concurrent senders. NULL returns NULL.
*/
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
static int _rendezvous_send(Channel channel, Var value, int owned) {
  if (x2c_thread_stopping()) return -1;
  if (channel.closed) return 0;
  ChannelWait *receiver = _live_wait(&channel.receivers);
  if (receiver) {
    receiver.value = value;
    receiver.owned = owned;
    receiver.committed = 1;
    _remove_wait(&channel.receivers, receiver);
    _notify(channel);
    return 1;
  }
  ChannelWait *wait = &rendezvous_wait;
  *wait = (ChannelWait) {
    .value = value, .owner = x2c_thread_wait_owner(), .owned = owned
  };
  _append_wait(&channel.senders, wait);
  while (!wait.committed && !channel.closed && !x2c_thread_stopping())
    x2c_thread_wait(&channel.changed);
  if (wait.committed) return 1;
  _remove_wait(&channel.senders, wait);
  return x2c_thread_stopping() ? -1 : 0;
}

static int _rendezvous_receive(Channel channel, Var &out, int &owned) {
  if (x2c_thread_stopping()) return -1;
  ChannelWait *sender = _live_wait(&channel.senders);
  if (sender && !channel.closed) {
    out = sender.value;
    owned = sender.owned;
    sender.committed = 1;
    _remove_wait(&channel.senders, sender);
    _notify(channel);
    return 1;
  }
  if (channel.closed) return 0;
  ChannelWait *wait = &rendezvous_wait;
  *wait = (ChannelWait) { .owner = x2c_thread_wait_owner() };
  _append_wait(&channel.receivers, wait);
  while (!wait.committed && !channel.closed && !x2c_thread_stopping())
    x2c_thread_wait(&channel.changed);
  if (wait.committed) {
    out = wait.value;
    owned = wait.owned;
    return 1;
  }
  _remove_wait(&channel.receivers, wait);
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

/* A sender owns native queue storage until commitment. The queue, then the
   receiver, owns the accepted node independently of Scope lists. */
static ChannelMessage *_message(Var value, int owned) {
  ChannelMessage *message = malloc(sizeof(ChannelMessage));
  if (!message) raise %(alloc-fail (operation "Channel.send"));
  *message = (ChannelMessage) { .value = value, .owned = owned };
  return message;
}

/* Container movement is physical: it does not visit keys, elements, or
   referenced objects. Custom roots already carry an exclusive subtree. */
static int _container(Var value) => value is <array> || value is <map>;

static Scope _container_contents(Var value) {
  if (value is <map>) {
    Map map = value;
    return map.scope;
  }
  Block array = value.pointer();
  return array.lifetime;
}

static void _move_container(Var value, Scope *destination) {
  if (value is <map>) {
    Map map = value;
    map.move_to(destination);
  }
  else {
    Block array = value.pointer();
    array.move_to(destination);
  }
}

static void _send(Channel channel, Var value, int owned) {
  if (!channel) raise %(bad-arg (operation "Channel.send"));
  if (value is void) raise %(void-op (operation "Channel.send"));
  if (channel.type != <var> && value.tag() != channel.type)
    raise %(bad-types (operation "Channel.send"));
  if (owned && !value.pointer())
    raise %(bad-arg (operation "Channel.send_owned"));

  ChannelMessage *message = NULL;
  int status = 0;
  defer if (message && status != 1) free(message);
  if (channel.capacity) message = _message(value, owned);

  int container = owned && _container(value);
  Scope payload = NULL, previous = NULL;
  Scope contents = container ? _container_contents(value) : NULL;
  Scope contents_parent = contents ? contents.parent() : NULL;
  if (owned) {
    Scope owner = Scope.owner(value.pointer());
    previous = container ? owner : owner.parent();
    if (container) {
      payload = Scope.new();
      _move_container(value, &payload);
    }
    else { payload = owner; payload.transfer(NULL); }
  }

  x2c_thread_wait_lock();
  status = channel.capacity ? _buffer_send(channel, message)
                            : _rendezvous_send(channel, value, owned);
  x2c_thread_wait_unlock();
  if (status != 1 && owned) {
    if (container) {
      _move_container(value, &previous);
      if (contents) contents.transfer(contents_parent);
      payload.destroy();
    }
    else payload.transfer(previous);
  }
  if (status < 0) x2c_thread_cancel();
  if (!status) raise %(bad-state (operation "Channel.send") (closed 1));
}

/** Sends non-void representation bits without changing referenced storage
    ownership. Waits for queue capacity or a rendezvous match. Acceptance
    commits under synchronization; later stop cannot retract that send.
    Raises: <bad-arg> for NULL, <void-op> for void, <bad-types> for a tag
    mismatch, <bad-state> for closure or cooperative stop, or <alloc-fail>
    for native buffered queue storage. Failure dispatch holds no queue lock.
*/
void Channel.send(Channel c, Var value) => _send(c, value, 0);

/** Hands off an exclusively owned payload. Ordinary Map and Array records,
    buffers, and existing owned contents move into a transport Scope created
    only for this send. Custom or typed roots require a preexisting exclusive
    inactive subtree containing their full physical storage. The detached
    scope is recovered through the root's allocation header while queued.
    Failed sends restore the container allocation owner and contents parent,
    or the custom subtree parent, before raising. Acceptance transfers access
    and cleanup responsibility. This cannot disarm initializer auto or defer;
    the caller must not leave such cleanup armed after acceptance. A subtree
    must not be handed off twice. Canonical Strings/Lists and independent
    referenced objects are not implicitly adopted. Pointer provenance and
    ownership graphs remain caller responsibilities.
    Raises: the send causes, or <bad-arg> for a null/nonpointer payload.
*/
void Channel.send_owned(Channel c, Var value) => _send(c, value, 1);

/** Receives one accepted Var. Ordinary payloads stay borrowed. Owned Map and
    Array storage moves into the receiver's private active Scope, releasing
    the empty transport Scope. Prepared custom subtrees join that private
    owner. Receiver failure cleanup reclaims received storage normally.
    Returns void only after close and draining; null remains ordinary data.
    A committed delivery succeeds despite a later stop request.
    Raises: <bad-arg> for NULL, <alloc-fail> preparing receiver storage, or
    <bad-state> for cooperative stop.
*/
Var Channel.receive(Channel channel) {
  if (!channel) raise %(bad-arg (operation "Channel.receive"));
  Scope *destination = Scope.top();
  if (!*destination) *destination = Scope.new();
  Var value = void;
  ChannelMessage *message = NULL;
  int owned = 0;
  x2c_thread_wait_lock();
  int status = channel.capacity ? _buffer_receive(channel, &message)
                               : _rendezvous_receive(channel, value, owned);
  if (message) { value = message.value; owned = message.owned; }
  x2c_thread_wait_unlock();
  if (message) free(message);
  if (owned) {
    Scope transport = Scope.owner(value.pointer());
    if (_container(value)) {
      _move_container(value, destination);
      transport.destroy();
    }
    else transport.transfer(*destination);
  }
  if (status < 0) x2c_thread_cancel();
  return value;
}

/** Ends sends and wakes waiters; accepted messages remain available to drain.
    Repeated close is harmless. Closing does not stop Thread users, free
    payloads, or acknowledge completion of a borrow.
    Raises: <bad-arg> for NULL.
*/
void Channel.close(Channel channel) {
  if (!channel) raise %(bad-arg (operation "Channel.close"));
  x2c_thread_wait_lock();
  channel.closed = 1;
  _notify(channel);
  x2c_thread_wait_unlock();
}

/** Closes and destroys an unused Channel's complete storage scope. Every
    user and waiter must already have finished. Undelivered owned payload
    subtrees are destroyed outside the queue monitor; ordinary payloads are
    not followed. NULL does nothing. Owner destruction releases these native
    queue nodes and resources through the same finalizer.
*/
void Channel.free(Channel channel) {
  if (channel) { channel.close(); channel.lifetime.destroy(); }
}

$cleanup.by(Channel, free);

// boxing and iteration

/** Boxes the borrowed Channel handle without changing its lifetime. */
Var Channel.var(Channel channel) => Var.new(<channel>, channel);

/** Reads a Channel handle with its exact tag. Ownership is unchanged.
    Raises: <bad-types> for another tag.
*/
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
    The Channel must outlive traversal.
*/
Iter Channel.iter(Channel c, Iter dest) => dest.init(c, _next, void);

protocol Iter(Channel);
