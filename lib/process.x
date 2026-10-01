/*  process.x -- run commands and pipelines without a shell

    Copyright (c) 2026 Gary William Flake

    Job owns running a command or pipeline without a shell. A command is an
    ordinary `List` whose elements' `str`s become its arguments, and a `List`
    of commands is a pipeline. A job runs once, when its first result is
    requested, and records that run; its status is the last failing stage's
    status, with 128 plus the signal for a signalled stage. The calling
    process's own environment is read here too, beside the `env` option that
    sets a child's.
*/

#pragma once
#include "x2c.x"

/** A command or pipeline and the record of its one run.
    A job that is still running when its Scope ends, or when its `$auto`
    block exits, is terminated and reaped.
*/
class Job struct {
  List stages;
  struct _Launch *launch;
  long *pids;
  int *statuses;
  int count, started, finished, status, nul_output, nul_errors;
  File output_file, errors_file;
  String output_text, errors_text;
} *;

protocol Cleanup(Job);

meta Job Var.job(Var value);
meta Var Job.var(Job job);

/** The receiverless owner of `Env.get`. */
typedef enum Env {
  ENV_NAMESPACE
} Env;

#pragma private

#include "meta.x"
$(import "job-errors.xmacro")

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

/* Everything a child needs is prepared before `fork`, so the child only
   duplicates descriptors, changes directory, and calls `execvp`. */
typedef struct _Launch {
  String dir, input, stdout_path, stderr_path;
  int has_input, capture_output, capture_errors, errors_to_output;
  char **environment;
} Launch;

/* The descriptors a stage reads and writes as its standard streams. -1
   leaves a stream inherited from the parent. */
typedef struct Stdio { int input, output, errors; } Stdio;

/* What a child writes to its report pipe when a step fails: the step and
   its errno. */
typedef struct Failure { int step, error; } Failure;

enum { _STEP_DIR = 1, _STEP_EXEC = 2 };

// launching

/* The one launch of a job. The job counts as started before the first
   fork, so a launch that fails part way records its partial run: the stages
   already started are terminated and reaped, and capture files are closed,
   before the error transfers. `stdio` holds the next stage's input, the
   last stage's output, and every stage's errors. */
static void Job._start(Job j) {
  j.started = 1;
  j._open_table();
  Stdio stdio = { -1, -1, -1 }, int launched = 0;
  defer if (!launched) j.cleanup();
  defer j._close_streams(stdio);
  j._open_streams(stdio);
  fflush(NULL);
  int index = 0;
  foreach (List stage, j.stages) stdio.input = j._stage(index++, stage, stdio);
  launched = 1;
}

/* The finalizer reaps through `pids`, and newer blocks in the job's Scope
   are reclaimed before it runs, so the table lives outside the Scope. A
   stage the launch never reaches reports 127. */
static void Job._open_table(Job job) {
  int count = job.stages.len();
  job.pids = calloc(count + 1, sizeof(long) + sizeof(int));
  if (!job.pids) $job.error("start.alloc");
  job.statuses = (int *) (job.pids + count + 1);
  job.count = count;
  for (int i = 0; i < job.count; i++) job.statuses[i] = 127;
}

/* A capture file's descriptor closes with the file, when the job reads it. */
static void Job._close_streams(Job job, Stdio stdio) {
  _close(stdio.input);
  if (!job.output_file) _close(stdio.output);
  if (!job.errors_file) _close(stdio.errors);
}

/* The first stage reads the `input` text, the last writes the `stdout`
   stream, and every stage writes the `stderr` stream. Each descriptor
   reaches `stdio` as it opens, so the launch closes it on every exit. */
static void Job._open_streams(Job job, Stdio &stdio) {
  Launch *launch = job.launch;
  if (launch.has_input) stdio.input = _input(launch.input);
  stdio.output =
    _stream(job.output_file, launch.capture_output, launch.stdout_path);
  stdio.errors =
    _stream(job.errors_file, launch.capture_errors, launch.stderr_path);
}

/* The first stage reads a copy of the descriptor of a capture file that
   holds `text`. */
static int _input(String text) {
  File file = $auto(_capture_file());
  file.write_all(text, text.len());
  file.rewind();
  int fd = dup(file.fileno());
  _close_on_exec(fd);
  return fd;
}

/* A stream the stages write: a capture file, which the job keeps in `file`
   and reads when it finishes, the file at `path`, or -1 for the parent's. */
static int _stream(File &file, int capture, String path) {
  if (!capture) return path ? _open_output(path) : -1;
  file = _capture_file();
  return file.fileno();
}

/* Spawns `stage` and returns the read end of the pipe to the next stage,
   or -1 after the last. The pipe belongs to the stage until it spawns: a
   `spawned` flag disarms the cleanup, since a write into `link` would put
   the array in the transfer-preserved set, whose qualifier `_pipe` would
   then discard. */
static int Job._stage(Job job, int index, List stage, Stdio stdio) {
  int link[2] = { -1, -1 };
  if (index < job.count - 1) {
    _pipe(link);
    stdio.output = link[1];
  }
  int spawned = 0;
  {
    defer if (!spawned) { _close(link[0]); _close(link[1]); }
    job._spawn(index, stage, stdio);
    spawned = 1;
  }
  _close(link[1]);
  _close(stdio.input);
  return link[0];
}

// spawning a stage

static void Job._spawn(Job job, int index, List stage, Stdio stdio) {
  char **argv = _argv(stage);
  int report[2];
  _pipe(report);
  pid_t pid = fork();
  if (pid == 0) _child(argv, job.launch, stdio, report[1]);
  int fork_error = errno;
  close(report[1]);
  Failure failure = {0};
  if (pid > 0) failure = _read_report(report[0]);
  close(report[0]);
  if (pid < 0) _io_fail(fork_error);
  job.pids[index] = pid;
  if (failure.step) _child_failed(failure, job.launch.dir, argv);
}

static char **_argv(List stage) {
  if (!stage) $job.error("start.empty");
  char **argv = Scope.calloc(stage.len() + 1, sizeof(char *));
  int index = 0;
  // An empty word is a NULL String, which would end the vector early.
  foreach (Var word, stage) {
    String text = word.str();
    argv[index++] = text ? text : "";
  }
  return argv;
}

/* The report pipe is close-on-exec: a successful `execvp` closes it without
   writing, and a failed step writes which step failed and its errno. */
static void _child(char **argv, Launch *launch, Stdio stdio, int report) {
  stdio.input = _above_stdio(stdio.input);
  stdio.output = _above_stdio(stdio.output);
  stdio.errors = _above_stdio(stdio.errors);
  report = _above_stdio(report);
  if (stdio.input >= 0) dup2(stdio.input, STDIN_FILENO);
  if (stdio.output >= 0) dup2(stdio.output, STDOUT_FILENO);
  if (launch.errors_to_output) dup2(STDOUT_FILENO, STDERR_FILENO);
  else if (stdio.errors >= 0) dup2(stdio.errors, STDERR_FILENO);
  Failure failure = { _STEP_DIR, 0 };
  if (!launch.dir || chdir(launch.dir) == 0) {
    if (launch.environment) environ = launch.environment;
    execvp(argv[0], argv);
    failure.step = _STEP_EXEC;
  }
  failure.error = errno;
  ssize_t written = write(report, &failure, sizeof(failure));
  (void) written;
  _exit(127);
}

/* A parent with its standard streams closed can hold a launch descriptor at
   0, 1, or 2, where an earlier `dup2` would overwrite it and a `dup2` onto
   its own number would leave it close-on-exec. The copy closes on exec. */
static int _above_stdio(int fd) =>
  fd >= 0 && fd <= STDERR_FILENO ?
    fcntl(fd, F_DUPFD_CLOEXEC, STDERR_FILENO + 1) : fd;

/* The child's report, or a zero step when `execvp` closed the pipe without
   one. */
static Failure _read_report(int fd) {
  Failure failure = {0};
  ssize_t count;
  do count = read(fd, &failure, sizeof(failure));
  while (count < 0 && errno == EINTR);
  return count == sizeof(failure) ? failure : (Failure) {0};
}

static void _child_failed(Failure failure, String dir, char **argv) {
  int error = failure.error;
  if (failure.step == _STEP_DIR) File.path_error("Job.start", dir, error);
  String program = argv[0];
  if (error == ENOENT)
    $job.error("start.missing", program, error);
  $job.error("start.program", program, error);
}

// descriptors

static File _capture_file(void) {
  File file = tmpfile();
  if (!file) _io_fail(errno);
  _close_on_exec(file.fileno());
  return file;
}

static void _close_on_exec(int fd) {
  fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);
}

static int _open_output(String path) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (fd < 0) {
    int error = errno;
    $job.error("start.path", path, error);
  }
  _close_on_exec(fd);
  return fd;
}

static void _pipe(int fds[2]) {
  if (pipe(fds)) _io_fail(errno);
  _close_on_exec(fds[0]);
  _close_on_exec(fds[1]);
}

static void _close(int fd) {
  if (fd >= 0) close(fd);
}

static void _io_fail(int error) {
  $job.error("start.io", error);
}

// waiting

static void Job._reap(Job job, int index, int flags) {
  int status;
  pid_t pid;
  do pid = waitpid((pid_t) job.pids[index], &status, flags);
  while (pid < 0 && errno == EINTR);
  if (!pid) return;
  job.statuses[index] = pid < 0 ? -1 : _decoded_status(status);
  job.pids[index] = 0;
}

static int _decoded_status(int status) {
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
  return -1;
}

static int Job._running(Job job) {
  int running = 0;
  for (int i = 0; i < job.count; i++) {
    if (job.pids[i]) job._reap(i, WNOHANG);
    if (job.pids[i]) running = 1;
  }
  return running;
}

static void Job._finish(Job job) {
  if (job.finished) return;
  job.finished = 1;
  for (int i = 0; i < job.count; i++)
    if (job.statuses[i]) job.status = job.statuses[i];
  job.output_text = _captured(job.output_file, job.nul_output);
  job.errors_text = _captured(job.errors_file, job.nul_errors);
}

/* Reads and closes a capture file. Text with a NUL byte cannot be a
   `String`, so it is recorded in `nul` for `output` or `errors` to raise and
   the status stays readable. */
static String _captured(File &file, int &nul) {
  File owned = file;
  file = NULL;
  if (!owned) return NULL;
  owned.rewind();
  String text = NULL;
  try text = owned.string_close();
  catch %(bad-arg *): nul = 1;
  return text;
}

/* Terminates and reaps every running stage without touching capture files,
   which may already be reclaimed when a finalizer calls this. */
static void Job._terminate(Job job) {
  job.kill(SIGTERM);
  for (int waited = 0; waited < 1000 && job._running(); waited++) usleep(1000);
  job.kill(SIGKILL);
  for (int i = 0; i < job.count; i++) if (job.pids[i]) job._reap(i, 0);
}

// jobs

/** Returns a `Job` for `command`, a command or pipeline, without starting
    it. The job captures standard output and passes standard error through.
    Its first result starts it, waits, and records the run. A `Job`
    destination calls this converter, so the call is usually left implicit.

    ```x2c
    ~#include "process.x"
    ~int main(void) {
    Job job = %(printf "a\nb\n");
    ~  return job.status() == 0 && job.lines().len() == 2 ? 0 : 1;
    ~}
    ```
*/
meta native Job List.job(List command) => Job.new(command);

static Job Job.new(List command) {
  Job job = Scope.malloc_finalized(sizeof(struct Job), _drop_job);
  memset(job, 0, sizeof(struct Job));
  job.stages = _stages(command);
  job.launch = Scope.calloc(1, sizeof(Launch));
  job.launch.capture_output = 1;
  return job;
}

static void _drop_job(void *ptr) {
  Job job = ptr;
  if (job.started && !job.finished) job._terminate();
  if (job.output_file) job.output_file.close();
  if (job.errors_file) job.errors_file.close();
  job.output_file = job.errors_file = NULL;
  free(job.pids);
}

// A command whose first element is a List is a pipeline of those commands.
static List _stages(List command) =>
  command && command.car() is List ? command : %($command);

/** Adds `command` after the last stage of `job`, reading that stage's
    output, and returns the job. A pipeline `command` adds each of its
    stages.
    Raises: `<bad-arg>` for a job that has started.
*/
Job Job.pipe(Job job, List command) {
  job._unstarted("Job.pipe");
  job.stages = job.stages.append(_stages(command));
  return job;
}

static Job Job._unstarted(Job job, String operation) {
  if (job.started)
    $job.error("job.started", operation);
  return job;
}

// options

/** Sets `options` on `job` and returns it.
    The keys are atoms: `dir` names the working directory, `env` is a `Map`
    of variables added to the inherited environment, and `input` is a
    `String` given to the first stage's standard input. `stdout` is
    `capture`, `inherit`, or a file path and applies to the last stage;
    `stderr` is `inherit`, `capture`, `stdout` to merge, or a file path and
    applies to every stage. A key set again replaces its earlier value.

    ```x2c
    ~#include "process.x"
    ~int main(void) {
    String root = %(pwd).job().options({dir: "/"}).output();
    ~  return root == "/\n" ? 0 : 1;
    ~}
    ```

    Raises: `<bad-arg>` for an unknown key or a job that has started.
*/
Job Job.options(Job job, Map options) {
  Launch *launch = job._unstarted("Job.options").launch;
  foreach (Var (key, value), options) {
    if (key is not Symbol)
      $job.error("options.key");
    launch.set(key, value);
  }
  return job;
}

static void Launch.set(Launch *l, Symbol name, Var value) {
  switch (name) {
    case <dir>:    l.dir = value; break;
    case <env>:    l.environment = _environment(value); break;
    case <input>:  l.input = value; l.has_input = 1; break;
    case <stdout>: l.route_output(value); break;
    case <stderr>: l.route_errors(value); break;
    default: $job.error("options.unknown", name);
  }
}

static void Launch.route_output(Launch *l, Var value) {
  l.capture_output = _is(value, <capture>);
  l.stdout_path = l.capture_output || _is(value, <inherit>) ? NULL : value;
}

static void Launch.route_errors(Launch *l, Var value) {
  l.capture_errors = _is(value, <capture>);
  l.errors_to_output = _is(value, <stdout>);
  l.stderr_path = l.capture_errors || l.errors_to_output ||
    _is(value, <inherit>) ? NULL : value;
}

static int _is(Var value, Symbol name) =>
  value is Symbol && value == name;

/** Makes `job` pass standard output through instead of capturing it, the
    same as `options({stdout: <inherit>})`, and returns it.
    Raises: `<bad-arg>` for a job that has started.
*/
Job Job.live(Job job) => job.options({stdout: <inherit>});

// running jobs

/** Starts `job` without waiting and returns it. A job that has started is
    returned unchanged.
    Raises: `<not-found>` when a program or the `dir` option does not exist,
    `<io-fail>` when a pipe, fork, output file, or other start step fails, or
    `<bad-arg>` for an empty command.
*/
meta native Job Job.start(Job job) {
  if (!job.started) job._start();
  return job;
}

/** Returns the status of `job`, starting it and waiting as needed: the exit
    status, or 128 plus a signal. A stage that never ran because the start
    raised reports 127. A status that is not zero is an ordinary result here.
    Raises: the start causes of `Job.start`.
*/
int Job.status(Job job) {
  job.start();
  for (int i = 0; i < job.count; i++) if (job.pids[i]) job._reap(i, 0);
  job._finish();
  return job.status;
}

/** Returns `job` once its status is zero, starting it and waiting as needed.
    Raises: `<cmd-fail>` with `command` and `status` details, plus `output`
    and `errors` when they were captured, or the start causes of `Job.start`.
*/
Job Job.check(Job job) {
  int status = job.status();
  if (!status) return job;
  List stages = job.stages;
  List command = stages.cdr() ? stages : stages.car();
  String output = job.output_text, errors = job.errors_text;
  int captured = job.launch.capture_output;
  int logged = job.launch.capture_errors;
  if (captured && logged)
    $job.error("check.both", command, status, output, errors);
  if (captured)
    $job.error("check.output", command, status, output);
  if (logged)
    $job.error("check.errors", command, status, errors);
  $job.error("check.status", command, status);
}

/** Passes standard output through, waits for `job`, and raises when its
    status is not zero: `live()` followed by `check()`.
    Raises: the causes of `Job.live` and `Job.check`.
*/
void Job.run(Job job) {
  job.live().check();
}

/** Returns the captured standard output of `job`, starting it and waiting
    as needed. A live job, or one whose output was empty, returns NULL.
    Raises: the causes of `Job.check`, or `<bad-arg>` when the output
    contains a NUL byte.
*/
String Job.output(Job job) {
  job.check();
  return _text(job.output_text, job.nul_output, "Job.output");
}

static String _text(String text, int nul, String operation) {
  if (nul) $job.error("text.nul", operation);
  return text;
}

/** Returns the captured standard output of `job` as lines without their
    endings.
    Raises: the causes of `Job.output`.
*/
List Job.lines(Job job) => job.output().split_lines(0);

/** Returns the captured standard error of `job`, starting it and waiting as
    needed, or NULL when standard error was not captured or was empty.
    Raises: the start causes of `Job.start`, or `<bad-arg>` when the captured
    text contains a NUL byte.
*/
String Job.errors(Job job) {
  job.status();
  return _text(job.errors_text, job.nul_errors, "Job.errors");
}

/** Reports whether every stage of `job` has exited, without blocking. A job
    that has not started reports 0.
*/
int Job.ready(Job job) {
  if (!job.started) return 0;
  if (job.finished) return 1;
  if (job._running()) return 0;
  job._finish();
  return 1;
}

/** Sends `signal` to every stage of `job` that is still running. */
void Job.kill(Job job, int signal) {
  for (int i = 0; i < job.count; i++)
    if (job.pids[i]) kill((pid_t) job.pids[i], signal);
}

/** Terminates and reaps a job that is still running: `SIGTERM`, then
    `SIGKILL` to any stage still running a second later.
*/
void Job.cleanup(Job job) {
  if (!job || !job.started || job.finished) return;
  job._terminate();
  job._finish();
}

/** Removes and returns the first job in `jobs` that has finished, waiting
    until one does. An empty `jobs` returns NULL.
    Raises: `<bad-arg>` when a job in `jobs` has not started.
*/
Job Job.wait_any(Array jobs) {
  foreach (Job job, jobs)
    if (!job.started)
      $job.error("wait.unstarted");
  while (jobs.len()) {
    for (int i = 0; i < jobs.len(); i++) {
      Job job = jobs[i];
      if (job.ready()) return jobs.remove(i);
    }
    usleep(1000);
  }
  return NULL;
}

// the environment

/** Returns the value of this process's environment variable `name`, or
    NULL when it is unset. The `env` option sets variables for a child
    instead.
*/
String Env.get(String name) {
  const char *value = getenv(name);
  return value ? String.new(value) : NULL;
}

static char **_environment(Map env) {
  Map names = {};
  foreach (Var name, env.keys()) names[name.str()] = 1;
  Array entries = [];
  for (char **entry = environ; *entry; entry++) {
    String text = String.new(*entry);
    int equals = text.find("=");
    if (!names.contains(equals < 0 ? text : text[:equals])) entries.push(text);
  }
  foreach (Var (name, value), env) entries.push(%"$name=$value");
  char **out = Scope.calloc(entries.len() + 1, sizeof(char *));
  int index = 0;
  foreach (String entry, entries) out[index++] = entry;
  return out;
}
