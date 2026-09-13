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

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "buffer.x"

static String _stem(String input) {
  const char *base = strrchr(input, '/');
  base = base ? base + 1 : input;
  return String.new_len(base, strlen(base) - 2);
}

/** Parses prerequisite words after the first literal colon in `text`.
    Backslash escapes and doubled dollars are decoded in that region. A
    backslash-newline continues the rule; an ordinary newline ends it before
    any phony rules. A word immediately before that newline is currently
    returned twice. This accepts internally generated rules with colon-free
    targets rather than general Make syntax. A NULL input or no parsed
    prerequisites returns NULL. Returned cells and path `String`s follow the
    current canonical `List` and `String` pool lifetimes.
*/
List translation_depfile_parse(String text) {
  if (!text) return NULL;
  Array paths = %[], Buffer word = Buffer.new(0), int prerequisites = 0;
  for (const char *ch = text; *ch; ch++) {
    if (!prerequisites) {
      if (*ch == ':') prerequisites = 1;
      continue;
    }
    if (*ch == '\\' && ch[1]) {
      ch++;
      if (*ch == '\n') continue;
      word.write_char(*ch);
      continue;
    }
    if (*ch == '$' && ch[1] == '$') {
      word.write_char('$');
      ch++;
      continue;
    }
    if (*ch == '\n') {
      if (word.len()) paths.push(word.str());
      break;
    }
    if (*ch == ' ' || *ch == '\t' || *ch == '\r') {
      if (word.len()) {
        paths.push(word.str());
        word.clear();
      }
      continue;
    }
    word.write_char(*ch);
  }
  if (word.len()) paths.push(word.str());
  word.free();
  List result = paths.list_free();
  return result;
}

/* Backslash-escape space, tab, '#', ':', and backslash as Make word bytes.
   Make expands a single dollar before matching dependencies, so dollars are
   doubled separately. */
static int _write_word(File output, String word) {
  if (!word) return output.puts("\\ ");
  foreach (char ch, word) {
    if (ch == '$') {
      if (output.puts("$$") == EOF) return 0;
      continue;
    }
    if (ch == ' ' || ch == '\t' || ch == '#' || ch == ':' || ch == '\\')
      if (output.putc('\\') == EOF) return 0;
    if (output.putc(ch) == EOF) return 0;
  }
  return 1;
}

static void _add(Array paths, String path) {
  if (path && !paths.contains(path)) paths.push(path);
}

static Array _prerequisites(
  CliRequest request, Compiler compiler, String input) {
  /* Collection and cached replay populate a Map with no publication order.
     Deduplicate and sort paths so both routes write the same depfile. Symbol
     artifacts are dependencies only when translation reads them. */
  Array paths = %[];
  if (compiler.deps.len())
    foreach (Var (path, content_hash), compiler.deps) _add(paths, path);
  else _add(paths, input);
  if (!request.no_cpp && !request.live_symbols) {
    String root = x2c_get_root();
    _add(paths, %"$root/etc/symbols.xlisp");
    if (header_symbols_active())
      _add(paths, %"$root/etc/header-symbols.xlisp");
  }
  paths.sort();
  return paths;
}

static int _write_targets(
  File output, CliRequest request, String output_dir, String stem) {
  if (request.dep_target) return _write_word(output, request.dep_target);
  String base = %"${output_dir.rstrip(%"/")}/$stem";
  if (!_write_word(output, %"$base.c")) return 0;
  if (output.putc(' ') == EOF) return 0;
  return _write_word(output, %"$base.h");
}

static int _write_contents(
  File output, CliRequest request, Compiler compiler, String input,
  String output_dir, String stem) {
  Array paths = _prerequisites(request, compiler, input);
  char primary_buffer[PATH_MAX];
  String primary = realpath(input, primary_buffer) ?
                   %"$primary_buffer" : input;
  int ok = _write_targets(output, request, output_dir, stem);
  if (ok && output.putc(':') == EOF) ok = 0;
  foreach (Var value, paths) {
    if (!ok || output.putc(' ') == EOF) {
      ok = 0;
      break;
    }
    if (!_write_word(output, value)) {
      ok = 0;
      break;
    }
  }
  if (ok && output.putc('\n') == EOF) ok = 0;
  /* Keep the dependency rule first. `translation_depfile_parse` stops at this
     newline so build fingerprints never treat following phony targets as
     prerequisites. */
  if (ok && !request.no_phony_deps) {
    foreach (Var value, paths) {
      String path = value;
      if (path == primary) continue;
      if (!_write_word(output, path) || output.puts(":\n") == EOF) {
        ok = 0;
        break;
      }
    }
  }
  paths.free();
  return ok && !output.error();
}

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
  String stem = _stem(input);
  String path = request.dep_file ? request.dep_file :
                %"${output_dir.rstrip(%"/")}/$stem.d";
  String temporary = %"$path.tmp.%ld".printf((long) getpid());
  File output = fopen(temporary, "w");
  if (!output) {
    fprintf(stderr, "x2c: error: cannot open dependency file: %s\n", path);
    fprintf(stderr, "note: %s\n", strerror(errno));
    return 0;
  }
  int ok = _write_contents(
    output, request, compiler, input, output_dir, stem);
  int close_error = output.close();
  if (!ok || close_error || rename(temporary, path)) {
    int error = errno;
    unlink(temporary);
    fprintf(stderr, "x2c: error: cannot write dependency file: %s\n", path);
    fprintf(stderr, "note: %s\n", strerror(error));
    return 0;
  }
  return 1;
}
