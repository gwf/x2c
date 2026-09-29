/*  meta-helper-client.x -- the compiler's side of the project meta helper

    Copyright (c) 2026 Gary William Flake.

    The project meta build (`meta-project.x`) compiles each unit's `meta`
    group (`meta-group.x`) into one helper program. This file owns the
    compiler's side of that helper: starting it, one request and one reply
    per call, and reporting a body that fails, crashes, or runs too long.
*/
#pragma once
#include "compiler.x"

#pragma private
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

/* The project's helper, its tables' failures by index, and the table each
   input calls, which last for the process; a forked translation worker
   inherits them. */
static String helper_path = NULL;
static Map helper_failures = NULL, helper_units = NULL;
static Scope helper_scope = NULL;

/* The helper this process runs, its ends of the two pipes, the reply bytes
   read so far, the table the unit being translated calls, whether that
   unit's reset is still to be sent, and the helper's wait status once it
   has been reaped, or -1. */
static pid_t helper_pid = 0, helper_owner = 0;
static int helper_to = -1, helper_from = -1, helper_table = 0;
static int helper_reset = 0, helper_status = -1;
static Buffer helper_input = NULL;

// calls

/* One call of a project `meta` function, whose failures are reported at
   `site`. Its reply is due by `deadline`, `limit` seconds after the
   request, or at any time when `deadline` is 0. */
typedef struct Call {
  Compiler compiler, String name, Token site, double limit, deadline;
} Call;

/** Calls the project `meta` function `name` in the helper with the values
    `arguments`, for the call at `site`, and returns its result. A warning
    the body makes is reported at `site` and a failure it reports is the
    call's failure. A body that crashes, exits, or passes the deadline ends
    the helper, which is reported at `site` and started again for the next
    call. */
Var Compiler.meta_helper_call(
  Compiler c, String name, Token site, List arguments) {
  Call call = {.compiler = c, .name = name, .site = site};
  call.check();
  if (!_helper_start()) call.refuse("the compile-time helper did not start");
  call.send(arguments);
  call.set_deadline();
  for (;;) {
    Var reply = call.next_reply();
    match (reply) {
      case %(warning ?(String message) ?(List notes)):
        c.report_warning(<macro>, message, site, notes);
      case %(value ?value): return value;
      case %(void): return void;
      case %(error ?(String message) ?(List notes)):
        c.report_error(<macro>, message, site, notes);
      case %(dependency ?(String path) ?(String hash)):
        c.deps.merge_translation_dependency(path, hash);
      case %(missing): call.refuse(c.meta_call_missing(name));
      case %(failure (?code *detail)): Error.raise(code, detail);
      default: call.stopped("the helper sent an unknown reply");
    }
  }
}

/* Refuses the call when the project's helper or the unit's table did not
   build, or when the function returns a struct or union. */
static void Call.check(Call *call) {
  Var failure;
  if (!helper_path && helper_failures && helper_failures.try_get(-1, failure))
    call.refuse(failure);
  if (!helper_path) call.refuse("the project meta module was not built");
  if (helper_failures && helper_failures.try_get(helper_table, failure))
    call.refuse(failure);
  call.compiler.refuse_record_meta_call(call.name, call.site);
}

/* Sends the call, after the unit's reset when that is still to be sent. */
static void Call.send(Call *call, List arguments) {
  if (helper_reset) {
    _helper_send(%(reset $helper_table));
    helper_reset = 0;
  }
  _helper_send(%(call ${call.name} $arguments ${Macro.subject()}));
}

/* The limit is `X2C_META_TIMEOUT` in seconds, 60 by default; zero or less
   sets no deadline. */
static void Call.set_deadline(Call *call) {
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
static Var Call.next_reply(Call *call) {
  Var reply;
  int status = _helper_receive(call.deadline, reply);
  if (status < 0) call.overdue();
  if (!status) call.stopped(_helper_ending());
  return reply;
}

// the helper process

/* Starts the helper unless this process runs one. Every pipe end is
   close-on-exec, and the helper keeps only its descriptors 3 and 4, so it
   reads the end of its requests as soon as this process closes its end or
   ends. The helper leads a process group of its own, which every process
   it starts joins; this side sets the group too, so it exists before the
   helper runs. */
static int _helper_start(void) {
  if (_helper_running()) return 1;
  helper_pid = 0;
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
  pid_t pid = fork();
  if (!pid) _helper_exec(requests[0], replies[1]);
  close(requests[0]);
  close(replies[1]);
  if (pid < 0) {
    close(requests[1]);
    close(replies[0]);
    return 0;
  }
  setpgid(pid, pid);
  helper_pid = pid;
  helper_owner = getpid();
  helper_to = requests[1];
  helper_from = replies[0];
  if (helper_input) helper_input.clear();
  helper_reset = 1;
  return 1;
}

/* Runs the helper in the forked child with its requests on descriptor 3
   and its replies on 4, as the leader of a new process group. Copying each
   end above 10 first keeps `dup2` from overwriting the other end or
   leaving one close-on-exec. */
static void _helper_exec(int requests, int replies) {
  int in = fcntl(requests, F_DUPFD_CLOEXEC, 10);
  int out = fcntl(replies, F_DUPFD_CLOEXEC, 10);
  dup2(in, 3);
  dup2(out, 4);
  setpgid(0, 0);
  execl(helper_path, helper_path, (char *) NULL);
  _exit(127);
}

/* Whether this process started the helper `helper_pid` names. A worker
   forked from a process that runs one starts its own. */
static int _helper_running(void) => helper_pid > 0 && helper_owner == getpid();

/* Whether the helper has ended, which reaps it and keeps its status. */
static int _helper_reaped(void) {
  int status;
  if (helper_status < 0 &&
      waitpid(helper_pid, &status, WNOHANG) == helper_pid)
    helper_status = status;
  return helper_status >= 0;
}

/* Ends the helper this process started, if any, and forgets it: asks it
   to quit, or sends `signal` to its process group, and reaps it. A process
   group lasts, under its id, while any process in it runs, so killing the
   helper's group after the reap ends only what the helper started and
   left running, such as a job whose body crashed. Returns the helper's
   wait status. */
static int _helper_stop(int signal) {
  int status = 0;
  if (_helper_running()) {
    if (signal) killpg(helper_pid, signal);
    else _helper_send(%(quit));
    close(helper_to);
    close(helper_from);
    if (helper_status < 0) waitpid(helper_pid, &helper_status, 0);
    killpg(helper_pid, SIGKILL);
    status = helper_status;
  }
  helper_pid = 0;
  helper_status = -1;
  helper_to = helper_from = -1;
  if (helper_input) helper_input.clear();
  return status;
}

/* Why the helper that answered no more ended: how it exited, or the signal
   that stopped it, which is also how a body that overflows the stack
   ends. */
static String _helper_ending(void) {
  int status = _helper_stop(0), code = WEXITSTATUS(status);
  if (!WIFSIGNALED(status)) return %"the body exited with status $code";
  int signal = WTERMSIG(status);
  String name = String.new(strsignal(signal));
  return %"the body crashed or overflowed the stack (signal $signal: $name)";
}

// frames

/* Sends one frame, or returns 0 when the helper has gone. A write to a
   helper that has exited must not end the compiler with SIGPIPE. */
static int _helper_send(List message) {
  Buffer out = $auto(Buffer.new(0));
  if (!datum_frame(out, message)) return 0;
  String frame = %"$out";
  void (*previous)(int) = signal(SIGPIPE, SIG_IGN);
  size_t done = 0, size = frame.len();
  while (done < size) {
    ssize_t n = write(helper_to, (char *) frame + done, size - done);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) break;
    done += n;
  }
  signal(SIGPIPE, previous);
  return done == size;
}

/* Reads the next reply frame into `reply`. Returns 1, 0 when the helper
   ended, or -1 when `deadline` passed first. */
static int _helper_receive(double deadline, Var &reply) {
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
  String input = helper_input;
  size_t used = 0;
  if (!datum_unframe(input, used, reply)) return 0;
  String rest = input[used:];
  helper_input.clear();
  if (rest) helper_input.write(rest);
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
  struct pollfd ready = { .fd = helper_from, .events = POLLIN };
  int polled = poll(&ready, 1, wait);
  if (polled < 0 && errno == EINTR) return 1;
  if (polled == 0) return _helper_reaped() ? 0 : 1;
  char bytes[65536];
  ssize_t n = read(helper_from, bytes, sizeof bytes);
  if (n < 0 && errno == EINTR) return 1;
  if (n <= 0) return 0;
  helper_input.write(String.new_len(bytes, n));
  return 1;
}

// failures

static void Call.refuse(Call *call, String why) =>
  call.compiler.refuse_meta_call(call.name, call.site, why);

/* Kills the helper, which passed the call's deadline, and reports the
   call. */
static void Call.overdue(Call *call) {
  _helper_stop(SIGKILL);
  call.compiler.report_error(
    <macro>, "%s%g s".printf("this meta call ran longer than ", call.limit),
    call.site,
    %("function: ${call.name}"
      "set X2C_META_TIMEOUT to a larger limit in seconds, or 0 for none"));
}

static void Call.stopped(Call *call, String reason) {
  call.compiler.report_error(
    <macro>, "this meta call stopped the compile-time helper", call.site,
    %("function: ${call.name}" "reason: $reason"));
}

// lifecycle

/** Uses the helper at `path`, or none when it is NULL, whose tables named
    in `failures` could not be built, each with why, and whose table for
    each input path is in `units`. */
void Compiler.use_meta_helper(String path, Map failures, Map units) {
  if (!path && !failures) return;
  if (!helper_scope) Scope.shutdown_hook(_helper_shutdown);
  $scope(&helper_scope) {
    helper_path = path ? String.new(path) : NULL;
    helper_failures = failures ? failures.copy() : NULL;
    helper_units = units ? units.copy() : NULL;
    helper_input = Buffer.new(0);
  }
}

/** Selects the table of the unit at `filename` for the calls that follow,
    and resets the unit's `meta static` values before the first one. */
void Compiler.begin_meta_unit(String filename) {
  Var table;
  helper_table = helper_units && filename &&
    helper_units.try_get(Path.absolute(filename), table) ? table.integer() : 0;
  helper_reset = 1;
}

/** Stops the helper this process runs, which a translation worker does
    when its units are done and every process does as it ends. */
void Compiler.stop_meta_helper(void) { _helper_stop(0); }

static void _helper_shutdown(void) {
  _helper_stop(0);
  helper_scope.destroy();
  helper_scope = NULL;
  helper_path = NULL;
  helper_failures = helper_units = NULL;
  helper_input = NULL;
}
