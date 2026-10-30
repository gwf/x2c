/*  repl-worker.x -- native session process and terminal protocol

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "repl-program.x"
#include "repl-inspect.x"
#include "repl-input.x"
#include "datum.x"
#include "file.x"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif

typedef struct ReplWorker {
  pid_t pid;
  int to, from, terminal, status;
  Buffer pending;
  String snapshot;
  List roots;
  String directory;
  String failure;
} *ReplWorker;

typedef struct ReplWorkerStart {
  List arguments, roots, requested;
  String snapshot;
  ReplWorker previous;
  ReplInput input;
  int interactive;
} ReplWorkerStart;

CliRequest repl_native_request(List arguments);

static volatile sig_atomic_t _worker_interrupted;
static ReplSession _worker_session;

static void _worker_shutdown(void) {
  ReplSession session = _worker_session;
  _worker_session = NULL;
  if (session) session.close();
}

/** Marks the active worker request for cancellation by the supervisor. */
void repl_worker_interrupt(int signal) {
  (void) signal;
  _worker_interrupted = 1;
}

static int _worker_write(int fd, String bytes) {
  size_t sent = 0;
  while (sent < bytes.len()) {
    ssize_t count = write(fd, bytes + sent, bytes.len() - sent);
    if (count > 0) sent += count;
    else if (count < 0 && errno == EINTR && !_worker_interrupted) continue;
    else return 0;
  }
  return 1;
}

static int _worker_send(int fd, Var value) {
  Buffer frame = auto Buffer.new(0);
  return frame.write_datum_frame(value) && _worker_write(fd, frame);
}

static int _worker_frame(Buffer pending, Var &value) {
  size_t available = pending.content.length;
  if (!available) return 0;
  const char *bytes = (const char *) pending.content.bytes;
  const char *newline = memchr(bytes, '\n', available);
  if (!newline || newline == bytes) return 0;
  size_t header = newline - bytes + 1;
  size_t length = strtoul(bytes, NULL, 10);
  if (length > available - header) return 0;
  size_t used = 0;
  String text = pending;
  if (!text.read_datum_frame(used, value)) return 0;
  String remaining = text[used:];
  pending.clear();
  if (remaining) pending.write(remaining);
  return 1;
}

static int _worker_read(int fd, Buffer pending, Var &value) {
  while (!_worker_frame(pending, value)) {
    char bytes[4096];
    ssize_t count = read(fd, bytes, sizeof(bytes));
    if (count > 0) pending.write_len(bytes, count);
    else if (count < 0 && errno == EINTR) continue;
    else return 0;
  }
  return 1;
}

static String _worker_reason(ReplWorker worker) {
  if (_worker_interrupted) return "interrupted";
  int status = worker.status;
  if (WIFSIGNALED(status))
    return %"native worker ended with signal $((int) WTERMSIG(status))";
  if (WIFEXITED(status))
    return %"native worker exited with status $((int) WEXITSTATUS(status))";
  return "native worker disconnected";
}

static void _worker_descriptors(ReplWorker worker) {
  if (worker.to >= 0) close(worker.to), worker.to = -1;
  if (worker.from >= 0) close(worker.from), worker.from = -1;
  if (worker.terminal >= 0) close(worker.terminal), worker.terminal = -1;
}

static void _worker_reap(ReplWorker worker, int force) {
  if (!worker) return;
  if (worker.pid > 0) {
    if (force) {
      kill((pid_t) -(long) worker.pid, SIGKILL);
      kill(worker.pid, SIGKILL);
    }
    for (;;) {
      if (_worker_interrupted) {
        kill((pid_t) -(long) worker.pid, SIGKILL);
        kill(worker.pid, SIGKILL);
      }
      if (waitpid(worker.pid, &worker.status, 0) >= 0 || errno != EINTR) break;
    }
    worker.pid = 0;
  }
  _worker_descriptors(worker);
}

static Map _worker_receive(ReplWorker worker, int input) {
  for (;;) {
    if (_worker_interrupted) {
      _worker_reap(worker, 1);
      worker.failure = "interrupted";
      return NULL;
    }
    Var value = void;
    if (_worker_frame(worker.pending, value)) return value;
    if (waitpid(worker.pid, &worker.status, WNOHANG) == worker.pid) {
      kill((pid_t) -(long) worker.pid, SIGKILL);
      worker.pid = 0;
      struct pollfd reply = {.fd = worker.from, .events = POLLIN};
      while (!_worker_interrupted && poll(&reply, 1, 0) > 0 &&
             (reply.revents & POLLIN)) {
        char bytes[4096];
        ssize_t count = read(worker.from, bytes, sizeof(bytes));
        if (count > 0) worker.pending.write_len(bytes, count);
        else if (count < 0 && errno == EINTR) continue;
        else break;
      }
      int complete = _worker_frame(worker.pending, value);
      _worker_descriptors(worker);
      if (complete) return value;
      worker.failure = _worker_reason(worker);
      return NULL;
    }
    struct pollfd events[2] = {
      { .fd = worker.from, .events = POLLIN },
      { .fd = input && worker.terminal >= 0 ? STDIN_FILENO : -1,
        .events = POLLIN }
    };
    int ready = poll(events, 2, 100);
    if (ready < 0 && errno == EINTR) continue;
    if (ready < 0) break;
    if (events[1].revents & POLLIN) {
      char bytes[4096];
      ssize_t count = read(STDIN_FILENO, bytes, sizeof(bytes));
      if (count > 0)
        _worker_write(worker.terminal, String.new_len(bytes, count));
      else if (!count) _worker_write(worker.terminal, "\004");
    }
    if (events[0].revents & (POLLIN | POLLHUP | POLLERR)) {
      char bytes[4096];
      ssize_t count = read(worker.from, bytes, sizeof(bytes));
      if (count > 0) worker.pending.write_len(bytes, count);
      else if (count < 0 && errno == EINTR) continue;
      else break;
    }
  }
  _worker_reap(worker, 1);
  worker.failure = _worker_reason(worker);
  return NULL;
}

/** Sends source or an inspection query to the worker; no native value crosses. */
Map repl_worker_call(ReplWorker worker, Map message, int input) {
  if (!worker || worker.pid <= 0) return NULL;
  _worker_interrupted = 0;
  worker.failure = NULL;
  if (!_worker_send(worker.to, message)) {
    _worker_reap(worker, 1);
    worker.failure = "native worker disconnected";
    return NULL;
  }
  return _worker_receive(worker, input);
}

/** Retires the worker after session cleanup, or kills a failed worker. */
void repl_worker_close(ReplWorker worker) {
  if (!worker) return;
  if (worker.pid > 0) {
    Map reply = repl_worker_call(worker, {operation: <quit>}, 0);
    _worker_reap(worker, reply == NULL);
  }
  worker.pending.free();
  xfree(worker);
}

static Map _worker_result(ReplSession session, ReplResult result) {
  with (session.compiler.text = result.source) {
    foreach (Var diagnostic, result.diagnostics)
      session.compiler.print_diagnostic(diagnostic);
  }
  return {status: result.status, formatted: result.formatted ? result.formatted : "",
          artifact: result.artifact ? result.artifact : "",
          name: result.name ? result.name : "",
          message: result.message ? result.message : "",
          cause: result.cause ? result.cause.repr() : "",
          syntax: result.syntax ? result.syntax.repr() : ""};
}

static String _worker_stats(ReplSession session, int verbose) {
  Buffer text = auto Buffer.new(0);
  ScopeStats scope = Scope.stats();
  PoolStats pool = Pool.stats(Pool.current());
  text.printf("session: definitions=%u\n", session.names.len());
  text.printf("scope (worker): live-allocation-objects=%zu "
              "live-requested-bytes=%zu\n",
              scope.live_allocations, scope.live_requested_bytes);
  text.printf("pool (worker): backing-capacity-bytes=%zu active-bytes=%zu "
              "depot-bytes=%zu\n",
              pool.backing_bytes, pool.active_bytes, pool.depot_bytes);
  if (verbose) {
    text.printf("scope (worker): allocation-calls=%zu free-calls=%zu "
                "reallocation-calls=%zu\n",
                scope.allocation_calls, scope.free_calls,
                scope.reallocation_calls);
    text.printf("pool (worker): active-blocks=%zu depot-blocks=%zu\n",
                pool.active_blocks, pool.depot_blocks);
  }
  return text;
}

static Map _worker_dispatch(ReplSession session, Map message) {
  Symbol operation = message[<operation>];
  String text = message[<text>];
  if (operation == <submit>) return _worker_result(session, session.submit(text));
  if (operation == <inspect>)
    return _worker_result(session, session.inspect_expression(
      text, message[<depth>], message[<limit>]));
  if (operation == <complete>) {
    ReplCompletion c = session.complete(text, message[<cursor>]);
    Array candidates = auto [];
    foreach (List row, c.candidates) {
      Var description = void, declaration = void;
      if (row.len() == 2 && session.descriptions.try_get(row.cadr(), description) &&
          description is <map> &&
          description.map().try_get("declaration", declaration) &&
          declaration is <string>)
        candidates.push(%(@row $declaration));
      else candidates.push(row);
    }
    return {status: <ok>, start: c.start, end: c.end, candidates: candidates.list()};
  }
  String output = NULL;
  if (operation == <symbols>) {
    output = session.symbol_text(
      message[<prefix>], message[<kind>], message[<path>], message[<all>]);
    return {status: <ok>, text: output};
  }
  if (operation == <info>) output = session.info(text);
  else if (operation == <source>) output = session.source(text);
  else if (operation == <members>) output = session.members(text);
  else if (operation == <stats>) output = _worker_stats(session, message[<verbose>]);
  else if (operation == <files>) {
    Buffer listing = auto Buffer.new(0);
    CliRequest request = session.frontend.request;
    if (session.program)
      foreach (String path, session.program.roots) listing.printf("root: %s\n", path);
    listing.printf("include directories: %s\n", request.include_dirs.repr());
    listing.printf("C options: %s\n", request.cc_args.repr());
    listing.printf("link options: %s\n", request.ld_args.repr());
    if (request.manifest) listing.printf("manifest: %s\n", request.manifest);
    if (request.target) listing.printf("target: %s\n", request.target);
    if (request.profile) listing.printf("profile: %s\n", request.profile);
    output = listing;
  }
  else if (operation == <ast>) {
    List entry = session.inspect(text);
    match (entry) case %(function (typed ?syntax) *): output = syntax.repr();
    if (!output) return {status: <failed>, message: %"no prompt AST for $text"};
  }
  else if (operation == <lowered> && session.info(text))
    output = "native: executable submissions compile through the ordinary compiler";
  if (output) return {status: <ok>, text: output};
  return {status: <failed>, message: %"no visible declaration for $text"};
}

static String _worker_snapshot(ReplProgram program, String retained) {
  if (retained || !program) return retained;
  retained = %"$(program.directory)/program.snapshot";
  Buffer data = auto Buffer.new(0);
  if (!data.write_datum(repl_program_snapshot(program), 1)) {
    fputs("native program snapshot contains a non-data value\n", stderr);
    exit(1);
  }
  File file = auto File.open(retained, "wb");
  file.write_all(data.content.bytes, data.len());
  return retained;
}

static void _worker_serve(
  CliRequest request, List roots, List requested, String snapshot, int from, int to) {
  signal(SIGINT, SIG_DFL);
  signal(SIGPIPE, SIG_DFL);
  // Native exit hooks run before Context's registered process shutdown.
  Context.open_isolated_named("native REPL worker");
  Scope.shutdown_hook(_worker_shutdown);
  Frontend.load_support(request);
  Frontend frontend = Frontend.new(request);
  ParsedUnit unit;
  if (!frontend.open_session(unit)) {
    foreach (Var diagnostic, unit.compiler.diagnostics())
      unit.compiler.print_diagnostic(diagnostic);
    _worker_send(to, {status: <failed>, message: "could not open compiler session"});
    exit(1);
  }
  ReplSession session = ReplSession.new(unit.compiler);
  _worker_session = session;
  session.frontend = frontend;
  ReplProgram program = NULL;
  String failure = NULL;
  if (snapshot) {
    Var state = void;
    unsigned cursor = 0;
    Path.read_text(snapshot).read_datum(cursor, state);
    program = repl_program_restore(state, failure);
  }
  else if (roots || request.inputs || request.manifest || request.target || request.profile)
    program = repl_program_build_selected(frontend, roots, requested, failure);
  if (failure) {
    _worker_send(to, {status: <failed>, message: failure});
    exit(1);
  }
  if (program) {
    repl_program_bind(program, session);
    session.program = program;
  }
  String retained = _worker_snapshot(program, snapshot);
  if (!_worker_send(to, {status: <ready>, snapshot: retained,
                        roots: program ? program.roots : roots,
                        directory: program ? program.directory : ""})) {
    fputs("native program snapshot contains a non-data value\n", stderr);
    exit(1);
  }
  Buffer pending = Buffer.new(0);
  Var value = void;
  while (_worker_read(from, pending, value)) {
    Map message = value;
    if (message[<operation>] == <quit>) {
      session.run_cleanups();
      if (program) repl_program_close(program);
      fflush(NULL);
      exit(0);
    }
    Map result = NULL;
    try result = _worker_dispatch(session, message);
    catch %(?kind *details):
      result = {status: <failed>, message: cons(kind, details).repr()};
    fflush(stdout);
    fflush(stderr);
    if (!_worker_send(to, result)) break;
  }
  session.run_cleanups();
  if (program) repl_program_close(program);
  fflush(NULL);
  exit(0);
}

/** Starts a fresh native session without retiring an existing worker. */
ReplWorker repl_worker_start(ReplWorkerStart start) {
  _worker_interrupted = 0;
  int requests[2], replies[2], master = -1, slave = -1;
  if (pipe(requests) || pipe(replies)) {
    int error = errno;
    raise %(io-fail (operation "repl worker pipes") (errno $error));
  }
  if (start.interactive) {
    if (openpty(&master, &slave, NULL, NULL, NULL)) {
      int error = errno;
      raise %(io-fail (operation "repl worker terminal") (errno $error));
    }
    struct termios mode;
    if (!tcgetattr(slave, &mode)) {
      mode.c_lflag &= ~ECHO;
      tcsetattr(slave, TCSANOW, &mode);
    }
  }
  fcntl(requests[0], F_SETFD, FD_CLOEXEC);
  fcntl(requests[1], F_SETFD, FD_CLOEXEC);
  fcntl(replies[0], F_SETFD, FD_CLOEXEC);
  fcntl(replies[1], F_SETFD, FD_CLOEXEC);
  fflush(NULL);
  pid_t pid = fork();
  if (pid < 0) {
    int error = errno;
    raise %(io-fail (operation "repl worker fork") (errno $error));
  }
  if (!pid) {
    close(requests[1]);
    close(replies[0]);
    if (start.previous) {
      if (start.previous.to >= 0) close(start.previous.to);
      if (start.previous.from >= 0) close(start.previous.from);
      if (start.previous.terminal >= 0) close(start.previous.terminal);
    }
    start.input.discard_inherited();
    setsid();
    if (master >= 0) {
      close(master);
      const char *terminal = ttyname(slave);
      if (!terminal || !freopen(terminal, "r", stdin)) {
        perror("native worker stdin");
        _exit(1);
      }
      ioctl(STDIN_FILENO, TIOCSCTTY, 0);
      close(slave);
    }
    else {
      if (!freopen("/dev/null", "r", stdin)) {
        perror("native worker stdin");
        _exit(1);
      }
    }
    CliRequest request = repl_native_request(start.arguments);
    _worker_serve(request, start.roots, start.requested, start.snapshot,
                  requests[0], replies[1]);
  }
  close(requests[0]);
  close(replies[1]);
  if (slave >= 0) close(slave);
  ReplWorker worker = xcalloc(1, sizeof(struct ReplWorker));
  worker.pid = pid;
  worker.to = requests[1];
  worker.from = replies[0];
  worker.terminal = master;
  worker.pending = Buffer.new(0);
  Map ready = _worker_receive(worker, 0);
  if (!ready || ready[<status>] != <ready>) {
    if (ready) worker.failure = ready[<message>];
    _worker_reap(worker, ready == NULL);
    return worker;
  }
  worker.snapshot = ready[<snapshot>];
  worker.roots = ready[<roots>];
  worker.directory = ready[<directory>];
  return worker;
}
