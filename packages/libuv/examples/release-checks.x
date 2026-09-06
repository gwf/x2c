/*  release-checks.x -- supervise a batch of release checks on one loop.

    Each check is a child in a sandbox directory with a fixed environment
    and its own deadline. The loop reports every check as it finishes, a
    directory watcher reports changes, and a scan finds the artifacts to
    read asynchronously. SIGINT or SIGTERM abandons the batch
    instead of orphaning it.
*/

import "libuv" with UvFs, UvLoop, UvProcess, UvSignal, UvTimer, UvWatch;

#include <signal.h>
#include <sys/stat.h>

typedef struct Check *Check;
typedef struct Artifact *Artifact;

struct Check {
  String name;
  UvProcess process;
  int reported;
};

struct Artifact {
  String name;
  Bytes content;
};

static void _abandon(UvSignal signal, Var value) {
  printf("%s", %"\nsignal ${signal.number()}: ${value.string()}\n");
  signal.loop().stop();
}

static void _out_of_budget(UvTimer timer, Var value) {
  printf("%s", %"the batch ran past its ${value.string()} budget\n");
  timer.loop().stop();
}

static void _settled(UvTimer timer, Var value) {
  (void) value;
  timer.loop().stop();
}

/*  A watch event can name the directory itself or a removed entry. Scan
    after the children finish to find the files that can actually be read.
*/
static void _artifact(UvWatch watch, Var value) {
  (void) value;
  if (watch.entry()) printf("  changed      %s\n", watch.entry());
}

static void _scan(UvFs request, Var value) {
  Array names = value;
  for (int index = 0; index < request.entry_count(); index++)
    if (request.entry_type(index) == UV_DIRENT_FILE)
      names.push(request.entry_name(index));
}

static void _artifact_read(UvFs request, Var value) {
  Artifact artifact = value.pointer();
  artifact.content = request;
}

static Var _plan(
  UvLoop loop, String work, Map environment, String name, String script,
  long deadline) {
  Check check = Scope.calloc(1, sizeof(struct Check));
  check.name = name;
  check.process = loop.command(%("/bin/sh" "-c" $script))
    .directory(work).environment(environment).deadline(deadline).start();
  check.process.close_stdin();
  return (void *) check;
}

/*  A clean sandbox: the checks read release.txt and write into out/,
    which is the directory the watcher reports on. Returns that directory.
*/
static String _sandbox(String work) {
  mkdir(work, 0700);
  mkdir(%"$work/out", 0700);
  File source = File.open(%"$work/release.txt", %"w");
  source.puts(%"alpha\nbeta\ngamma\n");
  source.close();
  return %"$work/out";
}

/*  Reports every check that has finished since the last turn and returns
    how many of the batch are now accounted for.
*/
static int _report_finished(Array checks, int *passed, int *expired) {
  int settled = 0;
  foreach(Var value, checks) {
    Check check = value.pointer();
    if (check.reported) settled++;
    if (check.reported || !check.process.exited()) continue;
    check.reported = 1;
    settled++;
    if (check.process.timed_out()) {
      (*expired)++;
      printf("  %-12s timed out\n", check.name);
      continue;
    }
    if (check.process.exit_status()) {
      printf("  %-12s failed   %s", check.name, check.process.stderr());
      continue;
    }
    (*passed)++;
    printf("  %-12s ok       %s", check.name, check.process.stdout());
  }
  return settled;
}

int main(void) {
  String work = %"/tmp/x2c-libuv-release";
  String output = _sandbox(work);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  Map environment = %{
    "PATH": "/usr/bin:/bin", "RELEASE_MODE": "strict"
  };
  Array artifacts = %[];
  Array checks = %[];
  int passed = 0, expired = 0;

  UvWatch watch = loop.watch(output, 0, _artifact);
  UvTimer budget = loop.timer(5000, 0, %"5 s", _out_of_budget);
  loop.signal(SIGINT, %"batch abandoned", _abandon);
  loop.signal(SIGTERM, %"batch abandoned", _abandon);

  checks.push(_plan(
    loop, work, environment, %"line-count",
    %"wc -l < release.txt | tr -d ' ' | tee out/lines.txt", 2000
  ));
  checks.push(_plan(
    loop, work, environment, %"fingerprint",
    %"cksum release.txt | cut -d' ' -f1 | tee out/sum.txt", 2000
  ));
  checks.push(_plan(
    loop, work, environment, %"environment", %"printenv RELEASE_MODE", 2000
  ));
  checks.push(_plan(
    loop, work, environment, %"slow-scan", %"sleep 30", 200
  ));

  printf("%s", %"${checks.len()} checks in $work\n");
  while (_report_finished(checks, &passed, &expired) < checks.len()) {
    if (!loop.run(UV_RUN_ONCE)) break;
  }

  /*  A signal ends the batch early, so kill whatever is still running and
      let the loop reap it; no child outlives this program. The watcher
      also lags the children, so give it time to name the last artifacts.
  */
  foreach(Var value, checks) {
    Check check = value.pointer();
    if (!check.process.exited()) check.process.kill(SIGKILL);
  }
  loop.timer(400, 0, 0, _settled);
  loop.run(UV_RUN_DEFAULT);
  _report_finished(checks, &passed, &expired);
  watch.stop();
  budget.stop();

  loop.scan(output, artifacts, _scan);
  loop.run(UV_RUN_DEFAULT);

  Array contents = %[];
  foreach(String name, artifacts) {
    Artifact artifact = Scope.calloc(1, sizeof(struct Artifact));
    artifact.name = name;
    contents.push((void *) artifact);
    loop.read_file(
      %"$output/${artifact.name}", 1024,
      Var.new(<p48>, artifact), _artifact_read
    );
  }
  loop.run(UV_RUN_DEFAULT);
  foreach(Var value, contents) {
    Artifact artifact = value.pointer();
    printf(
      "  artifact     %-12s %.*s", artifact.name,
      (int) artifact.content.len(), (char *) artifact.content
    );
  }
  printf("%s", %"$passed passed, $expired timed out\n");
  foreach(Var value, checks) ((Check) value.pointer()).process.free();
  return 0;
}
