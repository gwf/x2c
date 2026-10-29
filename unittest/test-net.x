/*  test-net.x -- blocking TCP ownership, I/O, and cooperative stopping */

#include "net.x"
#include "test-support.x"
#include "test-macros.x"
#include <errno.h>
#include <time.h>
#include <unistd.h>

static void net_exchange_and_half_close(void) {
  $test.scoped();
  Listener listener = auto Listener.bind("127.0.0.1", 0);
  EXPECT_TRUE(listener.port() > 0);
  Socket client = auto Socket.connect("127.0.0.1", listener.port(), 1000);
  Socket peer = auto listener.accept();
  EXPECT_TRUE(client.peer().startswith("127.0.0.1:"));
  EXPECT_TRUE(peer.peer().startswith("127.0.0.1:"));
  EXPECT_TRUE(client.input.fileno() != client.output.fileno());
  int enabled = 0;
  socklen_t size = sizeof(enabled);
  EXPECT_INT_EQ(getsockopt(peer.fd, IPPROTO_TCP, TCP_NODELAY,
                          &enabled, &size), 0);
  EXPECT_TRUE(enabled != 0);
  client.output.puts("hello\n");
  EXPECT_INT_EQ(client.output.flush(), 0);
  EXPECT_STR_EQ(peer.input.readline(), "hello\n");
  peer.output.puts("world\n");
  EXPECT_INT_EQ(peer.output.flush(), 0);
  EXPECT_STR_EQ(client.input.readline(), "world\n");
  client.shutdown_write();
  EXPECT_NULL(peer.input.readline());
  EXPECT_TRUE(peer.input.eof());
  peer.output.puts("after eof\n");
  EXPECT_INT_EQ(peer.output.flush(), 0);
  EXPECT_STR_EQ(client.input.readline(), "after eof\n");
  peer.close();
  peer.close();
  EXPECT_INT_EQ(peer.fd, -1);
  EXPECT_NULL(peer.input);
  EXPECT_NULL(peer.output);
}

static void net_timeout_reports_errno(void) {
  $test.scoped();
  Listener listener = auto Listener.bind("127.0.0.1", 0);
  Socket client = auto Socket.connect("127.0.0.1", listener.port(), 1000);
  Socket peer = auto listener.accept();
  peer.set_timeout(100);
  int caught = 0;
  try peer.input.readline();
  catch %(io-fail *detail): {
    caught++;
    int error = detail.assoc(<errno>);
    EXPECT_TRUE(error == EAGAIN || error == EWOULDBLOCK);
  }
  EXPECT_INT_EQ(caught, 1);
  peer.set_timeout(0);
  peer.input.clearerr();
  client.output.puts("again\n");
  client.output.flush();
  EXPECT_STR_EQ(peer.input.readline(), "again\n");
}

static void net_listener_repr_preserves_fields_and_stop(void) {
  $test.scoped();
  Listener listener = auto Listener.bind("127.0.0.1", 0);
  Buffer expected = auto Buffer.new(0);
  expected.printf("Listener { fd: %d, host: \"127.0.0.1\", port: %d, stopped: 0 }",
                  listener.fd, listener.port());
  EXPECT_STR_EQ(listener.repr(), expected.str());
  listener.stop();
  expected.clear();
  expected.printf("Listener { fd: %d, host: \"127.0.0.1\", port: %d, stopped: 1 }",
                  listener.fd, listener.port());
  EXPECT_STR_EQ(listener.repr(), expected.str());
  EXPECT_STR_EQ(Listener.repr(NULL), Listener.str(NULL));
}

typedef struct NetAccept { Listener listener; } NetAccept;

static Var _accept_worker(const void *input, size_t size) {
  (void) size;
  const NetAccept *request = input;
  Socket peer = auto request->listener.accept();
  return peer == NULL;
}

static Var _stop_worker(const void *input, size_t size) {
  (void) size;
  const NetAccept *request = input;
  request->listener.stop();
  return 1;
}

static void net_listener_stop_unblocks_accept(void) {
  $test.scoped();
  Listener listener = auto Listener.bind("127.0.0.1", 0);
  NetAccept request = {listener};
  Thread acceptor = Thread.start_raw(
    _accept_worker, &request, sizeof(request));
  Thread stopper = Thread.start_raw(_stop_worker, &request, sizeof(request));
  EXPECT_INT_EQ(stopper.join().integer(), 1);
  EXPECT_INT_EQ(acceptor.join().integer(), 1);
  stopper.free();
  acceptor.free();
  EXPECT_NULL(listener.accept());
}

static void net_thread_stop_cancels_accept(void) {
  $test.scoped();
  Listener listener = auto Listener.bind("127.0.0.1", 0);
  NetAccept request = {listener};
  Thread acceptor = Thread.start_raw(
    _accept_worker, &request, sizeof(request));
  acceptor.stop();
  int caught = 0;
  try acceptor.join();
  catch %(join-fail *): caught++;
  acceptor.free();
  EXPECT_INT_EQ(caught, 1);
}

static void net_invalid_arguments_and_names(void) {
  $test.scoped();
  int caught = 0;
  try Listener.bind("127.0.0.1", -1);
  catch %(bad-arg *): caught++;
  try Listener.bind("127.0.0.1", 65536);
  catch %(bad-arg *): caught++;
  try Socket.connect(NULL, 80, 100);
  catch %(bad-arg *): caught++;
  try Socket.connect("127.0.0.1", 80, -1);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 4);
  int missing = 0;
  try Socket.connect("x2c-networking-test.invalid", 80, 100);
  catch %(not-found *): missing++;
  EXPECT_INT_EQ(missing, 1);
}

static void net_refused_connection_reports_errno(void) {
  $test.scoped();
  Listener listener = auto Listener.bind("127.0.0.1", 0);
  int port = listener.port();
  listener.close();
  int caught = 0;
  try Socket.connect("127.0.0.1", port, 100);
  catch %(io-fail *detail): {
    caught++;
    EXPECT_INT_EQ(detail.assoc(<errno>).integer(), ECONNREFUSED);
  }
  EXPECT_INT_EQ(caught, 1);
}

static void net_adopt_failure_releases_descriptor(void) {
  $test.scoped();
  int fd = open("/dev/null", O_RDONLY);
  EXPECT_TRUE(fd >= 0);
  int caught = 0;
  try Socket.adopt(fd);
  catch %(io-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(fcntl(fd, F_GETFD), -1);
  EXPECT_INT_EQ(errno, EBADF);
}

static void net_ipv6_loopback(void) {
  $test.scoped();
  Listener listener = NULL;
  try listener = Listener.bind("::1", 0);
  catch %(io-fail *): {
    TestHarness_skip("net_ipv6_loopback", "IPv6 loopback unavailable");
    return;
  }
  catch %(not-found *): {
    TestHarness_skip("net_ipv6_loopback", "IPv6 resolution unavailable");
    return;
  }
  defer listener.close();
  Socket client = auto Socket.connect("::1", listener.port(), 1000);
  Socket peer = auto listener.accept();
  EXPECT_TRUE(client.peer().startswith("[::1]:"));
  client.output.puts("ipv6\n");
  EXPECT_INT_EQ(client.output.flush(), 0);
  EXPECT_STR_EQ(peer.input.readline(), "ipv6\n");
}

static void net_descriptor_handoff(void) {
  $test.scoped();
  Listener listener = auto Listener.bind(NULL, 0);
  Socket client = auto Socket.connect("127.0.0.1", listener.port(), 1000);
  int fd = x2c_net_accept_fd(listener);
  EXPECT_TRUE(fd >= 0);
  Socket peer = auto Socket.adopt(fd);
  client.output.puts("handoff\n");
  EXPECT_INT_EQ(client.output.flush(), 0);
  EXPECT_STR_EQ(peer.input.readline(), "handoff\n");
  listener.stop();
  EXPECT_INT_EQ(x2c_net_accept_fd(listener), -1);
}

void net_suite(void) {
  $test.run(net_listener_repr_preserves_fields_and_stop);
  $test.run(net_exchange_and_half_close);
  $test.run(net_timeout_reports_errno);
  $test.run(net_listener_stop_unblocks_accept);
  $test.run(net_thread_stop_cancels_accept);
  $test.run(net_invalid_arguments_and_names);
  $test.run(net_refused_connection_reports_errno);
  $test.run(net_adopt_failure_releases_descriptor);
  $test.run(net_ipv6_loopback);
  $test.run(net_descriptor_handoff);
}
