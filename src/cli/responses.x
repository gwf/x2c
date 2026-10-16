/*  responses.x -- response-file expansion and tokenization

    Copyright (c) 2026 Gary William Flake.
*/

/** Reads initial arguments. Script options defer response-file expansion
    until parsing, so program arguments remain literal. The caller owns
    the returned Array. */
Array CliRequest.read_arguments(int argc, char **argv) {
  Array args = [];
  int script = argc > 1 && !strcmp(argv[1], "script");
  for (int i = 1; i < argc; i++) {
    if (script) args.push(String.new(argv[i]));
    else _expand_argument(args, String.new(argv[i]), NULL);
  }
  return args;
}

/** Copies the driver's already-read vector, or returns NULL for direct
    invocation. The caller owns the Array; no word is expanded again. */
Array CliRequest.command_arguments(int argc, char **argv) {
  if (argc < 2 || strcmp(argv[1], "--driver-arguments")) return NULL;
  Array arguments = [];
  for (int i = 2; i < argc; i++) arguments.push(String.new(argv[i]));
  return arguments;
}

// response files

/* `@file` expands to the file's words, recursively, and `@@word` is the
   literal `@word`. `stack` holds the absolute paths being expanded, so a
   file that includes itself, directly or not, is an error. */
module void _expand_argument(Array out, String arg, List stack) {
  if (!arg || arg[0] != '@') {
    out.push(arg);
    return;
  }
  if (arg[1] == '@') {
    out.push(arg[1:]);
    return;
  }
  if (arg.len() == 1)
    Diagnostics.driver_error("empty response-file reference '@'");
  String path = arg[1:], identity = Path.absolute(path);
  if (identity in stack)
    _fail(%"recursive response-file inclusion: $path", NULL);
  List nested = cons(identity, stack);
  foreach (String word, _response_arguments(path))
    _expand_argument(out, word, nested);
}

/* Reads response-file tokens with ordinary quoting and UTF-8 checks.
   Returns canonical Strings without expanding `@` references. Paths and
   arguments retain the producing pool lifetime. */
module List _response_arguments(String path) {
  size_t length = 0, char *text = _read_response_file(path, length);
  Array words = _response_words(path, text, length);
  Scope.free(text);
  return words.list_free();
}

/* The whole file, which must be UTF-8 without a NUL byte. */
static char *_read_response_file(String path, size_t &length) {
  FILE *file = fopen(path, "rb");
  if (!file) _response_error(path, 1, strerror(errno));
  long end = _response_size(file, path);
  char *text = Scope.malloc((size_t) end + 1);
  size_t got = fread(text, 1, (size_t) end, file), int failed = ferror(file);
  fclose(file);
  if (failed || got != (size_t) end)
    _response_error(path, 1, "could not read complete file");
  text[got] = 0;
  if (memchr(text, 0, got)) _response_error(path, 1, "embedded NUL byte");
  if (!_valid_utf8((unsigned char *) text))
    _response_error(path, 1, "input is not valid UTF-8");
  length = got;
  return text;
}

/* The size of the open file, with its position back at the start. */
static long _response_size(FILE *file, String path) {
  long end = -1;
  if (!fseek(file, 0, SEEK_END)) end = ftell(file);
  if (end < 0 || fseek(file, 0, SEEK_SET)) {
    int error = errno;
    fclose(file);
    _response_error(path, 1, strerror(error));
  }
  return end;
}

/* Shortest forms of scalar values only: no overlong sequence, surrogate, or
   code point above U+10FFFF. `text` is NUL-terminated and has no other NUL. */
static int _valid_utf8(const unsigned char *text) {
  while (*text) {
    int length = scan_utf8_length(text);
    if (length < 0) return 0;
    text += length;
  }
  return 1;
}

/* Response-file words. Whitespace separates words; quotes and a backslash
   keep what they cover, newlines included; and `#` as the first nonspace
   character of a line starts a comment. `blank` holds until a line's first
   nonspace character, and `started` marks a word begun, perhaps by empty
   quotes. */
static typedef struct Words {
  Array out, String path, Buffer word;
  int line, blank, started, quote, escaped, comment;
} Words;

static Array _response_words(String path, const char *text, size_t length) {
  Words w = {
    .out = [], .path = path, .word = Buffer.new(0), .line = 1, .blank = 1};
  for (size_t i = 0; i < length; i++) _scan(w, (unsigned char) text[i]);
  _finish_words(w);
  w.word.free();
  return w.out;
}

/* Inside a comment only a newline counts. A backslash escapes the next
   character, in quotes or out. */
static void _scan(Words &w, int c) {
  if (w.comment) {
    if (c == '\n') _newline(w);
  }
  else if (w.escaped) {
    w.escaped = 0;
    _put(w, c);
  }
  else if (c == '\\') {
    w.escaped = 1;
    w.blank = 0;
  }
  else if (w.quote) {
    if (c == w.quote) w.quote = 0;
    else _put(w, c);
  }
  else _bare(w, c);
}

/* Outside quotes, a quote opens, `#` on a blank line starts a comment, and
   whitespace ends a word. */
static void _bare(Words &w, int c) {
  if (c == '\'' || c == '"') {
    w.quote = c;
    w.started = 1;
    w.blank = 0;
  }
  else if (w.blank && c == '#') w.comment = 1;
  else if (isspace(c)) {
    _flush(w);
    if (c == '\n') _newline(w);
  }
  else {
    w.blank = 0;
    _put(w, c);
  }
}

/* Quoted and escaped newlines stay in the word and still count as lines. */
static void _put(Words &w, int c) {
  w.word.write_char(c);
  w.started = 1;
  if (c == '\n') w.line++;
}

static void _newline(Words &w) {
  w.comment = 0;
  w.blank = 1;
  w.line++;
}

static void _flush(Words &w) {
  if (!w.started) return;
  w.out.push(w.word.str());
  w.word.clear();
  w.started = 0;
}

/* The text may end in a comment, but not in quotes or after a backslash. */
static void _finish_words(Words &w) {
  if (w.comment) return;
  if (w.escaped) _response_error(w.path, w.line, "trailing backslash");
  if (w.quote) _response_error(w.path, w.line, "unterminated quote");
  _flush(w);
}

static void _response_error(String path, int line, const char *message) {
  fprintf(
    stderr, "x2c: error: response file '%s':%d: %s\n", path, line, message);
  exit(2);
}
