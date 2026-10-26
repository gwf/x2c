/*  sources.x -- compile-time SDK sources

    Copyright (c) 2026 Gary William Flake.
*/

static macro Stmt $fail.meta_sdk_source_capture(Expr $value) =>
  MetaContext.reject(
    "Code.source_text requires complete captured syntax",
    active.has_bindings ? NULL : %("value: $($value.repr())"));

static macro Stmt $fail.meta_sdk_embed_path_empty() =>
  MetaContext.reject("x2c_embed_text requires a non-empty path", NULL);

static macro Stmt $fail.meta_sdk_embed_literal(Expr $requested) =>
  _reject_value(
    "x2c_embed_text requires a String or captured String literal",
    $requested);

static macro Stmt $fail.meta_sdk_embed_read(Expr $c, Expr $path) =>
  _embed_reject($c, "cannot read embedded text", $path);

static macro Stmt $fail.meta_sdk_embed_nul(Expr $c, Expr $path) =>
  _embed_reject($c, "embedded text contains an embedded NUL", $path);

static macro Stmt $fail.meta_sdk_embed_size(Expr $c, Expr $path) =>
  _embed_reject($c, "embedded text exceeds the String size limit", $path);

static macro Stmt $fail.meta_sdk_embed_file(Expr $c, Expr $path) =>
  _embed_reject($c, "embedded text is not a regular file", $path);

static macro Stmt $fail.meta_sdk_embed_open(Expr $c, Expr $path) =>
  _embed_reject($c, "cannot open embedded text", $path);

static macro Expression $note.meta_sdk_path_notes(Expr $c, Expr $path) =>
  %("path: $($c.display_path($path))");

// source and literals

/** Answers `Code.source_text`, declared in `lib/meta.x`. */
String Code.source_text(Var value) {
  match (value) case %((text ?(String text)) (file ?) (syntax ?)): return text;
  _require_expansion("Code.source_text");
  Var stored = void;
  if (!active.captures ||
      !active.captures.try_get(((ulong) value.u64), stored))
    $fail.meta_sdk_source_capture(value);
  List source = stored;
  int begin = source.caddr(), end = source.last();
  return String.new_len(active.expander.text + begin, end - begin);
}

/** Answers `x2c_embed_text`, declared in `lib/meta.x`. */
String x2c_embed_text(Var requested) {
  _require_expansion("x2c_embed_text");
  Compiler c = active.expander;
  String source_file = active.definition_file, requested_path = NULL;
  if (requested is <string>) requested_path = requested;
  else requested_path = _embed_literal(requested, source_file);
  if (!requested_path.len())
    $fail.meta_sdk_embed_path_empty();
  String path = _embed_path(c, source_file, requested_path);
  String text = c.sources ? _embed_source(c, path) : _embed_file(c, path);
  c.deps.merge_translation_dependency(path, "%08x".printf(text.hash()));
  return text;
}

static String _embed_path(
  Compiler c, String source_file, String requested) {
  if (requested[0] == '/') return c.canonical_path(requested);
  String base = Path.dirname(c.source_path(source_file));
  return c.canonical_path(%"$base/$requested");
}

static String _embed_literal(Var requested, String &source_file) {
  Var stored = void, syntax = requested;
  match (requested)
    case %((text ?) (file ?(String file)) (syntax ?carried)): {
      syntax = carried;
      stored = %(source $file);
    }
  if (stored is void && active.captures)
    active.captures.try_get(((ulong) requested.u64), stored);
  String requested_path = NULL;
  if (stored is void || !_literal_string(syntax, requested_path))
    $fail.meta_sdk_embed_literal(requested);
  List source = stored;
  source_file = source.cadr();
  return requested_path;
}

static String _embed_source(Compiler c, String path) {
  String text;
  if (!c.read_source(path, text))
    $fail.meta_sdk_embed_read(c, path);
  return text;
}

static String _embed_file(Compiler c, String path) {
  File file = _open_embed_file(c, path);
  String text = NULL;
  try text = file.string_close();
  catch %(io-fail *): $fail.meta_sdk_embed_read(c, path);
  catch %(bad-arg *):
    $fail.meta_sdk_embed_nul(c, path);
  catch %(size-limit *):
    $fail.meta_sdk_embed_size(c, path);
  return text;
}

static File _open_embed_file(Compiler c, String path) {
  struct stat info;
  if (!stat(path, &info) && !S_ISREG(info.st_mode))
    $fail.meta_sdk_embed_file(c, path);
  File file = NULL;
  try file = path.open("r");
  catch %((!or not-found io-fail) *):
    $fail.meta_sdk_embed_open(c, path);
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    $fail.meta_sdk_embed_file(c, path);
  }
  if ((uintmax_t) info.st_size >= INT_MAX) {
    file.close();
    $fail.meta_sdk_embed_size(c, path);
  }
  return file;
}

static void _embed_reject(Compiler c, String message, String path) {
  MetaContext.reject(message, $note.meta_sdk_path_notes(c, path));
}

static int _literal_string(Var syntax, String &value) {
  match (syntax)
    case %(expr ? $($source_literal_content(%(? ?source)))): {
      if (source is not <string>) break;
      String text = source;
      int quoted = text.len() >= 2 && text[0] == '"' &&
        text[text.len() - 1] == '"';
      int percent_quoted = text.len() >= 3 && text[0] == '%' &&
        text[1] == '"' && text[text.len() - 1] == '"';
      if (quoted || percent_quoted) {
        value = text.parse();
        return 1;
      }
    }
  return 0;
}

/** Returns what a `meta` parameter declared `Source` receives for the
    captured syntax `value`: `((text T) (file F) (syntax value))`, where `T`
    is the text the developer wrote and `F` the file it is in.
*/
List MetaContext.source_description(Var value) {
  String text = Code.source_text(value);
  List source = active.captures[((ulong) value.u64)];
  return %((text $text) (file $(source.cadr())) (syntax $value));
}
