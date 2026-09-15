/*  process.x -- run commands and pipelines without a shell

    Copyright (c) 2026 Gary William Flake

    A command is an ordinary `List`. Each element's `str` becomes one
    argument and no shell reads the words, so `%(grep $pattern $file)` passes
    a pattern containing spaces or quotes as a single argument. A `List`
    whose first element is itself a `List` is a pipeline, one command per
    element. `List.options` puts an options `Map` in front of either shape.

    Children inherit the standard streams unless an option routes them. A
    pipeline's status is the status of its last failing stage, or zero when
    every stage succeeds. A signalled stage reports 128 plus the signal.
*/

#pragma once
#include "x2c.x"

/** A started command or pipeline.
    `Job.wait` reaps every stage and collects captured output. A `$auto` job
    that is still running when its block exits is terminated and reaped.
*/
class Job struct {
  List command;
  long *pids;
  int *statuses;
  int count, finished, status;
  File output_file, errors_file;
  String output_text, errors_text;
} *;

protocol Cleanup(Job);

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

static Map _command_options(List command) {
  if (!command || command.car() is not Map) return NULL;
  return command.car();
}

static List _command_body(List command) =>
  _command_options(command) ? command.cdr() : command;

static List _command_stages(List command) {
  List body = _command_body(command);
  return body && body.car() is List ? body : %($body);
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

static _Launch _launch(Map options) {
  _Launch launch = {0};
  if (!options) return launch;
  foreach (Var (key, value), options) {
    if (key is not Symbol)
      raise %(bad-arg (operation "List.start") (why "option keys are atoms"));
    Symbol name = key;
    switch (name) {
      case <dir>:
        launch.dir = value.str();
        break;
      case <env>:
        launch.environment = _environment(value);
        break;
      case <input>:
        launch.input = value.str();
        break;
      case <stdout>:
        if (value is Symbol && value.symbol() == <capture>)
          launch.capture_output = 1;
        else launch.stdout_path = value.str();
        break;
      case <stderr>:
        if (value is Symbol && value.symbol() == <capture>)
          launch.capture_errors = 1;
        else if (value is Symbol && value.symbol() == <stdout>)
          launch.errors_to_output = 1;
        else launch.stderr_path = value.str();
        break;
      default:
        raise %(bad-arg (operation "List.start") (option $name));
    }
  }
  return launch;
}

static void _close_on_exec(int fd) {
  fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);
}

static void _pipe(int fds[2]) {
  if (pipe(fds)) {
    int error = errno;
    raise %(io-fail (operation "List.start") (errno $error));
  }
  _close_on_exec(fds[0]);
  _close_on_exec(fds[1]);
}

static int _open_output(String path) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (fd < 0) {
    int error = errno;
    raise %(io-fail (operation "List.start") (path $path) (errno $error));
  }
  _close_on_exec(fd);
  return fd;
}

static File _capture_file(void) {
  File file = tmpfile();
  if (!file) {
    int error = errno;
    raise %(io-fail (operation "List.start") (errno $error));
  }
  _close_on_exec(file.fileno());
  return file;
}

static void _close(int fd) {
  if (fd >= 0) close(fd);
}

static char **_argv(List stage) {
  if (!stage)
    raise %(bad-arg (operation "List.start") (why "empty command"));
  char **argv = Scope.calloc(stage.len() + 1, sizeof(char *));
  int index = 0;
  foreach (Var word, stage) argv[index++] = word.str();
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

/* Terminates the stages already started and closes capture files, so a
   start that fails part way leaves no child or descriptor behind. */
static void Job._abandon(Job job) {
  job.kill(SIGTERM);
  job.wait();
}

static void Job._spawn(
  Job job, int index, List stage, _Launch *launch, int stdin_fd,
  int stdout_fd, int stderr_fd) {
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
    raise %(io-fail (operation "List.start") (errno $fork_error));
  job.pids[index] = pid;
  if (count != sizeof(failure)) return;
  int error = failure[1];
  if (failure[0] == _STEP_DIR) {
    String dir = launch->dir;
    if (error == ENOENT)
      raise %(not-found (operation "List.start") (path $dir) (errno $error));
    raise %(io-fail (operation "List.start") (path $dir) (errno $error));
  }
  String program = argv[0];
  if (error == ENOENT)
    raise %(not-found (operation "List.start") (program $program)
            (errno $error));
  raise %(io-fail (operation "List.start") (program $program)
          (errno $error));
}

static Job Job.new(List command, int count) {
  Job job = Scope.calloc(1, sizeof(struct Job));
  job.command = command;
  job.count = count;
  job.pids = Scope.calloc(count, sizeof(long));
  job.statuses = Scope.calloc(count, sizeof(int));
  return job;
}

static Job _start(List command, int capture_output) {
  _Launch launch = _launch(_command_options(command));
  if (capture_output) launch.capture_output = 1;
  List stages = _command_stages(command);
  Job job = Job.new(_command_body(command), stages.len());
  int input = -1, output = -1, errors = -1, started = 0;
  defer if (!started) job._abandon();
  if (launch.input) {
    File file = _capture_file();
    file.write_all(launch.input, launch.input.len());
    file.rewind();
    input = dup(file.fileno());
    file.close();
    _close_on_exec(input);
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
  int previous = input, index = 0, last = job.count - 1;
  {
    defer {
      _close(previous);
      if (!job.output_file) _close(output);
      if (!job.errors_file) _close(errors);
    }
    foreach (List stage, stages) {
      int link[2] = { -1, -1 };
      if (index < last) _pipe(link);
      {
        defer _close(link[1]);
        job._spawn(index, stage, &launch, previous,
                   index < last ? link[1] : output, errors);
      }
      _close(previous);
      previous = link[0];
      index++;
    }
  }
  started = 1;
  return job;
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

static void Job._reap(Job job, int index, int flags) {
  int status;
  pid_t pid;
  do pid = waitpid((pid_t) job.pids[index], &status, flags);
  while (pid < 0 && errno == EINTR);
  if (!pid) return;
  job.statuses[index] = pid < 0 ? -1 : _decoded_status(status);
  job.pids[index] = 0;
}

/** Returns a new command that runs `command` with `options`.
    The keys are atoms: `dir` names the working directory, `env` is a `Map`
    of variables added to the inherited environment, and `input` is a
    `String` fed to the first stage's standard input. `stdout` is a path or
    `capture`; `stderr` is a path, `capture`, or `stdout`. Standard output
    options apply to the last stage and `stderr` to every stage. Options
    already on `command` are kept unless `options` replaces the same key.

    ```x2c
    ~#include "process.x"
    ~int main(void) {
    String home = %(pwd).options(%{dir: "/"}).output();
    ~  return home == "/\n" ? 0 : 1;
    ~}
    ```
*/
List List.options(List command, Map options) {
  Map existing = _command_options(command);
  Map merged = existing ? existing.copy().merge(options) : options;
  List body = _command_body(command);
  return %($merged @body);
}

/** Returns a pipeline that sends the output of `command` into `next`.
    Either side may already be a pipeline; the options of both sides are
    merged, with `next` replacing any key both define.
*/
List List.pipe(List command, List next) {
  Map options = _command_options(command), after = _command_options(next);
  if (after) options = options ? options.copy().merge(after) : after;
  List stages = _command_stages(command).append(_command_stages(next));
  return options ? %($options @stages) : stages;
}

/** Starts `command` and returns its running `Job`.
    Raises: `<not-found>` when a program or the `dir` option does not exist,
    `<io-fail>` when a pipe, fork, output file, or other start step fails, or
    `<bad-arg>` for an empty command or an unknown option. Stages already
    started are terminated and reaped before the error transfers.
*/
Job List.start(List command) => _start(command, 0);

/** Runs `command` to completion and returns its status.
    A non-zero status is an ordinary result here.
    Raises: the start causes of `List.start`.
*/
int List.status(List command) => _start(command, 0).wait();

/** Runs `command` to completion with the standard streams inherited.
    Raises: `<cmd-fail>` with `command` and `status` details when the status
    is not zero, or the start causes of `List.start`.
*/
void List.run(List command) {
  _start(command, 0).check();
}

/** Runs `command` and returns its captured standard output.
    Raises: `<cmd-fail>` when the status is not zero, or the start causes of
    `List.start`.
*/
String List.output(List command) {
  Job job = _start(command, 1);
  job.check();
  return job.output_text;
}

/** Runs `command` and returns its standard output as lines without their
    endings.
    Raises: the causes of `List.output`.
*/
List List.lines(List command) => command.output().split_lines(0);

/** Returns the program arguments that follow `argv[0]` as `String`s. */
List List.arguments(int argc, char **argv) {
  List result = NULL;
  for (int i = argc - 1; i > 0; i--)
    result = %(${String.new(argv[i])} @result);
  return result;
}

/** Reports whether every stage of `job` has exited, without blocking. */
int Job.ready(Job job) {
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

/** Waits for every stage of `job` and returns the pipeline status.
    Waiting again returns the same status.
*/
int Job.wait(Job job) {
  for (int i = 0; i < job.count; i++)
    if (job.pids[i]) job._reap(i, 0);
  job._finish();
  return job.status;
}

/** Waits for `job` and raises when its status is not zero.
    Raises: `<cmd-fail>` with `command` and `status` details, plus `errors`
    when standard error was captured.
*/
void Job.check(Job job) {
  int status = job.wait();
  if (!status) return;
  List command = job.command;
  String errors = job.errors_text;
  if (errors)
    raise %(cmd-fail (command $command) (status $status) (errors $errors));
  raise %(cmd-fail (command $command) (status $status));
}

/** Waits for `job` and returns its captured standard output, or NULL when
    output was not captured or was empty.
*/
String Job.output(Job job) {
  job.wait();
  return job.output_text;
}

/** Waits for `job` and returns its captured standard error, or NULL when
    errors were not captured or were empty.
*/
String Job.errors(Job job) {
  job.wait();
  return job.errors_text;
}

/** Sends `signal` to every stage of `job` that has not been reaped. */
void Job.kill(Job job, int signal) {
  for (int i = 0; i < job.count; i++)
    if (job.pids[i]) kill((pid_t) job.pids[i], signal);
}

/** Terminates and reaps a job that is still running. */
void Job.cleanup(Job job) {
  if (job && !job.finished) job._abandon();
}

/** Removes and returns the first job in `jobs` that has finished, waiting
    until one does. An empty `jobs` returns NULL.
*/
Job Job.wait_any(Array jobs) {
  while (jobs.len()) {
    for (int i = 0; i < jobs.len(); i++) {
      Job job = jobs[i];
      if (job.ready()) return jobs.remove(i);
    }
    usleep(1000);
  }
  return NULL;
}
