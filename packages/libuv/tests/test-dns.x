/*  test-dns.x -- copied addresses and asynchronous DNS requests */

import "libuv" with UvAddress, UvLookup, UvLoop;

#include "test-support.x"
#include <netdb.h>
#include <stdlib.h>

$(import "../../../unittest/test-macros.xmacro")

typedef struct LookupState {
  uv_getaddrinfo_t *native;
  uv_thread_t loop_thread;
  uv_thread_t callback_thread;
  size_t count;
  int calls;
  int cleaned;
  int cancelled;
} LookupState;

static void _record_lookup(UvLookup lookup, Var value) {
  LookupState *state = value.pointer();
  state.callback_thread = uv_thread_self();
  state.calls++;
  state.native = lookup.native();
  state.cleaned = lookup.native()->addrinfo == NULL;
  state.cancelled = lookup.cancelled();
  state.count = lookup.count();
}

static void numeric_addresses_round_trip(void) {
  UvAddress ip4 = UvAddress.ip4(%"127.0.0.1", 4321);
  EXPECT_STR_EQ(ip4.host(), %"127.0.0.1");
  EXPECT_INT_EQ(ip4.port(), 4321);
  EXPECT_INT_EQ(ip4.family(), AF_INET);
  EXPECT_INT_EQ(ip4.socket_type(), 0);
  EXPECT_INT_EQ(ip4.protocol(), 0);
  EXPECT_INT_EQ(ip4.scope_id(), 0);
  EXPECT_NULL(ip4.canonical_name());
  EXPECT_INT_EQ(ip4.native()->sa_family, AF_INET);

  UvAddress ip6 = UvAddress.ip6(%"::1", 4321);
  EXPECT_STR_EQ(ip6.host(), %"::1");
  EXPECT_INT_EQ(ip6.port(), 4321);
  EXPECT_INT_EQ(ip6.family(), AF_INET6);
  EXPECT_INT_EQ(ip6.socket_type(), 0);
  EXPECT_INT_EQ(ip6.protocol(), 0);
  EXPECT_INT_EQ(ip6.scope_id(), 0);
  EXPECT_NULL(ip6.canonical_name());
  EXPECT_INT_EQ(ip6.native()->sa_family, AF_INET6);

  int caught = 0;
  try UvAddress.ip4(%"not-an-ip", 80);
  catch %(io-fail (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"ip4_addr");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try UvAddress.ip6(%"::1", 65536);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"ip6");
  }
  EXPECT_TRUE(caught);
}

static void _verify_numeric_lookup(
  UvLookup lookup, int family, int socket_type, int transport, String host,
  int port) {
  EXPECT_TRUE(lookup.count() > 0);
  for (int index = 0; index < (int) lookup.count(); index++) {
    UvAddress address = lookup.address(index);
    EXPECT_INT_EQ(address.family(), family);
    EXPECT_INT_EQ(address.socket_type(), socket_type);
    EXPECT_INT_EQ(address.protocol(), transport);
    EXPECT_STR_EQ(address.host(), host);
    EXPECT_INT_EQ(address.port(), port);
    EXPECT_INT_EQ(address.native()->sa_family, family);
  }
}

static void lookup_hints_copy_ipv4_and_ipv6_results(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  LookupState ip4_state = { 0 }, ip6_state = { 0 };
  ip4_state.loop_thread = ip6_state.loop_thread = uv_thread_self();

  UvLookup ip4 = loop.lookup(%"127.0.0.1", %"4321")
    .hints(AF_INET, SOCK_DGRAM, IPPROTO_UDP,
           AI_NUMERICHOST | AI_NUMERICSERV)
    .start(Var.new(<p48>, &ip4_state), _record_lookup);
  UvLookup ip6 = loop.lookup(%"::1", %"4321")
    .hints(AF_INET6, SOCK_DGRAM, IPPROTO_UDP,
           AI_NUMERICHOST | AI_NUMERICSERV)
    .start(Var.new(<p48>, &ip6_state), _record_lookup);

  EXPECT_PTR_EQ(ip4.loop(), loop);
  EXPECT_PTR_EQ(ip4.native()->data, ip4);
  EXPECT_PTR_EQ(ip6.native()->data, ip6);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(ip4_state.calls, 1);
  EXPECT_INT_EQ(ip6_state.calls, 1);
  EXPECT_TRUE(ip4_state.cleaned);
  EXPECT_TRUE(ip6_state.cleaned);
  EXPECT_TRUE(uv_thread_equal(
    &ip4_state.loop_thread, &ip4_state.callback_thread
  ));
  EXPECT_TRUE(uv_thread_equal(
    &ip6_state.loop_thread, &ip6_state.callback_thread
  ));
  EXPECT_NULL(ip4.native()->addrinfo);
  EXPECT_NULL(ip6.native()->addrinfo);
  _verify_numeric_lookup(
    ip4, AF_INET, SOCK_DGRAM, IPPROTO_UDP, %"127.0.0.1", 4321
  );
  _verify_numeric_lookup(
    ip6, AF_INET6, SOCK_DGRAM, IPPROTO_UDP, %"::1", 4321
  );
}

static void resolve_and_canonical_names_use_copied_results(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  LookupState resolved_state = { 0 }, canonical_state = { 0 };
  UvLookup resolved = loop.resolve(
    %"localhost", %"80", Var.new(<p48>, &resolved_state), _record_lookup
  );
  UvLookup canonical = loop.lookup(%"localhost", %"80")
    .hints(AF_UNSPEC, SOCK_STREAM, 0, AI_CANONNAME)
    .start(Var.new(<p48>, &canonical_state), _record_lookup);

  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(resolved_state.calls, 1);
  EXPECT_INT_EQ(canonical_state.calls, 1);
  EXPECT_TRUE(resolved.count() > 0);
  EXPECT_TRUE(canonical.count() > 0);
  EXPECT_INT_EQ(resolved.address(0).socket_type(), SOCK_STREAM);
  EXPECT_NOT_NULL(canonical.address(0).canonical_name());
  EXPECT_NULL(resolved.native()->addrinfo);
  EXPECT_NULL(canonical.native()->addrinfo);
  EXPECT_FALSE(resolved.cancel());

  int caught = 0;
  try resolved.address(-1);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"lookup_address");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try resolved.address((int) resolved.count());
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"lookup_address");
  }
  EXPECT_TRUE(caught);
}

static void invalid_numeric_host_preserves_libuv_error_detail(void) {
  UvLoop loop = UvLoop.new();
  LookupState state = { 0 };
  UvLookup lookup = loop.lookup(%"not-an-ip", %"80")
    .hints(AF_UNSPEC, SOCK_STREAM, IPPROTO_TCP,
           AI_NUMERICHOST | AI_NUMERICSERV)
    .start(Var.new(<p48>, &state), _record_lookup);

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(io-fail (library ?library) (operation ?operation)
         (status ?code) (name ?name) (message ?message) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"libuv");
    EXPECT_STR_EQ(operation.string(), %"getaddrinfo");
    EXPECT_INT_EQ(code.integer(), UV_EAI_NONAME);
    EXPECT_STR_EQ(name.string(), String.new(uv_err_name(UV_EAI_NONAME)));
    EXPECT_STR_EQ(
      message.string(), String.new(uv_strerror(UV_EAI_NONAME))
    );
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(state.calls, 0);
  EXPECT_NULL(lookup.native()->addrinfo);
  EXPECT_FALSE(lookup.cancel());
  EXPECT_NULL(loop.free());
}

static void loop_free_rejects_a_pending_lookup_without_draining_it(void) {
  UvLoop loop = UvLoop.new();
  LookupState state = { 0 };
  UvLookup lookup = loop.resolve(
    %"127.0.0.1", %"80", Var.new(<p48>, &state), _record_lookup
  );

  int caught = 0;
  try loop.free();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"loop_free");
  }
  EXPECT_TRUE(caught);
  if (!caught) return;

  EXPECT_INT_EQ(state.calls, 0);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.calls, 1);
  EXPECT_TRUE(lookup.count() > 0);
  EXPECT_NULL(loop.free());
}

static void lookup_builder_rejects_invalid_lifetimes(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  int caught = 0;
  try loop.lookup(NULL, NULL);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"lookup");
  }
  EXPECT_TRUE(caught);

  UvLookup lookup = loop.lookup(%"127.0.0.1", %"80");
  caught = 0;
  try lookup.count();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"lookup_count");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try lookup.cancel();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"lookup_cancel");
  }
  EXPECT_TRUE(caught);

  LookupState state = { 0 };
  lookup.start(Var.new(<p48>, &state), _record_lookup);
  caught = 0;
  try lookup.hints(AF_INET, SOCK_STREAM, 0, 0);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"lookup_hints");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try lookup.start(Var.new(<p48>, &state), _record_lookup);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"lookup_start");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.calls, 1);

  UvLoop closed = UvLoop.new();
  UvLookup abandoned = closed.lookup(%"127.0.0.1", %"80");
  closed.free();
  caught = 0;
  try abandoned.start(void, _record_lookup);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"lookup_start");
  }
  EXPECT_TRUE(caught);
}

typedef struct PoolBlocker {
  uv_work_t work;
  uv_sem_t started;
  uv_sem_t release;
  int after_calls;
  int after_status;
} PoolBlocker;

static void _hold_only_pool_worker(uv_work_t *request) {
  PoolBlocker *blocker = request->data;
  uv_sem_post(&blocker->started);
  uv_sem_wait(&blocker->release);
}

static void _pool_worker_released(uv_work_t *request, int status) {
  PoolBlocker *blocker = request->data;
  blocker->after_calls++;
  blocker->after_status = status;
}

static void accepted_cancel_keeps_request_alive_until_completion(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  PoolBlocker blocker = { 0 };
  LookupState state = { 0 };
  EXPECT_INT_EQ(uv_sem_init(&blocker.started, 0), 0);
  EXPECT_INT_EQ(uv_sem_init(&blocker.release, 0), 0);
  blocker.work.data = &blocker;
  EXPECT_INT_EQ(uv_queue_work(
    loop.native(), &blocker.work,
    _hold_only_pool_worker, _pool_worker_released
  ), 0);
  uv_sem_wait(&blocker.started);

  UvLookup lookup = loop.resolve(
    %"127.0.0.1", %"80", Var.new(<p48>, &state), _record_lookup
  );
  uv_getaddrinfo_t *native = lookup.native();
  EXPECT_TRUE(lookup.cancel());
  uv_sem_post(&blocker.release);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);

  EXPECT_INT_EQ(blocker.after_calls, 1);
  EXPECT_INT_EQ(blocker.after_status, 0);
  EXPECT_INT_EQ(state.calls, 1);
  EXPECT_TRUE(state.cancelled);
  EXPECT_INT_EQ(state.count, 0);
  EXPECT_PTR_EQ(state.native, native);
  EXPECT_NULL(native->addrinfo);
  EXPECT_FALSE(lookup.cancel());
  uv_sem_destroy(&blocker.started);
  uv_sem_destroy(&blocker.release);
}

typedef struct FailingLookupState {
  String copied_host;
  int calls;
  int cleaned;
} FailingLookupState;

static void _raise_after_lookup(UvLookup lookup, Var value) {
  FailingLookupState *state = value.pointer();
  state.calls++;
  state.cleaned = lookup.native()->addrinfo == NULL;
  state.copied_host = lookup.address(0).host();
  raise %(malformed (library "test")
          (reason "a lookup callback failed"));
}

static void lookup_callback_errors_preserve_results_and_loop_resumption(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  FailingLookupState failed = { 0 };
  UvLookup first = loop.resolve(
    %"127.0.0.1", %"80", Var.new(<p48>, &failed), _raise_after_lookup
  );

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library *) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"a lookup callback failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(failed.calls, 1);
  EXPECT_TRUE(failed.cleaned);
  EXPECT_STR_EQ(failed.copied_host, %"127.0.0.1");
  EXPECT_STR_EQ(first.address(0).host(), %"127.0.0.1");
  EXPECT_NULL(first.native()->addrinfo);

  LookupState resumed = { 0 };
  UvLookup second = loop.resolve(
    %"::1", %"80", Var.new(<p48>, &resumed), _record_lookup
  );
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(resumed.calls, 1);
  EXPECT_STR_EQ(second.address(0).host(), %"::1");
}

void dns_suite(void) {
  $test.run(numeric_addresses_round_trip);
  $test.run(lookup_hints_copy_ipv4_and_ipv6_results);
  $test.run(resolve_and_canonical_names_use_copied_results);
  $test.run(invalid_numeric_host_preserves_libuv_error_detail);
  $test.run(loop_free_rejects_a_pending_lookup_without_draining_it);
  $test.run(lookup_builder_rejects_invalid_lifetimes);
  $test.run(accepted_cancel_keeps_request_alive_until_completion);
  $test.run(lookup_callback_errors_preserve_results_and_loop_resumption);
}

int main(void) {
  setenv("UV_THREADPOOL_SIZE", "1", 1);
  TestHarness_begin();
  $test.suite(dns_suite);
  return TestHarness_finish();
}
