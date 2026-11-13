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
    (-h --help (help "Show help and exit"))
    (-j (value n) (default "1") (help "Run up to <n> test files concurrently"))
    (--filter (value substring) repeated
      (help "Select test names containing <substring>"))
    (--list (help "List matching tests"))
    (-q --quiet (help "Suppress successful test lines"))
    (--manifest-path (value file)
      (help "Read this project manifest"))
    (--target (value name)
      (help "Use this manifest target's include directories"))
    (--profile (value name) (help "Use this manifest profile"))
    (inputs repeated (help "Test files or directories")));
  Map options = NULL;
  try options = Args.parse(Args.from_argv(argc, argv), spec);
  catch %(bad-arg (operation "Args.parse") (reason ?why) *detail): {
    String option = detail.assoc(<option>);
    Diagnostics.driver_error(option ? %"test: $why '$option'" : %"test: $why");
  }
  if (options["help"].integer()) {
    String about = "\nBuild and run test files, found below the nearest "
                   "x2c.toml or\nthe current directory unless <inputs> "
                   "name them.\n\nOptions:";
    fputs(Args.usage("x2c test", spec).replace("\nOptions:", about), stdout);
    return 0;
  }
  Run run = _configure(options);
  Array files = _discover(options["inputs"], run.root);
  if (!files.len()) _no_tests(options["inputs"], run.root);
  _run_files(run, files);
  printf(
    "files: %d passed, %d failed; tests: %d passed, %d failed\n",
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
  project.manifest = options["manifest-path"];
  project.target = options["target"];
  project.profile = options["profile"];
  String manifest = project.project_manifest();
  Path root =
    manifest ? Path.dirname(Path.absolute(manifest)) : Path.absolute(".");
  if (manifest) {
    project.manifest = manifest;
    // The selected target follows all its dependencies.
    for (ProjectBuild node = ProjectBuild.plan(project); node;
         node = node.next)
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

/* Says where discovery looked and what it selects. */
static void _no_tests(List operands, Path root) {
  String searched = operands ? " ".join(operands) : _shown(root);
  Diagnostics.driver_fail(
    %"test: no test files found in $searched",
    "tests are *_test.x and test_*.x files, and .x files in tests/");
}

static Array _discover(List operands, Path root) {
  Map unique = {};
  int explicit = !!operands;
  String root_prefix = %"$(root.rstrip("/"))/";
  if (!operands) operands = $(root);
  foreach (Path operand in operands) {
    Path path = Path.absolute(operand);
    if (path.is_file()) unique[path] = 1;
    else if (path.is_dir()) {
      Path base = path == root || path.startswith(root_prefix) ? root : path;
      String prefix = %"$(base.rstrip("/"))/";
      int tests = explicit && path != root && path.basename() == "tests";
      _discover_directory(unique, path, prefix, tests);
    }
    else
      Diagnostics.driver_error(%"test: no such file or directory '$operand'");
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
    if (relative.startswith(".x2c-build/") || "/.x2c-build/" in relative ||
        file.basename() == ".x2c-build") continue;
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
      _report(run, job, files[reported], files.len() > 1);
      reported++;
    }
    Job.wait_any(pending);
  }
}

/* Prints a file's output, its locations relative to the working
   directory, under the file's name when the run has several files. */
static void _report(Run &run, Job job, Path file, int named) {
  int status = job.status();
  String output = status ? job.output_text : job.output();
  int passed, failed, skipped;
  int counts = _summary_counts(output, passed, failed, skipped);
  if (run.filtered && status == 2 && counts &&
      !passed && !failed && !skipped) return;
  String shown = _shown(file);
  if (named) printf("Testing %s\n", shown);
  if (output) fputs(output.replace(%"$file:", %"$shown:"), stdout);
  if (status) run.files_failed++;
  else run.files_passed++;
  if (counts) {
    run.tests_passed += passed;
    run.tests_failed += failed;
  }
}

/* `path` relative to the working directory when it lies in it. */
static String _shown(Path path) {
  String directory = Path.absolute(".").rstrip("/");
  if (path == directory) return ".";
  String prefix = %"$directory/";
  return path.startswith(prefix) ? path.remove_prefix(prefix) : path;
}

static int _summary_counts(
  String output, int &passed, int &failed, int &skipped) {
  foreach (String line in output.split_lines().reverse()) {
    if (!line) continue;
    int end = 0;
    int fields = sscanf(
      line, "%d passed, %d failed, %d skipped%n",
      &passed, &failed, &skipped, &end);
    if (fields == 3 && end == line.len()) return 1;
  }
  return 0;
}

static Job _start(Run run, Path file) {
  Array command = [Compiler.driver_executable(), "script"];
  foreach (String dir in run.project.include_dirs) {
    command.push("-I");
    command.push(dir);
  }
  foreach (String dir in run.project.package_dirs) {
    command.push("--package-dir");
    command.push(dir);
  }
  foreach (String arg in run.project.cpp_args) command.push(arg);
  foreach (String arg in run.project.cc_args) {
    command.push("-Xcc");
    command.push(arg);
  }
  foreach (String arg in run.project.ld_args) {
    command.push("-Xlinker");
    command.push(arg);
  }
  command.push(file);
  foreach (String arg in run.program_args) command.push(arg);
  Job job = command.list();
  return job.options(
    stderr: <stdout>,
    env: {"X2C_CACHE_DIR": %"$(run.root)/.x2c-build/tests"}).start();
}
