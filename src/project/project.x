/*  project.x -- x2c project manifests

    Copyright (c) 2026 Gary William Flake.

    A project manifest defines source membership, deterministic glob
    expansion, target relationships, and named profiles. Resolved targets
    lower to the same CliRequest a direct build uses.
*/

#pragma once
#include "cli/cli.x"

/** Links native build requests in dependency-first order.
    `ProjectBuild.plan` returns the head. Each node and copied `CliRequest`
    struct is owned by the current `Scope` and needs no individual cleanup; its
    `String` and `List` fields retain their canonical pool lifetimes and may
    share values with the command request.
*/
typedef struct ProjectBuild {
  CliRequest request;
  struct ProjectBuild *next;
} *ProjectBuild;

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "buffer.x"

// the manifest model

/* A target or profile exists from its first mention. `declared` records
   that its own section appeared, and `seen` holds the keys that section
   set. */
module typedef struct ProjectProfile {
  String name, optimization, int debug, List defines, c_flags, link_flags;
  Map seen, int declared, struct ProjectProfile *next;
} *ProjectProfile;

module typedef struct ProjectTarget {
  String name, Symbol kind, String output, List sources, exclude, dependencies;
  List native_modules, include_dirs, package_dirs, defines, c_flags;
  List library_dirs, libraries, link_flags;
  ProjectProfile profiles;
  Map seen, int declared, visiting, visited, planned;
  struct ProjectTarget *next;
} *ProjectTarget;

module typedef struct ProjectDependency {
  String name, version;
  struct ProjectDependency *next;
} *ProjectDependency;

/* A project holds its manifest's settings, the command request it serves,
   and, while it plans, the selected target and the build list. */
module typedef struct Project {
  String path, root, text, default_target, build_dir, build_root, Map seen;
  ProjectDependency dependencies;
  Map dependency_seen;
  int declared, dependency_declared;
  SourceView sources;
  ProjectTarget targets;
  CliRequest command, ProjectTarget selected;
  ProjectBuild head;
  ProjectBuild tail;
} *Project;

module {
  "manifest.x",
  "planning.x",
  "sources.x",
}
