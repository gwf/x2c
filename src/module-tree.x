/*  module-tree.x -- explicit source membership and module ancestry

    Copyright (c) 2026 Gary William Flake

    Companion directories locate possible entry files. Only a module block
    enrolls a source; an unlisted file remains an ordinary translation unit.
*/

#pragma once
#include "compiler.x"
#include "sourceview.x"
#include "utils.x"

typedef struct ModuleEntry {
  String path, prefix, preamble;
  List members;
  int block_start, block_end;
} *ModuleEntry;

typedef struct ModuleTree {
  Compiler compiler;
  Map entries, owners;
} *ModuleTree;

ModuleTree ModuleTree.new(Compiler c) {
  ModuleTree tree = Scope.malloc(sizeof(struct ModuleTree));
  *tree = (struct ModuleTree) {
    .compiler = c, .entries = {}, .owners = {}};
  return tree;
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

static int ModuleScan.member(ModuleScan &scan, Token token) {
  String spelling = String.new_len(token.text + 1, token.len - 2).unescape();
  String path = Path.absolute(Path.join(scan.directory, spelling));
  if (!path.startswith(scan.companion + "/")) {
    scan.tree._report(scan.entry.path,
      %"module member '$spelling' escapes its companion directory");
    return 0;
  }
  if (!is_source_file(path) || !scan.tree.compiler.sources.exists(path)) {
    scan.tree._report(scan.entry.path,
      %"module member '$spelling' is not a readable x2c source");
    return 0;
  }
  if (path in scan.seen) {
    scan.tree._report(scan.entry.path,
      %"module member '$spelling' is listed more than once");
    return 0;
  }
  scan.seen[path] = 1;
  scan.members.push(path);
  return 1;
}

static Token ModuleScan.block(ModuleScan &scan, Token open) {
  Token token = Token.skip_trivia(open + 1);
  while (token.type != <"}">) {
    if (token.type != <lit-char*>) {
      scan.tree._report(scan.entry.path,
        "module block requires comma-separated string paths");
      return NULL;
    }
    if (!scan.member(token)) return NULL;
    token = Token.skip_trivia(token + 1);
    if (token.type == <"}">) break;
    if (token.type != <",">) {
      scan.tree._report(scan.entry.path,
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
      .path = path, .prefix =
        %"_x2c_mod_${filename_hash(home_portable_path(path))}_",
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
ModuleEntry ModuleTree.entry(ModuleTree tree, String canonical_path) {
  String path = Path.absolute(canonical_path);
  Var cached;
  if (tree.entries.try_get(path, cached)) return cached.pointer();
  ModuleEntry entry = tree._scan(path);
  tree.entries[path] = Var.new(<p48>, entry);
  if (entry) tree.owners[path] = path;
  return entry;
}

// ownership

/* A path can be named by more than one ancestor entry. Discovery examines
   all candidates before retaining its owner, rather than taking the first. */
static String ModuleTree._parent(ModuleTree tree, String path) {
  String parent = NULL;
  for (String dir = Path.dirname(path); dir != "/";
       dir = Path.dirname(dir)) {
    ModuleEntry entry = tree.entry(dir + ".x");
    if (!entry || !entry.members.contains(path)) continue;
    if (parent && parent != entry.path) {
      tree._report(path, %"source belongs to both '$parent' and '${entry.path}'");
      return NULL;
    }
    parent = entry.path;
  }
  return parent;
}

/** Returns the enclosing entry only for an explicitly enrolled member.
    An entry owns itself; its enrollment in a parent is recorded separately.
*/
String ModuleTree.owner(ModuleTree tree, String path) {
  path = Path.absolute(path);
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
  Array entries = [];
  String owner = tree.owner(path);
  while (owner) {
    entries.push(owner);
    (void) tree.owner(owner);
    Var parent = tree.owners[%(parent $owner)];
    owner = parent is <string> ? parent.string() : NULL;
  }
  return entries;
}
