/*  format.x -- code formatting helpers for the x2c compiler

    Copyright (c) 2025 Gary William Flake

    Converts emitted token `List`s to pretty or compact C text without changing
    token order. Parenthesis depth suppresses statement breaks within
    expressions, and preprocessor tokens normalize escaped quotes before
    `Buffer` materializes the final `String`.
*/

#pragma once
#include "compiler.x"

#pragma private

// whitespace rules

static int _is_prefix_punct(char ch) =>
  ch == '.' || ch == '[' || ch == '(' || ch == '{';

static int _is_suffix_punct(char ch) =>
  ch == '(' || ch == '.' || ch == '[' || ch == ']' || ch == ')' ||
         ch == ';' || ch == ',' || ch == '{' || ch == '}';

static int _need_space(String prev, String curr) {
  if (!prev || !curr) return 0;
  char p = prev[-1], c = curr[0];
  if (c == '\n' || p == '\n') return 0;
  if (_is_suffix_punct(c)) return 0;
  if (_is_prefix_punct(p)) return 0;
  return 1;
}

static String _normalized_token(String token) {
  if (token && token[0] == '#') return token.replace("\\\"", "\"");
  return token;
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
  while (buff.len() > 0 && buff.get(-1) == ' ') buff.unwrite(1);
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
  return _token_is(car(rest).str(), '}');
}

// pretty print formatting

/** Returns a canonical formatted C `String` for an emitted token `List`.
    Token order and `code` are unchanged. Braces indent by two spaces,
    semicolons break lines only outside parentheses, and preprocessor tokens
    occupy their own lines with escaped quotes normalized. An empty `List`
    returns the empty `String`. Emitted `src-at` markers carry existing
    compiler origin IDs; zero restores `output_file` at its physical line.

    Raises: `<size-limit>` or `<alloc-fail>` while materializing the result.
*/
char *Compiler.code_pretty_string(
  Compiler compiler, List code, String output_file) {
  Buffer buff = Buffer.new(0);
  int indent = 0, paren_depth = 0, directive_break = 0;
  int output_line = 1, scanned = 0, source_line = 0;
  String prev_token = NULL;

  for (List lst = code; lst; lst = cdr(lst)) {
    if (car(lst) == <src-at>) {
      lst = cdr(lst);
      List location = compiler.origin_location(car(lst).integer());
      while (buff.len() > 0 && buff.get(-1) == ' ') buff.unwrite(1);
      if (buff.len() > 0 && buff.get(-1) != '\n') _write_newline(buff);
      while (scanned < buff.len())
        if (buff.get(scanned++) == '\n') output_line++;
      String file = location ? location.assoc(<file>).str() : output_file;
      if (!file) file = %"<generated>";
      int line = location ? location.assoc(<line>).integer()
                          : output_line + 1;
      source_line = location ? line : 0;
      String escaped = file.escape().replace("$$", "$");
      buff.write(%"#line $line \"$escaped\"");
      _write_newline(buff);
      if (indent > 0) _write_indent(buff, indent);
      directive_break = 1;
      prev_token = NULL;
      continue;
    }
    String token = _normalized_token(car(lst).str());
    char last = token ? token[-1] : '\0';

    /* A directive writes its own newline. The emitter may follow it with a
       space token beginning with another newline; consume that byte so no
       blank line appears that the intended C does not have. */
    if (directive_break) {
      directive_break = 0;
      if (token && token[0] == '\n') {
        _write_token(buff, token + 1, source_line);
        prev_token = NULL;
        continue;
      }
    }

    if (_is_preprocessor(token)) {
      while (buff.len() > 0 && buff.get(-1) == ' ') buff.unwrite(1);
      if (buff.len() > 0 && buff.get(-1) != '\n') _write_newline(buff);
      _write_token(buff, token, 0);
      _write_newline(buff);
      if (indent > 0) _write_indent(buff, indent);
      directive_break = 1;
      prev_token = NULL;
      continue;
    }

    if (last == '(') paren_depth++;
    else if (last == ')') {
      paren_depth--;
      if (paren_depth < 0) paren_depth = 0;
    }

    if (_token_is(token, '}')) {
      if (indent >= 2) indent -= 2;
      if (buff.len() > 0 && buff.get(-1) != '\n')
        _write_mapped_newline(buff, source_line);
      if (indent > 0) _write_indent(buff, indent);
      prev_token = NULL;
    }
    else if (_need_space(prev_token, token)) buff.write(" ");

    _write_token(buff, token, source_line);

    if (_token_is(token, '{')) {
      indent += 2;
      _write_mapped_newline(buff, source_line);
      if (indent > 0) _write_indent(buff, indent);
      prev_token = NULL;
    }
    else if (last == ';') {
      if (paren_depth == 0) {
        _write_mapped_newline(buff, source_line);
        if (!_next_is_closing_brace(cdr(lst)) && indent > 0)
          _write_indent(buff, indent);
        prev_token = NULL;
      }
      else {
        buff.write(" ");
        prev_token = token;
      }
    }
    else if (_token_is(token, '}')) {
      _write_mapped_newline(buff, source_line);
      if (indent > 0) _write_indent(buff, indent);
      prev_token = NULL;
    }
    else prev_token = token;
  }

  char *result = buff.str_free();
  return result;
}
