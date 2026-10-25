/*  strings.x -- interpolated text parsing and decoding */

static macro Stmt $fail.literals_string_segment(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected string segment",
    $site, NULL);

/* strings

   `%"..."` reads text segments and `$` insertions in source order. A text
   segment drops its line continuations, turns CR and CRLF into LF, and
   decodes escapes and `$$`. */

/** Parses a percent `String` literal and returns its typed expression after
    the closing quote. Static segments enter the compiler cache unless
    `runtime_literals` is set; interpolated segments remain source ordered.
*/
List Compiler.parse_string_literal(Compiler c) {
  c.expect(<"%\"">);
  if (c.test(<"\"">)) return %(expr ("String") (0));
  List segments = _parse_string_segments(c);
  c.expect(<"\"">);
  if (segments.match(%((cache *))))
    return %(expr ("String") $(segments.car()));
  return %(expr ("String") $(source_string_content(segments)));
}

static List _parse_string_segments(Compiler c) {
  Array segments = [];
  while (c.peek(0) != <"\"">) segments.push(_parse_string_segment(c));
  return segments.list_free();
}

static List _parse_string_segment(Compiler c) {
  switch (c.peek(0)) {
    case <segment>: return _parse_text_segment(c);
    case <$>:       return _parse_named_segment(c);
    case <"${">: case <"$(">: return _parse_grouped_segment(c);
    default:
      $fail.literals_string_segment(c, c.token);
  }
}

static List _parse_text_segment(Compiler c) {
  String text = _decode_segment(c.token.text);
  if (c.runtime_literals) {
    c.next();
    return %(segexp (expr ("String") (literal ("String") $text)));
  }
  List cached =
    c.cache(%(string (expr ("String") (literal ("String") $text))));
  c.next();
  return cached;
}

static List _parse_named_segment(Compiler c) {
  List expr = _parse_named_reference(c, <$>);
  expr = c.convert_segment_to_string(expr);
  return %(segvar $expr);
}

static List _parse_grouped_segment(Compiler c) {
  Symbol close = c.peek(0) == <"$("> ? <)> : <"}">;
  c.next();
  List expr = c.parse_expression();
  c.check_explicit_converter(expr, %("String"), 1);
  expr = c.convert_segment_to_string(expr);
  c.expect(close);
  return %(segexp $expr);
}

static String _decode_segment(String raw) {
  if (!raw) return "";
  raw = _normalize_newlines(raw);
  if (!("$$" in raw)) return raw.unescape();
  int n = raw.len(), dst = 0;
  char *buf = xmalloc(n + 1);
  for (int i = 0; i < n; i++) {
    char ch = raw[i];
    buf[dst++] = ch;
    if (ch == '\\' && i + 1 < n) buf[dst++] = raw[++i];
    else if (ch == '$' && i + 1 < n && raw[i + 1] == '$') i++;
  }
  buf[dst] = '\0';
  String text = String.new_len(buf, dst);
  xfree(buf);
  return text.unescape();
}

/* Text with no line continuation and no CR returns unchanged. */
static String _normalize_newlines(String raw) {
  int n = raw.len(), char *buf = xmalloc(n + 1);
  int dst = 0, changed = 0, i = 0;
  while (i < n) {
    char ch = raw[i];
    int skip = ch == '\\' ? _continuation(raw, i, n) : 0;
    if (skip) {
      changed = 1;
      i += skip;
    }
    else if (ch == '\r') {
      changed = 1;
      buf[dst++] = '\n';
      i++;
      if (i < n && raw[i] == '\n') i++;
    }
    else {
      buf[dst++] = ch;
      i++;
    }
  }
  String normalized = changed ? String.new_len(buf, dst) : raw;
  xfree(buf);
  return normalized;
}

/* The length of the line continuation at the backslash at `i`: 2 before
   LF, 3 before CRLF, and 0 otherwise. */
static int _continuation(String raw, int i, int n) {
  if (i + 1 >= n) return 0;
  if (raw[i + 1] == '\n') return 2;
  return raw[i + 1] == '\r' && i + 2 < n && raw[i + 2] == '\n' ? 3 : 0;
}
