/*  test-process.x -- unit tests for commands, pipelines, and jobs */

#include "process.x"
#include "test-support.x"
$(import "test-macros.xmacro")
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

static void process_arguments_stay_whole(void) {
  $test.scoped();
  String spaced = "two  words", dashed = "-n", empty = "";
  EXPECT_STR_EQ(%(printf "%s|" $spaced $dashed $empty q).job().output(),
                "two  words|-n||q|");
}

static void process_job_runs_once(void) {
  $test.scoped();
  char path[] = "/tmp/x2c-process-XXXXXX";
  int fd = mkstemp(path);
  if (!EXPECT_TRUE(fd >= 0)) return;
  close(fd);
  String log = String.new(path);
  Job job = %(sh -c "echo run >> \$1; echo out; echo err >&2" sh $log)
    .job().options({stderr: <capture>});
  EXPECT_FALSE(job.started);
  EXPECT_INT_EQ(job.status(), 0);
  EXPECT_STR_EQ(job.output(), "out\n");
  EXPECT_LIST_EQ(job.lines(), %("out"));
  EXPECT_STR_EQ(job.errors(), "err\n");
  EXPECT_TRUE(job.check() == job);
  EXPECT_TRUE(job.start() == job);
  EXPECT_INT_EQ(job.status(), 0);
  File file = File.open(path, "r");
  EXPECT_STR_EQ(file.string_close(), "run\n");
  unlink(path);
}

static void process_status_reports_exit_and_signal(void) {
  $test.scoped();
  EXPECT_INT_EQ(%(true).job().status(), 0);
  EXPECT_INT_EQ(%(sh -c "exit 7").job().status(), 7);
  EXPECT_INT_EQ(%(sh -c ${"kill -TERM $$"}).job().status(), 128 + SIGTERM);
}

static void process_status_and_errors_never_raise(void) {
  $test.scoped();
  Job job = %(sh -c "echo out; echo err >&2; exit 3").job()
    .options({stderr: <capture>});
  EXPECT_STR_EQ(job.errors(), "err\n");
  EXPECT_INT_EQ(job.status(), 3);
  EXPECT_NULL(%(sh -c "exit 2").job().errors());
}

static void process_run_raises_command_failure(void) {
  $test.scoped();
  %(true).job().run();
  int caught = 0;
  try %(sh -c "exit 3").job().run();
  catch %(cmd-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.repr(),
                  "((command (sh -c \"exit 3\")) (status 3))");
  }
  EXPECT_INT_EQ(caught, 1);
}

static void process_failure_detail_carries_captures(void) {
  $test.scoped();
  int caught = 0;
  try %(sh -c "echo out; exit 5").job().output();
  catch %(cmd-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<command>).repr(),
                  "(sh -c \"echo out; exit 5\")");
    EXPECT_STR_EQ(detail.assoc(<output>).string(), "out\n");
    EXPECT_TRUE(detail.assoc(<errors>) is void);
  }
  try %(sh -c "echo out; echo err >&2; exit 5").job()
    .options({stderr: <capture>}).lines();
  catch %(cmd-fail *detail): {
    caught++;
    EXPECT_INT_EQ(detail.assoc(<status>).integer(), 5);
    EXPECT_STR_EQ(detail.assoc(<output>).string(), "out\n");
    EXPECT_STR_EQ(detail.assoc(<errors>).string(), "err\n");
  }
  try %(sh -c "echo err >&2; exit 5").job()
    .options({stdout: <inherit>, stderr: <capture>}).check();
  catch %(cmd-fail *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<output>) is void);
    EXPECT_STR_EQ(detail.assoc(<errors>).string(), "err\n");
  }
  EXPECT_INT_EQ(caught, 3);
}

static void process_output_and_lines_capture_stdout(void) {
  $test.scoped();
  EXPECT_STR_EQ(%(printf "a\nb\n").job().output(), "a\nb\n");
  EXPECT_LIST_EQ(%(printf "a\nb\n").job().lines(), %("a" "b"));
  EXPECT_NULL(%(true).job().output());
  int caught = 0;
  try %(sh -c "echo partial; exit 2").job().output();
  catch %(cmd-fail *): caught++;
  try %(sh -c "echo partial; exit 2").job().lines();
  catch %(cmd-fail *): caught++;
  EXPECT_INT_EQ(caught, 2);
}

static void process_live_passes_output_through(void) {
  $test.scoped();
  char path[] = "/tmp/x2c-process-XXXXXX";
  int fd = mkstemp(path);
  if (!EXPECT_TRUE(fd >= 0)) return;
  int saved = dup(STDOUT_FILENO);
  fflush(stdout);
  dup2(fd, STDOUT_FILENO);
  close(fd);
  Job captured = %(echo captured);
  Job live = %(echo live).job().live();
  try {
    EXPECT_STR_EQ(captured.output(), "captured\n");
    EXPECT_NULL(live.output());
    EXPECT_NULL(live.lines());
  }
  finally {
    fflush(stdout);
    dup2(saved, STDOUT_FILENO);
    close(saved);
  }
  File file = File.open(path, "r");
  EXPECT_STR_EQ(file.string_close(), "live\n");
  unlink(path);
}

static void process_pipelines_join_stages(void) {
  $test.scoped();
  EXPECT_STR_EQ(%(printf "b\na\nb\n").job().pipe(%(sort)).pipe(%(uniq))
                  .output(),
                "a\nb\n");
  EXPECT_STR_EQ(%(printf "x\ny\n").job().pipe(%(wc -l)).output()
                  .strip(" \n"),
                "2");
  Job three = %(printf "c\n").job().pipe(%(cat)).pipe(%(tr c d));
  EXPECT_INT_EQ(three.stages.len(), 3);
  EXPECT_STR_EQ(three.output(), "d\n");
  int caught = 0;
  try %(false).job().pipe(%(cat)).check();
  catch %(cmd-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<command>).repr(), "((false) (cat))");
  }
  EXPECT_INT_EQ(caught, 1);
}

static void process_nested_pipelines_compose_with_pipe(void) {
  $test.scoped();
  EXPECT_STR_EQ(%((printf "b\na\nb\n") (sort) (uniq)).job().output(),
                "a\nb\n");
  Job nested = %((printf "c\n") (cat)).job().pipe(%(tr c d));
  EXPECT_INT_EQ(nested.stages.len(), 3);
  EXPECT_STR_EQ(nested.output(), "d\n");
  Job appended = %(printf "e\n").job().pipe(%((cat) (tr e f)));
  EXPECT_INT_EQ(appended.stages.len(), 3);
  EXPECT_STR_EQ(appended.output(), "f\n");
  EXPECT_INT_EQ(%((sh -c "exit 4") (cat)).job().status(), 4);
  EXPECT_INT_EQ(%((sh -c "exit 4") (sh -c "cat; exit 5")).job().status(), 5);
  EXPECT_INT_EQ(%((false) (true)).job().status(), 1);
  int caught = 0;
  try %((false) (cat)).job().check();
  catch %(cmd-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<command>).repr(), "((false) (cat))");
  }
  EXPECT_INT_EQ(caught, 1);
  EXPECT_STR_EQ(%((sh -c "pwd; echo one >&2") (sh -c "cat; echo two >&2"))
                  .job().options({dir: "/", input: "in\n", stderr: <stdout>})
                  .output(),
                "/\none\ntwo\n");
  Job logged = %((sh -c "cat; echo one >&2") (sh -c "cat; echo two >&2"))
    .job().options({input: "in\n", stderr: <capture>});
  EXPECT_STR_EQ(logged.output(), "in\n");
  EXPECT_TRUE(logged.errors() == "one\ntwo\n" ||
              logged.errors() == "two\none\n");
}

static void process_pipeline_status_is_last_failure(void) {
  $test.scoped();
  EXPECT_INT_EQ(%(sh -c "exit 4").job().pipe(%(cat)).status(), 4);
  EXPECT_INT_EQ(%(sh -c "exit 4").job().pipe(%(sh -c "cat; exit 5"))
                  .status(),
                5);
  EXPECT_INT_EQ(%(false).job().pipe(%(true)).status(), 1);
}

static void process_options_route_streams(void) {
  $test.scoped();
  EXPECT_STR_EQ(%(tr a-z A-Z).job().options({input: "shout"}).output(),
                "SHOUT");
  EXPECT_STR_EQ(%(pwd).job().options({dir: "/"}).output(), "/\n");
  EXPECT_STR_EQ(%(sh -c "echo \$X2C_PROCESS_TEST").job()
                  .options({env: {X2C_PROCESS_TEST: "set"}}).output(),
                "set\n");
  EXPECT_STR_EQ(%(sh -c "echo out; echo err >&2").job()
                  .options({stderr: <stdout>}).output(),
                "out\nerr\n");
  Job job = %(sh -c "echo err >&2; exit 6").job()
    .options({stderr: <capture>}).start();
  EXPECT_INT_EQ(job.status(), 6);
  EXPECT_STR_EQ(job.errors(), "err\n");
}

static void process_options_write_files_and_merge(void) {
  $test.scoped();
  char path[] = "/tmp/x2c-process-XXXXXX";
  int fd = mkstemp(path);
  if (!EXPECT_TRUE(fd >= 0)) return;
  close(fd);
  String output = String.new(path);
  %(printf hello).job().options({stdout: output}).check();
  File file = File.open(path, "r");
  EXPECT_STR_EQ(file.string_close(), "hello");
  Job job = %(pwd).job().options({dir: "/", stdout: output})
    .options({input: "x"}).live().options({stdout: <capture>});
  EXPECT_STR_EQ(job.output(), "/\n");
  EXPECT_STR_EQ(%(pwd).job().options({dir: "/"}).pipe(%(cat)).output(),
                "/\n");
  unlink(path);
}

static void process_changes_after_start_raise(void) {
  $test.scoped();
  Job job = %(true);
  job.status();
  int caught = 0;
  try job.options({dir: "/"});
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Job.options");
  }
  try job.pipe(%(cat));
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Job.pipe");
  }
  try job.live();
  catch %(bad-arg *): caught++;
  try job.run();
  catch %(bad-arg *): caught++;
  try %(true).job().options({cwd: "/"});
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<option>).symbol() == <cwd>);
  }
  EXPECT_INT_EQ(caught, 5);
}

static void process_start_failures_raise(void) {
  $test.scoped();
  int caught = 0;
  try %(x2c-process-test-missing-program).job().run();
  catch %(not-found *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<program>).string(),
                  "x2c-process-test-missing-program");
    EXPECT_INT_EQ(detail.assoc(<errno>).integer(), ENOENT);
  }
  try %(pwd).job().options({dir: "/x2c-process-test-missing"}).run();
  catch %(not-found *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<path>).string(), "/x2c-process-test-missing");
  }
  try %(sleep 30).job().pipe(%(x2c-process-test-missing-program)).run();
  catch %(not-found *): caught++;
  Job empty = %();
  try empty.start();
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(empty.status(), 127);
  EXPECT_INT_EQ(caught, 4);

  int before = dup(STDERR_FILENO);
  close(before);
  for (int i = 0; i < 64; i++) {
    try %(pwd).job().options({stderr: <capture>, dir: "/x2c-missing"})
      .output();
    catch %(not-found *): caught++;
  }
  int after = dup(STDERR_FILENO);
  close(after);
  EXPECT_INT_EQ(caught, 68);
  EXPECT_INT_EQ(after, before);
}

static void process_jobs_wait_kill_and_clean_up(void) {
  $test.scoped();
  Array jobs = [];
  for (int i = 3; i >= 1; i--)
    jobs.push(%(sh -c ${%"sleep 0.$i; exit $i"}).job().start());
  Array order = [];
  while (jobs.len()) order.push(Job.wait_any(jobs).status());
  EXPECT_TRUE(order.equal([1, 2, 3]));
  EXPECT_NULL(Job.wait_any(jobs));
  jobs.push(%(true).job());
  int caught = 0;
  try Job.wait_any(jobs);
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Job.wait_any");
  }
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(jobs.len(), 1);
  jobs.pop();

  Job killed = %(sleep 30);
  EXPECT_FALSE(killed.ready());
  killed.start();
  EXPECT_FALSE(killed.ready());
  killed.kill(SIGKILL);
  EXPECT_INT_EQ(killed.status(), 128 + SIGKILL);
  EXPECT_TRUE(killed.ready());

  long pid = 0;
  {
    Job sleeper = $auto(%(sleep 30).job().start());
    pid = sleeper.pids[0];
  }
  EXPECT_TRUE(pid > 0 && kill((pid_t) pid, 0) != 0);

  pid = 0;
  try {
    Job sleeper = $auto(%(sleep 30).job().start());
    pid = sleeper.pids[0];
    raise %(bad-state (operation "test"));
  }
  catch %(bad-state *): {}
  EXPECT_TRUE(pid > 0 && kill((pid_t) pid, 0) != 0);

  Job done = %(echo done).job().start();
  EXPECT_STR_EQ(done.output(), "done\n");
  EXPECT_INT_EQ(done.status(), 0);
}

static void process_env_reads_the_calling_process(void) {
  $test.scoped();
  String name = "X2C_TEST_ENVIRONMENT_VALUE";
  EXPECT_NULL(Env.get(name));
  setenv(name, "present", 1);
  EXPECT_STR_EQ(Env.get(name), "present");
  unsetenv(name);
  EXPECT_NULL(Env.get(name));
}

void process_suite(void) {
  $test.run(process_arguments_stay_whole);
  $test.run(process_env_reads_the_calling_process);
  $test.run(process_job_runs_once);
  $test.run(process_status_reports_exit_and_signal);
  $test.run(process_status_and_errors_never_raise);
  $test.run(process_run_raises_command_failure);
  $test.run(process_failure_detail_carries_captures);
  $test.run(process_output_and_lines_capture_stdout);
  $test.run(process_live_passes_output_through);
  $test.run(process_pipelines_join_stages);
  $test.run(process_nested_pipelines_compose_with_pipe);
  $test.run(process_pipeline_status_is_last_failure);
  $test.run(process_options_route_streams);
  $test.run(process_options_write_files_and_merge);
  $test.run(process_changes_after_start_raise);
  $test.run(process_start_failures_raise);
  $test.run(process_jobs_wait_kill_and_clean_up);
}
