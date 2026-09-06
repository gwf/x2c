/*  mutex.x -- shared mutable-state coordination

    Copyright (c) 2026 Gary William Flake

    `Mutex` is an opaque native mutex. Its `Scope` owner must outlive every
    thread that can use it, and it may be freed only while unlocked.
*/

#pragma once

$(import "error-macros.xmacro")

#include "common.x"

/** A native mutex allocated in the active `Scope` without recursive locking.
    Its `Scope` and handle must outlive every user and waiter. Destroy it only
    while unlocked, and do not use the handle or its storage after that.
*/
typedef struct Mutex *Mutex;

#pragma private

#include "scope.x"

#include <errno.h>
#include <pthread.h>

struct Mutex {
  pthread_mutex_t native;
};

static void _error(const char *operation, int error) {
  String name = String.new(operation);
  raise %(io-fail (operation $name) (errno $error));
}

/** Creates an unlocked `Mutex` owned by the active `Scope`.
    Raises: `<alloc-fail>` when storage cannot be allocated, or `<io-fail>`
    when native mutex initialization fails. An initialization failure releases
    the allocated storage.
*/
Mutex Mutex.new(void) {
  Mutex mutex = Scope.malloc(sizeof(struct Mutex));
  int error = pthread_mutex_init(&mutex.native, NULL);
  if (error) {
    Scope.free(mutex);
    _error("pthread_mutex_init", error);
  }
  return mutex;
}

/** Locks `mutex`, waiting until it becomes available.
    The `Mutex` is non-recursive; the caller must not already hold it.
    Raises: `<bad-state>` for NULL, or `<io-fail>` when native locking fails.
*/
void Mutex.lock(Mutex mutex) {
  if (!mutex) raise %(bad-state (owner "Mutex.lock"));
  int error = pthread_mutex_lock(&mutex.native);
  if (error) _error("pthread_mutex_lock", error);
}

/** Attempts to lock `mutex` without waiting.
    Returns one when acquired or zero when busy.
    Raises: `<bad-state>` for NULL, or `<io-fail>` for another native failure.
*/
int Mutex.try_lock(Mutex mutex) {
  if (!mutex) raise %(bad-state (owner "Mutex.try_lock"));
  int error = pthread_mutex_trylock(&mutex.native);
  if (!error) return 1;
  if (error == EBUSY) return 0;
  _error("pthread_mutex_trylock", error);
}

/** Unlocks a `Mutex` held by the calling thread.
    Raises: `<bad-state>` for NULL, or `<io-fail>` when native unlocking fails.
*/
void Mutex.unlock(Mutex mutex) {
  if (!mutex) raise %(bad-state (owner "Mutex.unlock"));
  int error = pthread_mutex_unlock(&mutex.native);
  if (error) _error("pthread_mutex_unlock", error);
}

/** Destroys an unused, unlocked `Mutex` and releases its `Scope` storage.
    Native destruction occurs first, so a native failure leaves the allocation
    intact. No thread may retain the handle or be waiting on it.
    Raises: `<bad-state>` for NULL, or `<io-fail>` when native destruction
    fails.
*/
void Mutex.free(Mutex mutex) {
  if (!mutex) raise %(bad-state (owner "Mutex.free"));
  int error = pthread_mutex_destroy(&mutex.native);
  if (error) _error("pthread_mutex_destroy", error);
  Scope.free(mutex);
}
