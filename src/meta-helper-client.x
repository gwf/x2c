/*  meta-helper-client.x -- the compiler's side of the project meta helper

    Copyright (c) 2026 Gary William Flake.

    The project meta build (`meta-project.x`) compiles each unit's `meta`
    group (`meta-group.x`) into one helper program. This file owns the
    compiler's side of that helper: starting it, one request and its
    replies per call, answers to the queries a body asks, and reporting a
    body that fails, crashes, or runs too long.
*/
#pragma once
#include "compiler.x"

#include "meta-group.x"
#include "datum.x"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

// diagnostics

static macro Stmt $fail.meta_helper_client_helper_timeout(
  Expr $c, Expr $site, Expr $limit, Expr $name) {
  $c.report_error(
    <macro>,
    "%s%g s".printf("this meta call ran longer than ", $limit),
    $site, %("function: ${$name}" "set X2C_META_TIMEOUT to a larger limit in seconds, or 0 for none"));
}

static macro Stmt $fail.meta_helper_client_helper_stopped(
  Expr $c, Expr $site, Expr $name, Expr $reason) {
  $c.report_error(
    <macro>,
    "this meta call stopped the compile-time helper",
    $site, %("function: ${$name}" "reason: ${$reason}"));
}

/** Reports a meta function's error `message` with `notes` under
    `category` at the position recorded first in or around `node`, or at
    `site` when it has none. A `fatal` report does not return. */
void Compiler.report_meta_error(
  Compiler c, Var node, Symbol category, String message, Token site,
  List notes, int fatal) {
  int origin = _syntax_origin(node);
  Token token = origin ? NULL : site;
  $let(c.origin, origin ? origin : c.origin) {
    if (fatal) c.report_error(category, message, token, notes);
    c.report_problem(category, message, token, notes);
  }
}

/* The `N` of the first `(at N ...)` in or around `node`, or 0. */
static int _syntax_origin(Var node) {
  if (node is not <list>) return 0;
  match (node) case %(at ?(int origin) ?): return origin;
  foreach (Var child, node.list()) {
    int origin = _syntax_origin(child);
    if (origin) return origin;
  }
  return 0;
}

/** Owns one compiled helper's configuration and process. Callers close it
    after its last call; closing again is harmless. */
typedef struct MetaHelper {
  String path, snapshot;
  Map failures, units;
  Scope scope;
  pid_t pid, owner;
  int to, from, table, reset, status;
  Buffer input;
} *MetaHelper;

static MetaHelper primary = NULL, active = NULL;
static Scope primary_scope = NULL;

// calls

/* One call of a project `meta` function in helper table `table`, whose
   failures are reported at `site`. Starting the helper, sending the request
   and receiving its reply take at most `limit` seconds, or any time when
   `deadline` is 0. */
static typedef struct Call {
  Compiler compiler, String name, Token site, int table;
  double limit, deadline;
} Call;

/** Calls the project `meta` function `name` in the helper with the values
    `arguments`, for the call at `site`, and returns its result. A warning
    the body makes is reported at `site` and a failure it reports is the
    call's failure. A body that crashes, exits, or passes the deadline ends
    the helper, which is reported at `site` and started again for the next
    call. The call runs in the table of the file that wrote it: an included
    file's own, which runs the constants it computes as its own translation
    does, or else the unit's. */
Var Compiler.meta_helper_call(
  Compiler c, String name, Token site, List arguments, String provider) {
  MetaHelper previous = active;
  active = c.meta_helper ? c.meta_helper : primary;
  defer active = previous;
  if (!active)
    c.refuse_meta_call(name, site, "the project meta module was not built");
  if (c.shallow) c.collection_native = 1;
  String file = provider ? Path.real(Compiler.absolute_home_path(provider))
                         : Path.real(c.token_source(site, NULL));
  Call call = {
    .compiler = c, .name = name, .site = site,
    .table = _table_of(file, active.table)};
  _check(call);
  c.refuse_record_meta_call(name, site);
  _set_deadline(call);
  if (!_start()) _refuse(call, "the compile-time helper did not start");
  _send(call, arguments);
  for (;;) {
    Var reply = _next_reply(call);
    match (reply) {
      case %(warning ?(String message) ?(List notes)):
        c.report_warning(<macro>, message, site, notes);
      case %(value ?value): return value;
      case %(void): return void;
      case %(error ?(String message) ?(List notes)):
        c.report_error(<macro>, message, site, notes);
      case %(error ?(String message) ?(List notes) (at ?node ?category)):
        c.report_meta_error(node, category, message, site, notes, 1);
      case %(dependency ?(String path) ?(String hash)):
        c.deps.merge_translation_dependency(path, hash);
      case %(query ?(String operation) ?(List operands)):
        _answer(call, operation, operands);
      case %(missing): _refuse(call, c.meta_call_missing(name));
      case %(failure (?code *detail)): Error.raise(code, detail);
      default: _stopped(call, "the helper sent an unknown reply");
    }
  }
}

/* Answers the body's query with the compiler's own `operation` applied to
   `operands` at the call's site, in the state the call sees; a `void`
   operation answers nil. A failed answer ends the helper, which waits for
   it, before the failure leaves. */
static void _answer(Call &c, String operation, List operands) {
  Var value = void;
  try value = c.compiler.apply_meta_function(operation, operands, c.site);
  catch %(?code *detail): {
    _stop(SIGKILL);
    Error.raise(code, detail);
  }
  if (value is void) value = %();
  _send_frame(c, %(answer $value));
}

/* Refuses the call when the project's helper or the call's table did not
   build, or when the function returns a struct or union. */
static void _check(Call &call) {
  Var failure;
  if (!active.path && active.failures && active.failures.try_get(-1, failure))
    _refuse(call, failure);
  if (!active.path) _refuse(call, "the project meta module was not built");
  if (active.failures && active.failures.try_get(call.table, failure))
    _refuse(call, failure);
}

/* Sends the call, after the unit's reset when that is still to be sent. */
static void _send(Call &c, List arguments) {
  if (active.reset) {
    _send_frame(c, %(reset));
    active.reset = 0;
  }
  Var subject = Macro.subject();
  if (subject is void) subject = %();
  _send_frame(c, %(call ${c.table} ${c.name} $arguments $subject));
}

static void _send_frame(Call &call, List message) {
  int status = _write_frame(message, call.deadline);
  if (status < 0) _overdue(call);
  if (!status) _stopped(call, _exit_reason());
}

/* The limit is `X2C_META_TIMEOUT` in seconds, 60 by default; zero or less
   sets no deadline. */
static void _set_deadline(Call &call) {
  String text = Env.get("X2C_META_TIMEOUT");
  call.limit = text ? atof(text) : 60.0;
  call.deadline = call.limit > 0 ? _now() + call.limit : 0;
}

static double _now(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec + now.tv_nsec / 1e9;
}

/* The next reply. A helper that passes the deadline or ends first is
   reported at the call. */
static Var _next_reply(Call &call) {
  Var reply;
  int status = _read_reply(call.deadline, reply);
  if (status < 0) _overdue(call);
  if (!status) _stopped(call, _exit_reason());
  return reply;
}

// the helper process

/* Starts the helper unless this process runs one. Every pipe end is
   close-on-exec, and the helper keeps only its descriptors 3 and 4, so it
   reads the end of its requests as soon as this process closes its end or
   ends. The helper leads a process group of its own, which every process
   it starts joins; this side sets the group too, so it exists before the
   helper runs. */
static int _start(void) {
  if (_running()) return 1;
  active.pid = 0;
  int requests[2], replies[2];
  if (pipe(requests)) return 0;
  if (pipe(replies)) {
    close(requests[0]);
    close(requests[1]);
    return 0;
  }
  for (int i = 0; i < 2; i++) {
    fcntl(requests[i], F_SETFD, FD_CLOEXEC);
    fcntl(replies[i], F_SETFD, FD_CLOEXEC);
  }
  int flags = fcntl(requests[1], F_GETFL);
  if (flags < 0 || fcntl(requests[1], F_SETFL, flags | O_NONBLOCK) < 0) {
    close(requests[0]);
    close(requests[1]);
    close(replies[0]);
    close(replies[1]);
    return 0;
  }
  pid_t pid = fork();
  if (!pid) _exec(requests[0], replies[1]);
  close(requests[0]);
  close(replies[1]);
  if (pid < 0) {
    close(requests[1]);
    close(replies[0]);
    return 0;
  }
  setpgid(pid, pid);
  active.pid = pid;
  active.owner = getpid();
  active.to = requests[1];
  active.from = replies[0];
  if (active.input) active.input.clear();
  active.reset = 1;
  return 1;
}

/* Runs the helper in the forked child with its requests on descriptor 3
   and its replies on 4, as the leader of a new process group. Copying each
   end above 10 first keeps `dup2` from overwriting the other end or
   leaving one close-on-exec. */
static void _exec(int requests, int replies) {
  int in = fcntl(requests, F_DUPFD_CLOEXEC, 10);
  int out = fcntl(replies, F_DUPFD_CLOEXEC, 10);
  dup2(in, 3);
  dup2(out, 4);
  setpgid(0, 0);
  execl(active.path, active.path, (char *) NULL);
  _exit(127);
}

/* Whether this process started the active helper. A worker
   forked from a process that runs one starts its own. */
static int _running(void) =>
  active && active.pid > 0 && active.owner == getpid();

/* Whether the helper has ended, which reaps it and keeps its status. */
static int _reaped(void) {
  int status;
  if (active.status < 0 &&
      waitpid(active.pid, &status, WNOHANG) == active.pid)
    active.status = status;
  return active.status >= 0;
}

/* Ends the helper this process started, if any, and forgets it: asks it
   to quit, or sends `signal` to its process group, and reaps it. A process
   group lasts, under its id, while any process in it runs, so killing the
   helper's group after the reap ends only what the helper started and
   left running, such as a job whose body crashed. Returns the helper's
   wait status. */
static int _stop(int signal) {
  int status = 0;
  if (_running()) {
    if (signal) killpg(active.pid, signal);
    else _write_frame(%(quit), 0);
    close(active.to);
    close(active.from);
    if (active.status < 0) waitpid(active.pid, &active.status, 0);
    killpg(active.pid, SIGKILL);
    status = active.status;
  }
  active.pid = 0;
  active.status = -1;
  active.to = active.from = -1;
  if (active.input) active.input.clear();
  return status;
}

/* Why the helper that answered no more ended: how it exited, or the signal
   that stopped it, which is also how a body that overflows the stack
   ends. */
static String _exit_reason(void) {
  int signal, code = Job.decode_wait_status(_stop(0), signal);
  if (!signal) return %"the body exited with status $code";
  String name = String.new(strsignal(signal));
  return %"the body crashed or overflowed the stack (signal $signal: $name)";
}

// frames

/* Sends one frame, returning 1, 0 when the helper has gone, or -1 when
   `deadline` passes. A helper that has exited must not end the compiler
   with SIGPIPE; a helper not reading must not block its deadline. */
static int _write_frame(List message, double deadline) {
  Buffer out = $auto(Buffer.new(0));
  if (!datum_frame(out, message)) return 0;
  String frame = %"$out";
  void (*previous)(int) = signal(SIGPIPE, SIG_IGN);
  size_t done = 0, size = frame.len();
  int status = 1;
  while (done < size) {
    int wait = 100;
    if (deadline > 0) {
      double left = deadline - _now();
      if (left <= 0) { status = -1; break; }
      if (left < 0.1) wait = (int) (left * 1000) + 1;
    }
    ssize_t n = write(active.to, (char *) frame + done, size - done);
    if (n > 0) { done += n; continue; }
    if (n < 0 && errno == EINTR) continue;
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      struct pollfd ready = { .fd = active.to, .events = POLLOUT };
      int polled = poll(&ready, 1, wait);
      if ((polled < 0 && errno != EINTR) || _reaped() ||
          (ready.revents & (POLLERR | POLLHUP | POLLNVAL))) {
        status = 0;
        break;
      }
      continue;
    }
    status = 0;
    break;
  }
  signal(SIGPIPE, previous);
  return status;
}

/* Reads the next reply frame into `reply`. Returns 1, 0 when the helper
   ended, or -1 when `deadline` passed first. */
static int _read_reply(double deadline, Var &reply) {
  for (;;) {
    int framed = 0;
    try framed = _take_frame(reply);
    catch %((!or incomplete malformed) *): return 0;
    if (framed) return 1;
    int more = _read_input(deadline);
    if (more <= 0) return more;
  }
}

/* Moves the first frame of the reply bytes read so far into `reply`, or
   returns 0 while they hold no complete frame. */
static int _take_frame(Var &reply) {
  String input = active.input;
  size_t used = 0;
  if (!datum_unframe(input, used, reply)) return 0;
  String rest = input[used:];
  active.input.clear();
  if (rest) active.input.write(rest);
  return 1;
}

/* Waits for more reply bytes until `deadline`, or for as long as it takes
   when it is 0, and reads them. Returns 1 to look for a frame again, 0
   when the helper ended, or -1 when `deadline` passed first. A process
   that the helper started before it could close its end of the replies
   keeps that end open after the helper ends, so a wait lasts at most
   100 ms before it asks whether the helper has ended. */
static int _read_input(double deadline) {
  int wait = 100;
  if (deadline > 0) {
    double left = deadline - _now();
    if (left <= 0) return -1;
    if (left < 0.1) wait = (int) (left * 1000) + 1;
  }
  struct pollfd ready = { .fd = active.from, .events = POLLIN };
  int polled = poll(&ready, 1, wait);
  if (polled < 0 && errno == EINTR) return 1;
  if (polled == 0) return _reaped() ? 0 : 1;
  char bytes[65536];
  ssize_t n = read(active.from, bytes, sizeof bytes);
  if (n < 0 && errno == EINTR) return 1;
  if (n <= 0) return 0;
  active.input.write(String.new_len(bytes, n));
  return 1;
}

// failures

static void _refuse(Call &call, String why) =>
  call.compiler.refuse_meta_call(call.name, call.site, why);

/* Kills the helper, which passed the call's deadline, and reports the
   call. */
static void _overdue(Call &c) {
  _stop(SIGKILL);
  $fail.meta_helper_client_helper_timeout(c.compiler, c.site, c.limit, c.name);
}

static void _stopped(Call &call, String reason) {
  $fail.meta_helper_client_helper_stopped(
    call.compiler, call.site, call.name, reason);
}

// lifecycle

/** Creates an independent helper at `path`, with failures by table index
    and source paths mapped to their table indices. No process starts until
    a call needs it. The caller keeps the canonical configuration values. */
MetaHelper MetaHelper.new(String path, Map failures, Map units) {
  MetaHelper helper = Scope.malloc_finalized(sizeof(struct MetaHelper), _drop);
  *helper = (struct MetaHelper) {
    .path = path, .to = -1, .from = -1, .status = -1};
  $scope(&helper.scope) {
    helper.failures = failures ? failures.copy() : NULL;
    helper.units = units ? units.copy() : NULL;
    helper.input = Buffer.new(0);
  }
  return helper;
}

/** Retains this helper's executable independently of later cache rebuilds.
    The copy lasts until close, including across helper restarts. */
void MetaHelper.retain_executable(MetaHelper helper) {
  helper.snapshot = Path.temp_dir();
  String path = %"${helper.snapshot}/helper";
  Path.copy_file(helper.path, path);
  helper.path = path;
}

/** Uses `helper` for ordinary translation, retaining its configuration
    through process shutdown. Replaces and closes the preceding helper. */
void Compiler.use_meta_helper(MetaHelper helper) {
  if (primary) primary.close();
  if (!primary_scope) Scope.shutdown_hook(_shutdown);
  primary = helper;
  if (!helper) return;
  Scope.move(helper, &primary_scope);
  helper.path.try_own();
  foreach (Var (key, value), helper.failures) value.string().try_own();
  foreach (Var (key, value), helper.units) key.string().try_own();
}

/** Checks that this helper built the provider table needed by `name`.
    Does not invoke the function or reset native state. */
void MetaHelper.check(MetaHelper m, Compiler c, String name, String provider) {
  MetaHelper previous = active;
  active = m;
  defer active = previous;
  Call call = {
    .compiler = c, .name = name, .site = c.token,
    .table = _table_of(Path.real(provider), 0)};
  _check(call);
}

/** Selects the table of the unit at `filename` for the calls that follow,
    and resets the unit's `meta static` values before the first one. */
void Compiler.begin_meta_unit(Compiler c, String filename) {
  MetaHelper previous = active;
  active = c.meta_helper ? c.meta_helper : primary;
  defer active = previous;
  if (!active) return;
  active.table = filename ? _table_of(Path.absolute(filename), 0) : 0;
  active.reset = 1;
}

/* The table of the file at `path`, or `otherwise`. */
static int _table_of(String path, int otherwise) {
  Var table;
  return active.units && path && active.units.try_get(path, table)
    ? table.integer() : otherwise;
}

/** Stops the helper this process runs, which a translation worker does
    when its units are done and every process does as it ends. */
void Compiler.stop_meta_helper(void) {
  if (!primary) return;
  MetaHelper previous = active;
  active = primary;
  defer active = previous;
  _stop(0);
}

/** Stops this helper and releases its pipe buffer and configuration maps.
    A later close is harmless. */
void MetaHelper.close(MetaHelper helper) {
  if (!helper || !helper.scope) return;
  MetaHelper previous = active;
  active = helper;
  defer active = previous;
  _stop(0);
  if (helper.snapshot) {
    unlink(%"${helper.snapshot}/helper");
    rmdir(helper.snapshot);
    helper.snapshot = NULL;
  }
  helper.scope.destroy();
  helper.scope = NULL;
  helper.path = NULL;
  helper.failures = helper.units = NULL;
  helper.input = NULL;
}

static void _drop(void *raw) { MetaHelper.close(raw); }

static void _shutdown(void) {
  primary_scope.destroy();
  primary_scope = NULL;
  primary = NULL;
}
