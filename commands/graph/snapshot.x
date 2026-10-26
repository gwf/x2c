/*  snapshot.x -- full project analysis and explicit snapshot lifecycle

    Copyright (c) 2026 Gary William Flake
*/

#pragma once
#include "frontend.x"
#include "meta-project.x"
#include "project/project.x"
#include "snapshot-common.x"

Map graph_snapshot_extract(ParsedUnit *parsed, String domain);
void graph_snapshot_resolve(Map snapshot);
Map graph_snapshot_query(Map snapshot, Map query);
Map graph_snapshot_diff(Map before, Map after);

static String _snapshot_fingerprint(Path path) {
  if (path.is_dir()) return snapshot_text(path.list_dir().sort());
  return path.content_identity();
}

static CliRequest _snapshot_request(Array arguments) {
  Array words = ["build"];
  foreach (String word, arguments)
    words.push(word == "-I" ? "--x-include-dir" : word);
  CliRequest request = CliRequest.parse_arguments(words);
  request.sources = SourceView.new();
  request.source_facts = request.source_map = 1;
  request.dry_run = 1;
  return request;
}

static ProjectBuild _snapshot_plan(CliRequest request) {
  if (!request.inputs) return ProjectBuild.plan(request);
  if (request.manifest || request.target || request.profile)
    raise %(bad-arg (reason "manifest options conflict with explicit inputs"));
  ProjectBuild plan = xcalloc(1, sizeof(struct ProjectBuild));
  plan.request = request;
  return plan;
}

static String _snapshot_domain(CliRequest request) =>
  request.label ? request.label : "inputs";

static Array _snapshot_inputs(CliRequest request) {
  Map seen = {};
  Array inputs = [];
  foreach (String input, request.inputs) {
    if (!Path.is_x2c_source(input)) continue;
    String path = Path.absolute(input);
    if (!(path in seen)) { seen[path] = 1; inputs.push(path); }
  }
  return inputs.sort();
}

static Array _snapshot_membership(ProjectBuild plan) {
  Array rows = [];
  for (ProjectBuild node = plan; node; node = node.next) {
    String domain = _snapshot_domain(node.request);
    foreach (String path, _snapshot_inputs(node.request))
      rows.push(%"$domain::$path");
  }
  return rows.sort();
}

static Map _snapshot_links(ProjectBuild plan) {
  Map outputs = {}, links = {};
  for (ProjectBuild node = plan; node; node = node.next) {
    CliRequest request = node.request;
    String domain = _snapshot_domain(request);
    Array allowed = [];
    foreach (String input, request.inputs) {
      String dependency = outputs[Path.absolute(input)];
      if (!dependency) continue;
      allowed.push(dependency);
      foreach (String transitive, links[dependency])
        if (!(transitive in allowed)) allowed.push(transitive);
    }
    links[domain] = allowed.sort();
    if (request.output) outputs[Path.absolute(request.output)] = domain;
  }
  return links;
}

static void _snapshot_dependency(Map fingerprints, String path) {
  if (path.startswith("cwd:")) path = path[4:];
  path = Path.absolute(path);
  if (!(path in fingerprints)) fingerprints[path] =
    _snapshot_fingerprint(path);
}

static void _snapshot_merge(Map snapshot, Map unit, Map files) {
  foreach (String key, %("entities" "edges")) {
    Array destination = snapshot[key];
    foreach (Var row, unit[key]) destination.push(row);
  }
  Array sources = snapshot["files"];
  foreach (Map file, unit["files"]) {
    String path = file["path"];
    if (files.contains(path)) {
      if (files[path] != file["text"])
        raise %(bad-state (reason "source changed during snapshot")
                (path $path));
    }
    else { files[path] = file["text"]; sources.push(file); }
  }
  Map types = snapshot["types"];
  foreach (Var (key, value), unit["types"]) types[key] = value;
}

static void _snapshot_analyze(Map snapshot, ProjectBuild plan) {
  Map fingerprints = snapshot["fingerprints"];
  Map files = {};
  for (ProjectBuild node = plan; node; node = node.next) {
    CliRequest request = node.request;
    request.dry_run = 0;
    Array inputs = _snapshot_inputs(request);
    Frontend frontend = Frontend.new(request);
    frontend.prepare_meta(inputs);
    foreach (String input, inputs) {
      // Collection cache rows outlive their compiler's source declarations.
      // A saved-analysis unit needs fresh declaration provenance as well.
      Compiler.refresh_source_collections();
      ParsedUnit parsed;
      if (!frontend.open_reporting(input, parsed))
        raise %(malformed (input $input));
      String retained = NULL;
      try {
        Map unit = graph_snapshot_extract(&parsed, _snapshot_domain(request));
        Map dependencies = {};
        foreach (String path, parsed.compiler.deps.keys())
          _snapshot_dependency(dependencies, path);
        _snapshot_dependency(dependencies, input);
        foreach (String module, request.native_modules)
          _snapshot_dependency(dependencies, module);
        unit["fingerprints"] = dependencies;
        retained = parsed.context.export(snapshot_text(unit));
      }
      finally parsed.close();
      Map unit = snapshot_value(retained);
      _snapshot_merge(snapshot, unit, files);
      foreach (Var (path, fingerprint), unit["fingerprints"])
        fingerprints[path] = fingerprint;
    }
  }
}

static Map _snapshot_build(Array arguments) {
  CliRequest request = _snapshot_request(arguments);
  ProjectBuild plan = _snapshot_plan(request);
  Map snapshot = {
    "version": 1, "compiler": x2c_embedded_identity(),
    "cwd": Path.absolute("."), "arguments": arguments,
    "entities": [], "edges": [], "files": [], "types": {},
    "fingerprints": {}, "membership": _snapshot_membership(plan),
    "links": _snapshot_links(plan),
    "coverage": ["bound macro-expanded syntax",
      "direct calls and recorded references; indirect targets unresolved",
      "no later transforms, C bodies, or general alias analysis"]};
  if (!request.inputs) {
    String manifest = request.project_manifest();
    _snapshot_dependency(snapshot["fingerprints"], manifest);
  }
  _snapshot_analyze(snapshot, plan);
  graph_snapshot_resolve(snapshot);
  String contents = snapshot_text(snapshot);
  snapshot["identity"] = "%016llx".printf((unsigned long long)
    fnv_bytes(FNV_OFFSET_BASIS, contents, contents.len()));
  return snapshot;
}

static void _snapshot_publish(Path destination, Map snapshot) {
  destination = Path.absolute(destination);
  if (destination.exists() &&
      !destination.join("snapshot.datum").is_file())
    raise %(bad-arg (reason "destination is not a snapshot")
            (path $destination));
  Path parent = destination.dirname();
  parent.make_dirs();
  String template = parent.join(".x2c-snapshot-XXXXXX");
  char *buffer = xmemdup(template, template.len() + 1);
  if (!mkdtemp(buffer)) File.path_error("snapshot temporary", parent, errno);
  Path temporary = String.new(buffer);
  defer temporary.remove_tree();
  Path staged = temporary.join("snapshot.datum");
  staged.write_text(snapshot_text(snapshot));
  if (!destination.exists()) temporary.move_to(destination);
  else staged.move_to(destination.join("snapshot.datum"));
}

static Map _snapshot_status(Map snapshot, String executable) {
  Array changed = [], missing = [], added = [], removed = [];
  Map fingerprints = snapshot["fingerprints"];
  Array paths = fingerprints.keys();
  foreach (String path, paths.sort()) {
    if (!Path.exists(path) && fingerprints[path]) missing.push(path);
    else if (_snapshot_fingerprint(path) != fingerprints[path])
      changed.push(path);
  }
  String previous = Path.absolute(".");
  if (chdir(snapshot["cwd"].str()))
    File.path_error("snapshot cwd", snapshot["cwd"], errno);
  defer (void) chdir(previous);
  // Project diagnostics terminate the request. Isolate discovery so status
  // can still report changed files when the edited manifest is invalid.
  Array arguments = [executable, "_snapshot-members"];
  foreach (String word, snapshot["arguments"]) arguments.push(word);
  String output = NULL, errors = NULL;
  int status = tool_capture(arguments, output, errors);
  Array current = status ? [] : Json.parse(output).map()["membership"];
  Array recorded = snapshot["membership"];
  if (!status) {
    foreach (String path, current) if (!(path in recorded)) added.push(path);
    foreach (String path, recorded) if (!(path in current)) removed.push(path);
  }
  return {"snapshot": snapshot["identity"],
    "coverage": snapshot["coverage"],
    "fresh": Json.bool(!status && !changed.len() && !missing.len() &&
                       !added.len() && !removed.len()),
    "membership_checked": Json.bool(!status), "membership_error": errors,
    "changed": changed, "missing": missing,
    "added_inputs": added, "removed_inputs": removed};
}

/** Handles saved-analysis commands before ordinary graph parsing starts. */
int graph_snapshot_command(int argc, char **argv) {
  String verb = String.new(argv[1]);
  try {
    if (verb == "_snapshot-members") {
      Array arguments = [];
      for (int i = 2; i < argc; i++) arguments.push(String.new(argv[i]));
      Map result = {"membership": _snapshot_membership(
        _snapshot_plan(_snapshot_request(arguments)))};
      printf("%s\n", Var.json(result));
      return 0;
    }
    if (argc < 3) raise %(bad-arg (reason "snapshot path required"));
    Map result;
    if (verb == "snapshot") {
      Array arguments = [];
      for (int i = 3; i < argc; i++) arguments.push(String.new(argv[i]));
      Map snapshot = _snapshot_build(arguments);
      _snapshot_publish(String.new(argv[2]), snapshot);
      result = {"snapshot": snapshot["identity"],
        "path": Path.absolute(String.new(argv[2])),
        "coverage": snapshot["coverage"]};
    }
    else {
      Map snapshot = graph_snapshot_read(String.new(argv[2]));
      if (verb == "status" && argc == 3)
        result = _snapshot_status(snapshot, Path.absolute(String.new(argv[0])));
      else if (verb == "query" && argc == 4) {
        Var query = Json.read_file(String.new(argv[3]));
        if (query is not <map>) raise %(bad-arg (reason "query object required"));
        result = graph_snapshot_query(snapshot, query);
      }
      else if (verb == "diff" && argc == 4)
        result = graph_snapshot_diff(
          snapshot, graph_snapshot_read(String.new(argv[3])));
      else raise %(bad-arg (reason "wrong snapshot command operands"));
    }
    printf("%s\n", Var.json(result));
    return 0;
  }
  catch %(*failure): {
    fprintf(stderr, "x2c graph %s: %s\n", verb, failure.repr());
    return 2;
  }
}
