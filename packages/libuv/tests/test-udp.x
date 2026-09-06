/*  test-udp.x -- UDP datagrams, truncation, and request lifetimes */

import "libuv" with UvAddress, UvLoop, UvTimer, UvUdp;

#include "test-support.x"
#include <stdlib.h>
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static void _udp_timeout(UvTimer timer, Var value) {
  (void) timer;
  (void) value;
  raise %(timeout (library "libuv") (operation "UDP test"));
}

typedef struct UdpExchange {
  UvUdp receiver;
  UvUdp unconnected;
  UvUdp connected;
  UvTimer guard;
  Bytes packets[3];
  UvAddress sources[3];
  unsigned flags[3];
  int seen[3];
  int count;
  uv_thread_t driver;
  int callback_thread;
} UdpExchange;

static void _udp_exchange_receive(
  UvUdp udp, Bytes packet, UvAddress source, unsigned flags, Var value) {
  UdpExchange *state = value.pointer();
  uv_thread_t current = uv_thread_self();
  state.callback_thread &= uv_thread_equal(&state.driver, &current);
  int index = (flags & UV_UDP_PARTIAL) ? 2 : packet.len() ? 0 : 1;
  if (state.seen[index]) {
    raise %(malformed (library "test")
            (reason "duplicate UDP datagram"));
  }
  state.seen[index] = 1;
  state.packets[index] = packet;
  state.sources[index] = source;
  state.flags[index] = flags;
  state.count++;
  if (state.count == 3) {
    udp.stop();
    state.guard.stop();
  }
}

static void udp_sends_connected_unconnected_binary_and_empty_datagrams(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UdpExchange state = {
    .driver = uv_thread_self(),
    .callback_thread = 1
  };
  Var value = Var.new(<p48>, &state);
  state.guard = loop.timer(5000, 0, value, _udp_timeout);
  state.receiver = loop.udp()
    .bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .max_receive(8).receive(value, _udp_exchange_receive);
  UvAddress destination = state.receiver.local_address();
  UvAddress copied_target = UvAddress.ip4(
    destination.host(), destination.port()
  );
  state.unconnected = loop.udp().bind(
    UvAddress.ip4(%"127.0.0.1", 0), 0
  );
  state.connected = loop.udp().bind(
    UvAddress.ip4(%"127.0.0.1", 0), 0
  ).connect(destination);
  UvAddress unconnected = state.unconnected.local_address();
  UvAddress connected = state.connected.local_address();
  UvAddress peer = state.connected.peer_address();

  unsigned char binary_data[] = { 'u', 'd', 'p', 0, 'x', '2', 'c' };
  Bytes binary = Bytes.new(1).append(binary_data, sizeof(binary_data));
  Bytes empty = Bytes.new(1);
  Bytes diagnostic = Bytes.new(1).append(
    "0123456789abcdef", 16
  );
  state.unconnected.send_bytes(copied_target, binary);
  ((struct sockaddr_in *) copied_target.native())->sin_port = htons(9);
  state.connected.send_bytes(NULL, empty)
    .send_bytes(NULL, diagnostic);

  EXPECT_PTR_EQ(state.receiver.loop(), loop);
  EXPECT_NOT_NULL(state.receiver.native());
  EXPECT_INT_EQ(state.unconnected.send_queue_count(), 1);
  EXPECT_INT_EQ(
    state.unconnected.send_queue_size(), sizeof(binary_data)
  );
  EXPECT_INT_EQ(state.connected.send_queue_count(), 2);
  EXPECT_INT_EQ(state.connected.send_queue_size(), 16);
  EXPECT_STR_EQ(peer.host(), destination.host());
  EXPECT_INT_EQ(peer.port(), destination.port());
  memset(binary, '!', binary.len());
  memset(diagnostic, '!', diagnostic.len());
  binary.free();
  empty.free();
  diagnostic.free();

  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.count, 3);
  EXPECT_TRUE(state.callback_thread);
  EXPECT_INT_EQ(state.unconnected.send_queue_count(), 0);
  EXPECT_INT_EQ(state.unconnected.send_queue_size(), 0);
  EXPECT_INT_EQ(state.connected.send_queue_count(), 0);
  EXPECT_INT_EQ(state.connected.send_queue_size(), 0);
  EXPECT_INT_EQ(state.packets[0].len(), sizeof(binary_data));
  EXPECT_TRUE(!memcmp(
    state.packets[0], binary_data, sizeof(binary_data)
  ));
  EXPECT_NOT_NULL((void *) state.packets[1]);
  EXPECT_INT_EQ(state.packets[1].len(), 0);
  EXPECT_INT_EQ(state.packets[2].len(), 8);
  EXPECT_TRUE(!memcmp(state.packets[2], "01234567", 8));
  EXPECT_INT_EQ(state.flags[0], 0);
  EXPECT_INT_EQ(state.flags[1], 0);
  EXPECT_TRUE(state.flags[2] & UV_UDP_PARTIAL);
  EXPECT_STR_EQ(state.sources[0].host(), %"127.0.0.1");
  EXPECT_INT_EQ(state.sources[0].port(), unconnected.port());
  EXPECT_INT_EQ(state.sources[1].port(), connected.port());
  EXPECT_INT_EQ(state.sources[2].port(), connected.port());
  EXPECT_INT_EQ(state.sources[0].family(), AF_INET);
  EXPECT_INT_EQ(state.sources[0].socket_type(), SOCK_DGRAM);
  EXPECT_INT_EQ(state.sources[0].protocol(), IPPROTO_UDP);
  state.receiver.close();
  state.unconnected.close();
  state.connected.close();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
}

typedef struct UdpRestart {
  UvLoop loop;
  UvUdp receiver;
  UvUdp sender;
  UvTimer restart;
  UvTimer guard;
  Bytes first;
  Bytes second;
  unsigned first_flags;
  unsigned second_flags;
  int calls;
} UdpRestart;

static void _udp_restart_receive(
  UvUdp udp, Bytes packet, UvAddress source, unsigned flags, Var value);

static void _udp_restart_timer(UvTimer timer, Var value) {
  UdpRestart *state = value.pointer();
  timer.stop();
  state.receiver.max_receive(64).receive(value, _udp_restart_receive);
}

static void _udp_restart_receive(
  UvUdp udp, Bytes packet, UvAddress source, unsigned flags, Var value) {
  UdpRestart *state = value.pointer();
  state.calls++;
  if (state.calls == 1) {
    state.first = packet;
    state.first_flags = flags;
    udp.stop().stop();
    state.sender.send(udp.local_address(), %"B");
    state.restart = state.loop.timer(10, 0, value, _udp_restart_timer);
    return;
  }
  state.second = packet;
  state.second_flags = flags;
  udp.stop();
  state.guard.stop();
  (void) source;
}

static void udp_receive_limit_truncates_and_stop_restarts(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UdpRestart state = { .loop = loop };
  Var value = Var.new(<p48>, &state);
  state.guard = loop.timer(5000, 0, value, _udp_timeout);
  state.receiver = loop.udp()
    .bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .max_receive(4).receive(value, _udp_restart_receive);
  state.sender = loop.udp();
  Bytes first = Bytes.new(1).append("abcdefgh", 8);
  state.sender.send_bytes(state.receiver.local_address(), first);
  first.free();
  loop.run(UV_RUN_DEFAULT);

  EXPECT_INT_EQ(state.calls, 2);
  EXPECT_INT_EQ(state.first.len(), 4);
  EXPECT_TRUE(!memcmp(state.first, "abcd", 4));
  EXPECT_TRUE(state.first_flags & UV_UDP_PARTIAL);
  EXPECT_INT_EQ(state.second.len(), 1);
  EXPECT_INT_EQ(((unsigned char *) state.second)[0], 'B');
  EXPECT_INT_EQ(state.second_flags, 0);
  state.receiver.close();
  state.sender.close();
  loop.run(UV_RUN_DEFAULT);
}

typedef struct UdpLarge {
  UvUdp receiver;
  UvUdp sender;
  UvTimer guard;
  Bytes packet;
  unsigned flags;
} UdpLarge;

static void _udp_large_receive(
  UvUdp udp, Bytes packet, UvAddress source, unsigned flags, Var value) {
  UdpLarge *state = value.pointer();
  state.packet = packet;
  state.flags = flags;
  udp.stop();
  state.guard.stop();
  (void) source;
}

static void udp_default_receive_limit_accepts_a_large_datagram(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UdpLarge state = { 0 };
  Var value = Var.new(<p48>, &state);
  state.guard = loop.timer(5000, 0, value, _udp_timeout);
  state.receiver = loop.udp()
    .bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .receive(value, _udp_large_receive);
  uv_buf_t allocated = { 0 };
  state.receiver.native()->alloc_cb(
    (uv_handle_t *) state.receiver.native(), 1, &allocated
  );
  EXPECT_INT_EQ(allocated.len, 64 * 1024);
  free(allocated.base);
  state.sender = loop.udp();
  unsigned char byte = 0x5a;
  Bytes packet = Bytes.new(1).append_fill(&byte, 8192);
  state.sender.send_bytes(state.receiver.local_address(), packet);
  memset(packet, 0xa5, packet.len());
  packet.free();
  loop.run(UV_RUN_DEFAULT);

  EXPECT_INT_EQ(state.packet.len(), 8192);
  EXPECT_INT_EQ(state.flags, 0);
  EXPECT_INT_EQ(((unsigned char *) state.packet)[0], 0x5a);
  EXPECT_INT_EQ(((unsigned char *) state.packet)[8191], 0x5a);
  state.receiver.close();
  state.sender.close();
  loop.run(UV_RUN_DEFAULT);
}

static void _udp_fail_receive(
  UvUdp udp, Bytes packet, UvAddress source, unsigned flags, Var value) {
  (void) udp;
  (void) packet;
  (void) source;
  (void) flags;
  (void) value;
  raise %(malformed (library "test") (reason "UDP receive failed"));
}

static void _udp_resume_timer(UvTimer timer, Var value) {
  int *calls = value.pointer();
  (*calls)++;
  timer.stop();
}

static void udp_callback_error_returns_from_run_and_the_loop_resumes(void) {
  UvLoop loop = UvLoop.new();
  UvUdp receiver = loop.udp()
    .bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .receive(void, _udp_fail_receive);
  UvUdp sender = loop.udp();
  Bytes packet = Bytes.new(1).append("fail", 4);
  sender.send_bytes(receiver.local_address(), packet);
  packet.free();

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library ?library) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"test");
    EXPECT_STR_EQ(reason.string(), %"UDP receive failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_TRUE(uv_is_closing((uv_handle_t *) receiver.native()));
  sender.close();
  loop.run(UV_RUN_DEFAULT);

  int resumed = 0;
  loop.timer(0, 0, Var.new(<p48>, &resumed), _udp_resume_timer);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(resumed, 1);
  EXPECT_NULL(loop.free());
}

static void udp_pending_send_prevents_loop_destruction_and_close_drains(void) {
  UvLoop loop = UvLoop.new();
  UvUdp receiver = loop.udp().bind(
    UvAddress.ip4(%"127.0.0.1", 0), 0
  );
  UvUdp sender = loop.udp();
  Bytes packet = Bytes.new(1).append("pending", 7);
  sender.send_bytes(receiver.local_address(), packet);
  packet.free();
  EXPECT_INT_EQ(sender.send_queue_count(), 1);

  int caught = 0;
  try loop.free();
  catch %(bad-state (library *) (operation ?operation)
          (reason *) (pending ?pending) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"loop_free");
    EXPECT_TRUE(pending.integer() > 0);
  }
  EXPECT_TRUE(caught);
  EXPECT_NULL(sender.close());
  EXPECT_NULL(sender.close());
  EXPECT_NULL(receiver.close());
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_NULL(loop.free());
}

static void _udp_count_receive(
  UvUdp udp, Bytes packet, UvAddress source, unsigned flags, Var value) {
  int *calls = value.pointer();
  (*calls)++;
  (void) udp;
  (void) packet;
  (void) source;
  (void) flags;
}

static void udp_rejects_invalid_state_and_ignores_native_no_event(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvUdp udp = loop.udp();
  int caught = 0;
  try udp.max_receive(0);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"udp_max_receive");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  Bytes byte = Bytes.new(1).append("x", 1);
  try udp.send_bytes(NULL, byte);
  catch %(io-fail (library *) (operation ?operation) (status *)
          (name ?name) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"udp_send");
    EXPECT_STR_EQ(name.string(), %"EDESTADDRREQ");
  }
  EXPECT_TRUE(caught);

  int calls = 0;
  udp.receive(Var.new(<p48>, &calls), _udp_count_receive);
  caught = 0;
  try udp.receive(Var.new(<p48>, &calls), _udp_count_receive);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"udp_receive");
  }
  EXPECT_TRUE(caught);
  uv_buf_t buffer = uv_buf_init(malloc(1), 1);
  udp.native()->recv_cb(udp.native(), 0, &buffer, NULL, 0);
  EXPECT_INT_EQ(calls, 0);
  EXPECT_PTR_EQ(udp.stop(), udp);
  EXPECT_PTR_EQ(udp.stop(), udp);

  UvUdp receiver = loop.udp().bind(
    UvAddress.ip4(%"127.0.0.1", 0), 0
  );
  udp.connect(receiver.local_address());
  caught = 0;
  try udp.send_bytes(receiver.local_address(), byte);
  catch %(io-fail (library *) (operation ?operation) (status *)
          (name ?name) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"udp_send");
    EXPECT_STR_EQ(name.string(), %"EISCONN");
  }
  EXPECT_TRUE(caught);
  caught = 0;
  try udp.connect(receiver.local_address());
  catch %(io-fail (library *) (operation ?operation) (status *)
          (name ?name) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"udp_connect");
    EXPECT_STR_EQ(name.string(), %"EISCONN");
  }
  EXPECT_TRUE(caught);
  byte.free();
  udp.close();
  caught = 0;
  try udp.send_queue_count();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"udp_send_queue_count");
  }
  EXPECT_TRUE(caught);
  receiver.close();
  loop.run(UV_RUN_DEFAULT);
}

void udp_suite(void) {
  $test.run(udp_sends_connected_unconnected_binary_and_empty_datagrams);
  $test.run(udp_receive_limit_truncates_and_stop_restarts);
  $test.run(udp_default_receive_limit_accepts_a_large_datagram);
  $test.run(udp_callback_error_returns_from_run_and_the_loop_resumes);
  $test.run(udp_pending_send_prevents_loop_destruction_and_close_drains);
  $test.run(udp_rejects_invalid_state_and_ignores_native_no_event);
}

int main(void) {
  TestHarness_begin();
  $test.suite(udp_suite);
  return TestHarness_finish();
}
