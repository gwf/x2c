/*  workflow.x -- application build and run orchestration

    Copyright (c) 2026 Gary William Flake.
*/

#pragma once
#include "build.x"
#include "project/project.x"
#include "translation.x"

static macro Stmt $progress.main_translation_verbose(
  Expr $directory, Expr $input) =>
  fprintf(stderr, "x2c: translate --out-dir %s %s\n", $directory, $input);

// builds

/* A build runs its explicit inputs as one target, or each target of its
   project manifest. Every target adds its compile commands to one
   database. */
int build_request(CliRequest request) {
  Array commands = request.compile_commands && !request.dry_run ? [] : NULL;
  int status = request.inputs
    ? _build_inputs(request, commands) : _build_manifest(request, commands);
  if (status || commands == NULL || request.command == <run>) return status;
  return !Build.write_commands(request.compile_commands, commands);
}

static int _build_inputs(CliRequest request, Array commands) {
  /* Manifest options have no meaning without a manifest. The build fails
     before it builds something the command did not describe. */
  if (request.manifest)
    Diagnostics.driver_error("--manifest-path conflicts with explicit inputs");
  if (request.target)
    Diagnostics.driver_error("--target conflicts with explicit inputs");
  if (request.profile)
    Diagnostics.driver_error("--profile conflicts with explicit inputs");
  return _build_target(request, commands);
}

static int _build_manifest(CliRequest request, Array commands) {
  if (request.compile_only)
    Diagnostics.driver_error(
      "--compile-only needs input operands, not a manifest");
  ProjectBuild first = ProjectBuild.plan(request);
  for (ProjectBuild node = first; node; node = node.next) {
    int status = _build_target(node.request, commands);
    if (status) return status;
  }
  return 0;
}

static int _build_target(CliRequest request, Array commands) {
  /* A target has its own build graph and native-action scratch. Isolate
     its Scope allocations and canonical values so a manifest dependency is
     reclaimed before the next target starts. */
  Context target = $auto(Context.open_isolated_named("build target"));
  defer Compiler.reset_macro_library();
  Build b = request.prepare();
  request.cc = target.export(request.cc);
  request.meta_cc = target.export(request.meta_cc);
  request.ar = target.export(request.ar);
  int status = _translate_target(request, b);
  if (!status) status = b.finish();
  if (!status) status = _add_commands(request, b, target, commands);
  if (status) {
    b.cleanup(0);
    return status;
  }
  b.report_success();
  if (request.command == <run>) status = b.run_program();
  else if (request.command == <script> && !request.dry_run)
    b.publish_script(%"${request.build_dir}/run");
  b.cleanup(1);
  return status;
}

/* A target translates its inputs, then a script's local includes, then a
   module's or its extensions' entry units. */
static int _translate_target(CliRequest request, Build b) {
  int status = _translate_units(request, b, request.inputs);
  /* A script's local `.x` includes are units of its program too; their
     objects have no other source. */
  if (!status && request.command == <script> && !request.dry_run)
    status = _translate_units(request, b, b.script_helpers());
  if (status || request.dry_run) return status;
  if (request.kind != <module> && !request.extensions) return 0;
  CliRequest entry =
    request.kind == <module> ? b.module_entry() : b.extension_entries();
  return _translate_units(entry, b, entry.inputs);
}

/* A target's compile commands join the build's database, which `run`
   writes before its program runs. */
static int _add_commands(
  CliRequest request, Build b, Context target, Array commands) {
  if (commands == NULL) return 0;
  foreach (String entry, b.compile_commands)
    commands.push(target.export(entry));
  if (request.command != <run>) return 0;
  return !Build.write_commands(request.compile_commands, commands);
}

/* Translates the stale `units` and registers every unit's generated files.
   Current units are skipped; the rest translate together, so one request
   can fill every job. Each unit keeps its own generated directory,
   so no two workers write the same file. */
static int _translate_units(CliRequest request, Build b, List units) {
  Map stale = {};
  List inputs = _stale_inputs(b, units, stale);
  if (!request.dry_run && inputs) {
    CliRequest translation = xmemdup(request, sizeof(struct CliRequest));
    translation.inputs = inputs;
    translation.out_dir = b.gen_root;
    if (translate_request(translation, stale, b, _translation_progress)) return 1;
  }
  _register_units(request, b, units, stale);
  return 0;
}

/* The units whose translation is not current, in order, with each one's
   generated directory in `stale`. A current unit counts as cached. */
static List _stale_inputs(Build b, List units, Map stale) {
  Array inputs = [];
  foreach (String input, units) {
    if (!Path.is_x2c_source(input)) continue;
    String directory = b.generated_dir(input);
    if (b.translation_current(input, directory)) {
      b.begin_translation(input);
      b.end_translation(input, 1);
      continue;
    }
    stale[input] = directory;
    inputs.push(input);
  }
  return inputs.list_free();
}

/* Registers every unit's generated files in input order, including package
   directories inserted between generated directories, before native
   compilation and linking. A dry run prints each stale unit's translation,
   and a real one records its fingerprint. */
static void _register_units(
  CliRequest request, Build b, List units, Map stale) {
  foreach (String input, units) {
    if (!Path.is_x2c_source(input)) continue;
    String directory = b.generated_dir(input);
    if (input in stale && request.dry_run) {
      b.begin_translation(input);
      $progress.main_translation_verbose(directory, input);
      b.end_translation(input, 0);
    }
    else if (input in stale) b.record_translation(input, directory);
    b.add_generated(input, directory);
  }
}

/* Translation reports only starts and successful completions. Cached units
   remain accounted for by the build's freshness pass. */
static void _translation_progress(void *context, String input, int completed) {
  Build b = context;
  if (completed) b.end_translation(input, 0);
  else b.begin_translation(input);
}
