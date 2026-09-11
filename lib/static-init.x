/*  static-init.x -- first-use storage for dynamic local statics

    Copyright (c) 2026 Gary William Flake

    A guard publishes native storage after the initializer succeeds. Pending
    owners and their wait edges share one lock; user initialization and Error
    transfer run outside it. Storage follows the process or worker lifetime,
    independently of Scope, Context, and the values referenced by its bytes.
*/

#pragma once
#include "common.x"
#pragma private

#include "exception.x"
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct StaticThread {
  X2CStatic *waiting, *values;
} StaticThread;

static threaded StaticThread static_thread;
static X2CStatic *static_values;
static pthread_mutex_t static_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t static_changed =
  (pthread_cond_t) PTHREAD_COND_INITIALIZER;

static void _native_error(int error) {
  if (!error) return;
  fprintf(stderr, "static initialization: synchronization failed (%d)\n",
          error);
  abort();
}

static void _lock(void) => _native_error(pthread_mutex_lock(&static_mutex));
static void _unlock(void) =>
  _native_error(pthread_mutex_unlock(&static_mutex));

static int _cycle(X2CStatic *guard, StaticThread *self) {
  StaticThread *owner = guard.owner;
  while (owner) {
    if (owner == self) return 1;
    owner = owner.waiting ? owner.waiting.owner : NULL;
  }
  return 0;
}

/* Acquires initialization of a compiler-owned zero-initialized guard.
    Returns one with zeroed, aligned `payload` for the winning initializer,
    or zero after another invocation has committed. The winner must register
    `x2c_static_abort` as a cleanup before evaluating user code and commit only
    after copying the complete value. It may use the pending address itself.
    Raises: `<bad-state>` for recursive or cyclic initialization,
    `<alloc-fail>` for native allocation failure. A failed initializer keeps
    its reserved address; the next attempt starts with zeroed bytes.
*/
int x2c_static_acquire(
  X2CStatic *guard, size_t size, size_t alignment, int per_thread) {
  if (__atomic_load_n(&guard.ready, __ATOMIC_ACQUIRE)) return 0;
  StaticThread *self = &static_thread;
  _lock();
  while (!__atomic_load_n(&guard.ready, __ATOMIC_RELAXED) && guard.owner) {
    if (_cycle(guard, self)) {
      _unlock();
      raise %(bad-state (owner "static initialization")
              (reason "recursive or cyclic initialization"));
    }
    self.waiting = guard;
    _native_error(pthread_cond_wait(&static_changed, &static_mutex));
    self.waiting = NULL;
  }
  if (__atomic_load_n(&guard.ready, __ATOMIC_RELAXED)) {
    _unlock();
    return 0;
  }
  guard.owner = self;
  _unlock();

  if (!guard.payload) {
    if (alignment < sizeof(void *)) alignment = sizeof(void *);
    void *payload = NULL;
    if (posix_memalign(&payload, alignment, size ? size : 1)) {
      x2c_static_abort(guard);
      raise %(alloc-fail (owner "static initialization"));
    }
    _lock();
    guard.payload = payload;
    X2CStatic **values = per_thread ? &static_thread.values : &static_values;
    guard.next = *values;
    *values = guard;
    _unlock();
  }
  memset(guard.payload, 0, size);
  return 1;
}

/* Publishes a completed initialization with release ordering.
    Only the winning initializer calls this, after filling `payload`.
*/
void x2c_static_commit(X2CStatic *guard) {
  _lock();
  guard.owner = NULL;
  __atomic_store_n(&guard.ready, 1, __ATOMIC_RELEASE);
  _native_error(pthread_cond_broadcast(&static_changed));
  _unlock();
}

/* Releases an unpublished initializer's ownership and wakes waiters.
    Reserved storage survives failed attempts so escaped addresses stay valid.
    Used directly as an `X2CCleanup` callback. A committed guard is unchanged,
    so normal cleanup after `x2c_static_commit` needs no separate flag.
*/
void x2c_static_abort(void *data) {
  X2CStatic *guard = data;
  if (__atomic_load_n(&guard.ready, __ATOMIC_ACQUIRE)) return;
  _lock();
  guard.owner = NULL;
  _native_error(pthread_cond_broadcast(&static_changed));
  _unlock();
}

static void _release(X2CStatic **values) {
  while (*values) {
    X2CStatic *guard = *values;
    *values = guard.next;
    free(guard.payload);
    guard.payload = NULL;
    guard.next = NULL;
    __atomic_store_n(&guard.ready, 0, __ATOMIC_RELEASE);
  }
}

/* Releases this worker's reserved dynamic `threaded` storage. */
void x2c_static_thread_release(void) {
  _release(&static_thread.values);
}

/* Releases reserved process storage after the runtime shutdown hooks. */
void x2c_static_shutdown(void) {
  _release(&static_values);
}
