/* task.x -- cooperative Channel jobs on stable native stacks */
#pragma once
#include "channel.x"
#include "thread-state.x"
#include <errno.h>
#include <limits.h>

/** Namespace for cooperative job batches; no public task handles exist. */
typedef struct Task *Task;

extern int x2c_task_stack_supported(void);
extern void *x2c_task_stack_new(
  void (*entry)(void *), void *argument, size_t size);
extern void x2c_task_stack_resume(void *stack);
extern void x2c_task_stack_yield(void *stack);
extern unsigned long x2c_task_stack_low(void *stack);
extern void x2c_task_stack_free(void *stack);

static typedef struct TaskRun *TaskRun;
static typedef struct TaskJob {
  TaskRun run;
  struct TaskJob *next;
  Func function;
  Var result, errors;
  void *stack, *scope_state, *error_state, *exception_state, *match_state;
  void *policy;
  Context context;
  Pool pool;
  X2CChannelMonitor *waiting;
  unsigned long stack_low;
  int stopped, parked, queued, finished;
} *TaskJob;

static struct TaskRun {
  TaskJob jobs, first, last;
  int count, prepared, finished, stopping, bound;
  size_t stack_size;
  Scope base, error_scope;
  Pool pool;
  X2CChannelMonitor monitor;
};

static threaded TaskJob current_task;
static threaded int task_batch_active;

macro Expression $task.run.jobs(Expr $jobs) => Task.run($jobs);

/** Runs zero-argument jobs cooperatively on the calling native thread.
    Channel waits park a job. The optional completed callback receives each
    successful result after job cleanup, under restored caller state, and
    must not wait for participant progress. Results retain ordinary owners.
    Jobs borrow the caller's active Scope and Pool through this call, start
    without a current Context, and copy effective Error policies and bound.
    Every exit finishes all jobs; failure stops unfinished participants.
    Thread.stop on the owner requests cooperative batch cancellation.
    Cleanup bodies must not suspend. Blocking native calls block all jobs.
    X2C_TASK_STACK_BYTES selects usable capacity before the call; the default
    is 8 MiB, rounded up to a native page. No job migrates between threads.
    Raises: bad-state for nested execution or an unsupported native target,
    bad-arg for invalid capacity/jobs, allocation/setup causes, join-fail for
    escaping job Errors, or completion-callback and owner-stop causes.
*/
void Task.run(Array jobs, Func completed) {
  if (!x2c_task_stack_supported())
    raise %(bad-state (operation "Task.run")
                     (reason "native task backend unavailable"));
  if (task_batch_active)
    raise %(bad-state (operation "Task.run")
                     (reason "nested task batches are unsupported"));
  if (!jobs.len()) return;
  task_batch_active = 1;
  defer task_batch_active = 0;
  Scope *base = Scope.top();
  if (!*base) *base = Scope.new();
  struct TaskRun run = {
    .count = jobs.len(), .base = *base, .pool = Pool.current(),
    .bound = Error.bound(), .stack_size = _stack_size() };
  _native_check(pthread_mutex_init(&run.monitor.mutex, NULL));
  defer _native_check(pthread_mutex_destroy(&run.monitor.mutex));
  _native_check(pthread_cond_init(&run.monitor.condition, NULL));
  defer _native_check(pthread_cond_destroy(&run.monitor.condition));
  defer _shutdown(&run);
  run.jobs = calloc(run.count, sizeof(struct TaskJob));
  if (!run.jobs) raise %(alloc-fail);
  for (int i = 0; i < run.count; i++) {
    _check_stop();
    _prepare(&run, &run.jobs[i], jobs[i]);
    _ready(&run.jobs[i]);
  }
  while (run.finished < run.count) {
    _check_stop();
    TaskJob job = _take(&run);
    _resume(job);
    if (!job.finished) continue;
    run.finished++;
    _release_stack(job);
    if (job.errors is not void) {
      Var errors = Context.export_scope(run.error_scope, run.pool, job.errors);
      raise %(join-fail (errors $errors));
    }
    _check_stop();
    if (completed) completed.apply_value(job.result);
  }
  _check_stop();
}

// Channel bridge

/** Returns the current borrowed task token, or NULL on native execution. */
void *x2c_task_current(void) => current_task;

/** Reads a task's queue-ordered cooperative stop request. */
int x2c_task_stopping(void *value) {
  TaskJob job = value;
  return job && __atomic_load_n(&job.stopped, __ATOMIC_ACQUIRE);
}

/** Wakes parked task waiters while the Channel monitor is locked. */
void x2c_task_channel_notify(X2CChannelMonitor *monitor) {
  for (X2CTaskWait *wait = monitor.tasks; wait; wait = wait.next)
    _ready(wait.task);
}

/** Parks the current task and returns with its Channel monitor locked.
    Channel's mutex protects this stack-local registration and stop/commit.
   Unregister native Thread before parking, then register again on resume. */
void x2c_task_channel_sleep(X2CChannelMonitor *monitor, Thread *owner) {
  TaskJob job = current_task;
  X2CTaskWait wait = { .task = job, .next = monitor.tasks };
  monitor.tasks = &wait;
  job.waiting = monitor;
  _native_check(pthread_mutex_lock(&job.run.monitor.mutex));
  job.parked = 1;
  _native_check(pthread_mutex_unlock(&job.run.monitor.mutex));
  int released = x2c_thread_channel_leave(*owner, monitor);
  _native_check(pthread_mutex_unlock(&monitor.mutex));
  _acknowledge(released);
  x2c_task_stack_yield(job.stack);
  _native_check(pthread_mutex_lock(&monitor.mutex));
  X2CTaskWait **at = &monitor.tasks;
  while (*at != &wait) at = &(*at).next;
  *at = wait.next;
  job.waiting = NULL;
  if (!x2c_thread_channel_enter(monitor, *owner))
    __atomic_store_n(&job.stopped, 1, __ATOMIC_RELEASE);
}

static void _entry(void *value) {
  TaskJob job = value;
  Error.initialize_raw();
  Error.policy_adopt(job.policy);
  job.policy = NULL;
  Error.bound_set(job.run.bound);
  int mark = Error.mark();
  try {
    ErrorHandler observer = Error.push(_capture_errors, (void *)job);
    defer Error.pop(observer);
    ErrorHandler logger = Error.push(Logger.error_handler, void);
    defer Error.pop(logger);
    if (x2c_task_stopping(job)) x2c_thread_cancel();
    job.result = job.function.apply(0, NULL);
  }
  catch %(join-fail *): _failed(job, mark);
  catch %(alloc-fail *): _failed(job, mark);
  x2c_match_thread_release();
  Error.shutdown_raw();
  job.finished = 1;
}

static Symbol _capture_errors(List errors, Var value) {
  TaskJob job = value.pointer();
  if (!errors) return <declined>;
  List entry = errors.last();
  Symbol code = entry.assoc(<code>);
  if (Error.policy_get(code) != <abort>) return <declined>;
  job.errors = Error.snapshot_in(
    errors, &job.run.error_scope, job.run.pool);
  raise %(join-fail (operation "Task callback"));
}

static void _failed(TaskJob job, int mark) {
  if (job.errors is void)
    job.errors = Error.since_in(mark, &job.run.error_scope, job.run.pool);
  job.result = void;
}

static void _exchange(TaskJob job) {
  x2c_scope_execution_swap(job.scope_state);
  job.context = x2c_context_exchange(job.context);
  job.pool = x2c_pool_exchange(job.pool);
  x2c_error_execution_swap(job.error_state);
  x2c_exception_execution_swap(job.exception_state);
  x2c_match_execution_swap(job.match_state);
  job.stack_low = x2c_execution_stack_exchange(job.stack_low);
}

static void _resume(TaskJob job) {
  _exchange(job);
  current_task = job;
  x2c_task_stack_resume(job.stack);
  current_task = NULL;
  _exchange(job);
}

// preparation and scheduling

static void _prepare(TaskRun run, TaskJob job, Func function) {
  job.run = run;
  job.function = function;
  job.result = job.errors = void;
  job.pool = run.pool;
  job.parked = 1;
  run.prepared++;
  if (!function) raise %(bad-arg (operation "Task.run"));
  job.policy = Error.policy_capture();
  job.scope_state = x2c_scope_execution_new(run.base);
  job.error_state = x2c_error_execution_new();
  job.exception_state = x2c_exception_execution_new();
  job.match_state = x2c_match_execution_new();
  job.stack = x2c_task_stack_new(_entry, job, run.stack_size);
  if (!job.stack) {
    int error = errno;
    raise %(alloc-fail (operation "Task stack") (errno $error));
  }
  job.stack_low = x2c_task_stack_low(job.stack);
}

static size_t _stack_size(void) {
  const char *setting = getenv("X2C_TASK_STACK_BYTES");
  if (!setting) return 8u << 20;
  char *end;
  errno = 0;
  unsigned long long size = strtoull(setting, &end, 10);
  if (!*setting || *setting == '-' || *end || errno ||
      size < 32768 || size > SIZE_MAX - 65536)
    raise %(bad-arg (operation "Task stack capacity"));
  return size;
}

static void _ready(TaskJob job) {
  TaskRun run = job.run;
  _native_check(pthread_mutex_lock(&run.monitor.mutex));
  if (job.parked && !job.queued && !job.finished) {
    job.next = NULL;
    if (run.last) run.last.next = job;
    else run.first = job;
    run.last = job;
    job.queued = 1;
    _native_check(pthread_cond_signal(&run.monitor.condition));
  }
  _native_check(pthread_mutex_unlock(&run.monitor.mutex));
}

static TaskJob _take(TaskRun run) {
  _native_check(pthread_mutex_lock(&run.monitor.mutex));
  while (!run.first) {
    Thread owner = NULL;
    if (!run.stopping &&
        !x2c_thread_channel_enter(&run.monitor, owner)) {
      _native_check(pthread_mutex_unlock(&run.monitor.mutex));
      x2c_thread_cancel();
    }
    _native_check(
      pthread_cond_wait(&run.monitor.condition, &run.monitor.mutex));
    int released = run.stopping ||
      x2c_thread_channel_leave(owner, &run.monitor);
    _native_check(pthread_mutex_unlock(&run.monitor.mutex));
    _acknowledge(released);
    if (!run.stopping) _check_stop();
    _native_check(pthread_mutex_lock(&run.monitor.mutex));
  }
  TaskJob job = run.first;
  run.first = job.next;
  if (!run.first) run.last = NULL;
  job.queued = 0;
  job.parked = 0;
  _native_check(pthread_mutex_unlock(&run.monitor.mutex));
  return job;
}

static void _check_stop(void) {
  if (x2c_thread_stopping()) x2c_thread_cancel();
}

static void _acknowledge(int released) {
  if (released) return;
  x2c_thread_wait_lock();
  x2c_thread_wait_unlock();
}

static void _shutdown(TaskRun run) {
  run.stopping = 1;
  int unfinished = 0;
  for (int i = 0; i < run.prepared; i++) {
    TaskJob job = &run.jobs[i];
    if (!job.stack || job.finished) continue;
    unfinished++;
    X2CChannelMonitor *monitor = job.waiting;
    if (monitor) _native_check(pthread_mutex_lock(&monitor.mutex));
    __atomic_store_n(&job.stopped, 1, __ATOMIC_RELEASE);
    _ready(job);
    if (monitor) _native_check(pthread_mutex_unlock(&monitor.mutex));
  }
  while (unfinished) {
    TaskJob job = _take(run);
    _resume(job);
    if (job.finished) { _release_stack(job); unfinished--; }
  }
  for (int i = 0; i < run.prepared; i++) _free(&run.jobs[i]);
  free(run.jobs);
  if (run.error_scope) run.error_scope.destroy();
}

static void _release_stack(TaskJob job) {
  x2c_task_stack_free(job.stack);
  job.stack = NULL;
}

static void _free(TaskJob job) {
  Error.policy_release(job.policy);
  if (job.scope_state) x2c_scope_execution_free(job.scope_state);
  if (job.error_state) x2c_error_execution_free(job.error_state);
  if (job.exception_state) x2c_exception_execution_free(job.exception_state);
  if (job.match_state) x2c_match_execution_free(job.match_state);
}

static void _native_check(int code) { if (code) abort(); }

$rewrite($task.run.jobs)
meta static Code _task_without_callback(Code code) {
  if (code ~= $task.run.jobs(?jobs))
    return $!void{ Task.run($jobs, NULL) };
  return code;
}
