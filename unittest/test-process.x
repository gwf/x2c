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
  String spaced = %"two  words", dashed = "-n", empty = "";
  EXPECT_STR_EQ(%(printf "%s|" $spaced $dashed $empty q).output(),
                "two  words|-n||q|");
  char *argv[] = { "tool", "first", "second third", NULL };
  EXPECT_LIST_EQ(List.arguments(3, argv), %("first" "second third"));
  EXPECT_NULL(List.arguments(1, argv));
}

static void process_status_reports_exit_and_signal(void) {
  $test.scoped();
  EXPECT_INT_EQ(%(true).status(), 0);
  EXPECT_INT_EQ(%(sh -c "exit 7").status(), 7);
  EXPECT_INT_EQ(%(sh -c ${"kill -TERM $$"}).status(), 128 + SIGTERM);
}

static void process_run_raises_command_failure(void) {
  $test.scoped();
  %(true).run();
  int caught = 0;
  try %(sh -c "exit 3").run();
  catch %(cmd-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<command>).repr(), "(sh -c \"exit 3\")");
    EXPECT_INT_EQ(detail.assoc(<status>).integer(), 3);
  }
  EXPECT_INT_EQ(caught, 1);
}

static void process_output_and_lines_capture_stdout(void) {
  $test.scoped();
  EXPECT_STR_EQ(%(printf "a\nb\n").output(), "a\nb\n");
  EXPECT_LIST_EQ(%(printf "a\nb\n").lines(), %("a" "b"));
  EXPECT_NULL(%(true).output());
  int caught = 0;
  try %(sh -c "echo partial; exit 2").output();
  catch %(cmd-fail *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void process_pipelines_join_stages(void) {
  $test.scoped();
  List pipeline = %((printf "b\na\nb\n") (sort) (uniq));
  EXPECT_STR_EQ(pipeline.output(), "a\nb\n");
  EXPECT_STR_EQ(%(printf "x\ny\n").pipe(%(wc -l)).output().strip(" \n"),
                "2");
  List three = %(printf "c\n").pipe(%(cat)).pipe(%(tr c d));
  EXPECT_INT_EQ(three.len(), 3);
  EXPECT_STR_EQ(three.output(), "d\n");
}

static void process_pipeline_status_is_last_failure(void) {
  $test.scoped();
  EXPECT_INT_EQ(%((sh -c "exit 4") (cat)).status(), 4);
  EXPECT_INT_EQ(%((sh -c "exit 4") (sh -c "cat; exit 5")).status(), 5);
  EXPECT_INT_EQ(%((false) (true)).status(), 1);
}

static void process_options_route_streams(void) {
  $test.scoped();
  EXPECT_STR_EQ(%(tr a-z A-Z).options(%{input: "shout"}).output(), "SHOUT");
  EXPECT_STR_EQ(%(pwd).options(%{dir: "/"}).output(), "/\n");
  EXPECT_STR_EQ(%(sh -c "echo \$X2C_PROCESS_TEST")
                  .options(%{env: {X2C_PROCESS_TEST: "set"}}).output(),
                "set\n");
  EXPECT_STR_EQ(%(sh -c "echo out; echo err >&2")
                  .options(%{stderr: stdout}).output(),
                "out\nerr\n");
  Job job = %(sh -c "echo err >&2; exit 6")
    .options(%{stderr: capture}).start();
  EXPECT_INT_EQ(job.wait(), 6);
  EXPECT_STR_EQ(job.errors(), "err\n");
  int caught = 0;
  try job.check();
  catch %(cmd-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<errors>).string(), "err\n");
  }
  EXPECT_INT_EQ(caught, 1);
}

static void process_options_write_files_and_merge(void) {
  $test.scoped();
  char path[] = "/tmp/x2c-process-XXXXXX";
  int fd = mkstemp(path);
  if (!EXPECT_TRUE(fd >= 0)) return;
  close(fd);
  String output = String.new(path);
  %(printf hello).options(%{stdout: $output}).run();
  File file = File.open(path, "r");
  EXPECT_STR_EQ(file.string_close(), "hello");
  List command = %(pwd).options(%{dir: "/"}).options(%{input: "x"});
  EXPECT_STR_EQ(command.output(), "/\n");
  EXPECT_STR_EQ(%(pwd).options(%{dir: "/"}).pipe(%(cat)).output(), "/\n");
  unlink(path);
}

static void process_start_failures_raise(void) {
  $test.scoped();
  int caught = 0;
  try %(x2c-process-test-missing-program).run();
  catch %(not-found *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<program>).string(),
                  "x2c-process-test-missing-program");
    EXPECT_INT_EQ(detail.assoc(Symbol.new("errno")).integer(), ENOENT);
  }
  try %(pwd).options(%{dir: "/x2c-process-test-missing"}).run();
  catch %(not-found *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<path>).string(), "/x2c-process-test-missing");
  }
  try %((sleep 30) (x2c-process-test-missing-program)).run();
  catch %(not-found *): caught++;
  try %(pwd).options(%{cwd: "/"}).run();
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<option>).symbol() == <cwd>);
  }
  try %().run();
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 5);

  int before = dup(STDERR_FILENO);
  close(before);
  for (int i = 0; i < 64; i++) {
    try %(pwd).options(%{stderr: capture, dir: "/x2c-missing"}).output();
    catch %(not-found *): caught++;
  }
  int after = dup(STDERR_FILENO);
  close(after);
  EXPECT_INT_EQ(caught, 69);
  EXPECT_INT_EQ(after, before);
}

static void process_jobs_wait_kill_and_clean_up(void) {
  $test.scoped();
  Array jobs = %[];
  for (int i = 3; i >= 1; i--)
    jobs.push(%(sh -c ${%"sleep 0.$i; exit $i"}).start());
  Array order = %[];
  while (jobs.len()) order.push(Job.wait_any(jobs).wait());
  EXPECT_TRUE(order.equal(%[1, 2, 3]));
  EXPECT_NULL(Job.wait_any(jobs));

  Job killed = %(sleep 30).start();
  EXPECT_FALSE(killed.ready());
  killed.kill(SIGKILL);
  EXPECT_INT_EQ(killed.wait(), 128 + SIGKILL);
  EXPECT_TRUE(killed.ready());

  long pid = 0;
  {
    Job sleeper = $auto(%(sleep 30).start());
    pid = sleeper.pids[0];
  }
  EXPECT_TRUE(pid > 0 && kill((pid_t) pid, 0) != 0);

  Job done = %(echo done).options(%{stdout: capture}).start();
  EXPECT_STR_EQ(done.output(), "done\n");
  EXPECT_INT_EQ(done.wait(), 0);
}

static void process_env_reads_the_calling_process(void) {
  $test.scoped();
  String name = %"X2C_TEST_ENVIRONMENT_VALUE";
  EXPECT_NULL(name.env());
  setenv(name, "present", 1);
  EXPECT_STR_EQ(name.env(), "present");
  unsetenv(name);
  EXPECT_NULL(name.env());
  EXPECT_NULL(String.env(NULL));
}

void process_suite(void) {
  $test.run(process_arguments_stay_whole);
  $test.run(process_env_reads_the_calling_process);
  $test.run(process_status_reports_exit_and_signal);
  $test.run(process_run_raises_command_failure);
  $test.run(process_output_and_lines_capture_stdout);
  $test.run(process_pipelines_join_stages);
  $test.run(process_pipeline_status_is_last_failure);
  $test.run(process_options_route_streams);
  $test.run(process_options_write_files_and_merge);
  $test.run(process_start_failures_raise);
  $test.run(process_jobs_wait_kill_and_clean_up);
}
