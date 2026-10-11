/*  module-tree.x -- explicit source membership and module ancestry

    Copyright (c) 2026 Gary William Flake

    Companion directories locate possible entry files. Only a module block
    enrolls a source; an unlisted file remains an ordinary translation unit.
*/

#pragma once
#include "compiler.x"
#include "sourceview.x"
#include "utils.x"

/** A module entry's source path, emitted prefix, prefix text, and members. */
typedef struct ModuleEntry {
  String path, prefix, preamble;
  List members, preamble_parts;
  int block_start, block_end;
} *ModuleEntry;

/** Request-owned module entries, ownership relationships, and search facts. */
typedef struct ModuleTree {
  Compiler compiler;
  Map entries, owners, dependencies;
} *ModuleTree;

/** Creates module discovery state using the compiler's source view. */
ModuleTree ModuleTree.new(Compiler c) {
  ModuleTree tree = Scope.malloc(sizeof(struct ModuleTree));
  *tree = (struct ModuleTree) {
    .compiler = c, .entries = {}, .owners = {}, .dependencies = {}};
  return tree;
}

/** Returns the generated support-header name for a module source. */
String Compiler.module_support_header(Compiler c, String path) =>
  %"_x2c_module_${filename_hash(c.module_tree.identity(c.canonical_path(path)))}.h";

/** Keeps module output guards independent of invocation path spelling. */
String Compiler.generated_unit_hash(Compiler c) =>
  filename_hash(
    c.module_owner ? c.module_tree.identity(c.canonical_path(c.filename)) +
      (c.native_fragment ? c.native_fragment : "") : c.filename);

/** Returns the relocatable identity of an enrolled source. Canonical paths
    still establish ownership. Identity collisions cannot share native names.
*/
String ModuleTree.identity(ModuleTree m, String spelling) {
  String path = absolute_path(spelling);
  Var cached;
  if (m.owners.try_get(%(identity $path), cached)) return cached;
  List ancestors = m.ancestors(path);
  String identity = home_portable_path(path), root = NULL;
  if (ancestors) {
    String entry = ancestors.last();
    root = Path.dirname(entry);
    String package = package_directory(m.compiler.package_source_dirs, path);
    if (!package)
      package = package_directory(m.compiler.package_dirs, path);
    if (package && package_source(package, path))
      identity = %"package:${Path.basename(package)}:${path[package.len() + 1:]}";
    else if (identity.startswith("/")) {
      String project = m.compiler.module_project_root;
      if (!project) project = m.project_root(path);
      if (project && path.startswith(project + "/")) {
        root = project;
        identity = %"project:${path[project.len() + 1:]}";
      }
      else identity = %"module:${path[root.len() + 1:]}";
    }
    String native_id = filename_hash(identity);
    String previous = m.owners[%(identity-owner $native_id)];
    if (previous && previous != path)
      m._report(
        path, %"module identity '$identity' collides with '$previous'; " +
        "use distinct entry names or a package/project namespace");
    m.owners[%(identity-owner $native_id)] = path;
  }
  m.owners[%(identity $path)] = identity;
  return identity;
}

static String ModuleTree.project_root(ModuleTree tree, String path) {
  Map searches = {};
  tree.owners[%(identity-searches $path)] = searches;
  for (String dir = Path.dirname(path); dir != "/"; dir = Path.dirname(dir)) {
    String candidate = Path.join(dir, "x2c.toml");
    int exists = tree.compiler.sources.exists(candidate);
    searches.merge_translation_dependency(
      candidate, exists ? (Var) 1 : (Var) "search:absent");
    if (exists) return dir;
  }
  return NULL;
}

/** Returns the native prefix using the same identity as support and init. */
String ModuleTree.prefix(ModuleTree tree, String path) {
  ModuleEntry entry = tree.entry(path);
  if (!entry.prefix)
    entry.prefix = %"_x2c_mod_${filename_hash(tree.identity(path))}_";
  return entry.prefix;
}

static void ModuleTree._report(
  ModuleTree tree, String path, String message) {
  tree.compiler.report_error(<parse>, message, NULL, %("module: $path"));
}

// metadata

static typedef struct ModuleScan {
  ModuleTree tree;
  ModuleEntry entry;
  String directory, companion;
  Map seen;
  Array members;
} ModuleScan;

static int ModuleScan.member(ModuleScan &m, Token token) {
  String spelling = String.new_len(token.text + 1, token.len - 2).unescape();
  String path = Path.absolute(Path.join(m.directory, spelling));
  if (!path.startswith(m.companion + "/")) {
    m.tree._report(
      m.entry.path,
      %"module member '$spelling' escapes its companion directory");
    return 0;
  }
  if (!is_source_file(path) || !m.tree.compiler.sources.exists(path)) {
    m.tree._report(
      m.entry.path,
      %"module member '$spelling' is not a readable x2c source");
    return 0;
  }
  if (path in m.seen) {
    m.tree._report(
      m.entry.path,
      %"module member '$spelling' is listed more than once");
    return 0;
  }
  m.seen[path] = 1;
  m.members.push(path);
  return 1;
}

static Token ModuleScan.block(ModuleScan &scan, Token open) {
  Token token = Token.skip_trivia(open + 1);
  while (token.type != <"}">) {
    if (token.type != <lit-char*>) {
      scan.tree._report(
        scan.entry.path,
        "module block requires comma-separated string paths");
      return NULL;
    }
    if (!scan.member(token)) return NULL;
    token = Token.skip_trivia(token + 1);
    if (token.type == <"}">) break;
    if (token.type != <",">) {
      scan.tree._report(
        scan.entry.path,
        "module block requires a comma between member paths");
      return NULL;
    }
    token = Token.skip_trivia(token + 1);
  }
  return token;
}

static ModuleEntry ModuleTree._scan(ModuleTree tree, String path) {
  String text;
  if (!tree.compiler.sources.read(path, text)) return NULL;
  Tokenizer tokenizer = Tokenizer.new(text, <x2c>);
  tokenizer.scan();
  ModuleEntry entry = NULL;
  for (Token token = Token.skip_trivia(tokenizer.tokens);
       token.type != <eof>; token = token.after_group()) {
    if (token.text != "module") continue;
    Token open = Token.skip_trivia(token + 1);
    if (open.type != <"{">) continue;
    if (entry) {
      tree._report(path, "source has more than one module block");
      return NULL;
    }
    entry = Scope.malloc(sizeof(struct ModuleEntry));
    *entry = (struct ModuleEntry) {
      .path = path,
      .preamble = text[:token.pos], .block_start = token.pos};
    ModuleScan scan = {
      .tree = tree, .entry = entry, .directory = Path.dirname(path),
      .companion = Path.absolute(
        Path.join(Path.dirname(path), Path.stem(path))),
      .seen = {}, .members = []};
    Token close = scan.block(open);
    if (!close) return NULL;
    entry.members = scan.members;
    entry.block_end = Token.skip_trivia(close + 1).pos;
    token = close;
  }
  return entry;
}

/** Reads an entry once. Non-entry files also retain their absent result. */
ModuleEntry ModuleTree.entry(ModuleTree m, String canonical_path) {
  Var cached;
  if (m.entries.try_get(canonical_path, cached)) return cached.pointer();
  String path = absolute_path(canonical_path);
  if (m.entries.try_get(path, cached)) return cached.pointer();
  m.dependencies.merge_translation_dependency(
    path,
    m.compiler.sources.exists(path) ? (Var) 1 : (Var) "search:absent");
  ModuleEntry entry = m._scan(path);
  m.entries[path] = Var.new(<p48>, entry);
  if (entry) m.owners[path] = path;
  return entry;
}

// ownership

/** The ownership search facts of this file, independent of prior walks. */
Map ModuleTree.ownership_dependencies(ModuleTree tree, String path) {
  path = absolute_path(path);
  Map dependencies = {};
  (void) tree.entry(path);
  dependencies.merge_translation_dependency(path, tree.dependencies[path]);
  for (String dir = Path.dirname(path); dir != "/";
       dir = Path.dirname(dir))
    foreach (String suffix, %(".x" ".xp")) {
      String candidate = dir + suffix;
      (void) tree.entry(candidate);
      dependencies.merge_translation_dependency(
        candidate,
        tree.dependencies[candidate]);
    }
  (void) tree.identity(path);
  Var identity_searches = tree.owners[%(identity-searches $path)];
  if (identity_searches is <map>)
    foreach (Var (candidate, hash), identity_searches.map())
      dependencies.merge_translation_dependency(candidate, hash);
  return dependencies;
}

/** Records an ownership query independently of its resolved search paths. */
List ModuleTree.ownership_query(ModuleTree tree, String path) {
  path = absolute_path(path);
  Array owners = [];
  foreach (String owner, tree.ancestors(path))
    owners.push(home_portable_path(owner));
  return %(ownership-search ${home_portable_path(path)}
    ${owners.list_free()} ${tree.identity(path)});
}

/* A path can be named by more than one ancestor entry. Discovery examines
   all candidates before retaining its owner, rather than taking the first. */
static String ModuleTree._parent(ModuleTree tree, String path) {
  String parent = NULL;
  for (String dir = Path.dirname(path); dir != "/";
       dir = Path.dirname(dir)) {
    foreach (String suffix, %(".x" ".xp")) {
      ModuleEntry entry = tree.entry(dir + suffix);
      if (!entry || !entry.members.contains(path)) continue;
      if (parent && parent != entry.path) {
        tree._report(path, %"source belongs to both '$parent' and '${entry.path}'");
        return NULL;
      }
      parent = entry.path;
    }
  }
  return parent;
}

/** Returns the enclosing entry only for an explicitly enrolled member.
    An entry owns itself; its enrollment in a parent is recorded separately.
*/
String ModuleTree.owner(ModuleTree tree, String path) {
  if (%(checked $path) in tree.owners) {
    Var owner = tree.owners[path];
    return owner is <string> ? owner.string() : NULL;
  }
  path = absolute_path(path);
  if (!(%(checked $path) in tree.owners)) {
    ModuleEntry entry = tree.entry(path);
    String parent = tree._parent(path);
    if (entry && parent) tree.owners[%(parent $path)] = parent;
    tree.owners[path] = entry ? path : parent;
    tree.owners[%(checked $path)] = 1;
  }
  Var owner = tree.owners[path];
  return owner is <string> ? owner.string() : NULL;
}

/** Lists the owning entry followed by its parent entries, nearest first. */
List ModuleTree.ancestors(ModuleTree tree, String path) {
  Var known;
  if (tree.owners.try_get(%(ancestors $path), known)) return known;
  Array entries = [];
  String owner = tree.owner(path);
  while (owner) {
    entries.push(owner);
    (void) tree.owner(owner);
    Var parent = tree.owners[%(parent $owner)];
    owner = parent is <string> ? parent.string() : NULL;
  }
  List ancestry = entries.list_free();
  tree.owners[%(ancestors $path)] = ancestry;
  return ancestry;
}

/** Expands source inputs into distinct enrolled units. An enrolled tree
    starts at its outer entry and follows explicit member order, even when
    the invocation names an implementation member first. */
List ModuleTree.units(ModuleTree tree, List inputs) {
  Array units = [];
  Map seen = {};
  foreach (String input, inputs) tree._enroll(input, units, seen);
  return units.list_free();
}

static void ModuleTree._enroll(
  ModuleTree tree, String path, Array units, Map seen) {
  String canonical = absolute_path(path);
  if (canonical in seen) return;
  if (is_source_file(canonical)) {
    List ancestry = tree.ancestors(canonical);
    if (ancestry) {
      String root = ancestry.reverse().car();
      if (root != canonical) {
        tree._enroll(root, units, seen);
        if (canonical in seen) return;
      }
    }
  }
  seen[canonical] = 1;
  units.push(path);
  if (!is_source_file(canonical)) return;
  if (tree.owner(canonical)) (void) tree.identity(canonical);
  ModuleEntry entry = tree.entry(canonical);
  if (!entry) return;
  foreach (String member, entry.members) {
    String owner = tree.owner(member);
    if (owner != canonical && owner != member)
      tree._report(
        member, "ancestor directly enrolls a nested implementation member");
    tree._enroll(member, units, seen);
  }
}
