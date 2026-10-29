/*  main.x -- discover and run project test programs

    Copyright (c) 2026 Gary William Flake.
*/
#include "project/project.x"
#include "args.x"
#include "process.x"

String x2c_embedded_identity(void);

static typedef struct Run {
  Path root;
  CliRequest project;
  List program_args;
  int jobs, filtered;
  int files_passed, files_failed, tests_passed, tests_failed;
} Run;

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  List spec = %(
    (-h --help (help "Show this help"))
    (-j (value N) (default "1") (help "Run up to N test files concurrently"))
    (--filter (value substring) repeated (help "Select test names containing substring"))
    (--list (help "List matching tests"))
    (-q --quiet (help "Suppress successful test lines"))
    (--manifest (value file) (help "Read this project manifest"))
    (--target (value name) (help "Use this manifest target's include directories"))
    (inputs repeated (help "Test files or directories")));
  Map options = NULL;
  try options = Args.parse(Args.from_argv(argc, argv), spec);
  catch %(bad-arg (operation "Args.parse") (reason ?why) *): {
    Diagnostics.driver_error(%"test: $why");
  }
  if (options["help"].integer()) {
    fputs(Args.usage("x2c test", spec), stdout);
    return 0;
  }
  Run run = _configure(options);
  Array files = _discover(options["inputs"], run.root);
  if (!files.len()) {
    fputs("x2c test: no test files found\n", stderr);
    return 2;
  }
  _run_files(run, files);
  printf("files: %d passed, %d failed; tests: %d passed, %d failed\n",
    run.files_passed, run.files_failed, run.tests_passed, run.tests_failed);
  return run.files_failed ? 1 : run.filtered && !run.files_passed ? 2 : 0;
}

static Run _configure(Map options) {
  String jobs = options["j"];
  char *end;
  long count = strtol(jobs ? jobs : "", &end, 10);
  if (!jobs || *end || count < 1 || count > INT_MAX)
    Diagnostics.driver_error("test: -j requires a positive integer");
  CliRequest project = CliRequest.new(<build>);
  project.manifest = options["manifest"];
  project.target = options["target"];
  project.dry_run = 1;
  String manifest = project.project_manifest();
  Path root = manifest ? Path.dirname(Path.absolute(manifest)) : Path.absolute(".");
  if (manifest) {
    project.manifest = manifest;
    // The selected target follows all its dependencies.
    for (ProjectBuild node = ProjectBuild.plan(project); node; node = node.next)
      project = node.request;
  }
  Array args = [];
  foreach (String filter in options["filter"].list()) {
    args.push("--filter");
    args.push(filter);
  }
  if (options["list"].integer()) args.push("--list");
  if (options["quiet"].integer()) args.push("--quiet");
  return (Run) {.root = root, .project = project,
    .program_args = args.list(), .jobs = count,
    .filtered = !!options["filter"].list()};
}

static Array _discover(List operands, Path root) {
  Map unique = {};
  int explicit = !!operands;
  String root_prefix = %"$(root.rstrip("/"))/";
  if (!operands) operands = $(root);
  foreach (Path path in operands) {
    path = Path.absolute(path);
    if (path.is_file()) unique[path] = 1;
    else if (path.is_dir()) {
      Path base = path == root || path.startswith(root_prefix) ? root : path;
      String prefix = %"$(base.rstrip("/"))/";
      int tests = explicit && path != root && path.basename() == "tests";
      _discover_directory(unique, path, prefix, tests);
    }
    else Diagnostics.driver_error(%"test: no such file or directory '$path'");
  }
  Array files = unique.keys();
  return files.sort();
}

static void _discover_directory(
  Map unique, Path directory, String prefix, int tests) {
  Array pending = [];
  foreach (String name in directory.list_dir().reverse())
    pending.push(directory.join(name));
  while (pending.len()) {
    Path file = pending.take_last();
    String relative = file.remove_prefix(prefix);
    if (relative.startswith(".x2c-build/") ||
        "/.x2c-build/" in relative || file.basename() == ".x2c-build") continue;
    if (file.is_file()) {
      String name = file.basename();
      if (name.endswith("_test.x") ||
          (name.startswith("test_") && name.endswith(".x")) ||
          ((tests || relative.startswith("tests/") || "/tests/" in relative) &&
            name.endswith(".x"))) unique[file] = 1;
    }
    else {
      struct stat info;
      if (lstat(file, &info) || !S_ISDIR(info.st_mode) ||
          access(file, R_OK | X_OK)) continue;
      foreach (String name in file.list_dir().reverse())
        pending.push(file.join(name));
    }
  }
}

static void _run_files(Run &run, Array files) {
  Array pending = [], ordered = [];
  int next = 0, reported = 0;
  while (reported < files.len()) {
    while (next < files.len() && pending.len() < run.jobs) {
      Job job = _start(run, files[next++]);
      pending.push(job);
      ordered.push(job);
    }
    while (reported < ordered.len()) {
      Job job = ordered[reported];
      if (!job.finished) break;
      _report(run, job);
      reported++;
    }
    Job.wait_any(pending);
  }
}

static void _report(Run &run, Job job) {
  int status = job.status();
  String output = status ? job.output_text : job.output();
  List lines = output.split_lines(0);
  String summary = lines ? lines.reverse().car() : NULL;
  int passed, failed, skipped;
  int counts = summary && sscanf(summary, "%d passed, %d failed, %d skipped",
                                  &passed, &failed, &skipped) == 3;
  if (run.filtered && status == 2 && counts &&
      !passed && !failed && !skipped) return;
  if (output) fputs(output, stdout);
  if (status) run.files_failed++;
  else run.files_passed++;
  if (counts) {
    run.tests_passed += passed;
    run.tests_failed += failed;
  }
}

static Job _start(Run run, Path file) {
  Array command = [Compiler.driver_executable(), "script"];
  foreach (String dir in run.project.include_dirs) {
    command.push("--x-include-dir");
    command.push(dir);
  }
  foreach (String dir in run.project.package_dirs) {
    command.push("--package-dir");
    command.push(dir);
  }
  command.push(file);
  foreach (String arg in run.program_args) command.push(arg);
  Job job = command.list();
  return job.options({stderr: <stdout>, env: {
    "X2C_CACHE_DIR": %"$(run.root)/.x2c-build/tests"
  }}).start();
}
