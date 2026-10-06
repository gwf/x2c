/*  format.x -- code formatting helpers for the x2c compiler

    Copyright (c) 2025 Gary William Flake

    Converts emitted token `List`s to pretty or compact C text without changing
    token order. Parenthesis depth suppresses statement breaks within
    expressions, and `Buffer` materializes the final `String`.
*/

#pragma once
#include "compiler.x"

#pragma private

// pretty print formatting

/* State for one formatting pass. `scanned` tracks the last byte counted in
   `output_line`; source markers need that physical line after prior writes. */
typedef struct Pretty {
  Compiler c;
  Buffer buff;
  String output_file, prev_token;
  int indent, paren_depth, directive_break;
  int output_line, scanned, source_line;
} Pretty;

/** Returns a canonical formatted C `String` for an emitted token `List`.
    Token order and `code` are unchanged. Braces indent by two spaces,
    semicolons break lines only outside parentheses, and preprocessor tokens
    occupy their own lines. An empty `List` returns the empty `String`.
    Emitted `src-at` markers carry existing compiler origin IDs; zero restores
    `output_file` at its physical line.

    Raises: `<size-limit>` or `<alloc-fail>` while materializing the result.
*/
char *Compiler.code_pretty_string(Compiler c, List code, String output_file) {
  Pretty p = {
    .c = c, .buff = Buffer.new(0), .output_file = output_file,
    .output_line = 1
  };
  for (List lst = code; lst; lst = lst.cdr()) {
    if (lst.car() == <src-at>) {
      lst = lst.cdr();
      p.source_marker(lst.car());
      continue;
    }
    String token = lst.car().str();
    /* A directive writes its own newline. The emitter may follow it with a
       space token beginning with another newline; consume that byte so no
       blank line appears that the intended C does not have. */
    if (p.directive_break) {
      p.directive_break = 0;
      if (token && token[0] == '\n') {
        _write_token(p.buff, token + 1, p.source_line);
        p.prev_token = NULL;
        continue;
      }
    }
    if (_is_preprocessor(token)) {
      p.directive(token);
      continue;
    }
    p.ordinary(token, lst.cdr());
  }
  return p.buff.str_free();
}

/* Emit a source position after flushing the preceding physical line. */
static void Pretty.source_marker(Pretty &p, Var value) {
  List location = p.c.origin_location(value);
  while (p.buff.len() > 0 && p.buff[-1] == ' ') p.buff.unwrite(1);
  if (p.buff.len() > 0 && p.buff[-1] != '\n') _write_newline(p.buff);
  while (p.scanned < p.buff.len())
    if (p.buff[p.scanned++] == '\n') p.output_line++;
  String file = location ? location.assoc(<file>) : p.output_file;
  if (!file) file = "<generated>";
  int line = location ? location.assoc(<line>) : p.output_line + 1;
  p.source_line = location ? line : 0;
  String escaped = file.escape().replace("$$", "$");
  p.buff.write(%"#line $line \"$escaped\"");
  _write_newline(p.buff);
  if (p.indent > 0) _write_indent(p.buff, p.indent);
  p.directive_break = 1;
  p.prev_token = NULL;
}

/* A preprocessor token occupies its own line. */
static void Pretty.directive(Pretty &p, String token) {
  while (p.buff.len() > 0 && p.buff[-1] == ' ') p.buff.unwrite(1);
  if (p.buff.len() > 0 && p.buff[-1] != '\n') _write_newline(p.buff);
  _write_token(p.buff, token, 0);
  _write_newline(p.buff);
  if (p.indent > 0) _write_indent(p.buff, p.indent);
  p.directive_break = 1;
  p.prev_token = NULL;
}

/* Write one ordinary token between its leading and trailing layout. */
static void Pretty.ordinary(Pretty &p, String token, List rest) {
  char last = token ? token[-1] : '\0';
  if (last == '(') p.paren_depth++;
  else if (last == ')') {
    p.paren_depth--;
    if (p.paren_depth < 0) p.paren_depth = 0;
  }
  p.before(token);
  _write_token(p.buff, token, p.source_line);
  p.after(token, last, rest);
}

static void Pretty.before(Pretty &p, String token) {
  if (_token_is(token, '}')) {
    if (p.indent >= 2) p.indent -= 2;
    if (p.buff.len() > 0 && p.buff[-1] != '\n')
      _write_mapped_newline(p.buff, p.source_line);
    if (p.indent > 0) _write_indent(p.buff, p.indent);
    p.prev_token = NULL;
  }
  else if (_need_space(p.prev_token, token)) p.buff.write(" ");
}

static void Pretty.after(Pretty &p, String token, char last, List rest) {
  if (_token_is(token, '{')) {
    p.indent += 2;
    _write_mapped_newline(p.buff, p.source_line);
    if (p.indent > 0) _write_indent(p.buff, p.indent);
    p.prev_token = NULL;
  }
  else if (last == ';') {
    if (p.paren_depth == 0) {
      _write_mapped_newline(p.buff, p.source_line);
      if (!_next_is_closing_brace(rest) && p.indent > 0)
        _write_indent(p.buff, p.indent);
      p.prev_token = NULL;
    }
    else {
      p.buff.write(" ");
      p.prev_token = token;
    }
  }
  else if (_token_is(token, '}')) {
    _write_mapped_newline(p.buff, p.source_line);
    if (p.indent > 0) _write_indent(p.buff, p.indent);
    p.prev_token = NULL;
  }
  else p.prev_token = token;
}

// whitespace rules

static int _is_prefix_punct(char ch) =>
  ch == '.' || ch == '[' || ch == '(' || ch == '{';

static int _is_suffix_punct(char ch) =>
  ch == '(' || ch == '.' || ch == '[' || ch == ']' || ch == ')' ||
  ch == ';' || ch == ',' || ch == '{' || ch == '}';

static int _need_space(String prev, String curr) {
  if (!prev || !curr) return 0;
  char p = prev[-1], c = curr[0];
  if (c == '\n' || p == '\n' || c == ' ' || p == ' ' ||
      c == '\t' || p == '\t') return 0;
  if (_is_suffix_punct(c)) return 0;
  if (_is_prefix_punct(p)) return 0;
  return 1;
}

static int _token_is(String token, char ch) =>
  token && token.len() == 1 && token[0] == ch;

static int _is_preprocessor(String token) => token && token[0] == '#';

static void _write_indent(Buffer buff, int indent) {
  static const char spaces[] =
    "                                                                ";
  while (indent > 0) {
    int chunk = indent;
    if (chunk >= (int) sizeof(spaces)) chunk = sizeof(spaces) - 1;
    buff.write_len(spaces, chunk);
    indent -= chunk;
  }
}

static void _write_newline(Buffer buff) {
  while (buff.len() > 0 && buff[-1] == ' ') buff.unwrite(1);
  buff.newline();
}

static void _write_mapped_newline(Buffer buff, int source_line) {
  _write_newline(buff);
  if (source_line) buff.write(%"#line $source_line\n");
}

static void _write_token(Buffer buff, String token, int source_line) {
  const char *start = token;
  while (start && *start) {
    const char *newline = strchr(start, '\n');
    if (!newline) {
      buff.write(start);
      return;
    }
    buff.write_len(start, newline - start);
    _write_mapped_newline(buff, source_line);
    start = newline + 1;
  }
}

static int _next_is_closing_brace(List rest) {
  if (!rest) return 0;
  return _token_is(rest.car().str(), '}');
}
