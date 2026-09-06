/*  libuv.x -- libuv loops, asynchronous I/O, processes, and watchers

    UvLoop owns one native event loop. Its filesystem requests and TCP,
    named-pipe, UDP, process, async, phase, timer, signal, and watch wrappers
    call x2c only while the caller drives that loop, on the thread that called
    UvLoop.run. User callbacks catch an x2c Error, stop the current loop run,
    and let UvLoop.run report it after libuv returns control to x2c.

    Each wrapper reaches its native handle through `.native()`, so anything
    this client does not wrap stays available on the pinned uv-152.h surface.
*/

#include "uv-152.h"

typedef struct UvLoop *UvLoop;
typedef struct UvProcess *UvProcess;
typedef struct UvAsync *UvAsync;
typedef struct UvIdle *UvIdle;
typedef struct UvPrepare *UvPrepare;
typedef struct UvCheck *UvCheck;
typedef struct UvAddress *UvAddress;
typedef struct UvLookup *UvLookup;
typedef struct UvTcp *UvTcp;
typedef struct UvPipe *UvPipe;
typedef struct UvUdp *UvUdp;
typedef struct UvFile *UvFile;
typedef struct UvFs *UvFs;
typedef struct UvStat *UvStat;
typedef struct UvTimer *UvTimer;
typedef struct UvSignal *UvSignal;
typedef struct UvWatch *UvWatch;

#pragma private

#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef void (*UvTimerFn)(UvTimer, Var);
typedef void (*UvAsyncFn)(UvAsync, Var);
typedef void (*UvIdleFn)(UvIdle, Var);
typedef void (*UvPrepareFn)(UvPrepare, Var);
typedef void (*UvCheckFn)(UvCheck, Var);
typedef void (*UvLookupFn)(UvLookup, Var);
typedef void (*UvTcpConnectFn)(UvTcp, Var);
typedef void (*UvTcpListenFn)(UvTcp, UvTcp, Var);
typedef void (*UvTcpReadFn)(UvTcp, Bytes, Var);
typedef void (*UvPipeConnectFn)(UvPipe, Var);
typedef void (*UvPipeListenFn)(UvPipe, UvPipe, Var);
typedef void (*UvPipeReadFn)(UvPipe, Bytes, Var);
typedef void (*UvUdpReceiveFn)(UvUdp, Bytes, UvAddress, unsigned, Var);
typedef void (*UvFsFn)(UvFs, Var);
typedef void (*UvSignalFn)(UvSignal, Var);
typedef void (*UvWatchFn)(UvWatch, Var);
typedef struct UvWrite *UvWrite;
typedef struct UvStream *UvStream;
typedef struct UvStreamWrite *UvStreamWrite;
typedef struct UvUdpSend *UvUdpSend;
typedef struct UvDirEntry *UvDirEntry;

typedef UvStream (*UvStreamAcceptFn)(UvStream);
typedef void (*UvStreamConnectFn)(UvStream);
typedef void (*UvStreamListenFn)(UvStream, UvStream);
typedef void (*UvStreamReadFn)(UvStream, Bytes);

typedef struct UvCapture {
  uv_pipe_t pipe;
  char *bytes;
  size_t length;
  size_t capacity;
  size_t limit;
  int status;
  int closed;
  int enabled;
} UvCapture;

typedef enum UvStdioMode {
  UV_STDIO_PIPE,
  UV_STDIO_INHERIT,
  UV_STDIO_IGNORE
} UvStdioMode;

struct UvWrite {
  uv_write_t request;
  UvProcess process;
  char *bytes;
};

struct UvLoop {
  uv_loop_t loop;
  size_t pending_requests;
  size_t open_files;
  int initialized;
  int running;
  Symbol callback_cause;
  List callback_detail;
};

struct UvAddress {
  struct sockaddr_storage address;
  socklen_t length;
  String host;
  String canonical_name;
  int socket_type;
  int protocol;
};

struct UvLookup {
  uv_getaddrinfo_t request;
  UvLoop loop;
  Scope owner_scope;
  Pool strings;
  String node;
  String service;
  struct addrinfo hints;
  struct UvAddress *addresses;
  size_t count;
  Var value;
  UvLookupFn handler;
  int status;
  int started;
  int completed;
  int cancelled;
};

struct UvStream {
  uv_stream_t *native;
  UvLoop loop;
  Scope owner_scope;
  void *owner;
  uv_connect_t connect_request;
  uv_shutdown_t shutdown_request;
  UvStreamAcceptFn accept;
  UvStreamConnectFn connected_fn;
  UvStreamListenFn listen_fn;
  UvStreamReadFn read_fn;
  String connect_operation;
  int connected;
  int connect_pending;
  int reading;
  int read_eof;
  int listening;
  int shutdown_pending;
  int shutdown_done;
  int closing;
  int closed;
};

struct UvStreamWrite {
  uv_write_t request;
  UvStream stream;
  char *bytes;
};

struct UvTcp {
  uv_tcp_t tcp;
  struct UvStream stream;
  Var connect_value;
  Var listen_value;
  Var read_value;
  UvTcpConnectFn connect_handler;
  UvTcpListenFn listen_handler;
  UvTcpReadFn read_handler;
};

struct UvPipe {
  uv_pipe_t pipe;
  struct UvStream stream;
  Var connect_value;
  Var listen_value;
  Var read_value;
  UvPipeConnectFn connect_handler;
  UvPipeListenFn listen_handler;
  UvPipeReadFn read_handler;
};

struct UvUdp {
  uv_udp_t udp;
  UvLoop loop;
  Scope owner_scope;
  Pool strings;
  Var receive_value;
  UvUdpReceiveFn receive_handler;
  size_t receive_limit;
  int receiving;
  int closing;
  int closed;
};

struct UvUdpSend {
  uv_udp_send_t request;
  UvUdp udp;
  char *bytes;
  struct sockaddr_storage address;
};

typedef enum UvFsPhase {
  UV_FS_PHASE_SINGLE,
  UV_FS_PHASE_OPEN,
  UV_FS_PHASE_TRANSFER,
  UV_FS_PHASE_CLOSE
} UvFsPhase;

struct UvFile {
  UvLoop loop;
  Scope owner_scope;
  uv_file descriptor;
  size_t pending;
  int closing;
  int closed;
};

struct UvStat {
  uv_stat_t value;
};

struct UvDirEntry {
  String name;
  uv_dirent_type_t type;
};

struct UvFs {
  uv_fs_t request;
  uv_fs_t close_request;
  UvLoop loop;
  Scope owner_scope;
  Pool strings;
  UvFile file;
  String path;
  char *buffer;
  size_t buffer_length;
  Bytes bytes;
  struct UvStat stat;
  struct UvDirEntry *entries;
  size_t entry_count;
  Var value;
  UvFsFn handler;
  uv_fs_type operation;
  UvFsPhase phase;
  uv_file descriptor;
  size_t offset;
  size_t limit;
  ssize_t result;
  String error_operation;
  Symbol failure_cause;
  List failure_detail;
  int status;
  int started;
  int completed;
  int cancelled;
  int limit_exceeded;
};

struct UvAsync {
  uv_async_t async;
  UvLoop loop;
  Var value;
  UvAsyncFn handler;
  int stopped;
};

struct UvIdle {
  uv_idle_t idle;
  UvLoop loop;
  Var value;
  UvIdleFn handler;
  int stopped;
};

struct UvPrepare {
  uv_prepare_t prepare;
  UvLoop loop;
  Var value;
  UvPrepareFn handler;
  int stopped;
};

struct UvCheck {
  uv_check_t check;
  UvLoop loop;
  Var value;
  UvCheckFn handler;
  int stopped;
};

struct UvTimer {
  uv_timer_t timer;
  UvLoop loop;
  Var value;
  UvTimerFn handler;
};

struct UvSignal {
  uv_signal_t signal;
  UvLoop loop;
  Var value;
  UvSignalFn handler;
  int number;
};

struct UvWatch {
  uv_fs_event_t event;
  UvLoop loop;
  Var value;
  UvWatchFn handler;
  String entry;
  Symbol kind;
  int status;
};

struct UvProcess {
  uv_process_t process;
  uv_pipe_t input;
  uv_timer_t deadline;
  uv_shutdown_t shutdown;
  UvCapture output;
  UvCapture error;
  UvLoop loop;
  String directory;
  char **argv;
  char **environment;
  long deadline_ms;
  UvStdioMode input_mode;
  UvStdioMode output_mode;
  UvStdioMode error_mode;
  int started;
  int released;
  int exited;
  int timed_out;
  int process_closed;
  int input_closed;
  int deadline_closed;
  int pending_writes;
  int shutdown_pending;
  int input_status;
  int64_t exit_status;
  int term_signal;
};

static void _uv_raise(String operation, int status) {
  String name = String.new(uv_err_name(status));
  String message = String.new(uv_strerror(status));
  raise %(io-fail (library "libuv") (operation $operation)
          (status $status) (name $name) (message $message));
}

static void _uv_callback_failed(UvLoop loop, Symbol cause, List detail) {
  if (!loop || loop.callback_cause) return;
  loop.callback_cause = cause;
  try loop.callback_detail = Error.snapshot(detail);
  catch %(?snapcause *): {
    loop.callback_cause = snapcause;
    loop.callback_detail = NULL;
  }
  if (loop.initialized) uv_stop(&loop.loop);
}

static String _uv_address_string(Pool strings, const char *text) {
  if (!text) return NULL;
  size_t length = strlen(text);
  if (length > INT_MAX) raise %(size-limit (library "libuv"));
  return String.new_in(strings, text, (int) length);
}

static void _uv_address_name(UvAddress address, Pool strings) {
  int family = ((struct sockaddr *) &address.address)->sa_family;
  if (family != AF_INET && family != AF_INET6) return;
  char host[INET6_ADDRSTRLEN];
  int status = uv_ip_name(
    (struct sockaddr *) &address.address, host, sizeof(host)
  );
  if (status < 0) _uv_raise(%"ip_name", status);
  address.host = _uv_address_string(strings, host);
}

static void _uv_address_copy(
  UvAddress address, struct addrinfo *info, Pool strings) {
  if (!info->ai_addr || info->ai_addrlen > sizeof(struct sockaddr_storage)) {
    raise %(bad-state (library "libuv") (operation "getaddrinfo")
            (reason "libuv returned an invalid socket address"));
  }
  memcpy(&address.address, info->ai_addr, info->ai_addrlen);
  address.length = info->ai_addrlen;
  address.socket_type = info->ai_socktype;
  address.protocol = info->ai_protocol;
  address.canonical_name = _uv_address_string(strings, info->ai_canonname);
  _uv_address_name(address, strings);
}

static void _uv_lookup_copy(UvLookup lookup, struct addrinfo *result) {
  for (struct addrinfo *info = result; info; info = info->ai_next) {
    lookup.count++;
  }
  lookup.addresses = Scope.calloc_in(
    &lookup.owner_scope, lookup.count, sizeof(struct UvAddress)
  );
  size_t index = 0;
  for (struct addrinfo *info = result; info; info = info->ai_next) {
    _uv_address_copy(&lookup.addresses[index++], info, lookup.strings);
  }
}

static void _uv_lookup_take_results(
  UvLookup lookup, int status, struct addrinfo *result) {
  defer {
    if (result) uv_freeaddrinfo(result);
    lookup.request.addrinfo = NULL;
  }
  if (status < 0 && !lookup.cancelled) {
    _uv_raise(%"getaddrinfo", status);
  }
  if (!lookup.cancelled) _uv_lookup_copy(lookup, result);
}

static void _uv_lookup_callback(
  uv_getaddrinfo_t *request, int status, struct addrinfo *result) {
  UvLookup lookup = request ? request->data : NULL;
  if (!lookup) {
    if (result) uv_freeaddrinfo(result);
    return;
  }
  lookup.loop.pending_requests--;
  lookup.status = status;
  lookup.completed = 1;
  lookup.cancelled = status == UV_ECANCELED || status == UV_EAI_CANCELED;

  try _uv_lookup_take_results(lookup, status, result);
  catch %(?cause *detail): {
    _uv_callback_failed(lookup.loop, cause, detail);
    return;
  }

  try lookup.handler(lookup, lookup.value);
  catch %(?cause *detail): {
    _uv_callback_failed(lookup.loop, cause, detail);
  }
}

static void _uv_process_ready(UvProcess process, String operation) {
  if (!process) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "process has not been started"));
  }
  if (process.released) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "process has been released"));
  }
  if (!process.started) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "process has not been started"));
  }
  if (process.input_status < 0) {
    _uv_raise(operation, process.input_status);
  }
}

static void _uv_process_pending(UvProcess process, String operation) {
  if (!process) {
    raise %(bad-arg (library "libuv") (operation $operation)
            (reason "a command is required"));
  }
  if (process.started) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "set this before starting the command"));
  }
}

static void _uv_alloc_event(
  uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  (void) handle;
  if (!suggested) suggested = 1;
  buffer->base = malloc(suggested);
  buffer->len = buffer->base ? suggested : 0;
}

static int _uv_capture_append(
  UvCapture *capture, const char *bytes, size_t length) {
  if (!length) return 1;
  if (length > capture.limit - capture.length) {
    capture.status = UV_ENOBUFS;
    return 0;
  }
  size_t needed = capture.length + length;
  if (needed > capture.capacity) {
    size_t capacity = capture.capacity ? capture.capacity : 4096;
    while (capacity < needed) {
      if (capacity > SIZE_MAX / 2) {
        capacity = needed;
        break;
      }
      capacity *= 2;
    }
    char *grown = realloc(capture.bytes, capacity);
    if (!grown) {
      capture.status = UV_ENOMEM;
      return 0;
    }
    capture.bytes = grown;
    capture.capacity = capacity;
  }
  memcpy(capture.bytes + capture.length, bytes, length);
  capture.length = needed;
  return 1;
}

static void _uv_capture_close_event(uv_handle_t *handle) {
  UvCapture *capture = handle ? handle->data : NULL;
  if (capture) capture.closed = 1;
}

static void _uv_capture_close(UvCapture *capture) {
  if (!capture || capture.closed) return;
  uv_stream_t *stream = (uv_stream_t *) &capture.pipe;
  uv_read_stop(stream);
  if (!uv_is_closing((uv_handle_t *) stream))
    uv_close((uv_handle_t *) stream, _uv_capture_close_event);
}

static void _uv_read_event(
  uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
  UvCapture *capture = stream ? stream->data : NULL;
  if (!capture) return;
  if (count > 0) {
    if (!_uv_capture_append(capture, buffer->base, (size_t) count))
      _uv_capture_close(capture);
    return;
  }
  if (count < 0) {
    if (count != UV_EOF && !capture.status) capture.status = (int) count;
    _uv_capture_close(capture);
  }
}

static void _uv_read_callback(
  uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
  _uv_read_event(stream, count, buffer);
  free(buffer ? buffer->base : NULL);
}

static void _uv_process_close_event(uv_handle_t *handle) {
  UvProcess process = handle ? handle->data : NULL;
  if (process) process.process_closed = 1;
}

static void _uv_deadline_close_event(uv_handle_t *handle) {
  UvProcess process = handle ? handle->data : NULL;
  if (process) process.deadline_closed = 1;
}

static void _uv_deadline_release(UvProcess process) {
  if (!process || process.deadline_closed) return;
  uv_handle_t *handle = (uv_handle_t *) &process.deadline;
  uv_timer_stop(&process.deadline);
  if (!uv_is_closing(handle))
    uv_close(handle, _uv_deadline_close_event);
}

/*  A child that outlives its deadline is killed outright; the ordinary exit
    callback then reports SIGKILL, and UvProcess.timed_out tells that apart
    from a signal the child received for another reason.
*/
static void _uv_deadline_event(uv_timer_t *handle) {
  UvProcess process = handle ? handle->data : NULL;
  if (!process) return;
  if (!process.exited) {
    process.timed_out = 1;
    uv_process_kill(&process.process, SIGKILL);
  }
  _uv_deadline_release(process);
}

static void _uv_process_exit_event(
  uv_process_t *handle, int64_t status, int signal) {
  UvProcess process = handle ? handle->data : NULL;
  if (!process) return;
  process.exit_status = status;
  process.term_signal = signal;
  process.exited = 1;
  _uv_deadline_release(process);
  if (!uv_is_closing((uv_handle_t *) handle))
    uv_close((uv_handle_t *) handle, _uv_process_close_event);
}

static void _uv_write_event(uv_write_t *request, int status) {
  UvWrite write = request ? request->data : NULL;
  if (!write) return;
  UvProcess process = write.process;
  if (process.pending_writes > 0) process.pending_writes--;
  if (status < 0 && !process.input_status) process.input_status = status;
  free(write.bytes);
  free(write);
}

static void _uv_input_close_event(uv_handle_t *handle) {
  UvProcess process = handle ? handle->data : NULL;
  if (process) process.input_closed = 1;
}

static void _uv_input_close(UvProcess process) {
  if (!process || process.input_closed) return;
  uv_handle_t *handle = (uv_handle_t *) &process.input;
  if (!uv_is_closing(handle)) uv_close(handle, _uv_input_close_event);
}

static void _uv_shutdown_event(uv_shutdown_t *request, int status) {
  UvProcess process = request ? request->data : NULL;
  if (!process) return;
  process.shutdown_pending = 0;
  if (status < 0 && status != UV_ENOTCONN && !process.input_status)
    process.input_status = status;
  _uv_input_close(process);
}

static void _uv_discard_closed_handles(UvLoop loop, UvProcess process) {
  while (loop && loop.initialized && process &&
         (!process.input_closed || !process.output.closed ||
          !process.error.closed))
    uv_run(&loop.loop, UV_RUN_NOWAIT);
}

/*  A loop-owned handle needs no close callback: nothing waits on it, and
    uv_is_closing already makes a second stop harmless.
*/
static void _uv_close_handle(uv_handle_t *handle) {
  if (handle && !uv_is_closing(handle)) uv_close(handle, NULL);
}

static void _uv_async_release(UvAsync async) {
  if (!async || async.stopped) return;
  async.stopped = 1;
  _uv_close_handle((uv_handle_t *) &async.async);
}

static void _uv_async_event(uv_async_t *handle) {
  UvAsync async = handle ? handle->data : NULL;
  if (!async) return;
  UvAsyncFn handler = async.handler;
  handler(async, async.value);
}

static void _uv_async_callback(uv_async_t *handle) {
  try _uv_async_event(handle);
  catch %(?cause *detail): {
    UvAsync async = handle ? handle->data : NULL;
    if (async) {
      _uv_callback_failed(async.loop, cause, detail);
      _uv_async_release(async);
    }
  }
}

static void _uv_idle_release(UvIdle idle) {
  if (!idle || idle.stopped) return;
  idle.stopped = 1;
  uv_idle_stop(&idle.idle);
  _uv_close_handle((uv_handle_t *) &idle.idle);
}

static void _uv_idle_event(uv_idle_t *handle) {
  UvIdle idle = handle ? handle->data : NULL;
  if (!idle) return;
  UvIdleFn handler = idle.handler;
  handler(idle, idle.value);
}

static void _uv_idle_callback(uv_idle_t *handle) {
  try _uv_idle_event(handle);
  catch %(?cause *detail): {
    UvIdle idle = handle ? handle->data : NULL;
    if (idle) {
      _uv_callback_failed(idle.loop, cause, detail);
      _uv_idle_release(idle);
    }
  }
}

static void _uv_prepare_release(UvPrepare prepare) {
  if (!prepare || prepare.stopped) return;
  prepare.stopped = 1;
  uv_prepare_stop(&prepare.prepare);
  _uv_close_handle((uv_handle_t *) &prepare.prepare);
}

static void _uv_prepare_event(uv_prepare_t *handle) {
  UvPrepare prepare = handle ? handle->data : NULL;
  if (!prepare) return;
  UvPrepareFn handler = prepare.handler;
  handler(prepare, prepare.value);
}

static void _uv_prepare_callback(uv_prepare_t *handle) {
  try _uv_prepare_event(handle);
  catch %(?cause *detail): {
    UvPrepare prepare = handle ? handle->data : NULL;
    if (prepare) {
      _uv_callback_failed(prepare.loop, cause, detail);
      _uv_prepare_release(prepare);
    }
  }
}

static void _uv_check_release(UvCheck check) {
  if (!check || check.stopped) return;
  check.stopped = 1;
  uv_check_stop(&check.check);
  _uv_close_handle((uv_handle_t *) &check.check);
}

static void _uv_check_event(uv_check_t *handle) {
  UvCheck check = handle ? handle->data : NULL;
  if (!check) return;
  UvCheckFn handler = check.handler;
  handler(check, check.value);
}

static void _uv_check_callback(uv_check_t *handle) {
  try _uv_check_event(handle);
  catch %(?cause *detail): {
    UvCheck check = handle ? handle->data : NULL;
    if (check) {
      _uv_callback_failed(check.loop, cause, detail);
      _uv_check_release(check);
    }
  }
}

static void _uv_timer_release(UvTimer timer) {
  if (!timer) return;
  uv_timer_stop(&timer.timer);
  _uv_close_handle((uv_handle_t *) &timer.timer);
}

static void _uv_timer_event(uv_timer_t *handle) {
  UvTimer timer = handle ? handle->data : NULL;
  if (!timer) return;
  UvTimerFn handler = timer.handler;
  handler(timer, timer.value);
}

/*  A repeating timer whose body raised would raise again on every tick and
    never let uv_run return, so the failure also stops the timer.
*/
static void _uv_timer_callback(uv_timer_t *handle) {
  try _uv_timer_event(handle);
  catch %(?cause *detail): {
    UvTimer timer = handle ? handle->data : NULL;
    if (timer) {
      _uv_callback_failed(timer.loop, cause, detail);
      _uv_timer_release(timer);
    }
  }
}

static void _uv_signal_release(UvSignal signal) {
  if (!signal) return;
  uv_signal_stop(&signal.signal);
  _uv_close_handle((uv_handle_t *) &signal.signal);
}

static void _uv_signal_event(uv_signal_t *handle, int number) {
  UvSignal signal = handle ? handle->data : NULL;
  if (!signal) return;
  signal.number = number;
  UvSignalFn handler = signal.handler;
  handler(signal, signal.value);
}

static void _uv_signal_callback(uv_signal_t *handle, int number) {
  try _uv_signal_event(handle, number);
  catch %(?cause *detail): {
    UvSignal signal = handle ? handle->data : NULL;
    if (signal) {
      _uv_callback_failed(signal.loop, cause, detail);
      _uv_signal_release(signal);
    }
  }
}

static void _uv_watch_release(UvWatch watch) {
  if (!watch) return;
  uv_fs_event_stop(&watch.event);
  _uv_close_handle((uv_handle_t *) &watch.event);
}

/*  libuv borrows `entry` only for this call, so copy it before invoking the
    consumer's callback. A NULL entry means libuv did not report a name.
*/
static void _uv_watch_event(
  uv_fs_event_t *handle, const char *entry, int events, int status) {
  UvWatch watch = handle ? handle->data : NULL;
  if (!watch) return;
  if (status < 0) {
    watch.status = status;
    _uv_watch_release(watch);
    return;
  }
  watch.entry = entry ? String.new((char *) entry) : NULL;
  watch.kind = (events & UV_RENAME) ? <rename> : <change>;
  UvWatchFn handler = watch.handler;
  handler(watch, watch.value);
}

static void _uv_watch_callback(
  uv_fs_event_t *handle, const char *entry, int events, int status) {
  try _uv_watch_event(handle, entry, events, status);
  catch %(?cause *detail): {
    UvWatch watch = handle ? handle->data : NULL;
    if (watch) {
      _uv_callback_failed(watch.loop, cause, detail);
      _uv_watch_release(watch);
    }
  }
}

static void _uv_stream_close(UvStream stream);
static void _uv_stream_connect_callback(uv_connect_t *request, int status);
static void _uv_stream_listen_callback(uv_stream_t *native, int status);
static void _uv_stream_read_callback(
  uv_stream_t *native, ssize_t count, const uv_buf_t *buffer);
static void _uv_stream_write_callback(uv_write_t *request, int status);
static void _uv_stream_shutdown_callback(uv_shutdown_t *request, int status);

static void _uv_stream_initialize(
  UvStream stream, UvLoop loop, uv_stream_t *native, void *owner) {
  stream.native = native;
  stream.loop = loop;
  stream.owner_scope = *Scope.top();
  stream.owner = owner;
  native->data = stream;
  stream.connect_request.data = stream;
  stream.shutdown_request.data = stream;
}

static UvTcp _uv_tcp_new(UvLoop loop) {
  UvTcp tcp = Scope.calloc(1, sizeof(struct UvTcp));
  int status = uv_tcp_init(&loop.loop, &tcp.tcp);
  if (status < 0) {
    Scope.free(tcp);
    _uv_raise(%"tcp_init", status);
  }
  _uv_stream_initialize(
    &tcp.stream, loop, (uv_stream_t *) &tcp.tcp, tcp
  );
  return tcp;
}

static UvPipe _uv_pipe_new(UvLoop loop) {
  UvPipe pipe = Scope.calloc(1, sizeof(struct UvPipe));
  int status = uv_pipe_init(&loop.loop, &pipe.pipe, 0);
  if (status < 0) {
    Scope.free(pipe);
    _uv_raise(%"pipe_init", status);
  }
  _uv_stream_initialize(
    &pipe.stream, loop, (uv_stream_t *) &pipe.pipe, pipe
  );
  return pipe;
}

static void _uv_stream_close_callback(uv_handle_t *handle) {
  UvStream stream = handle ? handle->data : NULL;
  if (!stream) return;
  stream.reading = 0;
  stream.listening = 0;
  stream.connected = 0;
  stream.closed = 1;
}

static void _uv_stream_close(UvStream stream) {
  if (!stream || stream.closing || stream.closed) return;
  stream.closing = 1;
  stream.reading = 0;
  stream.listening = 0;
  uv_read_stop(stream.native);
  uv_handle_t *handle = (uv_handle_t *) stream.native;
  if (!uv_is_closing(handle)) uv_close(handle, _uv_stream_close_callback);
}

static void _uv_stream_fail(UvStream stream, String operation, int status) {
  if (!stream) return;
  _uv_stream_close(stream);
  try _uv_raise(operation, status);
  catch %(?cause *detail): {
    _uv_callback_failed(stream.loop, cause, detail);
  }
}

static UvStream _uv_tcp_accept(UvStream listener) {
  UvTcp tcp = _uv_tcp_new(listener.loop);
  int status = uv_accept(listener.native, tcp.stream.native);
  if (status < 0) {
    _uv_stream_close(&tcp.stream);
    _uv_raise(%"accept", status);
  }
  tcp.stream.connected = 1;
  return &tcp.stream;
}

static void _uv_tcp_connected(UvStream stream) {
  UvTcp tcp = stream.owner;
  UvTcpConnectFn handler = tcp.connect_handler;
  handler(tcp, tcp.connect_value);
}

static void _uv_tcp_listen(UvStream listener, UvStream accepted) {
  UvTcp tcp = listener.owner;
  UvTcp peer = accepted.owner;
  UvTcpListenFn handler = tcp.listen_handler;
  handler(tcp, peer, tcp.listen_value);
}

static void _uv_tcp_read(UvStream stream, Bytes chunk) {
  UvTcp tcp = stream.owner;
  UvTcpReadFn handler = tcp.read_handler;
  handler(tcp, chunk, tcp.read_value);
}

static UvStream _uv_pipe_accept(UvStream listener) {
  UvPipe pipe = _uv_pipe_new(listener.loop);
  int status = uv_accept(listener.native, pipe.stream.native);
  if (status < 0) {
    _uv_stream_close(&pipe.stream);
    _uv_raise(%"accept", status);
  }
  pipe.stream.connected = 1;
  return &pipe.stream;
}

static void _uv_pipe_connected(UvStream stream) {
  UvPipe pipe = stream.owner;
  UvPipeConnectFn handler = pipe.connect_handler;
  handler(pipe, pipe.connect_value);
}

static void _uv_pipe_listen(UvStream listener, UvStream accepted) {
  UvPipe pipe = listener.owner;
  UvPipe peer = accepted.owner;
  UvPipeListenFn handler = pipe.listen_handler;
  handler(pipe, peer, pipe.listen_value);
}

static void _uv_pipe_read(UvStream stream, Bytes chunk) {
  UvPipe pipe = stream.owner;
  UvPipeReadFn handler = pipe.read_handler;
  handler(pipe, chunk, pipe.read_value);
}

static void _uv_stream_connect_callback(uv_connect_t *request, int status) {
  UvStream stream = request ? request->data : NULL;
  if (!stream) return;
  stream.connect_pending = 0;
  stream.loop.pending_requests--;
  if (status < 0) {
    if (!(status == UV_ECANCELED && stream.closing))
      _uv_stream_fail(stream, stream.connect_operation, status);
    return;
  }
  stream.connected = 1;
  try stream.connected_fn(stream);
  catch %(?cause *detail): {
    _uv_stream_close(stream);
    _uv_callback_failed(stream.loop, cause, detail);
  }
}

static void _uv_stream_listen_callback(uv_stream_t *native, int status) {
  UvStream listener = native ? native->data : NULL;
  if (!listener) return;
  if (status < 0) {
    _uv_stream_fail(listener, %"listen", status);
    return;
  }
  UvStream accepted = NULL;
  try {
    accepted = listener.accept(listener);
    listener.listen_fn(listener, accepted);
  }
  catch %(?cause *detail): {
    if (accepted) _uv_stream_close(accepted);
    _uv_stream_close(listener);
    _uv_callback_failed(listener.loop, cause, detail);
  }
}

static void _uv_stream_read_callback(
  uv_stream_t *native, ssize_t count, const uv_buf_t *buffer) {
  UvStream stream = native ? native->data : NULL;
  if (!stream) {
    free(buffer ? buffer->base : NULL);
    return;
  }
  if (!count) {
    free(buffer ? buffer->base : NULL);
    return;
  }
  if (count < 0) {
    free(buffer ? buffer->base : NULL);
    stream.reading = 0;
    if (count != UV_EOF) {
      _uv_stream_fail(stream, %"read", (int) count);
      return;
    }
    stream.read_eof = 1;
    try stream.read_fn(stream, NULL);
    catch %(?cause *detail): {
      _uv_stream_close(stream);
      _uv_callback_failed(stream.loop, cause, detail);
    }
    return;
  }

  Bytes chunk = NULL;
  try {
    chunk = Bytes.new(1).append(buffer->base, (size_t) count);
    chunk.block().move_to(&stream.owner_scope);
  }
  catch %(?cause *detail): {
    free(buffer ? buffer->base : NULL);
    _uv_stream_close(stream);
    _uv_callback_failed(stream.loop, cause, detail);
    return;
  }
  free(buffer ? buffer->base : NULL);
  try stream.read_fn(stream, chunk);
  catch %(?cause *detail): {
    _uv_stream_close(stream);
    _uv_callback_failed(stream.loop, cause, detail);
  }
}

static void _uv_stream_write_callback(uv_write_t *request, int status) {
  UvStreamWrite write = request ? request->data : NULL;
  if (!write) return;
  UvStream stream = write.stream;
  stream.loop.pending_requests--;
  Scope.free(write.bytes);
  Scope.free(write);
  if (status < 0 && !(status == UV_ECANCELED && stream.closing))
    _uv_stream_fail(stream, %"write", status);
}

static void _uv_stream_shutdown_callback(uv_shutdown_t *request, int status) {
  UvStream stream = request ? request->data : NULL;
  if (!stream) return;
  stream.shutdown_pending = 0;
  stream.shutdown_done = status >= 0;
  stream.loop.pending_requests--;
  if (status < 0 && !(status == UV_ECANCELED && stream.closing))
    _uv_stream_fail(stream, %"shutdown", status);
}

static void _uv_stream_start_read(UvStream stream) {
  int status = uv_read_start(
    stream.native, _uv_alloc_event, _uv_stream_read_callback
  );
  if (status < 0) _uv_raise(%"read_start", status);
  stream.reading = 1;
}

static void _uv_stream_stop_read(UvStream stream) {
  if (!stream.reading) return;
  int status = uv_read_stop(stream.native);
  if (status < 0) _uv_raise(%"read_stop", status);
  stream.reading = 0;
}

static void _uv_stream_submit_write(
  UvStream stream, const void *bytes, size_t length) {
  if (!length) return;
  if (length > UINT_MAX)
    raise %(size-limit (library "libuv") (operation "write")
            (length $length));
  UvStreamWrite write = Scope.calloc_in(
    &stream.owner_scope, 1, sizeof(struct UvStreamWrite)
  );
  write.stream = stream;
  write.bytes = Scope.memdup_in(&stream.owner_scope, bytes, length);
  write.request.data = write;
  uv_buf_t buffer = uv_buf_init(write.bytes, length);
  int status = uv_write(
    &write.request, stream.native, &buffer, 1, _uv_stream_write_callback
  );
  if (status < 0) {
    Scope.free(write.bytes);
    Scope.free(write);
    _uv_raise(%"write", status);
  }
  stream.loop.pending_requests++;
}

static void _uv_stream_submit_shutdown(UvStream stream) {
  if (stream.shutdown_pending || stream.shutdown_done) return;
  int status = uv_shutdown(
    &stream.shutdown_request, stream.native,
    _uv_stream_shutdown_callback
  );
  if (status < 0) _uv_raise(%"shutdown", status);
  stream.shutdown_pending = 1;
  stream.loop.pending_requests++;
}

static void _uv_close_walk_callback(uv_handle_t *handle, void *unused) {
  (void) unused;
  _uv_close_handle(handle);
}

UvLoop UvLoop.new(void) {
  UvLoop loop = Scope.calloc(1, sizeof(struct UvLoop));
  int status = uv_loop_init(&loop.loop);
  if (status < 0) {
    Scope.free(loop);
    _uv_raise(%"loop_init", status);
  }
  loop.initialized = 1;
  return loop;
}

/*  Rejects pending requests, then closes whatever callback handles and
    watchers the caller left open. Free processes first; their pipes belong
    to them, not to the loop. A handle that will not close leaves
    uv_loop_close to report EBUSY rather than spinning here.
*/
UvLoop UvLoop.free(UvLoop loop) {
  if (!loop || !loop.initialized) return NULL;
  if (loop.pending_requests || loop.open_files) {
    long pending = (long) loop.pending_requests;
    long files = (long) loop.open_files;
    raise %(bad-state (library "libuv") (operation "loop_free")
            (reason "the loop has pending requests or open files")
            (pending $pending) (files $files));
  }
  uv_walk(&loop.loop, _uv_close_walk_callback, NULL);
  uv_run(&loop.loop, UV_RUN_DEFAULT);
  int status = uv_loop_close(&loop.loop);
  if (status < 0) {
    _uv_raise(%"loop_close", status);
  }
  loop.initialized = 0;
  return NULL;
}

/*  The native loop, for anything uv-152.h offers and this client does not.
    struct UvLoop is private and its layout is not a contract; this is the
    only supported way to reach uv_loop_t.
*/
uv_loop_t *UvLoop.native(UvLoop loop) {
  return loop && loop.initialized ? &loop.loop : NULL;
}

int UvLoop.run(UvLoop loop, uv_run_mode mode) {
  if (!loop || !loop.initialized || loop.running) {
    raise %(bad-state (library "libuv") (operation "run")
            (reason "loop is null, closed, or already running"));
  }
  loop.running = 1;
  defer loop.running = 0;
  int pending = uv_run(&loop.loop, mode);
  if (loop.callback_cause) {
    Symbol cause = loop.callback_cause;
    List detail = loop.callback_detail;
    loop.callback_cause = 0;
    loop.callback_detail = NULL;
    Error.raise(cause, detail);
  }
  return pending;
}

int UvLoop.alive(UvLoop loop) {
  return loop && loop.initialized ? uv_loop_alive(&loop.loop) : 0;
}

void UvLoop.stop(UvLoop loop) {
  if (loop && loop.initialized) uv_stop(&loop.loop);
}

UvAddress UvAddress.ip4(String host, int port) {
  if (!host || port < 0 || port > UINT16_MAX) {
    raise %(bad-arg (library "libuv") (operation "ip4")
            (reason "a numeric host and a valid port are required"));
  }
  UvAddress address = Scope.calloc(1, sizeof(struct UvAddress));
  int status = uv_ip4_addr(
    host, port, (struct sockaddr_in *) &address.address
  );
  if (status < 0) {
    Scope.free(address);
    _uv_raise(%"ip4_addr", status);
  }
  address.length = sizeof(struct sockaddr_in);
  _uv_address_name(address, String.pool_current());
  return address;
}

UvAddress UvAddress.ip6(String host, int port) {
  if (!host || port < 0 || port > UINT16_MAX) {
    raise %(bad-arg (library "libuv") (operation "ip6")
            (reason "a numeric host and a valid port are required"));
  }
  UvAddress address = Scope.calloc(1, sizeof(struct UvAddress));
  int status = uv_ip6_addr(
    host, port, (struct sockaddr_in6 *) &address.address
  );
  if (status < 0) {
    Scope.free(address);
    _uv_raise(%"ip6_addr", status);
  }
  address.length = sizeof(struct sockaddr_in6);
  _uv_address_name(address, String.pool_current());
  return address;
}

String UvAddress.host(UvAddress address) {
  return address ? address.host : NULL;
}

int UvAddress.port(UvAddress address) {
  if (!address) return 0;
  int family = ((struct sockaddr *) &address.address)->sa_family;
  if (family == AF_INET) {
    struct sockaddr_in *ip4 = (struct sockaddr_in *) &address.address;
    return ntohs(ip4->sin_port);
  }
  if (family == AF_INET6) {
    struct sockaddr_in6 *ip6 = (struct sockaddr_in6 *) &address.address;
    return ntohs(ip6->sin6_port);
  }
  return 0;
}

int UvAddress.family(UvAddress address) {
  return address
    ? ((struct sockaddr *) &address.address)->sa_family
    : AF_UNSPEC;
}

int UvAddress.socket_type(UvAddress address) {
  return address ? address.socket_type : 0;
}

int UvAddress.protocol(UvAddress address) {
  return address ? address.protocol : 0;
}

unsigned int UvAddress.scope_id(UvAddress address) {
  if (!address || address.family() != AF_INET6) return 0;
  struct sockaddr_in6 *ip6 = (struct sockaddr_in6 *) &address.address;
  return ip6->sin6_scope_id;
}

String UvAddress.canonical_name(UvAddress address) {
  return address ? address.canonical_name : NULL;
}

const struct sockaddr *UvAddress.native(UvAddress address) {
  return address ? (struct sockaddr *) &address.address : NULL;
}

UvLookup UvLoop.lookup(UvLoop loop, String node, String service) {
  if (!loop || !loop.initialized || (!node && !service)) {
    raise %(bad-arg (library "libuv") (operation "lookup")
            (reason "a live loop and a node or service are required"));
  }
  UvLookup lookup = Scope.calloc(1, sizeof(struct UvLookup));
  lookup.loop = loop;
  lookup.owner_scope = *Scope.top();
  lookup.strings = String.pool_current();
  lookup.node = String.new(node);
  lookup.service = String.new(service);
  lookup.hints.ai_family = AF_UNSPEC;
  lookup.hints.ai_socktype = SOCK_STREAM;
  lookup.request.data = lookup;
  return lookup;
}

UvLookup UvLookup.hints(
  UvLookup lookup, int family, int socket_type, int transport, int flags) {
  if (!lookup) {
    raise %(bad-arg (library "libuv") (operation "lookup_hints")
            (reason "a lookup is required"));
  }
  if (lookup.started) {
    raise %(bad-state (library "libuv") (operation "lookup_hints")
            (reason "set hints before starting the lookup"));
  }
  with lookup.hints {
    memset(&_, 0, sizeof(_));
    _.ai_family = family;
    _.ai_socktype = socket_type;
    _.ai_protocol = transport;
    _.ai_flags = flags;
  }
  return lookup;
}

UvLookup UvLookup.start(
  UvLookup lookup, Var value, void (*fn)(UvLookup, Var)) {
  if (!lookup || !fn) {
    raise %(bad-arg (library "libuv") (operation "lookup_start")
            (reason "a lookup and callback are required"));
  }
  if (lookup.started) {
    raise %(bad-state (library "libuv") (operation "lookup_start")
            (reason "the lookup has already started"));
  }
  if (!lookup.loop || !lookup.loop.initialized) {
    raise %(bad-state (library "libuv") (operation "lookup_start")
            (reason "the lookup loop is closed"));
  }
  lookup.value = value;
  lookup.handler = fn;
  lookup.started = 1;
  int status = uv_getaddrinfo(
    &lookup.loop.loop, &lookup.request, _uv_lookup_callback,
    lookup.node, lookup.service, &lookup.hints
  );
  if (status < 0) {
    lookup.started = 0;
    lookup.handler = NULL;
    _uv_raise(%"getaddrinfo", status);
  }
  lookup.loop.pending_requests++;
  return lookup;
}

UvLookup UvLoop.resolve(
  UvLoop loop, String node, String service, Var value,
  void (*fn)(UvLookup, Var)) {
  return loop.lookup(node, service).start(value, fn);
}

int UvLookup.cancel(UvLookup lookup) {
  if (!lookup) {
    raise %(bad-arg (library "libuv") (operation "lookup_cancel")
            (reason "a lookup is required"));
  }
  if (!lookup.started) {
    raise %(bad-state (library "libuv") (operation "lookup_cancel")
            (reason "the lookup has not started"));
  }
  if (lookup.completed) return 0;
  int status = uv_cancel((uv_req_t *) &lookup.request);
  if (!status) return 1;
  if (status == UV_EBUSY) return 0;
  _uv_raise(%"getaddrinfo_cancel", status);
}

int UvLookup.cancelled(UvLookup lookup) {
  return lookup && lookup.completed && lookup.cancelled;
}

size_t UvLookup.count(UvLookup lookup) {
  if (!lookup || !lookup.completed) {
    raise %(bad-state (library "libuv") (operation "lookup_count")
            (reason "the lookup has not completed"));
  }
  if (lookup.status < 0 && !lookup.cancelled) {
    _uv_raise(%"getaddrinfo", lookup.status);
  }
  return lookup.count;
}

UvAddress UvLookup.address(UvLookup lookup, int index) {
  size_t count = lookup.count();
  if (index < 0 || (size_t) index >= count) {
    long size = (long) count;
    raise %(bad-arg (library "libuv") (operation "lookup_address")
            (index $index) (size $size));
  }
  return &lookup.addresses[index];
}

UvLoop UvLookup.loop(UvLookup lookup) {
  return lookup ? lookup.loop : NULL;
}

uv_getaddrinfo_t *UvLookup.native(UvLookup lookup) {
  return lookup ? &lookup.request : NULL;
}

static UvStream _uv_tcp_ready(UvTcp tcp, String operation) {
  if (!tcp) {
    raise %(bad-arg (library "libuv") (operation $operation)
            (reason "a TCP handle is required"));
  }
  UvStream stream = &tcp.stream;
  if (!stream.loop || !stream.loop.initialized || stream.closing ||
      stream.closed) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "the TCP handle or its loop is closed"));
  }
  return stream;
}

/*  Creates one TCP handle. Accepted connections use the same constructor,
    then uv_accept attaches the incoming stream to it.
*/
UvTcp UvLoop.tcp(UvLoop loop) {
  if (!loop || !loop.initialized) {
    raise %(bad-arg (library "libuv") (operation "tcp")
            (reason "a live loop is required"));
  }
  return _uv_tcp_new(loop);
}

UvTcp UvTcp.bind(UvTcp tcp, UvAddress address, unsigned flags) {
  _uv_tcp_ready(tcp, %"tcp_bind");
  if (!address || (address.family() != AF_INET &&
                   address.family() != AF_INET6)) {
    raise %(bad-arg (library "libuv") (operation "tcp_bind")
            (reason "an IPv4 or IPv6 address is required"));
  }
  int status = uv_tcp_bind(&tcp.tcp, address.native(), flags);
  if (status < 0) _uv_raise(%"tcp_bind", status);
  return tcp;
}

UvTcp UvTcp.connect(
  UvTcp tcp, UvAddress address, Var value, void (*fn)(UvTcp, Var)) {
  UvStream stream = _uv_tcp_ready(tcp, %"tcp_connect");
  if (!address || !fn) {
    raise %(bad-arg (library "libuv") (operation "tcp_connect")
            (reason "an address and callback are required"));
  }
  if (stream.connected || stream.connect_pending || stream.listening) {
    raise %(bad-state (library "libuv") (operation "tcp_connect")
            (reason "the TCP handle is already in use"));
  }
  tcp.connect_value = value;
  tcp.connect_handler = fn;
  stream.connected_fn = _uv_tcp_connected;
  stream.connect_operation = %"tcp_connect";
  int status = uv_tcp_connect(
    &stream.connect_request, &tcp.tcp, address.native(),
    _uv_stream_connect_callback
  );
  if (status < 0) {
    tcp.connect_handler = NULL;
    stream.connected_fn = NULL;
    _uv_raise(%"tcp_connect", status);
  }
  stream.connect_pending = 1;
  stream.loop.pending_requests++;
  return tcp;
}

/*  Accepts each pending connection before invoking `fn`. The accepted
    UvTcp belongs to the caller and remains independent of the listener.
*/
UvTcp UvTcp.listen(
  UvTcp tcp, int backlog, Var value, void (*fn)(UvTcp, UvTcp, Var)) {
  UvStream stream = _uv_tcp_ready(tcp, %"listen");
  if (!fn || backlog < 1) {
    raise %(bad-arg (library "libuv") (operation "listen")
            (reason "a positive backlog and callback are required"));
  }
  if (stream.connected || stream.connect_pending || stream.listening) {
    raise %(bad-state (library "libuv") (operation "listen")
            (reason "the TCP handle is already in use"));
  }
  tcp.listen_value = value;
  tcp.listen_handler = fn;
  stream.accept = _uv_tcp_accept;
  stream.listen_fn = _uv_tcp_listen;
  int status = uv_listen(
    stream.native, backlog, _uv_stream_listen_callback
  );
  if (status < 0) {
    tcp.listen_handler = NULL;
    stream.listen_fn = NULL;
    _uv_raise(%"listen", status);
  }
  stream.listening = 1;
  return tcp;
}

UvTcp UvTcp.read(UvTcp tcp, Var value, void (*fn)(UvTcp, Bytes, Var)) {
  UvStream stream = _uv_tcp_ready(tcp, %"read_start");
  if (!fn) {
    raise %(bad-arg (library "libuv") (operation "read_start")
            (reason "a callback is required"));
  }
  if (!stream.connected) {
    raise %(bad-state (library "libuv") (operation "read_start")
            (reason "the TCP handle is not connected"));
  }
  if (stream.read_eof) {
    raise %(bad-state (library "libuv") (operation "read_start")
            (reason "the TCP read side has reached EOF"));
  }
  if (stream.reading) {
    raise %(bad-state (library "libuv") (operation "read_start")
            (reason "reads have already started"));
  }
  tcp.read_value = value;
  tcp.read_handler = fn;
  stream.read_fn = _uv_tcp_read;
  _uv_stream_start_read(stream);
  return tcp;
}

UvTcp UvTcp.stop_read(UvTcp tcp) {
  UvStream stream = _uv_tcp_ready(tcp, %"read_stop");
  _uv_stream_stop_read(stream);
  return tcp;
}

static UvTcp _uv_tcp_write(UvTcp tcp, const void *bytes, size_t length) {
  UvStream stream = _uv_tcp_ready(tcp, %"write");
  if (!stream.connected) {
    raise %(bad-state (library "libuv") (operation "write")
            (reason "the TCP handle is not connected"));
  }
  if (stream.shutdown_pending || stream.shutdown_done) {
    raise %(bad-state (library "libuv") (operation "write")
            (reason "the TCP write side has shut down"));
  }
  _uv_stream_submit_write(stream, bytes, length);
  return tcp;
}

UvTcp UvTcp.write(UvTcp tcp, String text) {
  if (!text) {
    raise %(bad-arg (library "libuv") (operation "write")
            (reason "text is required"));
  }
  return _uv_tcp_write(tcp, text, (size_t) text.len());
}

UvTcp UvTcp.write_bytes(UvTcp tcp, Bytes bytes) {
  if (!bytes) {
    raise %(bad-arg (library "libuv") (operation "write")
            (reason "bytes are required"));
  }
  Block block = bytes;
  if (block.length && block.width > SIZE_MAX / block.length)
    raise %(size-limit (library "libuv") (operation "write"));
  return _uv_tcp_write(tcp, bytes, block.width * block.length);
}

UvTcp UvTcp.shutdown_write(UvTcp tcp) {
  UvStream stream = _uv_tcp_ready(tcp, %"shutdown");
  if (!stream.connected) {
    raise %(bad-state (library "libuv") (operation "shutdown")
            (reason "the TCP handle is not connected"));
  }
  _uv_stream_submit_shutdown(stream);
  return tcp;
}

UvTcp UvTcp.close(UvTcp tcp) {
  if (!tcp) return NULL;
  _uv_stream_close(&tcp.stream);
  return NULL;
}

static UvAddress _uv_tcp_address(UvTcp tcp, int peer) {
  UvStream stream = _uv_tcp_ready(
    tcp, peer ? %"tcp_getpeername" : %"tcp_getsockname"
  );
  UvAddress address = Scope.calloc(1, sizeof(struct UvAddress));
  int length = sizeof(address.address);
  int status = peer
    ? uv_tcp_getpeername(
        &tcp.tcp, (struct sockaddr *) &address.address, &length
      )
    : uv_tcp_getsockname(
        &tcp.tcp, (struct sockaddr *) &address.address, &length
      );
  if (status < 0) {
    Scope.free(address);
    _uv_raise(peer ? %"tcp_getpeername" : %"tcp_getsockname", status);
  }
  address.length = length;
  address.socket_type = SOCK_STREAM;
  address.protocol = IPPROTO_TCP;
  _uv_address_name(address, String.pool_current());
  (void) stream;
  return address;
}

UvAddress UvTcp.local_address(UvTcp tcp) {
  return _uv_tcp_address(tcp, 0);
}

UvAddress UvTcp.peer_address(UvTcp tcp) {
  return _uv_tcp_address(tcp, 1);
}

size_t UvTcp.write_queue_size(UvTcp tcp) {
  UvStream stream = _uv_tcp_ready(tcp, %"write_queue_size");
  return uv_stream_get_write_queue_size(stream.native);
}

UvLoop UvTcp.loop(UvTcp tcp) {
  return tcp ? tcp.stream.loop : NULL;
}

uv_tcp_t *UvTcp.native(UvTcp tcp) {
  return tcp ? &tcp.tcp : NULL;
}

static UvStream _uv_pipe_ready(UvPipe pipe, String operation) {
  if (!pipe) {
    raise %(bad-arg (library "libuv") (operation $operation)
            (reason "a pipe handle is required"));
  }
  UvStream stream = &pipe.stream;
  if (!stream.loop || !stream.loop.initialized || stream.closing ||
      stream.closed) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "the pipe handle or its loop is closed"));
  }
  return stream;
}

static void _uv_pipe_path(String name, String operation) {
  if (!name || !name.len() || memchr(name, '\0', name.len())) {
    raise %(bad-arg (library "libuv") (operation $operation)
            (reason "a filesystem path without embedded NUL is required"));
  }
}

UvPipe UvLoop.pipe(UvLoop loop) {
  if (!loop || !loop.initialized) {
    raise %(bad-arg (library "libuv") (operation "pipe")
            (reason "a live loop is required"));
  }
  return _uv_pipe_new(loop);
}

UvPipe UvPipe.bind(UvPipe pipe, String name) {
  _uv_pipe_ready(pipe, %"pipe_bind");
  _uv_pipe_path(name, %"pipe_bind");
  int status = uv_pipe_bind(&pipe.pipe, name);
  if (status < 0) _uv_raise(%"pipe_bind", status);
  return pipe;
}

UvPipe UvPipe.connect(
  UvPipe pipe, String name, Var value, void (*fn)(UvPipe, Var)) {
  UvStream stream = _uv_pipe_ready(pipe, %"pipe_connect");
  _uv_pipe_path(name, %"pipe_connect");
  if (!fn) {
    raise %(bad-arg (library "libuv") (operation "pipe_connect")
            (reason "a callback is required"));
  }
  if (stream.connected || stream.connect_pending || stream.listening) {
    raise %(bad-state (library "libuv") (operation "pipe_connect")
            (reason "the pipe handle is already in use"));
  }
  pipe.connect_value = value;
  pipe.connect_handler = fn;
  stream.connected_fn = _uv_pipe_connected;
  stream.connect_operation = %"pipe_connect";
  stream.connect_pending = 1;
  stream.loop.pending_requests++;
  uv_pipe_connect(
    &stream.connect_request, &pipe.pipe, name,
    _uv_stream_connect_callback
  );
  return pipe;
}

UvPipe UvPipe.listen(
  UvPipe pipe, int backlog, Var value, void (*fn)(UvPipe, UvPipe, Var)) {
  UvStream stream = _uv_pipe_ready(pipe, %"listen");
  if (!fn || backlog < 1) {
    raise %(bad-arg (library "libuv") (operation "listen")
            (reason "a positive backlog and callback are required"));
  }
  if (stream.connected || stream.connect_pending || stream.listening) {
    raise %(bad-state (library "libuv") (operation "listen")
            (reason "the pipe handle is already in use"));
  }
  pipe.listen_value = value;
  pipe.listen_handler = fn;
  stream.accept = _uv_pipe_accept;
  stream.listen_fn = _uv_pipe_listen;
  int status = uv_listen(
    stream.native, backlog, _uv_stream_listen_callback
  );
  if (status < 0) {
    pipe.listen_handler = NULL;
    stream.listen_fn = NULL;
    _uv_raise(%"listen", status);
  }
  stream.listening = 1;
  return pipe;
}

UvPipe UvPipe.read(UvPipe pipe, Var value, void (*fn)(UvPipe, Bytes, Var)) {
  UvStream stream = _uv_pipe_ready(pipe, %"read_start");
  if (!fn) {
    raise %(bad-arg (library "libuv") (operation "read_start")
            (reason "a callback is required"));
  }
  if (!stream.connected) {
    raise %(bad-state (library "libuv") (operation "read_start")
            (reason "the pipe handle is not connected"));
  }
  if (stream.read_eof) {
    raise %(bad-state (library "libuv") (operation "read_start")
            (reason "the pipe read side has reached EOF"));
  }
  if (stream.reading) {
    raise %(bad-state (library "libuv") (operation "read_start")
            (reason "reads have already started"));
  }
  pipe.read_value = value;
  pipe.read_handler = fn;
  stream.read_fn = _uv_pipe_read;
  _uv_stream_start_read(stream);
  return pipe;
}

UvPipe UvPipe.stop_read(UvPipe pipe) {
  UvStream stream = _uv_pipe_ready(pipe, %"read_stop");
  _uv_stream_stop_read(stream);
  return pipe;
}

static UvPipe _uv_pipe_write(UvPipe pipe, const void *bytes, size_t length) {
  UvStream stream = _uv_pipe_ready(pipe, %"write");
  if (!stream.connected) {
    raise %(bad-state (library "libuv") (operation "write")
            (reason "the pipe handle is not connected"));
  }
  if (stream.shutdown_pending || stream.shutdown_done) {
    raise %(bad-state (library "libuv") (operation "write")
            (reason "the pipe write side has shut down"));
  }
  _uv_stream_submit_write(stream, bytes, length);
  return pipe;
}

UvPipe UvPipe.write(UvPipe pipe, String text) {
  if (!text) {
    raise %(bad-arg (library "libuv") (operation "write")
            (reason "text is required"));
  }
  return _uv_pipe_write(pipe, text, (size_t) text.len());
}

UvPipe UvPipe.write_bytes(UvPipe pipe, Bytes bytes) {
  if (!bytes) {
    raise %(bad-arg (library "libuv") (operation "write")
            (reason "bytes are required"));
  }
  Block block = bytes;
  if (block.length && block.width > SIZE_MAX / block.length)
    raise %(size-limit (library "libuv") (operation "write"));
  return _uv_pipe_write(pipe, bytes, block.width * block.length);
}

UvPipe UvPipe.shutdown_write(UvPipe pipe) {
  UvStream stream = _uv_pipe_ready(pipe, %"shutdown");
  if (!stream.connected) {
    raise %(bad-state (library "libuv") (operation "shutdown")
            (reason "the pipe handle is not connected"));
  }
  _uv_stream_submit_shutdown(stream);
  return pipe;
}

UvPipe UvPipe.close(UvPipe pipe) {
  if (!pipe) return NULL;
  _uv_stream_close(&pipe.stream);
  return NULL;
}

static String _uv_pipe_name(UvPipe pipe, int peer) {
  _uv_pipe_ready(
    pipe, peer ? %"pipe_getpeername" : %"pipe_getsockname"
  );
  char byte = 0;
  char *buffer = &byte;
  size_t length = 1;
  int status = peer
    ? uv_pipe_getpeername(&pipe.pipe, buffer, &length)
    : uv_pipe_getsockname(&pipe.pipe, buffer, &length);
  int allocated = 0;
  if (status == UV_ENOBUFS) {
    if (!length || length > INT_MAX) {
      raise %(size-limit (library "libuv") (operation "pipe_name"));
    }
    buffer = Scope.malloc(length);
    allocated = 1;
    status = peer
      ? uv_pipe_getpeername(&pipe.pipe, buffer, &length)
      : uv_pipe_getsockname(&pipe.pipe, buffer, &length);
  }
  if (status < 0) {
    if (allocated) Scope.free(buffer);
    _uv_raise(peer ? %"pipe_getpeername" : %"pipe_getsockname", status);
  }
  if (length > INT_MAX || memchr(buffer, '\0', length)) {
    if (allocated) Scope.free(buffer);
    raise %(bad-enc (library "libuv") (operation "pipe_name"));
  }
  String name = String.new_len(buffer, (int) length);
  if (allocated) Scope.free(buffer);
  return name;
}

String UvPipe.local_name(UvPipe pipe) {
  return _uv_pipe_name(pipe, 0);
}

String UvPipe.peer_name(UvPipe pipe) {
  return _uv_pipe_name(pipe, 1);
}

size_t UvPipe.write_queue_size(UvPipe pipe) {
  UvStream stream = _uv_pipe_ready(pipe, %"write_queue_size");
  return uv_stream_get_write_queue_size(stream.native);
}

UvLoop UvPipe.loop(UvPipe pipe) {
  return pipe ? pipe.stream.loop : NULL;
}

uv_pipe_t *UvPipe.native(UvPipe pipe) {
  return pipe ? &pipe.pipe : NULL;
}

static UvUdp _uv_udp_ready(UvUdp udp, String operation) {
  if (!udp) {
    raise %(bad-arg (library "libuv") (operation $operation)
            (reason "a UDP handle is required"));
  }
  if (!udp.loop || !udp.loop.initialized || udp.closing || udp.closed) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "the UDP handle or its loop is closed"));
  }
  return udp;
}

static size_t _uv_udp_address_size(UvAddress address, String operation) {
  if (!address) {
    raise %(bad-arg (library "libuv") (operation $operation)
            (reason "an IP address is required"));
  }
  if (address.family() == AF_INET) return sizeof(struct sockaddr_in);
  if (address.family() == AF_INET6) return sizeof(struct sockaddr_in6);
  raise %(bad-arg (library "libuv") (operation $operation)
          (reason "an IPv4 or IPv6 address is required"));
}

static UvAddress _uv_udp_copy_address(
  UvUdp udp, const struct sockaddr *native) {
  size_t length = native && native->sa_family == AF_INET
    ? sizeof(struct sockaddr_in)
    : native && native->sa_family == AF_INET6
      ? sizeof(struct sockaddr_in6)
      : 0;
  if (!length) {
    raise %(bad-state (library "libuv") (operation "udp_receive")
            (reason "libuv returned an invalid source address"));
  }
  UvAddress address = Scope.calloc_in(
    &udp.owner_scope, 1, sizeof(struct UvAddress)
  );
  memcpy(&address.address, native, length);
  address.length = length;
  address.socket_type = SOCK_DGRAM;
  address.protocol = IPPROTO_UDP;
  _uv_address_name(address, udp.strings);
  return address;
}

static void _uv_udp_close_callback(uv_handle_t *handle) {
  UvUdp udp = handle ? handle->data : NULL;
  if (!udp) return;
  udp.receiving = 0;
  udp.closed = 1;
}

static void _uv_udp_close(UvUdp udp) {
  if (!udp || udp.closing || udp.closed) return;
  udp.closing = 1;
  if (udp.receiving) uv_udp_recv_stop(&udp.udp);
  udp.receiving = 0;
  uv_handle_t *handle = (uv_handle_t *) &udp.udp;
  if (!uv_is_closing(handle)) uv_close(handle, _uv_udp_close_callback);
}

static void _uv_udp_fail(UvUdp udp, String operation, int status) {
  if (!udp) return;
  _uv_udp_close(udp);
  try _uv_raise(operation, status);
  catch %(?cause *detail): {
    _uv_callback_failed(udp.loop, cause, detail);
  }
}

static void _uv_udp_alloc(
  uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  UvUdp udp = handle ? handle->data : NULL;
  size_t limit = udp ? udp.receive_limit : 0;
  buffer->base = limit ? malloc(limit) : NULL;
  buffer->len = buffer->base ? limit : 0;
  (void) suggested;
}

static void _uv_udp_receive_callback(
  uv_udp_t *native, ssize_t count, const uv_buf_t *buffer,
  const struct sockaddr *source, unsigned flags) {
  UvUdp udp = native ? native->data : NULL;
  if (!udp) {
    free(buffer ? buffer->base : NULL);
    return;
  }
  if (!count && !source) {
    free(buffer ? buffer->base : NULL);
    return;
  }
  if (count < 0) {
    free(buffer ? buffer->base : NULL);
    udp.receiving = 0;
    _uv_udp_fail(udp, %"udp_receive", (int) count);
    return;
  }

  Bytes bytes = NULL;
  UvAddress address = NULL;
  try {
    bytes = Bytes.new(1);
    if (count) bytes = bytes.append(buffer->base, (size_t) count);
    bytes.block().move_to(&udp.owner_scope);
    address = _uv_udp_copy_address(udp, source);
  }
  catch %(?cause *detail): {
    free(buffer ? buffer->base : NULL);
    _uv_udp_close(udp);
    _uv_callback_failed(udp.loop, cause, detail);
    return;
  }
  free(buffer ? buffer->base : NULL);
  try udp.receive_handler(
    udp, bytes, address, flags, udp.receive_value
  );
  catch %(?cause *detail): {
    _uv_udp_close(udp);
    _uv_callback_failed(udp.loop, cause, detail);
  }
}

static void _uv_udp_send_callback(uv_udp_send_t *request, int status) {
  UvUdpSend send = request ? request->data : NULL;
  if (!send) return;
  UvUdp udp = send.udp;
  udp.loop.pending_requests--;
  Scope.free(send.bytes);
  Scope.free(send);
  if (status < 0 && !(status == UV_ECANCELED && udp.closing))
    _uv_udp_fail(udp, %"udp_send", status);
}

UvUdp UvLoop.udp(UvLoop loop) {
  if (!loop || !loop.initialized) {
    raise %(bad-arg (library "libuv") (operation "udp")
            (reason "a live loop is required"));
  }
  UvUdp udp = Scope.calloc(1, sizeof(struct UvUdp));
  int status = uv_udp_init(&loop.loop, &udp.udp);
  if (status < 0) {
    Scope.free(udp);
    _uv_raise(%"udp_init", status);
  }
  udp.loop = loop;
  udp.owner_scope = *Scope.top();
  udp.strings = String.pool_current();
  udp.receive_limit = 64 * 1024;
  udp.udp.data = udp;
  return udp;
}

UvUdp UvUdp.bind(UvUdp udp, UvAddress address, unsigned flags) {
  _uv_udp_ready(udp, %"udp_bind");
  _uv_udp_address_size(address, %"udp_bind");
  int status = uv_udp_bind(&udp.udp, address.native(), flags);
  if (status < 0) _uv_raise(%"udp_bind", status);
  return udp;
}

UvUdp UvUdp.connect(UvUdp udp, UvAddress address) {
  _uv_udp_ready(udp, %"udp_connect");
  _uv_udp_address_size(address, %"udp_connect");
  int status = uv_udp_connect(&udp.udp, address.native());
  if (status < 0) _uv_raise(%"udp_connect", status);
  return udp;
}

static UvUdp _uv_udp_send(
  UvUdp udp, UvAddress target, const void *bytes, size_t length) {
  _uv_udp_ready(udp, %"udp_send");
  size_t target_length = target
    ? _uv_udp_address_size(target, %"udp_send")
    : 0;
  if (length > UINT_MAX) {
    raise %(size-limit (library "libuv") (operation "udp_send")
            (length $length));
  }
  UvUdpSend send = Scope.calloc_in(
    &udp.owner_scope, 1, sizeof(struct UvUdpSend)
  );
  send.udp = udp;
  send.bytes = length
    ? Scope.memdup_in(&udp.owner_scope, bytes, length)
    : Scope.malloc_in(&udp.owner_scope, 1);
  if (target_length) {
    memcpy(&send.address, target.native(), target_length);
  }
  send.request.data = send;
  uv_buf_t buffer = uv_buf_init(send.bytes, length);
  int status = uv_udp_send(
    &send.request, &udp.udp, &buffer, 1,
    target_length ? (struct sockaddr *) &send.address : NULL,
    _uv_udp_send_callback
  );
  if (status < 0) {
    Scope.free(send.bytes);
    Scope.free(send);
    _uv_raise(%"udp_send", status);
  }
  udp.loop.pending_requests++;
  return udp;
}

UvUdp UvUdp.send(UvUdp udp, UvAddress target, String text) {
  if (!text) {
    raise %(bad-arg (library "libuv") (operation "udp_send")
            (reason "text is required"));
  }
  return _uv_udp_send(udp, target, text, (size_t) text.len());
}

UvUdp UvUdp.send_bytes(UvUdp udp, UvAddress target, Bytes bytes) {
  if ((void *) bytes == NULL) {
    raise %(bad-arg (library "libuv") (operation "udp_send")
            (reason "bytes are required"));
  }
  Block block = bytes;
  if (block.length && block.width > SIZE_MAX / block.length) {
    raise %(size-limit (library "libuv") (operation "udp_send"));
  }
  return _uv_udp_send(
    udp, target, bytes, block.width * block.length
  );
}

UvUdp UvUdp.max_receive(UvUdp udp, size_t bytes) {
  _uv_udp_ready(udp, %"udp_max_receive");
  if (!bytes) {
    raise %(bad-arg (library "libuv") (operation "udp_max_receive")
            (reason "a positive limit is required"));
  }
  if (udp.receiving) {
    raise %(bad-state (library "libuv") (operation "udp_max_receive")
            (reason "stop receiving before changing the limit"));
  }
  udp.receive_limit = bytes;
  return udp;
}

UvUdp UvUdp.receive(
  UvUdp udp, Var value, void (*fn)(UvUdp, Bytes, UvAddress, unsigned, Var)) {
  _uv_udp_ready(udp, %"udp_receive");
  if (!fn) {
    raise %(bad-arg (library "libuv") (operation "udp_receive")
            (reason "a callback is required"));
  }
  if (udp.receiving) {
    raise %(bad-state (library "libuv") (operation "udp_receive")
            (reason "receiving has already started"));
  }
  udp.receive_value = value;
  udp.receive_handler = fn;
  int status = uv_udp_recv_start(
    &udp.udp, _uv_udp_alloc, _uv_udp_receive_callback
  );
  if (status < 0) _uv_raise(%"udp_recv_start", status);
  udp.receiving = 1;
  return udp;
}

UvUdp UvUdp.stop(UvUdp udp) {
  _uv_udp_ready(udp, %"udp_recv_stop");
  if (!udp.receiving) return udp;
  int status = uv_udp_recv_stop(&udp.udp);
  if (status < 0) _uv_raise(%"udp_recv_stop", status);
  udp.receiving = 0;
  return udp;
}

UvUdp UvUdp.close(UvUdp udp) {
  if (!udp) return NULL;
  _uv_udp_close(udp);
  return NULL;
}

static UvAddress _uv_udp_address(UvUdp udp, int peer) {
  _uv_udp_ready(
    udp, peer ? %"udp_getpeername" : %"udp_getsockname"
  );
  UvAddress address = Scope.calloc(1, sizeof(struct UvAddress));
  int length = sizeof(address.address);
  int status = peer
    ? uv_udp_getpeername(
        &udp.udp, (struct sockaddr *) &address.address, &length
      )
    : uv_udp_getsockname(
        &udp.udp, (struct sockaddr *) &address.address, &length
      );
  if (status < 0) {
    Scope.free(address);
    _uv_raise(peer ? %"udp_getpeername" : %"udp_getsockname", status);
  }
  address.length = length;
  address.socket_type = SOCK_DGRAM;
  address.protocol = IPPROTO_UDP;
  _uv_address_name(address, String.pool_current());
  return address;
}

UvAddress UvUdp.local_address(UvUdp udp) {
  return _uv_udp_address(udp, 0);
}

UvAddress UvUdp.peer_address(UvUdp udp) {
  return _uv_udp_address(udp, 1);
}

size_t UvUdp.send_queue_size(UvUdp udp) {
  _uv_udp_ready(udp, %"udp_send_queue_size");
  return uv_udp_get_send_queue_size(&udp.udp);
}

size_t UvUdp.send_queue_count(UvUdp udp) {
  _uv_udp_ready(udp, %"udp_send_queue_count");
  return uv_udp_get_send_queue_count(&udp.udp);
}

UvLoop UvUdp.loop(UvUdp udp) {
  return udp ? udp.loop : NULL;
}

uv_udp_t *UvUdp.native(UvUdp udp) {
  return udp ? &udp.udp : NULL;
}

static String _uv_fs_operation_name(uv_fs_type operation) {
  switch (operation) {
    case UV_FS_OPEN: return %"fs_open";
    case UV_FS_CLOSE: return %"fs_close";
    case UV_FS_READ: return %"fs_read";
    case UV_FS_WRITE: return %"fs_write";
    case UV_FS_STAT: return %"fs_stat";
    case UV_FS_SCANDIR: return %"fs_scandir";
    default: return %"fs";
  }
}

static UvFs _uv_fs_new_in(
  UvLoop loop, uv_fs_type operation, Var value, UvFsFn handler, Scope *owner) {
  if (!loop || !loop.initialized || !handler) {
    raise %(bad-arg (library "libuv") (operation "fs")
            (reason "a live loop and a callback are required"));
  }
  UvFs fs = Scope.calloc_in(owner, 1, sizeof(struct UvFs));
  fs.loop = loop;
  fs.owner_scope = *owner;
  fs.strings = String.pool_current();
  fs.value = value;
  fs.handler = handler;
  fs.operation = operation;
  fs.phase = UV_FS_PHASE_SINGLE;
  fs.descriptor = -1;
  fs.request.data = fs;
  return fs;
}

static UvFs _uv_fs_new(
  UvLoop loop, uv_fs_type operation, Var value, UvFsFn handler) {
  return _uv_fs_new_in(
    loop, operation, value, handler, Scope.top()
  );
}

static void _uv_fs_started(UvFs fs) {
  fs.started = 1;
  fs.loop.pending_requests++;
}

static void _uv_fs_submit_failed(UvFs fs, String operation, int status) {
  uv_fs_req_cleanup(&fs.request);
  Scope.free(fs.buffer);
  fs.buffer = NULL;
  if (fs.file && fs.file.pending) fs.file.pending--;
  if (fs.file && fs.operation == UV_FS_CLOSE) fs.file.closing = 0;
  _uv_raise(operation, status);
}

static void _uv_fs_reset_request(UvFs fs) {
  memset(&fs.request, 0, sizeof(fs.request));
  fs.request.data = fs;
}

static void _uv_fs_copy_bytes(UvFs fs, size_t length) {
  Bytes bytes = Bytes.new(1);
  if (length) bytes = bytes.append(fs.buffer, length);
  bytes.block().move_to(&fs.owner_scope);
  fs.bytes = bytes;
}

static void _uv_fs_copy_scan(UvFs fs) {
  size_t capacity = fs.request.result > 0
    ? (size_t) fs.request.result
    : 0;
  fs.entries = Scope.calloc_in(
    &fs.owner_scope, capacity, sizeof(struct UvDirEntry)
  );
  uv_dirent_t entry;
  int status;
  while (!(status = uv_fs_scandir_next(&fs.request, &entry))) {
    if (fs.entry_count >= capacity) {
      raise %(bad-state (library "libuv") (operation "fs_scandir")
              (reason "libuv returned more entries than it reported"));
    }
    fs.entries[fs.entry_count].name = _uv_address_string(
      fs.strings, entry.name
    );
    fs.entries[fs.entry_count].type = entry.type;
    fs.entry_count++;
  }
  if (status != UV_EOF) _uv_raise(%"fs_scandir_next", status);
}

static void _uv_fs_complete_file(UvFs fs) {
  UvFile file = fs.file;
  if (!file) return;
  if (file.pending) file.pending--;
  if (fs.operation != UV_FS_CLOSE) return;
  file.closing = 0;
  if (fs.result == UV_ECANCELED) return;
  file.closed = 1;
  file.descriptor = -1;
  if (file.loop.open_files) file.loop.open_files--;
}

static int _uv_fs_sync_close(uv_file descriptor);

static void _uv_fs_finish(UvFs fs) {
  fs.completed = 1;
  if (fs.loop.pending_requests) fs.loop.pending_requests--;
  Scope.free(fs.buffer);
  fs.buffer = NULL;
  if (fs.failure_cause) {
    _uv_callback_failed(fs.loop, fs.failure_cause, fs.failure_detail);
    return;
  }
  if (fs.status < 0 && !fs.cancelled) {
    String operation = fs.error_operation
      ? fs.error_operation
      : _uv_fs_operation_name(fs.operation);
    try _uv_raise(operation, fs.status);
    catch %(?cause *detail): {
      _uv_callback_failed(fs.loop, cause, detail);
    }
    return;
  }
  if (fs.limit_exceeded) {
    size_t limit = fs.limit;
    try raise %(size-limit (library "libuv")
                (operation "read_file") (limit $limit));
    catch %(?cause *detail): {
      _uv_callback_failed(fs.loop, cause, detail);
    }
    return;
  }
  try fs.handler(fs, fs.value);
  catch %(?cause *detail): {
    _uv_callback_failed(fs.loop, cause, detail);
  }
}

static void _uv_fs_single_callback(uv_fs_t *request) {
  UvFs fs = request ? request->data : NULL;
  if (!fs) return;
  fs.result = request->result;
  fs.status = request->result < 0 ? (int) request->result : 0;
  fs.cancelled = request->result == UV_ECANCELED;

  try {
    if (!fs.status && fs.operation == UV_FS_OPEN) {
      UvFile file = Scope.calloc_in(
        &fs.owner_scope, 1, sizeof(struct UvFile)
      );
      file.loop = fs.loop;
      file.owner_scope = fs.owner_scope;
      file.descriptor = (uv_file) fs.result;
      fs.file = file;
      fs.loop.open_files++;
    }
    else if (!fs.status && fs.operation == UV_FS_READ) {
      _uv_fs_copy_bytes(fs, (size_t) fs.result);
    }
    else if (!fs.status && fs.operation == UV_FS_STAT) {
      memcpy(&fs.stat.value, &request->statbuf, sizeof(uv_stat_t));
    }
    else if (!fs.status && fs.operation == UV_FS_SCANDIR) {
      _uv_fs_copy_scan(fs);
      fs.result = (ssize_t) fs.entry_count;
    }
  }
  catch %(?cause *detail): {
    uv_fs_req_cleanup(request);
    if (fs.operation == UV_FS_OPEN && fs.result >= 0)
      _uv_fs_sync_close((uv_file) fs.result);
    _uv_fs_complete_file(fs);
    Scope.free(fs.buffer);
    fs.buffer = NULL;
    fs.completed = 1;
    if (fs.loop.pending_requests) fs.loop.pending_requests--;
    _uv_callback_failed(fs.loop, cause, detail);
    return;
  }
  uv_fs_req_cleanup(request);
  _uv_fs_complete_file(fs);
  _uv_fs_finish(fs);
}

static int _uv_fs_sync_close(uv_file descriptor) {
  uv_fs_t request = { 0 };
  int status = uv_fs_close(NULL, &request, descriptor, NULL);
  uv_fs_req_cleanup(&request);
  return status;
}

static void _uv_fs_whole_callback(uv_fs_t *request);

static void _uv_fs_whole_closed(UvFs fs, ssize_t result) {
  if (fs.loop.open_files) fs.loop.open_files--;
  fs.descriptor = -1;
  if (result < 0 && !fs.status && !fs.cancelled &&
      !fs.limit_exceeded && !fs.failure_cause) {
    fs.status = (int) result;
    fs.result = result;
    fs.error_operation = %"fs_close";
  }
  if (!fs.status && !fs.cancelled &&
      !fs.limit_exceeded && !fs.failure_cause)
    fs.result = fs.operation == UV_FS_READ
      ? (ssize_t) fs.bytes.len()
      : (ssize_t) fs.offset;
  _uv_fs_finish(fs);
}

static void _uv_fs_whole_close(UvFs fs) {
  fs.phase = UV_FS_PHASE_CLOSE;
  memset(&fs.close_request, 0, sizeof(fs.close_request));
  fs.close_request.data = fs;
  int status = uv_fs_close(
    &fs.loop.loop, &fs.close_request, fs.descriptor,
    _uv_fs_whole_callback
  );
  if (status >= 0) return;
  uv_fs_req_cleanup(&fs.close_request);
  int close_status = _uv_fs_sync_close(fs.descriptor);
  if (fs.loop.open_files) fs.loop.open_files--;
  fs.descriptor = -1;
  if (!fs.status && !fs.cancelled &&
      !fs.limit_exceeded && !fs.failure_cause) {
    fs.status = status;
    fs.result = status;
    fs.error_operation = %"fs_close";
  }
  if (close_status < 0 && !fs.status && !fs.cancelled &&
      !fs.limit_exceeded && !fs.failure_cause) {
    fs.status = close_status;
    fs.error_operation = %"fs_close";
  }
  _uv_fs_finish(fs);
}

static void _uv_fs_whole_transfer(UvFs fs) {
  fs.phase = UV_FS_PHASE_TRANSFER;
  _uv_fs_reset_request(fs);
  int status;
  if (fs.operation == UV_FS_READ) {
    size_t used = fs.bytes.len();
    size_t available = used < fs.limit ? fs.limit - used : 0;
    size_t length = available >= 64 * 1024 ? 64 * 1024 : available + 1;
    uv_buf_t buffer = uv_buf_init(fs.buffer, (unsigned) length);
    status = uv_fs_read(
      &fs.loop.loop, &fs.request, fs.descriptor, &buffer, 1,
      (int64_t) used, _uv_fs_whole_callback
    );
  }
  else {
    size_t remaining = fs.buffer_length - fs.offset;
    if (remaining > 64 * 1024) remaining = 64 * 1024;
    uv_buf_t buffer = uv_buf_init(
      fs.buffer + fs.offset, (unsigned) remaining
    );
    status = uv_fs_write(
      &fs.loop.loop, &fs.request, fs.descriptor, &buffer, 1,
      (int64_t) fs.offset, _uv_fs_whole_callback
    );
  }
  if (status >= 0) return;
  uv_fs_req_cleanup(&fs.request);
  fs.status = status;
  fs.result = status;
  fs.error_operation = _uv_fs_operation_name(fs.operation);
  _uv_fs_whole_close(fs);
}

static void _uv_fs_whole_callback(uv_fs_t *request) {
  UvFs fs = request ? request->data : NULL;
  if (!fs) return;
  ssize_t result = request->result;
  uv_fs_req_cleanup(request);

  if (fs.phase == UV_FS_PHASE_CLOSE) {
    _uv_fs_whole_closed(fs, result);
    return;
  }
  if (result == UV_ECANCELED) {
    fs.cancelled = 1;
    fs.status = UV_ECANCELED;
    fs.result = UV_ECANCELED;
    if (fs.descriptor >= 0) _uv_fs_whole_close(fs);
    else {
      fs.result = UV_ECANCELED;
      _uv_fs_finish(fs);
    }
    return;
  }
  if (result < 0) {
    fs.status = (int) result;
    fs.result = result;
    fs.error_operation = fs.phase == UV_FS_PHASE_OPEN
      ? %"fs_open"
      : _uv_fs_operation_name(fs.operation);
    if (fs.descriptor >= 0) _uv_fs_whole_close(fs);
    else {
      fs.result = result;
      _uv_fs_finish(fs);
    }
    return;
  }
  if (fs.phase == UV_FS_PHASE_OPEN) {
    fs.descriptor = (uv_file) result;
    fs.loop.open_files++;
    _uv_fs_whole_transfer(fs);
    return;
  }

  if (fs.operation == UV_FS_READ) {
    if (!result) {
      _uv_fs_whole_close(fs);
      return;
    }
    size_t count = (size_t) result;
    size_t used = fs.bytes.len();
    if (count > fs.limit - used) {
      fs.limit_exceeded = 1;
      fs.result = UV_ENOBUFS;
      _uv_fs_whole_close(fs);
      return;
    }
    try fs.bytes = fs.bytes.append(fs.buffer, count);
    catch %(?cause *detail): {
      fs.failure_cause = cause;
      fs.result = UV_ENOMEM;
      try fs.failure_detail = Error.snapshot(detail);
      catch %(?snapcause *): {
        fs.failure_cause = snapcause;
        fs.failure_detail = NULL;
      }
      _uv_fs_whole_close(fs);
      return;
    }
    _uv_fs_whole_transfer(fs);
    return;
  }

  if (!result) {
    if (fs.offset == fs.buffer_length) {
      _uv_fs_whole_close(fs);
      return;
    }
    fs.status = UV_EIO;
    fs.result = UV_EIO;
    fs.error_operation = %"fs_write";
    _uv_fs_whole_close(fs);
    return;
  }
  fs.offset += (size_t) result;
  if (fs.offset < fs.buffer_length) _uv_fs_whole_transfer(fs);
  else _uv_fs_whole_close(fs);
}

UvFs UvLoop.open(
  UvLoop loop, String path, int flags, int mode, Var value,
  void (*fn)(UvFs, Var)) {
  if (!path || !path.len()) {
    raise %(bad-arg (library "libuv") (operation "fs_open")
            (reason "a nonempty path is required"));
  }
  UvFs fs = _uv_fs_new(loop, UV_FS_OPEN, value, fn);
  fs.path = String.new_in(fs.strings, path, path.len());
  int status = uv_fs_open(
    &loop.loop, &fs.request, fs.path, flags, mode,
    _uv_fs_single_callback
  );
  if (status < 0) _uv_fs_submit_failed(fs, %"fs_open", status);
  _uv_fs_started(fs);
  return fs;
}

static UvFile _uv_file_ready(UvFile file, String operation) {
  if (!file) {
    raise %(bad-arg (library "libuv") (operation $operation)
            (reason "a file is required"));
  }
  if (!file.loop || !file.loop.initialized || file.closing || file.closed) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "the file or its loop is closed"));
  }
  return file;
}

UvFs UvFile.read(
  UvFile file, size_t length, int64_t offset, Var value,
  void (*fn)(UvFs, Var)) {
  _uv_file_ready(file, %"fs_read");
  if (length > UINT_MAX) {
    raise %(size-limit (library "libuv") (operation "fs_read")
            (length $length));
  }
  UvFs fs = _uv_fs_new_in(
    file.loop, UV_FS_READ, value, fn, &file.owner_scope
  );
  fs.file = file;
  fs.buffer_length = length;
  fs.buffer = Scope.malloc_in(&fs.owner_scope, length ? length : 1);
  uv_buf_t buffer = uv_buf_init(fs.buffer, (unsigned) length);
  file.pending++;
  int status = uv_fs_read(
    &file.loop.loop, &fs.request, file.descriptor, &buffer, 1,
    offset, _uv_fs_single_callback
  );
  if (status < 0) _uv_fs_submit_failed(fs, %"fs_read", status);
  _uv_fs_started(fs);
  return fs;
}

static UvFs _uv_file_write(
  UvFile file, const void *bytes, size_t length, int64_t offset, Var value,
  UvFsFn fn) {
  _uv_file_ready(file, %"fs_write");
  if (length > UINT_MAX) {
    raise %(size-limit (library "libuv") (operation "fs_write")
            (length $length));
  }
  UvFs fs = _uv_fs_new_in(
    file.loop, UV_FS_WRITE, value, fn, &file.owner_scope
  );
  fs.file = file;
  fs.buffer_length = length;
  fs.buffer = length
    ? Scope.memdup_in(&fs.owner_scope, bytes, length)
    : Scope.malloc_in(&fs.owner_scope, 1);
  uv_buf_t buffer = uv_buf_init(fs.buffer, (unsigned) length);
  file.pending++;
  int status = uv_fs_write(
    &file.loop.loop, &fs.request, file.descriptor, &buffer, 1,
    offset, _uv_fs_single_callback
  );
  if (status < 0) _uv_fs_submit_failed(fs, %"fs_write", status);
  _uv_fs_started(fs);
  return fs;
}

UvFs UvFile.write(
  UvFile file, String text, int64_t offset, Var value, void (*fn)(UvFs, Var)) {
  if (!text) {
    raise %(bad-arg (library "libuv") (operation "fs_write")
            (reason "text is required"));
  }
  return _uv_file_write(file, text, text.len(), offset, value, fn);
}

UvFs UvFile.write_bytes(
  UvFile file, Bytes bytes, int64_t offset, Var value, void (*fn)(UvFs, Var)) {
  if ((void *) bytes == NULL) {
    raise %(bad-arg (library "libuv") (operation "fs_write")
            (reason "bytes are required"));
  }
  Block block = bytes;
  if (block.length && block.width > SIZE_MAX / block.length) {
    raise %(size-limit (library "libuv") (operation "fs_write"));
  }
  return _uv_file_write(
    file, bytes, block.width * block.length, offset, value, fn
  );
}

UvFs UvFile.close(UvFile file, Var value, void (*fn)(UvFs, Var)) {
  _uv_file_ready(file, %"fs_close");
  if (file.pending) {
    size_t pending = file.pending;
    raise %(bad-state (library "libuv") (operation "fs_close")
            (reason "the file has pending operations")
            (pending $pending));
  }
  UvFs fs = _uv_fs_new_in(
    file.loop, UV_FS_CLOSE, value, fn, &file.owner_scope
  );
  fs.file = file;
  file.pending++;
  file.closing = 1;
  int status = uv_fs_close(
    &file.loop.loop, &fs.request, file.descriptor,
    _uv_fs_single_callback
  );
  if (status < 0) _uv_fs_submit_failed(fs, %"fs_close", status);
  _uv_fs_started(fs);
  return fs;
}

UvLoop UvFile.loop(UvFile file) {
  return file ? file.loop : NULL;
}

uv_file UvFile.native(UvFile file) {
  _uv_file_ready(file, %"file_native");
  return file.descriptor;
}

static UvFs _uv_fs_whole(
  UvLoop loop, String path, uv_fs_type operation, const void *bytes,
  size_t length, size_t limit, int mode, Var value, UvFsFn fn) {
  String operation_name = _uv_fs_operation_name(operation);
  if (!path || !path.len()) {
    raise %(bad-arg (library "libuv")
            (operation $operation_name)
            (reason "a nonempty path is required"));
  }
  UvFs fs = _uv_fs_new(loop, operation, value, fn);
  fs.phase = UV_FS_PHASE_OPEN;
  fs.path = String.new_in(fs.strings, path, path.len());
  fs.limit = limit;
  if (operation == UV_FS_READ) {
    fs.bytes = Bytes.new(1);
    fs.bytes.block().move_to(&fs.owner_scope);
    fs.buffer = Scope.malloc_in(&fs.owner_scope, 64 * 1024);
  }
  else {
    fs.buffer_length = length;
    fs.buffer = length
      ? Scope.memdup_in(&fs.owner_scope, bytes, length)
      : Scope.malloc_in(&fs.owner_scope, 1);
  }
  int flags = operation == UV_FS_READ
    ? UV_FS_O_RDONLY
    : UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_TRUNC;
  int status = uv_fs_open(
    &loop.loop, &fs.request, fs.path, flags, mode,
    _uv_fs_whole_callback
  );
  if (status < 0) _uv_fs_submit_failed(fs, %"fs_open", status);
  _uv_fs_started(fs);
  return fs;
}

UvFs UvLoop.read_file(
  UvLoop loop, String path, size_t limit, Var value, void (*fn)(UvFs, Var)) {
  return _uv_fs_whole(
    loop, path, UV_FS_READ, NULL, 0, limit, 0, value, fn
  );
}

UvFs UvLoop.write_file(
  UvLoop loop, String path, String text, Var value, void (*fn)(UvFs, Var)) {
  if (!text) {
    raise %(bad-arg (library "libuv") (operation "write_file")
            (reason "text is required"));
  }
  return _uv_fs_whole(
    loop, path, UV_FS_WRITE, text, text.len(), 0, 0666, value, fn
  );
}

UvFs UvLoop.write_file_bytes(
  UvLoop loop, String path, Bytes bytes, Var value, void (*fn)(UvFs, Var)) {
  if ((void *) bytes == NULL) {
    raise %(bad-arg (library "libuv") (operation "write_file")
            (reason "bytes are required"));
  }
  Block block = bytes;
  if (block.length && block.width > SIZE_MAX / block.length) {
    raise %(size-limit (library "libuv") (operation "write_file"));
  }
  return _uv_fs_whole(
    loop, path, UV_FS_WRITE, bytes, block.width * block.length,
    0, 0666, value, fn
  );
}

UvFs UvLoop.stat(UvLoop loop, String path, Var value, void (*fn)(UvFs, Var)) {
  if (!path || !path.len()) {
    raise %(bad-arg (library "libuv") (operation "fs_stat")
            (reason "a nonempty path is required"));
  }
  UvFs fs = _uv_fs_new(loop, UV_FS_STAT, value, fn);
  fs.path = String.new_in(fs.strings, path, path.len());
  int status = uv_fs_stat(
    &loop.loop, &fs.request, fs.path, _uv_fs_single_callback
  );
  if (status < 0) _uv_fs_submit_failed(fs, %"fs_stat", status);
  _uv_fs_started(fs);
  return fs;
}

UvFs UvLoop.scan(UvLoop loop, String path, Var value, void (*fn)(UvFs, Var)) {
  if (!path || !path.len()) {
    raise %(bad-arg (library "libuv") (operation "fs_scandir")
            (reason "a nonempty path is required"));
  }
  UvFs fs = _uv_fs_new(loop, UV_FS_SCANDIR, value, fn);
  fs.path = String.new_in(fs.strings, path, path.len());
  int status = uv_fs_scandir(
    &loop.loop, &fs.request, fs.path, 0, _uv_fs_single_callback
  );
  if (status < 0) _uv_fs_submit_failed(fs, %"fs_scandir", status);
  _uv_fs_started(fs);
  return fs;
}

int UvFs.cancel(UvFs fs) {
  if (!fs) {
    raise %(bad-arg (library "libuv") (operation "fs_cancel")
            (reason "a filesystem request is required"));
  }
  if (!fs.started) {
    raise %(bad-state (library "libuv") (operation "fs_cancel")
            (reason "the filesystem request has not started"));
  }
  if (fs.completed || fs.phase == UV_FS_PHASE_CLOSE) return 0;
  int status = uv_cancel((uv_req_t *) &fs.request);
  if (!status) return 1;
  if (status == UV_EBUSY) return 0;
  _uv_raise(%"fs_cancel", status);
}

int UvFs.cancelled(UvFs fs) {
  return fs && fs.completed && fs.cancelled;
}

static UvFs _uv_fs_completed(UvFs fs, String operation) {
  if (!fs || !fs.completed) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "the filesystem request has not completed"));
  }
  return fs;
}

static void _uv_fs_check_failure(UvFs fs) {
  if (fs.failure_cause)
    Error.raise(fs.failure_cause, fs.failure_detail);
  if (fs.limit_exceeded) {
    size_t limit = fs.limit;
    raise %(size-limit (library "libuv")
            (operation "read_file") (limit $limit));
  }
  if (fs.status < 0 && !fs.cancelled) {
    _uv_raise(
      fs.error_operation ? fs.error_operation
                         : _uv_fs_operation_name(fs.operation),
      fs.status
    );
  }
}

static UvFs _uv_fs_result_type(
  UvFs fs, uv_fs_type expected, String operation) {
  _uv_fs_completed(fs, operation);
  if (fs.operation != expected || fs.cancelled) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "the request has no such result"));
  }
  _uv_fs_check_failure(fs);
  return fs;
}

uv_fs_type UvFs.operation(UvFs fs) {
  return fs ? fs.operation : UV_FS_UNKNOWN;
}

ssize_t UvFs.result(UvFs fs) {
  _uv_fs_completed(fs, %"fs_result");
  return fs.result;
}

UvFile UvFs.file(UvFs fs) {
  return _uv_fs_result_type(fs, UV_FS_OPEN, %"fs_file").file;
}

Bytes UvFs.bytes(UvFs fs) {
  return _uv_fs_result_type(fs, UV_FS_READ, %"fs_bytes").bytes;
}

UvStat UvFs.stat(UvFs fs) {
  _uv_fs_result_type(fs, UV_FS_STAT, %"fs_stat_result");
  return &fs.stat;
}

size_t UvFs.entry_count(UvFs fs) {
  return _uv_fs_result_type(
    fs, UV_FS_SCANDIR, %"fs_entry_count"
  ).entry_count;
}

static UvDirEntry _uv_fs_entry(UvFs fs, int index, String operation) {
  size_t count = fs.entry_count();
  if (index < 0 || (size_t) index >= count) {
    long size = (long) count;
    raise %(bad-arg (library "libuv") (operation $operation)
            (index $index) (size $size));
  }
  return &fs.entries[index];
}

String UvFs.entry_name(UvFs fs, int index) {
  return _uv_fs_entry(fs, index, %"fs_entry_name").name;
}

uv_dirent_type_t UvFs.entry_type(UvFs fs, int index) {
  return _uv_fs_entry(fs, index, %"fs_entry_type").type;
}

UvLoop UvFs.loop(UvFs fs) {
  return fs ? fs.loop : NULL;
}

uv_fs_t *UvFs.native(UvFs fs) {
  return fs ? &fs.request : NULL;
}

uint64_t UvStat.mode(UvStat stat) {
  return stat ? stat.value.st_mode : 0;
}

uint64_t UvStat.size(UvStat stat) {
  return stat ? stat.value.st_size : 0;
}

long UvStat.modified_seconds(UvStat stat) {
  return stat ? stat.value.st_mtim.tv_sec : 0;
}

long UvStat.modified_nanoseconds(UvStat stat) {
  return stat ? stat.value.st_mtim.tv_nsec : 0;
}

const uv_stat_t *UvStat.native(UvStat stat) {
  return stat ? &stat.value : NULL;
}

/*  A thread-safe, coalescing wakeup. `value` is callback state, not a value
    carried by each send. A sending x2c Thread must be joined before this
    handle or its loop closes.
*/
UvAsync UvLoop.async(UvLoop loop, Var value, void (*fn)(UvAsync, Var)) {
  if (!loop || !loop.initialized || !fn) {
    raise %(bad-arg (library "libuv") (operation "async")
            (reason "a live loop and a callback are required"));
  }
  UvAsync async = Scope.calloc(1, sizeof(struct UvAsync));
  async.loop = loop;
  async.value = value;
  async.handler = fn;
  int status = uv_async_init(&loop.loop, &async.async, _uv_async_callback);
  if (status < 0) {
    Scope.free(async);
    _uv_raise(%"async_init", status);
  }
  async.async.data = async;
  return async;
}

UvAsync UvAsync.send(UvAsync async) {
  if (!async) {
    raise %(bad-arg (library "libuv") (operation "async_send")
            (reason "an async handle is required"));
  }
  if (async.stopped) {
    raise %(bad-state (library "libuv") (operation "async_send")
            (reason "the async handle has stopped"));
  }
  int status = uv_async_send(&async.async);
  if (status < 0) _uv_raise(%"async_send", status);
  return async;
}

UvAsync UvAsync.stop(UvAsync async) {
  _uv_async_release(async);
  return NULL;
}

UvLoop UvAsync.loop(UvAsync async) {
  return async ? async.loop : NULL;
}

uv_async_t *UvAsync.native(UvAsync async) {
  return async ? &async.async : NULL;
}

/*  Runs once per loop turn before prepare and polling. An active idle handle
    forces a zero-timeout poll; it is a deliberate busy-loop mechanism, not a
    notification that the loop has nothing else to do.
*/
UvIdle UvLoop.idle(UvLoop loop, Var value, void (*fn)(UvIdle, Var)) {
  if (!loop || !loop.initialized || !fn) {
    raise %(bad-arg (library "libuv") (operation "idle")
            (reason "a live loop and a callback are required"));
  }
  UvIdle idle = Scope.calloc(1, sizeof(struct UvIdle));
  idle.loop = loop;
  idle.value = value;
  idle.handler = fn;
  int status = uv_idle_init(&loop.loop, &idle.idle);
  if (status < 0) {
    Scope.free(idle);
    _uv_raise(%"idle_init", status);
  }
  idle.idle.data = idle;
  status = uv_idle_start(&idle.idle, _uv_idle_callback);
  if (status < 0) {
    _uv_idle_release(idle);
    _uv_raise(%"idle_start", status);
  }
  return idle;
}

UvIdle UvIdle.stop(UvIdle idle) {
  _uv_idle_release(idle);
  return NULL;
}

UvLoop UvIdle.loop(UvIdle idle) {
  return idle ? idle.loop : NULL;
}

uv_idle_t *UvIdle.native(UvIdle idle) {
  return idle ? &idle.idle : NULL;
}

/*  Runs once per loop turn immediately before libuv polls for I/O. */
UvPrepare UvLoop.prepare(UvLoop loop, Var value, void (*fn)(UvPrepare, Var)) {
  if (!loop || !loop.initialized || !fn) {
    raise %(bad-arg (library "libuv") (operation "prepare")
            (reason "a live loop and a callback are required"));
  }
  UvPrepare prepare = Scope.calloc(1, sizeof(struct UvPrepare));
  prepare.loop = loop;
  prepare.value = value;
  prepare.handler = fn;
  int status = uv_prepare_init(&loop.loop, &prepare.prepare);
  if (status < 0) {
    Scope.free(prepare);
    _uv_raise(%"prepare_init", status);
  }
  prepare.prepare.data = prepare;
  status = uv_prepare_start(&prepare.prepare, _uv_prepare_callback);
  if (status < 0) {
    _uv_prepare_release(prepare);
    _uv_raise(%"prepare_start", status);
  }
  return prepare;
}

UvPrepare UvPrepare.stop(UvPrepare prepare) {
  _uv_prepare_release(prepare);
  return NULL;
}

UvLoop UvPrepare.loop(UvPrepare prepare) {
  return prepare ? prepare.loop : NULL;
}

uv_prepare_t *UvPrepare.native(UvPrepare prepare) {
  return prepare ? &prepare.prepare : NULL;
}

/*  Runs once per loop turn immediately after libuv polls for I/O. */
UvCheck UvLoop.check(UvLoop loop, Var value, void (*fn)(UvCheck, Var)) {
  if (!loop || !loop.initialized || !fn) {
    raise %(bad-arg (library "libuv") (operation "check")
            (reason "a live loop and a callback are required"));
  }
  UvCheck check = Scope.calloc(1, sizeof(struct UvCheck));
  check.loop = loop;
  check.value = value;
  check.handler = fn;
  int status = uv_check_init(&loop.loop, &check.check);
  if (status < 0) {
    Scope.free(check);
    _uv_raise(%"check_init", status);
  }
  check.check.data = check;
  status = uv_check_start(&check.check, _uv_check_callback);
  if (status < 0) {
    _uv_check_release(check);
    _uv_raise(%"check_start", status);
  }
  return check;
}

UvCheck UvCheck.stop(UvCheck check) {
  _uv_check_release(check);
  return NULL;
}

UvLoop UvCheck.loop(UvCheck check) {
  return check ? check.loop : NULL;
}

uv_check_t *UvCheck.native(UvCheck check) {
  return check ? &check.check : NULL;
}

/*  Calls `fn(timer, value)` after `delay` milliseconds, and every `repeat`
    milliseconds after that when `repeat` is positive. A repeating timer
    keeps the loop alive until something calls UvTimer.stop.
*/
UvTimer UvLoop.timer(
  UvLoop loop, long delay, long repeat, Var value, void (*fn)(UvTimer, Var)) {
  if (!loop || !loop.initialized || !fn || delay < 0 || repeat < 0) {
    raise %(bad-arg (library "libuv") (operation "timer")
            (reason "a live loop, a callback, and non-negative delays"));
  }
  UvTimer timer = Scope.calloc(1, sizeof(struct UvTimer));
  int status = uv_timer_init(&loop.loop, &timer.timer);
  if (status < 0) {
    Scope.free(timer);
    _uv_raise(%"timer_init", status);
  }
  timer.loop = loop;
  timer.value = value;
  timer.handler = fn;
  timer.timer.data = timer;
  status = uv_timer_start(
    &timer.timer, _uv_timer_callback, (uint64_t) delay, (uint64_t) repeat
  );
  if (status < 0) {
    _uv_timer_release(timer);
    _uv_raise(%"timer_start", status);
  }
  return timer;
}

UvTimer UvTimer.stop(UvTimer timer) {
  _uv_timer_release(timer);
  return NULL;
}

UvLoop UvTimer.loop(UvTimer timer) {
  return timer ? timer.loop : NULL;
}

uv_timer_t *UvTimer.native(UvTimer timer) {
  return timer ? &timer.timer : NULL;
}

/*  Calls `fn(signal, value)` when the process receives `number`. The handle
    is unreferenced, so it never keeps the loop alive by itself: a
    supervisor still exits when its children finish.
*/
UvSignal UvLoop.signal(
  UvLoop loop, int number, Var value, void (*fn)(UvSignal, Var)) {
  if (!loop || !loop.initialized || !fn || number <= 0) {
    raise %(bad-arg (library "libuv") (operation "signal")
            (reason "a live loop, a callback, and a signal number"));
  }
  UvSignal signal = Scope.calloc(1, sizeof(struct UvSignal));
  int status = uv_signal_init(&loop.loop, &signal.signal);
  if (status < 0) {
    Scope.free(signal);
    _uv_raise(%"signal_init", status);
  }
  signal.loop = loop;
  signal.value = value;
  signal.handler = fn;
  signal.number = number;
  signal.signal.data = signal;
  status = uv_signal_start(&signal.signal, _uv_signal_callback, number);
  if (status < 0) {
    _uv_signal_release(signal);
    _uv_raise(%"signal_start", status);
  }
  uv_unref((uv_handle_t *) &signal.signal);
  return signal;
}

/*  The signal most recently delivered to this handle, so one callback can
    serve SIGINT and SIGTERM.
*/
int UvSignal.number(UvSignal signal) {
  return signal ? signal.number : 0;
}

UvSignal UvSignal.stop(UvSignal signal) {
  _uv_signal_release(signal);
  return NULL;
}

UvLoop UvSignal.loop(UvSignal signal) {
  return signal ? signal.loop : NULL;
}

uv_signal_t *UvSignal.native(UvSignal signal) {
  return signal ? &signal.signal : NULL;
}

/*  Calls `fn(watch, value)` when `path` or an entry inside it changes. The
    watcher keeps the loop alive until something calls UvWatch.stop.
*/
UvWatch UvLoop.watch(
  UvLoop loop, String path, Var value, void (*fn)(UvWatch, Var)) {
  if (!loop || !loop.initialized || !fn || !path || !path.len()) {
    raise %(bad-arg (library "libuv") (operation "watch")
            (reason "a live loop, a callback, and a path are required"));
  }
  UvWatch watch = Scope.calloc(1, sizeof(struct UvWatch));
  int status = uv_fs_event_init(&loop.loop, &watch.event);
  if (status < 0) {
    Scope.free(watch);
    _uv_raise(%"fs_event_init", status);
  }
  watch.loop = loop;
  watch.value = value;
  watch.handler = fn;
  watch.event.data = watch;
  status = uv_fs_event_start(&watch.event, _uv_watch_callback, path, 0);
  if (status < 0) {
    _uv_watch_release(watch);
    _uv_raise(%"fs_event_start", status);
  }
  return watch;
}

/*  The name libuv reported, or NULL when none was supplied. It can name
    the watched directory itself or a removed entry. Valid until next event.
*/
String UvWatch.entry(UvWatch watch) {
  if (!watch) {
    raise %(bad-arg (library "libuv") (operation "entry")
            (reason "a watch is required"));
  }
  if (watch.status < 0) {
    _uv_raise(%"entry", watch.status);
  }
  return watch.entry;
}

/*  <rename> when the entry appeared, disappeared, or was renamed;
    <change> when its contents or metadata changed.
*/
Symbol UvWatch.kind(UvWatch watch) {
  return watch ? watch.kind : 0;
}

UvWatch UvWatch.stop(UvWatch watch) {
  _uv_watch_release(watch);
  return NULL;
}

UvLoop UvWatch.loop(UvWatch watch) {
  return watch ? watch.loop : NULL;
}

uv_fs_event_t *UvWatch.native(UvWatch watch) {
  return watch ? &watch.event : NULL;
}

/*  An unstarted child. Configure it, then start it; UvLoop.spawn is the
    same thing when no option is needed. The argv Strings must stay valid
    until UvProcess.start runs.
*/
UvProcess UvLoop.command(UvLoop loop, List arguments) {
  if (!loop || !loop.initialized || !arguments || !arguments.len()) {
    raise %(bad-arg (library "libuv") (operation "command")
            (reason "an initialized loop and nonempty argv are required"));
  }
  size_t count = arguments.len();
  if (count > INT_MAX) {
    raise %(size-limit (library "libuv") (operation "command")
            (arguments $count));
  }
  char **argv = Scope.calloc(count + 1, sizeof(char *));
  size_t index = 0;
  foreach(Var argument, arguments) {
    if (argument is not <string>) {
      raise %(bad-types (library "libuv") (operation "command")
              (reason "every argv value must be a String"));
    }
    String text = argument;
    argv[index++] = text ? text : "";
  }

  UvProcess process = Scope.calloc(1, sizeof(struct UvProcess));
  process.loop = loop;
  process.argv = argv;
  process.input_closed = 1;
  process.output.closed = 1;
  process.error.closed = 1;
  process.output.enabled = 1;
  process.error.enabled = 1;
  process.process_closed = 1;
  process.deadline_closed = 1;
  process.output.limit = 16 * 1024 * 1024;
  process.error.limit = 16 * 1024 * 1024;
  return process;
}

static UvStdioMode _uv_stdio_mode(Symbol mode, String operation) {
  if (mode == <pipe>) return UV_STDIO_PIPE;
  if (mode == <inherit>) return UV_STDIO_INHERIT;
  if (mode == <ignore>) return UV_STDIO_IGNORE;
  raise %(bad-arg (library "libuv") (operation $operation)
          (reason "stdio must be <pipe>, <inherit>, or <ignore>"));
}

/*  Configures stdin, stdout, and stderr before start. <pipe> enables the
    wrapper's write or capture methods, <inherit> uses file descriptors 0-2,
    and <ignore> attaches no child stream.
*/
UvProcess UvProcess.stdio(
  UvProcess process, Symbol input, Symbol output, Symbol error) {
  _uv_process_pending(process, %"stdio");
  process.input_mode = _uv_stdio_mode(input, %"stdio");
  process.output_mode = _uv_stdio_mode(output, %"stdio");
  process.error_mode = _uv_stdio_mode(error, %"stdio");
  process.output.enabled = process.output_mode == UV_STDIO_PIPE;
  process.error.enabled = process.error_mode == UV_STDIO_PIPE;
  return process;
}

UvProcess UvProcess.directory(UvProcess process, String path) {
  _uv_process_pending(process, %"directory");
  if (!path || !path.len()) {
    raise %(bad-arg (library "libuv") (operation "directory")
            (reason "a nonempty path is required"));
  }
  process.directory = path;
  return process;
}

/*  The child's complete environment, replacing the inherited one. Read
    uv_os_environ on the raw path when the child should inherit and extend.
*/
UvProcess UvProcess.environment(UvProcess process, Map variables) {
  _uv_process_pending(process, %"environment");
  if (!variables) {
    raise %(bad-arg (library "libuv") (operation "environment")
            (reason "a Map of names to values is required"));
  }
  char **environment = Scope.calloc(variables.len() + 1, sizeof(char *));
  size_t index = 0;
  foreach(Var (name, value), variables) {
    if (name is not <string> || value is not <string>) {
      raise %(bad-types (library "libuv") (operation "environment")
              (reason "every name and value must be a String"));
    }
    environment[index++] = %"%s=%s".printf(name.string(), value.string());
  }
  process.environment = environment;
  return process;
}

/*  Kills the child with SIGKILL after `milliseconds` of wall clock, from
    the moment it starts. UvProcess.timed_out reports it afterwards.
*/
UvProcess UvProcess.deadline(UvProcess process, long milliseconds) {
  _uv_process_pending(process, %"deadline");
  if (milliseconds <= 0) {
    raise %(bad-arg (library "libuv") (operation "deadline")
            (reason "a positive deadline in milliseconds is required"));
  }
  process.deadline_ms = milliseconds;
  return process;
}

UvProcess UvProcess.max_output(UvProcess process, size_t bytes) {
  _uv_process_pending(process, %"max_output");
  if (!bytes) {
    raise %(bad-arg (library "libuv") (operation "max_output")
            (reason "a positive limit is required"));
  }
  process.output.limit = bytes;
  process.error.limit = bytes;
  return process;
}

UvProcess UvProcess.start(UvProcess process) {
  _uv_process_pending(process, %"start");
  UvLoop loop = process.loop;

  int status = 0;
  if (process.input_mode == UV_STDIO_PIPE) {
    status = uv_pipe_init(&loop.loop, &process.input, 0);
    if (status < 0) goto pipe_failed;
    process.input_closed = 0;
    process.input.data = process;
  }
  if (process.output_mode == UV_STDIO_PIPE) {
    status = uv_pipe_init(&loop.loop, &process.output.pipe, 0);
    if (status < 0) {
      _uv_input_close(process);
      goto pipe_failed;
    }
    process.output.closed = 0;
    process.output.pipe.data = &process.output;
  }
  if (process.error_mode == UV_STDIO_PIPE) {
    status = uv_pipe_init(&loop.loop, &process.error.pipe, 0);
    if (status < 0) {
      _uv_input_close(process);
      _uv_capture_close(&process.output);
      goto pipe_failed;
    }
    process.error.closed = 0;
    process.error.pipe.data = &process.error;
  }

  uv_stdio_container_t stdio[3] = { 0 };
  if (process.input_mode == UV_STDIO_PIPE) {
    stdio[0].flags = UV_CREATE_PIPE | UV_READABLE_PIPE;
    stdio[0].data.stream = (uv_stream_t *) &process.input;
  }
  else if (process.input_mode == UV_STDIO_INHERIT) {
    stdio[0].flags = UV_INHERIT_FD;
    stdio[0].data.fd = 0;
  }
  if (process.output_mode == UV_STDIO_PIPE) {
    stdio[1].flags = UV_CREATE_PIPE | UV_WRITABLE_PIPE;
    stdio[1].data.stream = (uv_stream_t *) &process.output.pipe;
  }
  else if (process.output_mode == UV_STDIO_INHERIT) {
    stdio[1].flags = UV_INHERIT_FD;
    stdio[1].data.fd = 1;
  }
  if (process.error_mode == UV_STDIO_PIPE) {
    stdio[2].flags = UV_CREATE_PIPE | UV_WRITABLE_PIPE;
    stdio[2].data.stream = (uv_stream_t *) &process.error.pipe;
  }
  else if (process.error_mode == UV_STDIO_INHERIT) {
    stdio[2].flags = UV_INHERIT_FD;
    stdio[2].data.fd = 2;
  }

  uv_process_options_t options = { 0 };
  options.exit_cb = _uv_process_exit_event;
  options.file = process.argv[0];
  options.args = process.argv;
  options.cwd = process.directory;
  options.env = process.environment;
  options.stdio_count = 3;
  options.stdio = stdio;
  process.process.data = process;
  status = uv_spawn(&loop.loop, &process.process, &options);
  if (status < 0) {
    _uv_input_close(process);
    _uv_capture_close(&process.output);
    _uv_capture_close(&process.error);
    goto pipe_failed;
  }
  process.started = 1;
  process.process_closed = 0;
  process.shutdown.data = process;

  if (process.deadline_ms) {
    uv_timer_init(&loop.loop, &process.deadline);
    process.deadline.data = process;
    process.deadline_closed = 0;
    uv_timer_start(
      &process.deadline, _uv_deadline_event,
      (uint64_t) process.deadline_ms, 0
    );
  }

  if (process.output.enabled) {
    status = uv_read_start(
      (uv_stream_t *) &process.output.pipe,
      _uv_alloc_event, _uv_read_callback
    );
    if (status < 0) {
      process.output.status = status;
      _uv_capture_close(&process.output);
    }
  }
  if (process.error.enabled) {
    status = uv_read_start(
      (uv_stream_t *) &process.error.pipe,
      _uv_alloc_event, _uv_read_callback
    );
    if (status < 0) {
      process.error.status = status;
      _uv_capture_close(&process.error);
    }
  }
  return process;

pipe_failed: _uv_discard_closed_handles(loop, process);
  _uv_raise(%"spawn", status);
}

UvProcess UvLoop.spawn(UvLoop loop, List arguments) {
  return loop.command(arguments).start();
}

UvProcess UvProcess.write(UvProcess process, String text) {
  _uv_process_ready(process, %"write");
  if (process.input_mode != UV_STDIO_PIPE) {
    raise %(bad-state (library "libuv") (operation "write")
            (reason "stdin was not configured as <pipe>"));
  }
  if (process.input_closed || process.shutdown_pending) {
    raise %(bad-state (library "libuv") (operation "write")
            (reason "stdin is closed or shutting down"));
  }
  size_t length = text.len();
  if (!length) return process;
  if (length > UINT_MAX) {
    raise %(size-limit (library "libuv") (operation "write") (bytes $length));
  }
  UvWrite write = calloc(1, sizeof(struct UvWrite));
  if (!write) {
    raise %(alloc-fail (library "libuv") (operation "write")
            (bytes $length));
  }
  write.bytes = malloc(length);
  if (!write.bytes) {
    free(write);
    raise %(alloc-fail (library "libuv") (operation "write") (bytes $length));
  }
  write.process = process;
  write.request.data = write;
  memcpy(write.bytes, text, length);
  uv_buf_t buffer = uv_buf_init(write.bytes, (unsigned) length);
  int status = uv_write(
    &write.request, (uv_stream_t *) &process.input,
    &buffer, 1, _uv_write_event
  );
  if (status < 0) {
    free(write.bytes);
    free(write);
    _uv_raise(%"write", status);
  }
  process.pending_writes++;
  return process;
}

UvProcess UvProcess.close_stdin(UvProcess process) {
  _uv_process_ready(process, %"shutdown");
  if (process.input_mode != UV_STDIO_PIPE) return process;
  if (process.input_closed || process.shutdown_pending) return process;
  int status = uv_shutdown(
    &process.shutdown, (uv_stream_t *) &process.input,
    _uv_shutdown_event
  );
  if (status < 0) {
    if (status == UV_ENOTCONN) {
      _uv_input_close(process);
      return process;
    }
    _uv_raise(%"shutdown", status);
  }
  process.shutdown_pending = 1;
  return process;
}

UvProcess UvProcess.kill(UvProcess process, int number) {
  _uv_process_ready(process, %"process_kill");
  if (process.exited) {
    raise %(bad-state (library "libuv") (operation "process_kill")
            (reason "the process has already exited"));
  }
  int status = uv_process_kill(&process.process, number);
  if (status < 0) {
    _uv_raise(%"process_kill", status);
  }
  return process;
}

int UvProcess.pid(UvProcess process) {
  _uv_process_ready(process, %"process_get_pid");
  return (int) uv_process_get_pid(&process.process);
}

int UvProcess.exited(UvProcess process) {
  _uv_process_ready(process, %"exited");
  return process.exited;
}

int UvProcess.timed_out(UvProcess process) {
  _uv_process_ready(process, %"timed_out");
  return process.timed_out;
}

long UvProcess.exit_status(UvProcess process) {
  _uv_process_ready(process, %"exit_status");
  if (!process.exited) {
    raise %(bad-state (library "libuv") (operation "exit_status")
            (reason "the process has not exited"));
  }
  return (long) process.exit_status;
}

int UvProcess.term_signal(UvProcess process) {
  _uv_process_ready(process, %"term_signal");
  if (!process.exited) {
    raise %(bad-state (library "libuv") (operation "term_signal")
            (reason "the process has not exited"));
  }
  return process.term_signal;
}

uv_process_t *UvProcess.native(UvProcess process) {
  return process && process.started && !process.released
    ? &process.process : NULL;
}

static void _uv_capture_check(
  UvProcess process, UvCapture *capture, String operation) {
  _uv_process_ready(process, operation);
  if (!capture.enabled) {
    raise %(bad-state (library "libuv") (operation $operation)
            (reason "the stream was not captured"));
  }
  if (capture.status < 0) _uv_raise(operation, capture.status);
}

static Bytes _uv_capture_bytes(
  UvProcess process, UvCapture *capture, String operation) {
  _uv_capture_check(process, capture, operation);
  Bytes result = Bytes.new(1);
  return result.append(capture.bytes, capture.length);
}

static String _uv_capture_text(
  UvProcess process, UvCapture *capture, String operation) {
  _uv_capture_check(process, capture, operation);
  if (capture.length > INT_MAX) {
    size_t bytes = capture.length;
    raise %(size-limit (library "libuv") (operation $operation)
            (bytes $bytes));
  }
  if (capture.length && memchr(capture.bytes, '\0', capture.length)) {
    raise %(bad-enc (library "libuv") (operation $operation)
            (reason "captured bytes contain NUL; use the bytes method"));
  }
  return String.new_len(capture.bytes, (int) capture.length);
}

Bytes UvProcess.stdout_bytes(UvProcess process) {
  if (!process) {
    raise %(bad-arg (library "libuv") (operation "stdout_bytes"));
  }
  return _uv_capture_bytes(process, &process.output, %"stdout_bytes");
}

Bytes UvProcess.stderr_bytes(UvProcess process) {
  if (!process) {
    raise %(bad-arg (library "libuv") (operation "stderr_bytes"));
  }
  return _uv_capture_bytes(process, &process.error, %"stderr_bytes");
}

String UvProcess.stdout(UvProcess process) {
  if (!process) {
    raise %(bad-arg (library "libuv") (operation "stdout"));
  }
  return _uv_capture_text(process, &process.output, %"stdout");
}

String UvProcess.stderr(UvProcess process) {
  if (!process) {
    raise %(bad-arg (library "libuv") (operation "stderr"));
  }
  return _uv_capture_text(process, &process.error, %"stderr");
}

UvProcess UvProcess.free(UvProcess process) {
  if (!process) return NULL;
  if (process.started &&
      (!process.exited || !process.process_closed ||
       !process.input_closed || !process.output.closed ||
       !process.error.closed || !process.deadline_closed ||
       process.pending_writes || process.shutdown_pending)) {
    raise %(bad-state (library "libuv") (operation "process_free")
            (reason "run the loop until the process and pipes finish"));
  }
  free(process.output.bytes);
  free(process.error.bytes);
  process.output.bytes = NULL;
  process.error.bytes = NULL;
  process.released = 1;
  return NULL;
}
