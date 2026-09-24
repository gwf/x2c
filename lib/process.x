/*  process.x -- run commands and pipelines without a shell

    Copyright (c) 2026 Gary William Flake

    A command is an ordinary `List`. Each element's `str` becomes one
    argument and no shell reads the words, so `%(grep $pattern $file)` passes
    a pattern containing spaces or quotes as a single argument. A `List`
    whose first element is itself a `List` is a pipeline, one command per
    element. `List.job` turns a command into a `Job`, which holds its stages
    and stream options until the first result requested starts it. That run
    is recorded, so a job runs exactly once however many results are read
    from it.

    A pipeline's status is the status of its last failing stage, or zero
    when every stage succeeds. A signalled stage reports 128 plus the signal.

    This module also owns the calling process's own environment, which a
    script reads to decide what to run.
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

/** The receiverless owner of `Env.get`. */
typedef enum Env {
  ENV_NAMESPACE
} Env;

#pragma private

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
} _Launch;

enum { _STEP_DIR = 1, _STEP_EXEC = 2 };

static int _decoded_status(int status) {
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
  return -1;
}

static char **_environment(Map env) {
  Map names = {};
  foreach (Var name, env.keys()) names[name.str()] = 1;
  Array entries = [];
  for (char **entry = environ; *entry; entry++) {
    String text = String.new(*entry);
    int equals = text.find("=");
    if (!names.contains(equals < 0 ? text : text[:equals]))
      entries.push(text);
  }
  foreach (Var (name, value), env)
    entries.push(%"$name=$value");
  char **result = Scope.calloc(entries.len() + 1, sizeof(char *));
  int index = 0;
  foreach (String entry, entries) result[index++] = entry;
  return result;
}

// A command whose first element is a List is a pipeline of those commands.
static List _stages(List command) =>
  command && command.car() is List ? command : %($command);

static int _is(Var value, Symbol name) =>
  value is Symbol && value == name;

static void _close_on_exec(int fd) {
  fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);
}

static void _pipe(int fds[2]) {
  if (pipe(fds)) {
    int error = errno;
    raise %(io-fail (operation "Job.start") (errno $error));
  }
  _close_on_exec(fds[0]);
  _close_on_exec(fds[1]);
}

static int _open_output(String path) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (fd < 0) {
    int error = errno;
    raise %(io-fail (operation "Job.start") (path $path) (errno $error));
  }
  _close_on_exec(fd);
  return fd;
}

static File _capture_file(void) {
  File file = tmpfile();
  if (!file) {
    int error = errno;
    raise %(io-fail (operation "Job.start") (errno $error));
  }
  _close_on_exec(file.fileno());
  return file;
}

static void _close(int fd) {
  if (fd >= 0) close(fd);
}

static char **_argv(List stage) {
  if (!stage)
    raise %(bad-arg (operation "Job.start") (why "empty command"));
  char **argv = Scope.calloc(stage.len() + 1, sizeof(char *));
  int index = 0;
  // An empty word is a NULL String, which would end the vector early.
  foreach (Var word, stage) {
    String text = word.str();
    argv[index++] = text ? text : "";
  }
  return argv;
}

/* A parent with its standard streams closed can hold a launch descriptor at
   0, 1, or 2, where an earlier `dup2` would overwrite it and a `dup2` onto
   its own number would leave it close-on-exec. The copy closes on exec. */
static int _above_stdio(int fd) =>
  fd >= 0 && fd <= STDERR_FILENO ?
    fcntl(fd, F_DUPFD_CLOEXEC, STDERR_FILENO + 1) : fd;

/* The report pipe is close-on-exec: a successful `execvp` closes it without
   writing, and a failed step writes which step failed and its errno. */
static void _child(
  char **argv, _Launch *launch, int stdin_fd, int stdout_fd, int stderr_fd,
  int report) {
  stdin_fd = _above_stdio(stdin_fd);
  stdout_fd = _above_stdio(stdout_fd);
  stderr_fd = _above_stdio(stderr_fd);
  report = _above_stdio(report);
  if (stdin_fd >= 0) dup2(stdin_fd, STDIN_FILENO);
  if (stdout_fd >= 0) dup2(stdout_fd, STDOUT_FILENO);
  if (launch.errors_to_output) dup2(STDOUT_FILENO, STDERR_FILENO);
  else if (stderr_fd >= 0) dup2(stderr_fd, STDERR_FILENO);
  int failure[2] = { _STEP_DIR, 0 };
  if (!launch.dir || chdir(launch.dir) == 0) {
    if (launch.environment) environ = launch.environment;
    execvp(argv[0], argv);
    failure[0] = _STEP_EXEC;
  }
  failure[1] = errno;
  ssize_t written = write(report, failure, sizeof(failure));
  (void) written;
  _exit(127);
}

static void Job._spawn(
  Job job, int index, List stage, int stdin_fd, int stdout_fd,
  int stderr_fd) {
  _Launch *launch = job.launch;
  char **argv = _argv(stage);
  int report[2];
  _pipe(report);
  pid_t pid = fork();
  if (pid == 0)
    _child(argv, launch, stdin_fd, stdout_fd, stderr_fd, report[1]);
  int fork_error = errno, failure[2] = {0};
  close(report[1]);
  ssize_t count = 0;
  if (pid > 0) {
    do count = read(report[0], failure, sizeof(failure));
    while (count < 0 && errno == EINTR);
  }
  close(report[0]);
  if (pid < 0)
    raise %(io-fail (operation "Job.start") (errno $fork_error));
  job.pids[index] = pid;
  if (count != sizeof(failure)) return;
  int error = failure[1];
  if (failure[0] == _STEP_DIR)
    File.path_error("Job.start", launch.dir, error);
  String program = argv[0];
  if (error == ENOENT)
    raise %(not-found (operation "Job.start") (program $program)
            (errno $error));
  raise %(io-fail (operation "Job.start") (program $program)
          (errno $error));
}

/* The one launch of a job. The job counts as started before the first
   fork, so a launch that fails part way records its partial run: the stages
   already started are terminated and reaped, and capture files are closed,
   before the error transfers. */
static void Job._start(Job job) {
  _Launch *launch = job.launch;
  job.started = 1;
  int count = job.stages.len();
  /* The finalizer reaps through `pids`, and newer blocks in the job's Scope
     are reclaimed before it runs, so the table lives outside the Scope. */
  job.pids = calloc(count + 1, sizeof(long) + sizeof(int));
  if (!job.pids) raise %(alloc-fail);
  job.statuses = (int *) (job.pids + count + 1);
  job.count = count;
  // A stage the launch never reaches reports 127.
  for (int i = 0; i < job.count; i++) job.statuses[i] = 127;
  int previous = -1, output = -1, errors = -1, launched = 0;
  defer if (!launched) job.cleanup();
  defer {
    _close(previous);
    if (!job.output_file) _close(output);
    if (!job.errors_file) _close(errors);
  }
  if (launch.has_input) {
    File file = $auto(_capture_file());
    file.write_all(launch.input, launch.input.len());
    file.rewind();
    previous = dup(file.fileno());
    _close_on_exec(previous);
  }
  if (launch.capture_output) {
    job.output_file = _capture_file();
    output = job.output_file.fileno();
  }
  else if (launch.stdout_path) output = _open_output(launch.stdout_path);
  if (launch.capture_errors) {
    job.errors_file = _capture_file();
    errors = job.errors_file.fileno();
  }
  else if (launch.stderr_path) errors = _open_output(launch.stderr_path);
  fflush(NULL);
  int index = 0, last = job.count - 1;
  foreach (List stage, job.stages) {
    int link[2] = { -1, -1 };
    if (index < last) _pipe(link);
    /* Both ends belong to this stage until it spawns. `spawned` rather than
       a write into `link` keeps the array out of the transfer-preserved set,
       whose qualifier `_pipe` would then discard. */
    int spawned = 0;
    {
      defer if (!spawned) { _close(link[0]); _close(link[1]); }
      job._spawn(index, stage, previous, index < last ? link[1] : output,
                 errors);
      spawned = 1;
    }
    _close(link[1]);
    _close(previous);
    previous = link[0];
    index++;
  }
  launched = 1;
}

static void Job._reap(Job job, int index, int flags) {
  int status;
  pid_t pid;
  do pid = waitpid((pid_t) job.pids[index], &status, flags);
  while (pid < 0 && errno == EINTR);
  if (!pid) return;
  job.statuses[index] = pid < 0 ? -1 : _decoded_status(status);
  job.pids[index] = 0;
}

/* Reads and closes a capture file. Text with a NUL byte cannot be a
   `String`, so it is recorded in `nul` for `output` or `errors` to raise and
   the status stays readable. */
static String _captured(File file, int *nul) {
  if (!file) return NULL;
  file.rewind();
  String text = NULL;
  try text = file.string_close();
  catch %(bad-arg *): *nul = 1;
  return text;
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
  job.output_text = _captured(job.output_file, &job.nul_output);
  job.errors_text = _captured(job.errors_file, &job.nul_errors);
  job.output_file = job.errors_file = NULL;
}

static String _text(String text, int nul, String operation) {
  if (nul)
    raise %(bad-arg (operation $operation) (why "embedded NUL"));
  return text;
}

/* Terminates and reaps every running stage without touching capture files,
   which may already be reclaimed when a finalizer calls this. */
static void Job._terminate(Job job) {
  job.kill(SIGTERM);
  for (int waited = 0; waited < 1000 && job._running(); waited++)
    usleep(1000);
  job.kill(SIGKILL);
  for (int i = 0; i < job.count; i++)
    if (job.pids[i]) job._reap(i, 0);
}

static void _drop_job(void *ptr) {
  Job job = ptr;
  if (job.started && !job.finished) job._terminate();
  free(job.pids);
}

static Job Job.new(List command) {
  Job job = Scope.malloc_finalized(sizeof(struct Job), _drop_job);
  memset(job, 0, sizeof(struct Job));
  job.stages = _stages(command);
  job.launch = Scope.calloc(1, sizeof(_Launch));
  job.launch.capture_output = 1;
  return job;
}

static Job Job._unstarted(Job job, String operation) {
  if (job.started)
    raise %(bad-arg (operation $operation) (why "the job has started"));
  return job;
}

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
Job List.job(List command) => Job.new(command);

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
  _Launch *launch = job._unstarted("Job.options").launch;
  foreach (Var (key, value), options) {
    if (key is not Symbol)
      raise %(bad-arg (operation "Job.options")
              (why "option keys are atoms"));
    Symbol name = key;
    switch (name) {
      case <dir>:
        launch.dir = value;
        break;
      case <env>:
        launch.environment = _environment(value);
        break;
      case <input>:
        launch.input = value;
        launch.has_input = 1;
        break;
      case <stdout>:
        launch.capture_output = _is(value, <capture>);
        launch.stdout_path = launch.capture_output ||
          _is(value, <inherit>) ? NULL : value;
        break;
      case <stderr>:
        launch.capture_errors = _is(value, <capture>);
        launch.errors_to_output = _is(value, <stdout>);
        launch.stderr_path =
          launch.capture_errors || launch.errors_to_output ||
          _is(value, <inherit>) ? NULL : value;
        break;
      default:
        raise %(bad-arg (operation "Job.options") (option $name));
    }
  }
  return job;
}

/** Makes `job` pass standard output through instead of capturing it, the
    same as `options({stdout: <inherit>})`, and returns it.
    Raises: `<bad-arg>` for a job that has started.
*/
Job Job.live(Job job) => job.options({stdout: <inherit>});

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

/** Starts `job` without waiting and returns it. A job that has started is
    returned unchanged.
    Raises: `<not-found>` when a program or the `dir` option does not exist,
    `<io-fail>` when a pipe, fork, output file, or other start step fails, or
    `<bad-arg>` for an empty command.
*/
Job Job.start(Job job) {
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
  for (int i = 0; i < job.count; i++)
    if (job.pids[i]) job._reap(i, 0);
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
    raise %(cmd-fail (command $command) (status $status) (output $output)
            (errors $errors));
  if (captured)
    raise %(cmd-fail (command $command) (status $status) (output $output));
  if (logged)
    raise %(cmd-fail (command $command) (status $status) (errors $errors));
  raise %(cmd-fail (command $command) (status $status));
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
      raise %(bad-arg (operation "Job.wait_any")
              (why "a job has not started"));
  while (jobs.len()) {
    for (int i = 0; i < jobs.len(); i++) {
      Job job = jobs[i];
      if (job.ready()) return jobs.remove(i);
    }
    usleep(1000);
  }
  return NULL;
}

/** Returns the value of this process's environment variable `name`, or
    NULL when it is unset. The `env` option sets variables for a child
    instead.
*/
String Env.get(String name) {
  const char *value = getenv(name);
  return value ? String.new(value) : NULL;
}
