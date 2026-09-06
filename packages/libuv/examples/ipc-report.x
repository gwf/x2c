/*  ipc-report.x -- exchange one binary report over a named pipe */

import "libuv" with UvLoop, UvPipe, UvTimer;

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

typedef struct IpcState {
  UvPipe listener;
  UvPipe client;
  UvPipe server;
  UvTimer guard;
  Bytes received;
  String local_name;
  String peer_name;
  int eof;
} IpcState;

static void read_client(UvPipe pipe, Bytes chunk, Var value) {
  IpcState *state = value.pointer();
  if (chunk) {
    state.received = state.received.append(chunk, chunk.len());
    return;
  }
  state.eof++;
  pipe.close();
  state.server.close();
  state.listener.close();
  state.guard.stop();
}

static void read_server(UvPipe pipe, Bytes chunk, Var value) {
  IpcState *state = value.pointer();
  if (chunk) {
    pipe.write_bytes(chunk);
    return;
  }
  state.eof++;
  pipe.shutdown_write();
}

static void connected(UvPipe pipe, Var value) {
  IpcState *state = value.pointer();
  unsigned char report[] = { 'b', 'u', 'i', 'l', 'd', 0, 'o', 'k' };
  Bytes bytes = Bytes.new(1).append(report, sizeof(report));
  state.peer_name = pipe.peer_name();
  pipe.read(value, read_client).write_bytes(bytes).shutdown_write();
  bytes.free();
}

static void accepted(UvPipe listener, UvPipe pipe, Var value) {
  IpcState *state = value.pointer();
  state.server = pipe;
  state.local_name = pipe.local_name();
  pipe.read(value, read_server);
  (void) listener;
}

static void timed_out(UvTimer timer, Var value) {
  (void) timer;
  (void) value;
  raise %(timeout (operation "ipc-report")
          (reason "the named-pipe exchange did not finish"));
}

int main(void) {
  char directory[] = "/tmp/x2c-libuv-ipc-XXXXXX";
  if (!mkdtemp(directory)) {
    int error = errno;
    raise %(io-fail (operation "mkdtemp") (errno $error));
  }
  defer rmdir(directory);
  String path = %"$directory/report.sock";
  defer unlink(path);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  IpcState state = { .received = Bytes.new(1) };
  defer state.received.free();
  Var value = Var.new(<p48>, &state);
  state.guard = loop.timer(5000, 0, value, timed_out);
  state.listener = loop.pipe().bind(path).listen(4, value, accepted);
  state.client = loop.pipe().connect(path, value, connected);
  loop.run(UV_RUN_DEFAULT);

  unsigned char expected[] = { 'b', 'u', 'i', 'l', 'd', 0, 'o', 'k' };
  if (state.eof != 2 || !state.local_name.equal(path) ||
      !state.peer_name.equal(path) ||
      state.received.len() != sizeof(expected) ||
      memcmp(state.received, expected, sizeof(expected))) {
    raise %(malformed (operation "ipc-report")
            (reason "the echoed report changed"));
  }
  printf("%zu binary bytes echoed, %d EOFs\n",
         state.received.len(), state.eof);
  return 0;
}
