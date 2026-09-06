/*  test-raw-api.x -- pinned libuv header is directly usable from x2c */

#include "uv-152.h"
#include "test-support.x"
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

$(import "../../../unittest/test-macros.xmacro")

static void raw_loop_and_version_surface(void) {
  EXPECT_STR_EQ(String.new(uv_version_string()), %"1.52.1");
  EXPECT_INT_EQ(uv_version(), UV_VERSION_HEX);

  uv_loop_t loop;
  EXPECT_INT_EQ(uv_loop_init(&loop), 0);
  EXPECT_FALSE(uv_loop_alive(&loop));
  EXPECT_INT_EQ(uv_loop_close(&loop), 0);
}

static void raw_error_and_buffer_surface(void) {
  EXPECT_STR_EQ(String.new(uv_err_name(UV_ENOENT)), %"ENOENT");
  uv_buf_t buffer = uv_buf_init(NULL, 0);
  EXPECT_NULL(buffer.base);
  EXPECT_INT_EQ(buffer.len, 0);
}

static void _raw_async_close(uv_async_t *async) {
  uv_close((uv_handle_t *) async, NULL);
}

static void raw_async_notification_surface(void) {
  uv_loop_t loop;
  uv_async_t async;
  EXPECT_INT_EQ(uv_loop_init(&loop), 0);
  EXPECT_INT_EQ(uv_async_init(&loop, &async, _raw_async_close), 0);
  EXPECT_INT_EQ(uv_async_send(&async), 0);
  EXPECT_INT_EQ(uv_run(&loop, UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(uv_loop_close(&loop), 0);
}

static void _raw_idle_close(uv_idle_t *idle) {
  int *calls = idle->data;
  (*calls)++;
  uv_idle_stop(idle);
  uv_close((uv_handle_t *) idle, NULL);
}

static void _raw_prepare_close(uv_prepare_t *prepare) {
  int *calls = prepare->data;
  (*calls)++;
  uv_prepare_stop(prepare);
  uv_close((uv_handle_t *) prepare, NULL);
}

static void _raw_check_close(uv_check_t *check) {
  int *calls = check->data;
  (*calls)++;
  uv_check_stop(check);
  uv_close((uv_handle_t *) check, NULL);
}

static void raw_loop_phase_surface(void) {
  uv_loop_t loop;
  uv_idle_t idle;
  uv_prepare_t prepare;
  uv_check_t check;
  int calls = 0;
  EXPECT_INT_EQ(uv_loop_init(&loop), 0);
  EXPECT_INT_EQ(uv_idle_init(&loop, &idle), 0);
  EXPECT_INT_EQ(uv_prepare_init(&loop, &prepare), 0);
  EXPECT_INT_EQ(uv_check_init(&loop, &check), 0);
  idle.data = &calls;
  prepare.data = &calls;
  check.data = &calls;
  EXPECT_INT_EQ(uv_idle_start(&idle, _raw_idle_close), 0);
  EXPECT_INT_EQ(uv_prepare_start(&prepare, _raw_prepare_close), 0);
  EXPECT_INT_EQ(uv_check_start(&check, _raw_check_close), 0);
  EXPECT_INT_EQ(uv_run(&loop, UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(calls, 3);
  EXPECT_INT_EQ(uv_loop_close(&loop), 0);
}

static void raw_numeric_address_surface(void) {
  struct sockaddr_in ip4;
  struct sockaddr_in6 ip6;
  char host[INET6_ADDRSTRLEN];
  EXPECT_INT_EQ(uv_ip4_addr("127.0.0.1", 4321, &ip4), 0);
  EXPECT_INT_EQ(uv_ip4_name(&ip4, host, sizeof(host)), 0);
  EXPECT_STR_EQ(String.new(host), %"127.0.0.1");
  EXPECT_INT_EQ(ntohs(ip4.sin_port), 4321);

  EXPECT_INT_EQ(uv_ip6_addr("::1", 4321, &ip6), 0);
  EXPECT_INT_EQ(uv_ip6_name(&ip6, host, sizeof(host)), 0);
  EXPECT_STR_EQ(String.new(host), %"::1");
  EXPECT_INT_EQ(ntohs(ip6.sin6_port), 4321);
}

typedef struct RawLookupState {
  int calls;
  int status;
  int count;
  int family;
} RawLookupState;

static void _raw_lookup_complete(
  uv_getaddrinfo_t *request, int status, struct addrinfo *result) {
  RawLookupState *state = request->data;
  state->calls++;
  state->status = status;
  for (struct addrinfo *info = result; info; info = info->ai_next) {
    state->count++;
    state->family = info->ai_family;
  }
  if (result) uv_freeaddrinfo(result);
  request->addrinfo = NULL;
}

static void raw_dns_and_request_cancellation_surface(void) {
  uv_loop_t loop;
  uv_getaddrinfo_t request = { 0 };
  struct addrinfo hints = { 0 };
  RawLookupState state = { 0 };
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;
  request.data = &state;

  EXPECT_INT_EQ(uv_loop_init(&loop), 0);
  EXPECT_INT_EQ(uv_getaddrinfo(
    &loop, &request, _raw_lookup_complete,
    "127.0.0.1", "80", &hints
  ), 0);
  EXPECT_INT_EQ(uv_run(&loop, UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.calls, 1);
  EXPECT_INT_EQ(state.status, 0);
  EXPECT_TRUE(state.count > 0);
  EXPECT_INT_EQ(state.family, AF_INET);
  EXPECT_NULL(request.addrinfo);
  EXPECT_INT_EQ(uv_cancel((uv_req_t *) &request), UV_EBUSY);
  EXPECT_INT_EQ(uv_loop_close(&loop), 0);
}

typedef struct RawTcpState {
  uv_loop_t loop;
  uv_tcp_t listener;
  uv_tcp_t client;
  uv_tcp_t accepted;
  uv_connect_t connect;
  uv_write_t write;
  uv_shutdown_t shutdown;
  int accept_status;
  int connect_status;
  int write_status;
  int shutdown_status;
  int read_status;
  int connect_calls;
  int write_calls;
  int shutdown_calls;
  int read_calls;
  size_t bytes;
  size_t queued;
  int peer_port;
} RawTcpState;

static void _raw_tcp_alloc(
  uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  (void) handle;
  buffer->base = malloc(suggested ? suggested : 1);
  buffer->len = buffer->base ? (suggested ? suggested : 1) : 0;
}

static void _raw_tcp_read(
  uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
  RawTcpState *state = stream->data;
  if (count > 0) {
    state->read_calls++;
    state->bytes += count;
  }
  if (count < 0) {
    state->read_status = count;
    uv_read_stop(stream);
    uv_close((uv_handle_t *) &state->accepted, NULL);
    uv_close((uv_handle_t *) &state->listener, NULL);
  }
  free(buffer->base);
}

static void _raw_tcp_shutdown(uv_shutdown_t *request, int status) {
  RawTcpState *state = request->data;
  state->shutdown_calls++;
  state->shutdown_status = status;
  uv_close((uv_handle_t *) &state->client, NULL);
}

static void _raw_tcp_write(uv_write_t *request, int status) {
  RawTcpState *state = request->data;
  state->write_calls++;
  state->write_status = status;
}

static void _raw_tcp_connect(uv_connect_t *request, int status) {
  RawTcpState *state = request->data;
  state->connect_calls++;
  state->connect_status = status;
  if (status < 0) return;
  uv_buf_t message = uv_buf_init("raw\0tcp", 7);
  state->write.data = state;
  state->shutdown.data = state;
  state->write_status = uv_write(
    &state->write, (uv_stream_t *) &state->client,
    &message, 1, _raw_tcp_write
  );
  state->queued = uv_stream_get_write_queue_size(
    (uv_stream_t *) &state->client
  );
  state->shutdown_status = uv_shutdown(
    &state->shutdown, (uv_stream_t *) &state->client,
    _raw_tcp_shutdown
  );
}

static void _raw_tcp_accept(uv_stream_t *listener, int status) {
  RawTcpState *state = listener->data;
  state->accept_status = status;
  if (status < 0) return;
  state->accept_status = uv_tcp_init(&state->loop, &state->accepted);
  state->accepted.data = state;
  if (!state->accept_status)
    state->accept_status = uv_accept(
      listener, (uv_stream_t *) &state->accepted
    );
  struct sockaddr_storage peer;
  int length = sizeof(peer);
  if (!state->accept_status)
    state->accept_status = uv_tcp_getpeername(
      &state->accepted, (struct sockaddr *) &peer, &length
    );
  if (!state->accept_status)
    state->peer_port = ntohs(((struct sockaddr_in *) &peer)->sin_port);
  if (!state->accept_status)
    state->accept_status = uv_read_start(
      (uv_stream_t *) &state->accepted, _raw_tcp_alloc, _raw_tcp_read
    );
}

static void raw_tcp_and_stream_surface(void) {
  RawTcpState state = { 0 };
  struct sockaddr_in loopback;
  struct sockaddr_storage local;
  int length = sizeof(local);

  EXPECT_INT_EQ(uv_loop_init(&state.loop), 0);
  EXPECT_INT_EQ(uv_tcp_init(&state.loop, &state.listener), 0);
  EXPECT_INT_EQ(uv_tcp_init(&state.loop, &state.client), 0);
  EXPECT_INT_EQ(uv_ip4_addr("127.0.0.1", 0, &loopback), 0);
  EXPECT_INT_EQ(uv_tcp_bind(
    &state.listener, (struct sockaddr *) &loopback, 0
  ), 0);
  EXPECT_INT_EQ(uv_tcp_getsockname(
    &state.listener, (struct sockaddr *) &local, &length
  ), 0);
  state.listener.data = &state;
  state.client.data = &state;
  state.connect.data = &state;
  EXPECT_INT_EQ(uv_listen(
    (uv_stream_t *) &state.listener, 4, _raw_tcp_accept
  ), 0);
  EXPECT_INT_EQ(uv_tcp_connect(
    &state.connect, &state.client, (struct sockaddr *) &local,
    _raw_tcp_connect
  ), 0);
  EXPECT_INT_EQ(uv_run(&state.loop, UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.accept_status, 0);
  EXPECT_INT_EQ(state.connect_calls, 1);
  EXPECT_INT_EQ(state.connect_status, 0);
  EXPECT_INT_EQ(state.write_calls, 1);
  EXPECT_INT_EQ(state.write_status, 0);
  EXPECT_INT_EQ(state.shutdown_calls, 1);
  EXPECT_INT_EQ(state.shutdown_status, 0);
  EXPECT_INT_EQ(state.read_status, UV_EOF);
  EXPECT_TRUE(state.read_calls > 0);
  EXPECT_INT_EQ(state.bytes, 7);
  EXPECT_TRUE(state.peer_port > 0);
  EXPECT_TRUE(state.queued <= 7);
  EXPECT_INT_EQ(uv_loop_close(&state.loop), 0);
}

typedef struct RawPipeState {
  uv_loop_t loop;
  uv_pipe_t listener;
  uv_pipe_t client;
  uv_pipe_t accepted;
  uv_connect_t connect;
  char path[128];
  char listener_name[128];
  char client_peer[128];
  char accepted_name[128];
  size_t listener_length;
  size_t client_peer_length;
  size_t accepted_length;
  int accept_status;
  int connect_status;
  int accept_calls;
  int connect_calls;
} RawPipeState;

static void _raw_pipe_finish(RawPipeState *state) {
  if (!state->accept_calls || !state->connect_calls) return;
  uv_close((uv_handle_t *) &state->accepted, NULL);
  uv_close((uv_handle_t *) &state->client, NULL);
  uv_close((uv_handle_t *) &state->listener, NULL);
}

static void _raw_pipe_connect(uv_connect_t *request, int status) {
  RawPipeState *state = request->data;
  state->connect_calls++;
  state->connect_status = status;
  state->client_peer_length = sizeof(state->client_peer);
  if (!status)
    state->connect_status = uv_pipe_getpeername(
      &state->client, state->client_peer, &state->client_peer_length
    );
  _raw_pipe_finish(state);
}

static void _raw_pipe_accept(uv_stream_t *listener, int status) {
  RawPipeState *state = listener->data;
  state->accept_calls++;
  state->accept_status = status;
  if (!status)
    state->accept_status = uv_pipe_init(
      &state->loop, &state->accepted, 0
    );
  state->accepted.data = state;
  if (!state->accept_status)
    state->accept_status = uv_accept(
      listener, (uv_stream_t *) &state->accepted
    );
  state->accepted_length = sizeof(state->accepted_name);
  if (!state->accept_status)
    state->accept_status = uv_pipe_getsockname(
      &state->accepted, state->accepted_name, &state->accepted_length
    );
  _raw_pipe_finish(state);
}

static void raw_named_pipe_surface(void) {
  RawPipeState state = { 0 };
  snprintf(
    state.path, sizeof(state.path), "/tmp/x2c-libuv-raw-%d.sock",
    (int) getpid()
  );
  unlink(state.path);
  defer unlink(state.path);

  EXPECT_INT_EQ(uv_loop_init(&state.loop), 0);
  EXPECT_INT_EQ(uv_pipe_init(&state.loop, &state.listener, 0), 0);
  EXPECT_INT_EQ(uv_pipe_init(&state.loop, &state.client, 0), 0);
  state.listener.data = &state;
  state.client.data = &state;
  state.connect.data = &state;
  EXPECT_INT_EQ(uv_pipe_bind(&state.listener, state.path), 0);
  state.listener_length = sizeof(state.listener_name);
  EXPECT_INT_EQ(uv_pipe_getsockname(
    &state.listener, state.listener_name, &state.listener_length
  ), 0);
  EXPECT_INT_EQ(uv_listen(
    (uv_stream_t *) &state.listener, 4, _raw_pipe_accept
  ), 0);
  uv_pipe_connect(
    &state.connect, &state.client, state.path, _raw_pipe_connect
  );
  EXPECT_INT_EQ(uv_run(&state.loop, UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.accept_calls, 1);
  EXPECT_INT_EQ(state.connect_calls, 1);
  EXPECT_INT_EQ(state.accept_status, 0);
  EXPECT_INT_EQ(state.connect_status, 0);
  EXPECT_INT_EQ(state.listener_length, strlen(state.path));
  EXPECT_INT_EQ(state.accepted_length, strlen(state.path));
  EXPECT_INT_EQ(state.client_peer_length, strlen(state.path));
  EXPECT_TRUE(!memcmp(
    state.listener_name, state.path, state.listener_length
  ));
  EXPECT_TRUE(!memcmp(
    state.accepted_name, state.path, state.accepted_length
  ));
  EXPECT_TRUE(!memcmp(
    state.client_peer, state.path, state.client_peer_length
  ));
  EXPECT_INT_EQ(access(state.path, F_OK), -1);
  EXPECT_INT_EQ(uv_loop_close(&state.loop), 0);
}

typedef struct RawUdpState {
  uv_loop_t loop;
  uv_udp_t receiver;
  uv_udp_t unconnected;
  uv_udp_t connected;
  uv_udp_send_t sends[3];
  int send_calls;
  int send_status;
  int receive_calls;
  int empty;
  int partial;
  int closed;
  size_t bytes;
  int source_port;
} RawUdpState;

static void _raw_udp_finish(RawUdpState *state) {
  if (state->closed || state->send_calls != 3 ||
      state->receive_calls != 3) return;
  state->closed = 1;
  uv_udp_recv_stop(&state->receiver);
  uv_close((uv_handle_t *) &state->receiver, NULL);
  uv_close((uv_handle_t *) &state->unconnected, NULL);
  uv_close((uv_handle_t *) &state->connected, NULL);
}

static void _raw_udp_send(uv_udp_send_t *request, int status) {
  RawUdpState *state = request->data;
  state->send_calls++;
  if (status < 0) state->send_status = status;
  _raw_udp_finish(state);
}

static void _raw_udp_alloc(
  uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  (void) handle;
  (void) suggested;
  buffer->base = malloc(4);
  buffer->len = buffer->base ? 4 : 0;
}

static void _raw_udp_receive(
  uv_udp_t *udp, ssize_t count, const uv_buf_t *buffer,
  const struct sockaddr *source, unsigned flags) {
  RawUdpState *state = udp->data;
  if (count >= 0 && source) {
    state->receive_calls++;
    state->bytes += count;
    state->empty += count == 0;
    state->partial += !!(flags & UV_UDP_PARTIAL);
    state->source_port = ntohs(
      ((const struct sockaddr_in *) source)->sin_port
    );
  }
  free(buffer->base);
  _raw_udp_finish(state);
}

static void raw_udp_surface(void) {
  RawUdpState state = { 0 };
  struct sockaddr_in loopback;
  struct sockaddr_storage destination;
  struct sockaddr_storage peer;
  int destination_length = sizeof(destination);
  int peer_length = sizeof(peer);
  char binary[] = { 'u', 0, 'v' };
  char empty = 0;
  char oversized[] = "abcdefgh";
  uv_buf_t buffers[3] = {
    uv_buf_init(binary, sizeof(binary)),
    uv_buf_init(&empty, 0),
    uv_buf_init(oversized, 8)
  };

  EXPECT_INT_EQ(uv_loop_init(&state.loop), 0);
  EXPECT_INT_EQ(uv_udp_init(&state.loop, &state.receiver), 0);
  EXPECT_INT_EQ(uv_udp_init(&state.loop, &state.unconnected), 0);
  EXPECT_INT_EQ(uv_udp_init(&state.loop, &state.connected), 0);
  EXPECT_INT_EQ(uv_ip4_addr("127.0.0.1", 0, &loopback), 0);
  EXPECT_INT_EQ(uv_udp_bind(
    &state.receiver, (struct sockaddr *) &loopback, 0
  ), 0);
  EXPECT_INT_EQ(uv_udp_getsockname(
    &state.receiver, (struct sockaddr *) &destination,
    &destination_length
  ), 0);
  EXPECT_INT_EQ(uv_udp_bind(
    &state.unconnected, (struct sockaddr *) &loopback, 0
  ), 0);
  EXPECT_INT_EQ(uv_udp_bind(
    &state.connected, (struct sockaddr *) &loopback, 0
  ), 0);
  EXPECT_INT_EQ(uv_udp_connect(
    &state.connected, (struct sockaddr *) &destination
  ), 0);
  EXPECT_INT_EQ(uv_udp_getpeername(
    &state.connected, (struct sockaddr *) &peer, &peer_length
  ), 0);
  EXPECT_INT_EQ(((struct sockaddr *) &peer)->sa_family, AF_INET);
  EXPECT_INT_EQ(
    ((struct sockaddr_in *) &peer)->sin_port,
    ((struct sockaddr_in *) &destination)->sin_port
  );
  state.receiver.data = &state;
  state.unconnected.data = &state;
  state.connected.data = &state;
  for (int i = 0; i < 3; i++) state.sends[i].data = &state;
  EXPECT_INT_EQ(uv_udp_recv_start(
    &state.receiver, _raw_udp_alloc, _raw_udp_receive
  ), 0);
  EXPECT_INT_EQ(uv_udp_send(
    &state.sends[0], &state.unconnected, &buffers[0], 1,
    (struct sockaddr *) &destination, _raw_udp_send
  ), 0);
  EXPECT_INT_EQ(uv_udp_send(
    &state.sends[1], &state.connected, &buffers[1], 1,
    NULL, _raw_udp_send
  ), 0);
  EXPECT_INT_EQ(uv_udp_send(
    &state.sends[2], &state.connected, &buffers[2], 1,
    NULL, _raw_udp_send
  ), 0);
  EXPECT_INT_EQ(uv_udp_get_send_queue_count(&state.unconnected), 1);
  EXPECT_INT_EQ(uv_udp_get_send_queue_size(&state.unconnected), 3);
  EXPECT_INT_EQ(uv_udp_get_send_queue_count(&state.connected), 2);
  EXPECT_INT_EQ(uv_udp_get_send_queue_size(&state.connected), 8);
  EXPECT_INT_EQ(uv_run(&state.loop, UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.send_calls, 3);
  EXPECT_INT_EQ(state.send_status, 0);
  EXPECT_INT_EQ(state.receive_calls, 3);
  EXPECT_INT_EQ(state.empty, 1);
  EXPECT_INT_EQ(state.partial, 1);
  EXPECT_INT_EQ(state.bytes, 7);
  EXPECT_TRUE(state.source_port > 0);
  EXPECT_INT_EQ(uv_udp_get_send_queue_count(&state.unconnected), 0);
  EXPECT_INT_EQ(uv_udp_get_send_queue_size(&state.connected), 0);
  EXPECT_INT_EQ(uv_loop_close(&state.loop), 0);
}

static void raw_filesystem_surface(void) {
  char directory[128], path[160];
  snprintf(
    directory, sizeof(directory), "/tmp/x2c-libuv-raw-fs-%d",
    (int) getpid()
  );
  snprintf(path, sizeof(path), "%s/payload.bin", directory);
  unlink(path);
  rmdir(directory);
  EXPECT_INT_EQ(mkdir(directory, 0700), 0);
  defer {
    unlink(path);
    rmdir(directory);
  }

  uv_fs_t request = { 0 };
  int descriptor = uv_fs_open(
    NULL, &request, path,
    UV_FS_O_RDWR | UV_FS_O_CREAT | UV_FS_O_TRUNC, 0600, NULL
  );
  EXPECT_TRUE(descriptor >= 0);
  EXPECT_INT_EQ(uv_fs_get_type(&request), UV_FS_OPEN);
  EXPECT_INT_EQ(uv_fs_get_result(&request), descriptor);
  EXPECT_STR_EQ(String.new(uv_fs_get_path(&request)), String.new(path));
  uv_fs_req_cleanup(&request);

  char source[] = { 'r', 0, 'w' };
  uv_buf_t write_buffer = uv_buf_init(source, sizeof(source));
  EXPECT_INT_EQ(uv_fs_write(
    NULL, &request, descriptor, &write_buffer, 1, 0, NULL
  ), sizeof(source));
  EXPECT_INT_EQ(uv_fs_get_type(&request), UV_FS_WRITE);
  EXPECT_INT_EQ(uv_fs_get_result(&request), sizeof(source));
  uv_fs_req_cleanup(&request);

  char copied[sizeof(source)] = { 0 };
  uv_buf_t read_buffer = uv_buf_init(copied, sizeof(copied));
  EXPECT_INT_EQ(uv_fs_read(
    NULL, &request, descriptor, &read_buffer, 1, 0, NULL
  ), sizeof(copied));
  EXPECT_INT_EQ(uv_fs_get_type(&request), UV_FS_READ);
  EXPECT_TRUE(!memcmp(copied, source, sizeof(source)));
  uv_fs_req_cleanup(&request);

  EXPECT_INT_EQ(uv_fs_close(NULL, &request, descriptor, NULL), 0);
  EXPECT_INT_EQ(uv_fs_get_type(&request), UV_FS_CLOSE);
  uv_fs_req_cleanup(&request);

  EXPECT_INT_EQ(uv_fs_stat(NULL, &request, path, NULL), 0);
  EXPECT_INT_EQ(uv_fs_get_type(&request), UV_FS_STAT);
  EXPECT_INT_EQ(uv_fs_get_statbuf(&request)->st_size, sizeof(source));
  uv_fs_req_cleanup(&request);

  EXPECT_INT_EQ(uv_fs_scandir(
    NULL, &request, directory, 0, NULL
  ), 1);
  EXPECT_INT_EQ(uv_fs_get_type(&request), UV_FS_SCANDIR);
  uv_dirent_t entry;
  EXPECT_INT_EQ(uv_fs_scandir_next(&request, &entry), 0);
  EXPECT_STR_EQ(String.new(entry.name), %"payload.bin");
  EXPECT_INT_EQ(entry.type, UV_DIRENT_FILE);
  EXPECT_INT_EQ(uv_fs_scandir_next(&request, &entry), UV_EOF);
  EXPECT_NULL(uv_fs_get_ptr(&request));
  uv_fs_req_cleanup(&request);
}

void raw_uv_suite(void) {
  $test.run(raw_loop_and_version_surface);
  $test.run(raw_error_and_buffer_surface);
  $test.run(raw_async_notification_surface);
  $test.run(raw_loop_phase_surface);
  $test.run(raw_numeric_address_surface);
  $test.run(raw_dns_and_request_cancellation_surface);
  $test.run(raw_tcp_and_stream_surface);
  $test.run(raw_named_pipe_surface);
  $test.run(raw_udp_surface);
  $test.run(raw_filesystem_surface);
}

int main(void) {
  TestHarness_begin();
  $test.suite(raw_uv_suite);
  return TestHarness_finish();
}
