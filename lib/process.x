/*  process.x -- run commands and pipelines without a shell

    Copyright (c) 2026 Gary William Flake

    A command is an ordinary `List`. Each element's `str` becomes one
    argument and no shell reads the words, so `%(grep $pattern $file)` passes
    a pattern containing spaces or quotes as a single argument. `List.job`
    turns a command into a `Job`, which holds its stages and stream options
    until the first result requested starts it. That run is recorded, so a
    job runs exactly once however many results are read from it.

    A pipeline's status is the status of its last failing stage, or zero
    when every stage succeeds. A signalled stage reports 128 plus the signal.

    This module also owns the calling process's own argument list and
    environment, which a script reads to decide what to run.
*/

#pragma once
#include "x2c.x"

/** A command or pipeline and the record of its one run.
    A `$auto` job that is still running when its block exits is terminated
    and reaped.
*/
class Job struct {
  List stages;
  struct _Launch *launch;
  long *pids;
  int *statuses;
  int count, started, finished, status;
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
  int capture_output, capture_errors, errors_to_output;
  char **environment;
} _Launch;

enum { _STEP_DIR = 1, _STEP_EXEC = 2 };

static int _decoded_status(int status) {
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
  return -1;
}

static char **_environment(Map env) {
  Map names = %{};
  foreach (Var name, env.keys()) names[name.str()] = 1;
  Array entries = %[];
  for (char **entry = environ; *entry; entry++) {
    String text = String.new(*entry);
    int equals = text.find("=");
    if (!names.contains(equals < 0 ? text : text[:equals]))
      entries.push(text);
  }
  foreach (Var (name, value), env)
    entries.push(%"${name.str()}=${value.str()}");
  char **result = Scope.calloc(entries.len() + 1, sizeof(char *));
  int index = 0;
  foreach (String entry, entries) result[index++] = entry;
  return result;
}

static int _is(Var value, Symbol name) =>
  value is Symbol && value.symbol() == name;

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

/* The report pipe is close-on-exec: a successful `execvp` closes it without
   writing, and a failed step writes which step failed and its errno. */
static void _child(
  char **argv, _Launch *launch, int stdin_fd, int stdout_fd, int stderr_fd,
  int report) {
  if (stdin_fd >= 0) dup2(stdin_fd, STDIN_FILENO);
  if (stdout_fd >= 0) dup2(stdout_fd, STDOUT_FILENO);
  if (launch->errors_to_output) dup2(STDOUT_FILENO, STDERR_FILENO);
  else if (stderr_fd >= 0) dup2(stderr_fd, STDERR_FILENO);
  int failure[2] = { _STEP_DIR, 0 };
  if (!launch->dir || chdir(launch->dir) == 0) {
    if (launch->environment) environ = launch->environment;
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
  if (failure[0] == _STEP_DIR) {
    String dir = launch->dir;
    if (error == ENOENT)
      raise %(not-found (operation "Job.start") (path $dir) (errno $error));
    raise %(io-fail (operation "Job.start") (path $dir) (errno $error));
  }
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
  job.count = job.stages.len();
  job.pids = Scope.calloc(job.count, sizeof(long));
  job.statuses = Scope.calloc(job.count, sizeof(int));
  int input = -1, output = -1, errors = -1, launched = 0;
  defer if (!launched) job.cleanup();
  if (launch->input) {
    File file = _capture_file();
    file.write_all(launch->input, launch->input.len());
    file.rewind();
    input = dup(file.fileno());
    file.close();
    _close_on_exec(input);
  }
  if (launch->capture_output) {
    job.output_file = _capture_file();
    output = job.output_file.fileno();
  }
  else if (launch->stdout_path) output = _open_output(launch->stdout_path);
  if (launch->capture_errors) {
    job.errors_file = _capture_file();
    errors = job.errors_file.fileno();
  }
  else if (launch->stderr_path) errors = _open_output(launch->stderr_path);
  fflush(NULL);
  int previous = input, index = 0, last = job.count - 1;
  {
    defer {
      _close(previous);
      if (!job.output_file) _close(output);
      if (!job.errors_file) _close(errors);
    }
    foreach (List stage, job.stages) {
      int link[2] = { -1, -1 };
      if (index < last) _pipe(link);
      {
        defer _close(link[1]);
        job._spawn(index, stage, previous, index < last ? link[1] : output,
                   errors);
      }
      _close(previous);
      previous = link[0];
      index++;
    }
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

static void Job._finish(Job job) {
  if (job.finished) return;
  job.finished = 1;
  for (int i = 0; i < job.count; i++)
    if (job.statuses[i]) job.status = job.statuses[i];
  if (job.output_file) {
    job.output_file.rewind();
    job.output_text = job.output_file.string_close();
    job.output_file = NULL;
  }
  if (job.errors_file) {
    job.errors_file.rewind();
    job.errors_text = job.errors_file.string_close();
    job.errors_file = NULL;
  }
}

static Job Job.new(List command) {
  Job job = Scope.calloc(1, sizeof(struct Job));
  job.stages = %($command);
  job.launch = Scope.calloc(1, sizeof(_Launch));
  job.launch->capture_output = 1;
  return job;
}

static Job Job._unstarted(Job job, String operation) {
  if (job.started)
    raise %(bad-arg (operation $operation) (why "the job has started"));
  return job;
}

/** Returns a `Job` for `command` without starting it.
    The job captures standard output and passes standard error through. Its
    first result starts it, waits, and records the run.

    ```x2c
    ~#include "process.x"
    ~int main(void) {
    Job job = %(printf "a\nb\n").job();
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
    String root = %(pwd).job().options(%{dir: "/"}).output();
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
        launch->dir = value.str();
        break;
      case <env>:
        launch->environment = _environment(value);
        break;
      case <input>:
        launch->input = value.str();
        break;
      case <stdout>:
        launch->capture_output = _is(value, <capture>);
        launch->stdout_path = launch->capture_output ||
          _is(value, <inherit>) ? NULL : value.str();
        break;
      case <stderr>:
        launch->capture_errors = _is(value, <capture>);
        launch->errors_to_output = _is(value, <stdout>);
        launch->stderr_path =
          launch->capture_errors || launch->errors_to_output ||
          _is(value, <inherit>) ? NULL : value.str();
        break;
      default:
        raise %(bad-arg (operation "Job.options") (option $name));
    }
  }
  return job;
}

/** Makes `job` pass standard output through instead of capturing it, the
    same as `options(%{stdout: inherit})`, and returns it.
    Raises: `<bad-arg>` for a job that has started.
*/
Job Job.live(Job job) => job.options(%{stdout: inherit});

/** Adds `command` as the last stage of `job`, reading the output of the
    stage before it, and returns the job.
    Raises: `<bad-arg>` for a job that has started.
*/
Job Job.pipe(Job job, List command) {
  job._unstarted("Job.pipe");
  job.stages = job.stages.append(%($command));
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
    status, or 128 plus a signal. A status that is not zero is an ordinary
    result here.
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
  int captured = job.launch->capture_output;
  int logged = job.launch->capture_errors;
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
    Raises: the causes of `Job.check`.
*/
String Job.output(Job job) => job.check().output_text;

/** Returns the captured standard output of `job` as lines without their
    endings.
    Raises: the causes of `Job.check`.
*/
List Job.lines(Job job) => job.output().split_lines(0);

/** Returns the captured standard error of `job`, starting it and waiting as
    needed, or NULL when standard error was not captured or was empty.
    Raises: the start causes of `Job.start`.
*/
String Job.errors(Job job) {
  job.status();
  return job.errors_text;
}

/** Reports whether every stage of `job` has exited, without blocking. A job
    that has not started reports 0.
*/
int Job.ready(Job job) {
  if (!job.started) return 0;
  if (job.finished) return 1;
  int running = 0;
  for (int i = 0; i < job.count; i++) {
    if (job.pids[i]) job._reap(i, WNOHANG);
    if (job.pids[i]) running = 1;
  }
  if (running) return 0;
  job._finish();
  return 1;
}

/** Sends `signal` to every stage of `job` that is still running. */
void Job.kill(Job job, int signal) {
  for (int i = 0; i < job.count; i++)
    if (job.pids[i]) kill((pid_t) job.pids[i], signal);
}

/** Terminates and reaps a job that is still running. */
void Job.cleanup(Job job) {
  if (!job || !job.started || job.finished) return;
  job.kill(SIGTERM);
  job.status();
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

/** Returns the program arguments that follow `argv[0]` as `String`s. */
List List.arguments(int argc, char **argv) {
  List result = NULL;
  for (int i = argc - 1; i > 0; i--)
    result = %(${String.new(argv[i])} @result);
  return result;
}

/** Returns the value of this process's environment variable `name`, or
    NULL when it is unset. The `env` option sets variables for a child
    instead.
*/
String Env.get(String name) {
  const char *value = getenv(name);
  return value ? String.new(value) : NULL;
}
