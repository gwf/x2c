/*  test-pipe.x -- named-pipe clients, listeners, names, and cleanup */

import "libuv" with UvLoop, UvPipe, UvTimer;

#include "test-support.x"
#include <errno.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>

$(import "../../../unittest/test-macros.xmacro")

static String _pipe_path(String label) {
  int pid = (int) getpid();
  long nonce = (long) (uv_hrtime() & LONG_MAX);
  return %"/tmp/x2c-libuv-$label-$pid-$nonce.sock";
}

static void _pipe_timeout(UvTimer timer, Var value) {
  (void) timer;
  (void) value;
  raise %(timeout (library "libuv") (operation "pipe test"));
}

typedef struct PipeExchange {
  UvLoop loop;
  UvPipe listener;
  UvPipe client;
  UvPipe server;
  UvTimer guard;
  String path;
  String listener_name;
  String client_name;
  String client_peer;
  String server_name;
  String server_peer;
  Bytes received;
  Bytes retained;
  uv_thread_t driver;
  size_t final_queue;
  int connect_thread;
  int listen_thread;
  int read_thread;
  int client_eof;
  int server_eof;
} PipeExchange;

static int _same_pipe_thread(PipeExchange *state) {
  uv_thread_t current = uv_thread_self();
  return uv_thread_equal(&state.driver, &current);
}

static void _exchange_server_read(UvPipe pipe, Bytes chunk, Var value) {
  PipeExchange *state = value.pointer();
  state.read_thread &= _same_pipe_thread(state);
  if (chunk) {
    pipe.write_bytes(chunk);
    return;
  }
  state.server_eof++;
  pipe.shutdown_write();
}

static void _exchange_client_read(UvPipe pipe, Bytes chunk, Var value) {
  PipeExchange *state = value.pointer();
  state.read_thread &= _same_pipe_thread(state);
  if (chunk) {
    if (!state.retained) state.retained = chunk;
    state.received = state.received.append(chunk, chunk.len());
    return;
  }
  state.client_eof++;
  state.final_queue = pipe.write_queue_size();
  pipe.close();
  state.server.close();
  state.listener.close();
  state.guard.stop();
}

static void _exchange_connected(UvPipe pipe, Var value) {
  PipeExchange *state = value.pointer();
  state.connect_thread &= _same_pipe_thread(state);
  state.client_name = pipe.local_name();
  state.client_peer = pipe.peer_name();
  unsigned char payload[] = { 'p', 'i', 'p', 'e', 0, 'x', '2', 'c' };
  Bytes bytes = Bytes.new(1).append(payload, sizeof(payload));
  pipe.read(value, _exchange_client_read).write_bytes(bytes)
    .shutdown_write().shutdown_write();
  memset(bytes, '!', bytes.len());
  bytes.free();
}

static void _exchange_accepted(UvPipe listener, UvPipe pipe, Var value) {
  PipeExchange *state = value.pointer();
  state.listen_thread &= _same_pipe_thread(state);
  state.server = pipe;
  state.server_name = pipe.local_name();
  state.server_peer = pipe.peer_name();
  pipe.read(value, _exchange_server_read).stop_read()
    .read(value, _exchange_server_read);
  EXPECT_PTR_EQ(listener.native(), state.listener.native());
}

static void pipe_exchanges_binary_data_and_copies_names(void) {
  String path = _pipe_path(%"exchange");
  unlink(path);
  defer unlink(path);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  PipeExchange state = {
    .loop = loop,
    .path = path,
    .received = Bytes.new(1),
    .driver = uv_thread_self(),
    .connect_thread = 1,
    .listen_thread = 1,
    .read_thread = 1
  };
  defer state.received.free();
  Var value = Var.new(<p48>, &state);
  state.guard = loop.timer(5000, 0, value, _pipe_timeout);
  state.listener = loop.pipe().bind(path);
  state.listener_name = state.listener.local_name();
  state.listener.listen(4, value, _exchange_accepted);
  state.client = loop.pipe().connect(path, value, _exchange_connected);

  EXPECT_PTR_EQ(state.listener.loop(), loop);
  EXPECT_NOT_NULL(state.listener.native());
  EXPECT_STR_EQ(state.listener_name, path);
  EXPECT_INT_EQ(access(path, F_OK), 0);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);

  unsigned char expected[] = { 'p', 'i', 'p', 'e', 0, 'x', '2', 'c' };
  EXPECT_STR_EQ(state.client_peer, path);
  EXPECT_STR_EQ(state.server_name, path);
  EXPECT_INT_EQ(state.client_name.len(), 0);
  EXPECT_INT_EQ(state.server_peer.len(), 0);
  EXPECT_INT_EQ(state.received.len(), sizeof(expected));
  EXPECT_TRUE(!memcmp(state.received, expected, sizeof(expected)));
  EXPECT_NOT_NULL(state.retained);
  EXPECT_TRUE(state.retained.len() <= sizeof(expected));
  EXPECT_TRUE(!memcmp(state.retained, expected, state.retained.len()));
  EXPECT_INT_EQ(state.client_eof, 1);
  EXPECT_INT_EQ(state.server_eof, 1);
  EXPECT_INT_EQ(state.final_queue, 0);
  EXPECT_TRUE(state.connect_thread);
  EXPECT_TRUE(state.listen_thread);
  EXPECT_TRUE(state.read_thread);
  EXPECT_INT_EQ(access(path, F_OK), -1);
}

typedef struct OwnedPipe {
  UvPipe listener;
  UvPipe client;
  UvPipe server;
  UvTimer guard;
  Bytes received;
  int eof;
} OwnedPipe;

static void _owned_pipe_read(UvPipe pipe, Bytes chunk, Var value) {
  OwnedPipe *state = value.pointer();
  if (chunk) {
    state.received = state.received.append(chunk, chunk.len());
    return;
  }
  state.eof = 1;
  pipe.close();
  state.client.close();
  state.guard.stop();
}

static void _owned_pipe_connected(UvPipe pipe, Var value) {
  (void) value;
  pipe.write(%"owned").shutdown_write();
}

static void _owned_pipe_accepted(UvPipe listener, UvPipe pipe, Var value) {
  OwnedPipe *state = value.pointer();
  state.server = pipe;
  EXPECT_NULL(listener.close());
  EXPECT_NULL(listener.close());
  pipe.read(value, _owned_pipe_read);
}

static void pipe_accepted_connection_outlives_listener_and_removes_path(void) {
  String path = _pipe_path(%"owned");
  unlink(path);
  defer unlink(path);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  OwnedPipe state = {
    .received = Bytes.new(1)
  };
  defer state.received.free();
  Var value = Var.new(<p48>, &state);
  state.guard = loop.timer(5000, 0, value, _pipe_timeout);
  state.listener = loop.pipe().bind(path)
    .listen(2, value, _owned_pipe_accepted);
  state.client = loop.pipe().connect(path, value, _owned_pipe_connected);
  loop.run(UV_RUN_DEFAULT);

  EXPECT_NOT_NULL(state.server);
  EXPECT_INT_EQ(access(path, F_OK), -1);
  EXPECT_INT_EQ(errno, ENOENT);
  EXPECT_INT_EQ(state.eof, 1);
  EXPECT_INT_EQ(state.received.len(), 5);
  EXPECT_TRUE(!memcmp(state.received, "owned", 5));
}

static void _unexpected_pipe_connect(UvPipe pipe, Var value) {
  (void) pipe;
  int *calls = value.pointer();
  (*calls)++;
}

static void pipe_missing_path_reports_error_and_finishes_request(void) {
  String path = _pipe_path(%"missing");
  unlink(path);
  UvLoop loop = UvLoop.new();
  int calls = 0;
  UvPipe pipe = loop.pipe().connect(
    path, Var.new(<p48>, &calls), _unexpected_pipe_connect
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
  catch %(io-fail (library *) (operation ?operation) (status ?status)
          (name ?name) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"pipe_connect");
    EXPECT_INT_EQ(status.integer(), UV_ENOENT);
    EXPECT_STR_EQ(name.string(), %"ENOENT");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(calls, 0);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_NULL(pipe.close());
  EXPECT_NULL(pipe.close());
  EXPECT_NULL(loop.free());
}

static void pipe_failed_bind_does_not_remove_another_listeners_path(void) {
  String path = _pipe_path(%"occupied");
  unlink(path);
  defer unlink(path);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvPipe first = loop.pipe().bind(path);
  UvPipe second = loop.pipe();

  int caught = 0;
  try second.bind(path);
  catch %(io-fail (library *) (operation ?operation) (status *)
          (name ?name) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"pipe_bind");
    EXPECT_STR_EQ(name.string(), %"EADDRINUSE");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(access(path, F_OK), 0);
  second.close();
  EXPECT_INT_EQ(access(path, F_OK), 0);
  first.close();
  EXPECT_INT_EQ(access(path, F_OK), -1);
}

typedef struct PipeFailure {
  UvPipe listener;
  UvPipe client;
  UvPipe accepted;
  String path;
} PipeFailure;

static void _failing_pipe_read(UvPipe pipe, Bytes chunk, Var value) {
  (void) pipe;
  (void) chunk;
  (void) value;
  raise %(malformed (library "test") (reason "pipe read failed"));
}

static void _failure_pipe_connected(UvPipe pipe, Var value) {
  (void) value;
  pipe.write(%"fail").shutdown_write();
}

static void _failure_pipe_accepted(UvPipe listener, UvPipe pipe, Var value) {
  PipeFailure *state = value.pointer();
  state.accepted = pipe;
  pipe.read(value, _failing_pipe_read);
  (void) listener;
}

static void pipe_read_error_returns_from_run_and_the_loop_resumes(void) {
  String path = _pipe_path(%"read-fail");
  unlink(path);
  defer unlink(path);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  PipeFailure state = { .path = path };
  Var value = Var.new(<p48>, &state);
  state.listener = loop.pipe().bind(path)
    .listen(2, value, _failure_pipe_accepted);
  state.client = loop.pipe().connect(path, value, _failure_pipe_connected);

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library ?library) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"test");
    EXPECT_STR_EQ(reason.string(), %"pipe read failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_TRUE(uv_is_closing((uv_handle_t *) state.accepted.native()));
  state.client.close();
  state.listener.close();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(access(path, F_OK), -1);
}

static void _failing_pipe_accept(UvPipe listener, UvPipe pipe, Var value) {
  PipeFailure *state = value.pointer();
  state.listener = listener;
  state.accepted = pipe;
  raise %(malformed (library "test") (reason "pipe accept failed"));
}

static void _empty_pipe_connect(UvPipe pipe, Var value) {
  (void) pipe;
  (void) value;
}

static void pipe_accept_error_closes_listener_and_accepted_connection(void) {
  String path = _pipe_path(%"accept-fail");
  unlink(path);
  defer unlink(path);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  PipeFailure state = { .path = path };
  Var value = Var.new(<p48>, &state);
  state.listener = loop.pipe().bind(path)
    .listen(2, value, _failing_pipe_accept);
  state.client = loop.pipe().connect(path, value, _empty_pipe_connect);

  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library *) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(reason.string(), %"pipe accept failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_TRUE(uv_is_closing((uv_handle_t *) state.listener.native()));
  EXPECT_TRUE(uv_is_closing((uv_handle_t *) state.accepted.native()));
  state.client.close();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(access(path, F_OK), -1);
}

static void _ignore_pipe_read(UvPipe pipe, Bytes chunk, Var value) {
  (void) pipe;
  (void) chunk;
  (void) value;
}

static void pipe_rejects_invalid_names_and_operations_before_connection(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  UvPipe pipe = loop.pipe();
  int caught = 0;
  try pipe.bind(NULL);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"pipe_bind");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try pipe.write(%"x");
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"write");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try pipe.read(void, _ignore_pipe_read);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"read_start");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try pipe.shutdown_write();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"shutdown");
  }
  EXPECT_TRUE(caught);
  EXPECT_NULL(pipe.close());
  EXPECT_NULL(pipe.close());
}

void pipe_suite(void) {
  $test.run(pipe_exchanges_binary_data_and_copies_names);
  $test.run(pipe_accepted_connection_outlives_listener_and_removes_path);
  $test.run(pipe_missing_path_reports_error_and_finishes_request);
  $test.run(pipe_failed_bind_does_not_remove_another_listeners_path);
  $test.run(pipe_read_error_returns_from_run_and_the_loop_resumes);
  $test.run(pipe_accept_error_closes_listener_and_accepted_connection);
  $test.run(pipe_rejects_invalid_names_and_operations_before_connection);
}

int main(void) {
  TestHarness_begin();
  $test.suite(pipe_suite);
  return TestHarness_finish();
}
