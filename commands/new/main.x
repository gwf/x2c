/*  main.x -- create starter projects

    Copyright (c) 2026 Gary William Flake.
*/
#include "project/project.x"
#include "utils.x"
#include "args.x"

String x2c_embedded_identity(void);

// source templates

static macro Expression $source.project.manifest(Expr $name) =>
  %"[target.$($name)]
sources = [\"src/*.x\"]
";

static macro Expression $source.project.main() =>
  %"/*  main.x -- greet the name given on the command line */

#include <stdio.h>

int main(int argc, char **argv) {
  String name = argc > 1 ? argv[1] : \"world\";
  puts(%\"Hello, \$name!\");
  return 0;
}
";

static macro Expression $source.project.ignore() =>
  ".x2c-build/\n";

static macro Stmt $report.project.created(Expr $directory) {
  fprintf(
    stderr, "x2c: created %s\nRun 'x2c run' in %s to build and run it.\n",
    $directory, $directory);
}

static macro Stmt $report.project.name_invalid(Expr $name) {
  Diagnostics.driver_error(
    %"new: '$(
      $name)' is not a target name; use letters, digits, '_', and '-'");
}

static macro Stmt $report.project.directory_occupied(Expr $dir) {
  Diagnostics.driver_error(
    %"new: '$($dir)' exists and is not an empty directory");
}

// new projects

static int _create(Path dir, int quiet) {
  if (!dir) Diagnostics.driver_error("new: the directory operand is empty");
  String name = _starter_name(dir);
  try _write_starter(dir, name);
  catch %(io-fail *detail): Diagnostics.host_error(detail);
  if (!quiet) $report.project.created(dir);
  return 0;
}

/* The operand's own last component names the target, so a symbolic link
   is named for the link and not for what it points at. */
static String _starter_name(Path dir) {
  String name = dir.basename();
  if (name == "." || name == ".." || name == "/")
    name = Path.absolute(dir).basename();
  if (!ProjectBuild.valid_name(name))
    $report.project.name_invalid(name);
  return name;
}

static void _write_starter(Path dir, String name) {
  if (dir.exists() && (!dir.is_dir() || dir.list_dir()))
    $report.project.directory_occupied(dir);
  dir.join("src").make_dirs();
  dir.join("x2c.toml").write_text($source.project.manifest(name));
  dir.join("src/main.x").write_text($source.project.main());
  dir.join(".gitignore").write_text($source.project.ignore());
}

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  Array arguments = auto CliRequest.command_arguments(argc, argv);
  if (arguments) {
    CliRequest request = CliRequest.parse_arguments(arguments);
    return _create(request.inputs.car(), request.quiet);
  }
  arguments = Args.from_argv(argc, argv);
  arguments.unshift("new");
  CliRequest request = CliRequest.parse_arguments(arguments);
  return _create(request.inputs.car(), request.quiet);
}
