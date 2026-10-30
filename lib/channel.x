/*  channel.x -- Var transport and explicit storage handoff

    Copyright (c) 2026 Gary William Flake.

    Each queue owns its mutex; registered monitors order commitment with stop.
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
} *ChannelMessage;

/* Queue mutex owns membership, commitment, stop publication, and sleep. */
static typedef struct ChannelWait {
  Var value;
  Thread owner;
  struct ChannelWait *previous, *next;
  int committed, owned, linked;
} *ChannelWait;

/* Synchronous waits cannot reenter Channel code. Every exit unlinks before
   callbacks or Error dispatch. Native wait resources belong to the Channel. */
static threaded struct ChannelWait channel_wait;

static typedef struct ChannelWaits {
  ChannelWait first, last;
} ChannelWaits;

static struct Channel {
  Scope lifetime;
  Symbol type;
  size_t capacity, count;
  ChannelMessage first, last;
  ChannelWaits senders, receivers;
  X2CChannelMonitor monitor;
  int initialized, closed;
};

macro Expression $channel.new.empty() => Channel.new();
macro Expression $channel.new.one(Expr $value) => Channel.new($value);

$cleanup.by(Channel, free);

protocol Var(Channel);

protocol Iter(Channel);

// native resources and construction

/** Creates a Channel constrained to an exact Var tag, with capacity zero
    for rendezvous, a nonnegative integer for bounded buffering, or
    <unbounded>. The <var> tag permits every non-void Var without conversion.
    Short forms are new(), new(capacity), and new(tag); omitted capacity
    means rendezvous. Queuing does not intern or export message contents.
    Raises: <bad-arg> for an unknown tag or invalid capacity, <alloc-fail>
    for storage, or <io-fail> for native mutex or condition initialization.
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
  int error = pthread_mutex_init(&channel.monitor.mutex, NULL);
  if (error) raise %(io-fail (operation "pthread_mutex_init") (errno $error));
  channel.initialized = 1;
  error = pthread_cond_init(&channel.monitor.condition, NULL);
  if (error) raise %(io-fail (operation "pthread_cond_init") (errno $error));
  channel.initialized = 2;
  ready = 1;
  return channel;
}

/** Returns the Channel's own storage scope. Owned queued payloads stay
    detached; ordinary messages remain borrowed. This scope is not a shared
    adoption destination for concurrent senders. NULL returns NULL.
*/
Scope Channel.scope(Channel channel) => channel ? channel.lifetime : NULL;

// communication

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

/** Closes and destroys an unused Channel's complete storage scope. Every
    user and waiter must already have finished. Undelivered owned payload
    subtrees are destroyed outside the queue mutex; ordinary payloads are
    not followed. NULL does nothing. Owner destruction releases these native
    queue nodes and resources through the same finalizer.
*/
void Channel.free(Channel channel) {
  if (channel) { channel.closed = 1; channel.lifetime.destroy(); }
}

/** Ends sends and wakes waiters; accepted messages remain available to drain.
    Repeated close is harmless. Closing does not stop Thread users, free
    payloads, or acknowledge completion of a borrow.
    Raises: <bad-arg> for NULL.
*/
void Channel.close(Channel channel) {
  if (!channel) raise %(bad-arg (operation "Channel.close"));
  _lock(&channel.monitor.mutex);
  channel.closed = 1;
  _notify(channel);
  _unlock(&channel.monitor.mutex);
}

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

/** Initializes a borrowed iterator that blocks for each received message.
    Normal close and draining end iteration; cooperative stop raises instead.
    The Channel must outlive traversal.
*/
Iter Channel.iter(Channel c, Iter dest) => dest.init(c, _next, void);

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
  ChannelMessage message = NULL;
  int owned = 0;
  int status = channel.capacity ? _buffer_receive(channel, message)
                                : _rendezvous(channel, 0, value, owned);
  if (message) { value = message.value; owned = message.owned; }
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

static void _drop(void *bytes) {
  Channel channel = bytes;
  ChannelMessage message = channel.first;
  channel.first = channel.last = NULL;
  channel.count = 0;
  channel.closed = 1;
  while (message) {
    ChannelMessage next = message.next;
    if (message.owned) Scope.owner(message.value.pointer()).destroy();
    free(message);
    message = next;
  }
  if (channel.initialized == 2)
    _native_check(pthread_cond_destroy(&channel.monitor.condition));
  if (channel.initialized)
    _native_check(pthread_mutex_destroy(&channel.monitor.mutex));
}

static void _native_check(int error) {
  if (!error) return;
  fprintf(stderr, "Channel: native synchronization failed (%d)\n", error);
  abort();
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

static void _send(Channel channel, Var value, int owned) {
  if (!channel) raise %(bad-arg (operation "Channel.send"));
  if (value is void) raise %(void-op (operation "Channel.send"));
  if (channel.type != <var> && value.tag() != channel.type)
    raise %(bad-types (operation "Channel.send"));
  if (owned && !value.pointer())
    raise %(bad-arg (operation "Channel.send_owned"));

  ChannelMessage message = NULL;
  int status = 0;
  defer if (message && status != 1) free(message);
  if (channel.capacity) message = _message(value, owned);

  status = owned ? _send_owned(channel, message, value)
                 : channel.capacity ? _buffer_send(channel, message)
                                    : _rendezvous(channel, 1, value, owned);
  if (status < 0) x2c_thread_cancel();
  if (!status) raise %(bad-state (operation "Channel.send") (closed 1));
}

static int _send_owned(Channel channel, ChannelMessage message, Var value) {
  int container = _container(value), owned = 1, status = 0;
  Scope owner = Scope.owner(value.pointer());
  Scope previous = container ? owner : owner.parent(), payload = NULL;
  Scope contents = container ? _container_contents(value) : NULL;
  Scope contents_parent = contents ? contents.parent() : NULL;
  if (container) {
    payload = Scope.new();
    _move_container(value, &payload);
  }
  else { payload = owner; payload.transfer(NULL); }
  defer if (status != 1) {
    if (container) {
      _move_container(value, &previous);
      if (contents) contents.transfer(contents_parent);
      payload.destroy();
    }
    else payload.transfer(previous);
  }
  status = channel.capacity ? _buffer_send(channel, message)
                            : _rendezvous(channel, 1, value, owned);
  return status;
}

// queue commitment and private sleeping

static void _lock(pthread_mutex_t *mutex) {
  if (mutex) _native_check(pthread_mutex_lock(mutex));
}

static void _unlock(pthread_mutex_t *mutex) {
  if (mutex) _native_check(pthread_mutex_unlock(mutex));
}

static void _append_wait(ChannelWaits &queue, ChannelWait wait) {
  wait.previous = queue.last;
  wait.next = NULL;
  if (queue.last) queue.last.next = wait;
  else queue.first = wait;
  queue.last = wait;
  wait.linked = 1;
}

static void _remove_wait(ChannelWaits &queue, ChannelWait wait) {
  if (!wait.linked) return;
  if (wait.previous) wait.previous.next = wait.next;
  else queue.first = wait.next;
  if (wait.next) wait.next.previous = wait.previous;
  else queue.last = wait.previous;
  wait.linked = 0;
}

static void _notify(Channel channel) =>
  _native_check(pthread_cond_broadcast(&channel.monitor.condition));

/* Fresh registration and commitment hold one uninterrupted queue lock.
   Stop must claim and lock that monitor before publishing the caller flag. */
static int _buffer_send(Channel channel, ChannelMessage message) {
  Thread owner = NULL;
  _lock(&channel.monitor.mutex);
  if (!x2c_thread_channel_enter(&channel.monitor, owner)) {
    _unlock(&channel.monitor.mutex);
    return -1;
  }
  while (channel.count == channel.capacity && !channel.closed) {
    _sleep(channel);
    if (x2c_thread_wait_stopped(owner)) { _finish(channel, owner); return -1; }
  }
  int status = 0;
  if (!channel.closed) {
    if (channel.last) channel.last.next = message;
    else channel.first = message;
    channel.last = message;
    if (!channel.count++) _notify(channel);
    status = 1;
  }
  _finish(channel, owner);
  return status;
}

static int _buffer_receive(Channel channel, ChannelMessage &message) {
  Thread owner = NULL;
  _lock(&channel.monitor.mutex);
  if (!x2c_thread_channel_enter(&channel.monitor, owner)) {
    _unlock(&channel.monitor.mutex);
    return -1;
  }
  while (!channel.count && !channel.closed) {
    _sleep(channel);
    if (x2c_thread_wait_stopped(owner)) { _finish(channel, owner); return -1; }
  }
  int status = 0;
  if (channel.count) {
    message = channel.first;
    channel.first = message.next;
    if (!channel.first) channel.last = NULL;
    if (channel.count-- == channel.capacity) _notify(channel);
    status = 1;
  }
  _finish(channel, owner);
  return status;
}

static int _commit_available(
  Channel channel, int sending, ChannelWait peer, Var &value, int &owned) {
  if (peer) {
    if (sending) { peer.value = value; peer.owned = owned; }
    else { value = peer.value; owned = peer.owned; }
    peer.committed = 1;
    if (sending) _remove_wait(channel.receivers, peer);
    else _remove_wait(channel.senders, peer);
    _notify(channel);
    return 1;
  }
  return channel.closed ? 0 : 2;
}

/* Stop, notification, and the final predicate check share this mutex. */
static void _sleep(Channel channel) =>
  _native_check(pthread_cond_wait(
    &channel.monitor.condition, &channel.monitor.mutex));

/* Remove one stopped head per queue acquisition, then return for a fresh
   commitment check after releasing and reacquiring the mutex. */
static int _attempt(Channel channel, int sending, Var &value, int &owned) {
  ChannelWaits *other = sending ? &channel.receivers : &channel.senders;
  ChannelWait peer = channel.closed ? NULL : other.first;
  if (!peer || !x2c_thread_wait_stopped(peer.owner))
    return _commit_available(channel, sending, peer, value, owned);
  _remove_wait(*other, peer);
  _unlock(&channel.monitor.mutex);
  _lock(&channel.monitor.mutex);
  return 3;
}

static void _finish(Channel channel, Thread owner) {
  int released = x2c_thread_channel_leave(owner, &channel.monitor);
  _unlock(&channel.monitor.mutex);
  if (!released) {
    x2c_thread_wait_lock();
    x2c_thread_wait_unlock();
  }
}

/* Positive means committed, zero closed, negative stopped. Waiter storage is
   needed only after the freshly registered immediate attempt cannot commit. */
static int _rendezvous(Channel channel, int sending, Var &value, int &owned) {
  Thread owner = NULL;
  _lock(&channel.monitor.mutex);
  if (!x2c_thread_channel_enter(&channel.monitor, owner)) {
    _unlock(&channel.monitor.mutex);
    return -1;
  }
  int status = _attempt(channel, sending, value, owned);
  while (status == 3) {
    if (x2c_thread_wait_stopped(owner)) { status = -1; break; }
    status = _attempt(channel, sending, value, owned);
  }
  if (status == 2) return _wait_pending(channel, sending, owner, value, owned);
  _finish(channel, owner);
  return status;
}

static int _wait_pending(
  Channel channel, int sending, Thread owner, Var &value, int &owned) {
  ChannelWait wait = &channel_wait;
  *wait = (struct ChannelWait) {
    .value = value, .owner = owner, .owned = owned };
  int status = _wait_for_commit(channel, sending, wait, value, owned);
  if (wait.committed) { value = wait.value; owned = wait.owned; }
  if (sending) _remove_wait(channel.senders, wait);
  else _remove_wait(channel.receivers, wait);
  _finish(channel, owner);
  return status;
}

static int _wait_for_commit(
  Channel channel, int sending, ChannelWait wait, Var &value, int &owned) {
  while (1) {
    if (wait.committed) return 1;
    if (x2c_thread_wait_stopped(wait.owner)) return -1;
    int status = _attempt(channel, sending, value, owned);
    if (status == 3) continue;
    if (status != 2) return status;
    if (!wait.linked) {
      if (sending) _append_wait(channel.senders, wait);
      else _append_wait(channel.receivers, wait);
    }
    _sleep(channel);
  }
}

/* A sender owns native queue storage until commitment. The queue, then the
   receiver, owns the accepted node independently of Scope lists. */
static ChannelMessage _message(Var value, int owned) {
  ChannelMessage message = malloc(sizeof(struct ChannelMessage));
  if (!message) raise %(alloc-fail (operation "Channel.send"));
  *message = (struct ChannelMessage) { .value = value, .owned = owned };
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

static int _next(Iter iter, Var *out) {
  Channel channel = iter.obj;
  Var value = channel.receive();
  if (value is void) { iter.next = NULL; return 0; }
  *out = value;
  return 1;
}

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
