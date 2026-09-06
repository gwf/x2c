/*  test-tcp.x -- TCP clients, listeners, streams, and request lifetimes */

import "libuv" with UvAddress, UvLoop, UvTcp, UvTimer;

#include "test-support.x"
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

enum { TCP_CLIENTS = 3 };

typedef struct TcpTest TcpTest;

typedef struct TcpPeer {
  TcpTest *test;
  UvTcp tcp;
  Bytes received;
  Bytes retained;
  size_t final_queue;
  int index;
} TcpPeer;

struct TcpTest {
  UvLoop loop;
  UvTcp listener;
  UvTimer guard;
  TcpPeer clients[TCP_CLIENTS];
  TcpPeer servers[TCP_CLIENTS];
  int accepted;
  int client_eof;
  int server_eof;
  uv_thread_t driver;
  int connect_thread;
  int listen_thread;
  int read_thread;
};

static int _same_tcp_thread(TcpTest *test) {
  uv_thread_t current = uv_thread_self();
  return uv_thread_equal(&test.driver, &current);
}

static void _tcp_timeout(UvTimer timer, Var value) {
  (void) timer;
  (void) value;
  raise %(timeout (library "libuv") (operation "tcp test"));
}

static void _echo_read(UvTcp tcp, Bytes chunk, Var value) {
  TcpPeer *peer = value.pointer();
  peer.test.read_thread &= _same_tcp_thread(peer.test);
  if (chunk) {
    peer.received = peer.received.append(chunk, chunk.len());
    tcp.write_bytes(chunk);
    return;
  }
  peer.test.server_eof++;
  tcp.shutdown_write();
}

static void _client_read(UvTcp tcp, Bytes chunk, Var value) {
  TcpPeer *peer = value.pointer();
  peer.test.read_thread &= _same_tcp_thread(peer.test);
  if (chunk) {
    if (!peer.retained) peer.retained = chunk;
    peer.received = peer.received.append(chunk, chunk.len());
    return;
  }
  peer.test.client_eof++;
  peer.final_queue = tcp.write_queue_size();
  tcp.close();
  if (peer.test.client_eof != TCP_CLIENTS) return;
  for (int i = 0; i < TCP_CLIENTS; i++) peer.test.servers[i].tcp.close();
  peer.test.listener.close();
  peer.test.guard.stop();
}

static void _client_connected(UvTcp tcp, Var value) {
  TcpPeer *peer = value.pointer();
  peer.test.connect_thread &= _same_tcp_thread(peer.test);
  unsigned char payload[] = {
    (unsigned char) ('0' + peer.index), 0, 'x', '2', 'c'
  };
  Bytes bytes = Bytes.new(1).append(payload, sizeof(payload));
  UvAddress local = tcp.local_address();
  UvAddress remote = tcp.peer_address();
  EXPECT_TRUE(local.port() > 0);
  EXPECT_TRUE(remote.port() > 0);
  EXPECT_INT_EQ(remote.family(), AF_INET);
  tcp.read(value, _client_read).write_bytes(bytes)
    .shutdown_write().shutdown_write();
  memset(bytes, '!', bytes.len());
  bytes.free();
}

static void _client_accepted(UvTcp listener, UvTcp tcp, Var value) {
  TcpTest *test = value.pointer();
  test.listen_thread &= _same_tcp_thread(test);
  TcpPeer *peer = &test.servers[test.accepted++];
  peer.test = test;
  peer.tcp = tcp;
  peer.received = Bytes.new(1);
  EXPECT_TRUE(tcp.local_address().port() > 0);
  EXPECT_TRUE(tcp.peer_address().port() > 0);
  tcp.read(Var.new(<p48>, peer), _echo_read);
  EXPECT_PTR_EQ(listener.native(), test.listener.native());
}

static void tcp_exchanges_copied_binary_data_with_several_clients(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  TcpTest test = {
    .loop = loop,
    .driver = uv_thread_self(),
    .connect_thread = 1,
    .listen_thread = 1,
    .read_thread = 1
  };
  Var state = Var.new(<p48>, &test);
  test.guard = loop.timer(5000, 0, state, _tcp_timeout);
  test.listener = loop.tcp().bind(UvAddress.ip4(%"127.0.0.1", 0), 0);
  test.listener.listen(TCP_CLIENTS + 1, state, _client_accepted);
  UvAddress address = test.listener.local_address();

  EXPECT_PTR_EQ(test.listener.loop(), loop);
  EXPECT_NOT_NULL(test.listener.native());
  EXPECT_STR_EQ(address.host(), %"127.0.0.1");
  EXPECT_TRUE(address.port() > 0);
  EXPECT_INT_EQ(address.family(), AF_INET);
  EXPECT_INT_EQ(address.socket_type(), SOCK_STREAM);
  EXPECT_INT_EQ(address.protocol(), IPPROTO_TCP);

  for (int i = 0; i < TCP_CLIENTS; i++) {
    TcpPeer *peer = &test.clients[i];
    peer.test = &test;
    peer.index = i + 1;
    peer.received = Bytes.new(1);
    peer.tcp = loop.tcp().connect(
      UvAddress.ip4(address.host(), address.port()),
      Var.new(<p48>, peer), _client_connected
    );
  }
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(test.accepted, TCP_CLIENTS);
  EXPECT_INT_EQ(test.server_eof, TCP_CLIENTS);
  EXPECT_INT_EQ(test.client_eof, TCP_CLIENTS);
  EXPECT_TRUE(test.connect_thread);
  EXPECT_TRUE(test.listen_thread);
  EXPECT_TRUE(test.read_thread);
  for (int i = 0; i < TCP_CLIENTS; i++) {
    unsigned char expected[] = {
      (unsigned char) ('0' + i + 1), 0, 'x', '2', 'c'
    };
    EXPECT_INT_EQ(test.clients[i].received.len(), sizeof(expected));
    EXPECT_TRUE(!memcmp(test.clients[i].received, expected, sizeof(expected)));
    EXPECT_NOT_NULL(test.clients[i].retained);
    EXPECT_TRUE(test.clients[i].retained.len() <= sizeof(expected));
    EXPECT_TRUE(!memcmp(
      test.clients[i].retained, expected, test.clients[i].retained.len()
    ));
    EXPECT_INT_EQ(test.clients[i].final_queue, 0);
    test.clients[i].received.free();
    test.servers[i].received.free();
  }
}

typedef struct RestartState {
  UvLoop loop;
  UvTcp listener;
  UvTcp client;
  UvTcp server;
  UvTimer timer;
  Bytes received;
  int reads;
  int eof;
} RestartState;

static void _restart_read(UvTcp tcp, Bytes chunk, Var value) {
  RestartState *state = value.pointer();
  if (!chunk) {
    state.eof++;
    state.client.close();
    state.server.close();
    state.listener.close();
    return;
  }
  state.reads++;
  state.received = state.received.append(chunk, chunk.len());
  if (state.reads == 1) tcp.stop_read();
}

static void _restart_timer(UvTimer timer, Var value) {
  RestartState *state = value.pointer();
  timer.stop();
  state.server.read(value, _restart_read);
  state.client.write(%"B").shutdown_write();
}

static void _restart_connected(UvTcp tcp, Var value) {
  RestartState *state = value.pointer();
  tcp.write(%"A");
  state.timer = state.loop.timer(10, 0, value, _restart_timer);
}

static void _restart_accepted(UvTcp listener, UvTcp tcp, Var value) {
  (void) listener;
  RestartState *state = value.pointer();
  state.server = tcp;
  tcp.read(value, _restart_read);
}

static void tcp_reads_stop_and_restart_and_eof_is_null(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  RestartState state = { .loop = loop, .received = Bytes.new(1) };
  defer state.received.free();
  Var value = Var.new(<p48>, &state);
  state.listener = loop.tcp().bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .listen(4, value, _restart_accepted);
  UvAddress address = state.listener.local_address();
  state.client = loop.tcp().connect(address, value, _restart_connected);
  loop.run(UV_RUN_DEFAULT);

  EXPECT_INT_EQ(state.reads, 2);
  EXPECT_INT_EQ(state.eof, 1);
  EXPECT_INT_EQ(state.received.len(), 2);
  EXPECT_TRUE(!memcmp(state.received, "AB", 2));
}

typedef struct OwnedState {
  UvTcp listener;
  UvTcp client;
  UvTcp accepted;
  Bytes received;
  int eof;
  int restart_rejected;
} OwnedState;

static void _owned_read(UvTcp tcp, Bytes chunk, Var value) {
  OwnedState *state = value.pointer();
  if (chunk) {
    state.received = state.received.append(chunk, chunk.len());
    return;
  }
  state.eof = 1;
  try tcp.read(value, _owned_read);
  catch %(bad-state (library *) (operation ?operation) (reason ?reason) *): {
    state.restart_rejected = 1;
    EXPECT_STR_EQ(operation.string(), %"read_start");
    EXPECT_STR_EQ(reason.string(), %"the TCP read side has reached EOF");
  }
  tcp.close();
  state.client.close();
}

static void _owned_connected(UvTcp tcp, Var value) {
  (void) value;
  tcp.write(%"owned").shutdown_write();
}

static void _owned_accepted(UvTcp listener, UvTcp tcp, Var value) {
  OwnedState *state = value.pointer();
  state.accepted = tcp;
  listener.close();
  tcp.read(value, _owned_read);
}

static void tcp_accepted_connection_outlives_its_listener(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  OwnedState state = { .received = Bytes.new(1) };
  defer state.received.free();
  Var value = Var.new(<p48>, &state);
  state.listener = loop.tcp().bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .listen(2, value, _owned_accepted);
  state.client = loop.tcp().connect(
    state.listener.local_address(), value, _owned_connected
  );
  loop.run(UV_RUN_DEFAULT);
  EXPECT_NOT_NULL(state.accepted);
  EXPECT_INT_EQ(state.eof, 1);
  EXPECT_TRUE(state.restart_rejected);
  EXPECT_INT_EQ(state.received.len(), 5);
  EXPECT_TRUE(!memcmp(state.received, "owned", 5));
}

typedef struct PressureState {
  UvLoop loop;
  UvTcp listener;
  UvTcp sender;
  UvTcp receiver;
  UvTimer drain;
  Bytes received;
  size_t queued;
  size_t final_queue;
  size_t expected;
  int accepted;
  int connected;
  int eof;
} PressureState;

static void _pressure_read(UvTcp tcp, Bytes chunk, Var value) {
  PressureState *state = value.pointer();
  if (chunk) {
    state.received = state.received.append(chunk, chunk.len());
    return;
  }
  state.eof = 1;
  state.final_queue = state.sender.write_queue_size();
  tcp.close();
  state.sender.close();
  state.listener.close();
}

static void _pressure_drain(UvTimer timer, Var value) {
  PressureState *state = value.pointer();
  timer.stop();
  state.receiver.read(value, _pressure_read);
  state.sender.shutdown_write();
}

static void _pressure_begin(PressureState *state, Var value) {
  if (!state.accepted || !state.connected || state.drain) return;
  state.drain = state.loop.timer(10, 0, value, _pressure_drain);
}

static void _pressure_connected(UvTcp tcp, Var value) {
  PressureState *state = value.pointer();
  state.connected = 1;
  Scope.retain();
  Bytes source = Bytes.new(1);
  unsigned char byte = 0x5a;
  source = source.append_fill(&byte, 16 * 1024 * 1024);
  state.expected = source.len();
  tcp.write_bytes(source);
  state.queued = tcp.write_queue_size();
  memset(source, 0xa5, source.len());
  Scope.release();
  _pressure_begin(state, value);
}

static void _pressure_accepted(UvTcp listener, UvTcp tcp, Var value) {
  (void) listener;
  PressureState *state = value.pointer();
  state.receiver = tcp;
  state.accepted = 1;
  _pressure_begin(state, value);
}

static void tcp_large_writes_own_their_copy_and_report_backpressure(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  PressureState state = { .loop = loop, .received = Bytes.new(1) };
  defer state.received.free();
  Var value = Var.new(<p48>, &state);
  state.listener = loop.tcp().bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .listen(4, value, _pressure_accepted);
  state.sender = loop.tcp().connect(
    state.listener.local_address(), value, _pressure_connected
  );
  loop.run(UV_RUN_DEFAULT);

  EXPECT_TRUE(state.queued > 0);
  EXPECT_TRUE(state.queued <= state.expected);
  EXPECT_INT_EQ(state.received.len(), state.expected);
  EXPECT_INT_EQ(state.eof, 1);
  EXPECT_INT_EQ(state.final_queue, 0);
  for (size_t i = 0; i < state.received.len(); i++) {
    if (((unsigned char *) state.received)[i] != 0x5a)
      EXPECT_INT_EQ(((unsigned char *) state.received)[i], 0x5a);
  }
}

static void _unexpected_connect(UvTcp tcp, Var value) {
  (void) tcp;
  int *calls = value.pointer();
  (*calls)++;
}

static void _ignore_accept(UvTcp listener, UvTcp tcp, Var value) {
  (void) listener;
  (void) value;
  tcp.close();
}

static void tcp_refused_connection_reports_error_and_finishes_request(void) {
  UvLoop loop = UvLoop.new();
  UvTcp listener = loop.tcp().bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .listen(1, void, _ignore_accept);
  UvAddress unused = listener.local_address();
  listener.close();
  loop.run(UV_RUN_DEFAULT);

  int calls = 0;
  UvTcp client = loop.tcp().connect(
    unused, Var.new(<p48>, &calls), _unexpected_connect
  );
  int caught = 0;
  try loop.free();
  catch %(bad-state (library *) (operation ?operation) (reason *)
          (pending ?pending) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"loop_free");
    EXPECT_TRUE(pending.integer() > 0);
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(io-fail (library *) (operation ?operation) (status *)
          (name ?name) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"tcp_connect");
    EXPECT_STR_EQ(name.string(), %"ECONNREFUSED");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(calls, 0);
  loop.run(UV_RUN_DEFAULT);
  EXPECT_NULL(client.close());
  EXPECT_NULL(client.close());
  EXPECT_NULL(loop.free());
}

typedef struct FailureState {
  UvTcp listener;
  UvTcp client;
  UvTcp accepted;
} FailureState;

static void _failing_read(UvTcp tcp, Bytes chunk, Var value) {
  (void) tcp;
  (void) chunk;
  (void) value;
  raise %(malformed (library "test") (reason "TCP read failed"));
}

static void _failure_connected(UvTcp tcp, Var value) {
  tcp.write(%"fail").shutdown_write();
  (void) value;
}

static void _failure_accepted(UvTcp listener, UvTcp tcp, Var value) {
  (void) listener;
  FailureState *state = value.pointer();
  state.accepted = tcp;
  tcp.read(value, _failing_read);
}

static void tcp_read_error_returns_from_run_and_the_loop_resumes(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  FailureState state = { 0 };
  Var value = Var.new(<p48>, &state);
  state.listener = loop.tcp().bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .listen(2, value, _failure_accepted);
  state.client = loop.tcp().connect(
    state.listener.local_address(), value, _failure_connected
  );
  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library ?library) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"test");
    EXPECT_STR_EQ(reason.string(), %"TCP read failed");
  }
  EXPECT_TRUE(caught);
  state.client.close();
  state.listener.close();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
}

static void _failing_accept(UvTcp listener, UvTcp tcp, Var value) {
  FailureState *state = value.pointer();
  state.listener = listener;
  state.accepted = tcp;
  raise %(malformed (library "test") (reason "TCP accept failed"));
}

static void _empty_connect(UvTcp tcp, Var value) {
  (void) tcp;
  (void) value;
}

static void tcp_accept_error_closes_listener_and_accepted_connection(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  FailureState state = { 0 };
  Var value = Var.new(<p48>, &state);
  state.listener = loop.tcp().bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .listen(2, value, _failing_accept);
  state.client = loop.tcp().connect(
    state.listener.local_address(), value, _empty_connect
  );
  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library *) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"TCP accept failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_TRUE(uv_is_closing((uv_handle_t *) state.listener.native()));
  EXPECT_TRUE(uv_is_closing((uv_handle_t *) state.accepted.native()));
  state.client.close();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
}

static void tcp_rejects_stream_operations_before_connection(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvTcp tcp = loop.tcp();
  int caught = 0;
  try tcp.write(%"x");
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"write");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try tcp.shutdown_write();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"shutdown");
  }
  EXPECT_TRUE(caught);
  EXPECT_NULL(tcp.close());
  EXPECT_NULL(tcp.close());
}

void tcp_suite(void) {
  $test.run(tcp_exchanges_copied_binary_data_with_several_clients);
  $test.run(tcp_reads_stop_and_restart_and_eof_is_null);
  $test.run(tcp_accepted_connection_outlives_its_listener);
  $test.run(tcp_large_writes_own_their_copy_and_report_backpressure);
  $test.run(tcp_refused_connection_reports_error_and_finishes_request);
  $test.run(tcp_read_error_returns_from_run_and_the_loop_resumes);
  $test.run(tcp_accept_error_closes_listener_and_accepted_connection);
  $test.run(tcp_rejects_stream_operations_before_connection);
}

int main(void) {
  TestHarness_begin();
  $test.suite(tcp_suite);
  return TestHarness_finish();
}
