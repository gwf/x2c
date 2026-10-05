/*  deps.x -- Make dependency output for x2c translation units

    Copyright (c) 2026 Gary William Flake.

    Translation collects the prerequisites. This module writes them in a
    stable Make spelling and publishes the file atomically.
*/

#pragma once
#include "cli.x"
#include "compiler.x"
#include "utils.x"

#pragma private
#include "collect.x"

#include <stdio.h>
#include <string.h>

#include "buffer.x"

/** Publishes the Make depfile for one completed translation.
    `compiler.deps` must reflect the translated `input`, and the selected
    depfile's parent directory must exist. Disabled dependency output and
    inspection requests return one without writing. Otherwise prerequisites
    are unique and sorted; the target is `request.dep_target` or the generated
    C and header pair, followed by optional phony rules. A process-specific
    sibling is written and closed before rename, so handled open, write, close,
    or rename failures preserve any existing depfile, report to stderr, and
    return zero. Cleanup attempts to unlink an opened sibling but does not
    report an unlink failure. Allocation failure transfers through ordinary
    runtime `Error` handling instead of returning zero.
*/
int translation_depfile_write(
  CliRequest request, Compiler compiler, String input, String output_dir) {
  if (request.no_deps || request.inspects()) return 1;
  String path = request.dep_file ? request.dep_file :
    %"${output_dir.rstrip("/")}/${Path.stem(input)}.d";
  long error = 0;
  try {
    file_publish(%($path ${_contents(request, compiler, input, output_dir)}));
    return 1;
  }
  catch %((!or not-found io-fail) *failure): error = failure.assoc(<"errno">);
  fprintf(
    stderr, "x2c: error: cannot write dependency file: %s\nnote: %s\n", path,
    strerror(error));
  return 0;
}

/* Collection and cached replay populate a Map with no publication order, so
   paths are sorted to write the same depfile from both routes. */
static String _contents(
  CliRequest request, Compiler compiler, String input, String output_dir) {
  Array paths = $auto([]), searches = $auto([]);
  foreach (Var (path, content_hash), compiler.deps)
    (content_hash is <string> && String.startswith(content_hash, "search:") ?
      searches : paths).push(path);
  if (!paths.len()) paths.push(input);
  paths.sort();
  Buffer out = $auto(Buffer.new(0));
  _write_targets(out, request, input, output_dir);
  out.write_char(':');
  foreach (String path, paths) {
    out.write_char(' ');
    _write_word(out, path);
  }
  out.write_char('\n');
  /* Keep the dependency rule first. `translation_depfile_parse` stops at this
     newline so build fingerprints never treat following phony targets as
     prerequisites. */
  if (!request.no_phony_deps) _write_phony(out, paths, Path.absolute(input));
  // Make sees files only; retained x2c builds also check include searches.
  if (searches.len()) {
    out.write("# x2c-search:");
    searches.sort();
    foreach (String path, searches) {
      out.write_char(' ');
      _write_word(out, path);
    }
    out.write_char('\n');
  }
  return out;
}

static void _write_targets(
  Buffer out, CliRequest request, String input, String output_dir) {
  String base = %"${output_dir.rstrip("/")}/${Path.stem(input)}";
  _write_word(out, request.dep_target ? request.dep_target : %"$base.c");
  if (request.dep_target) return;
  out.write_char(' ');
  _write_word(out, %"$base.h");
}

// Every prerequisite except the primary input gets an empty phony rule.
static void _write_phony(Buffer out, Array paths, String primary) {
  foreach (String path, paths)
    if (path != primary) {
      _write_word(out, path);
      out.write(":\n");
    }
}

/* Backslash-escape space, tab, '#', ':', and backslash as Make word bytes.
   Make expands a single dollar before matching dependencies, so dollars are
   doubled separately. */
static void _write_word(Buffer out, String word) {
  if (!word) out.write("\\ ");
  foreach (char ch, word) {
    if (ch == '$') out.write_char('$');
    else if (ch == ' ' || ch == '\t' || ch == '#' || ch == ':' || ch == '\\')
      out.write_char('\\');
    out.write_char(ch);
  }
}

/** Parses prerequisite words after the first unescaped colon in `text`.
    Backslash escapes and doubled dollars are decoded in that region. A
    backslash-newline continues the rule; an ordinary newline ends it before
    any phony rules. Escaped target colons remain part of their words.
    A NULL input or no parsed prerequisites returns NULL.
    Returned cells and path `String`s follow the current canonical `List` and
    `String` pool lifetimes.
*/
List translation_depfile_parse(String text) {
  const char *ch = text;
  while (ch && *ch && *ch != '\n') {
    if (*ch == '\\' && ch[1]) { ch += 2; continue; }
    if (*ch == ':') break;
    ch++;
  }
  if (!ch || *ch != ':') return NULL;
  Array paths = [], Buffer word = Buffer.new(0);
  // The word before the newline is pushed once, after the loop.
  for (ch++; *ch && *ch != '\n'; ch++) {
    if (*ch == '\\' && ch[1]) {
      ch++;
      if (*ch != '\n') word.write_char(*ch);
      continue;
    }
    if (*ch == '$' && ch[1] == '$') ch++;
    if (*ch == ' ' || *ch == '\t' || *ch == '\r') _push_word(paths, word);
    else word.write_char(*ch);
  }
  _push_word(paths, word);
  word.free();
  return paths.list_free();
}

static void _push_word(Array paths, Buffer word) {
  if (!word.len()) return;
  paths.push(word.str());
  word.clear();
}
