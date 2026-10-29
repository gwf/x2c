/*  splice.x -- source collection splice

    Copyright (c) 2026 Gary William Flake.
*/

// module blocks

/* Assembles one text from a module's files. `line` is the text line that
   the next byte written begins. `path` and `text` are the file being
   appended, and `prefix` is its directory relative to the entry's, or NULL
   for the entry. `file_prefix` begins the spellings of that file's statics,
   and `prefixes` maps each file prefix taken to the name of its file.
   `root` is the entry's resolved directory. `splicing` holds
   the resolved paths of the files being appended. */
static typedef struct Splice {
  Compiler c, Buffer out, Array markers, Map members, splicing, prefixes;
  int line;
  String path, text, prefix, file_prefix, root;
} Splice;

/** Returns the x2c source at `path`, whose own text is `text`, with its
    file-scope `module` block replaced by the text of each member it names,
    in order, or NULL when the text has no block. Member paths are relative
    to the file that names them, and their own blocks are spliced in turn.
    A member's quoted include of a file beside it is spelled from the
    entry's directory, so it names the same file there.
*/
ModuleSource Compiler.module_source(Compiler c, String path, String text) {
  Buffer out = auto Buffer.new(0);
  Splice s = {
    .c = c, .out = out, .markers = [], .members = {}, .splicing = {},
    .prefixes = {}, .line = 1,
    .root = Path.absolute(Path.dirname(path))};
  s.splicing[Path.absolute(path)] = 1;
  String own = _file_prefix(Path.stem(path));
  s.prefixes[own] = Path.basename(path);
  if (!_file(s, path, text, NULL, own)) return NULL;
  ModuleSource source = xcalloc(1, sizeof(struct ModuleSource));
  *source = (struct ModuleSource) {
    .text = s.out.str(), .own = text, .markers = s.markers,
    .members = s.members};
  return source;
}

// source collection splice

/* Appends a file with its block spliced and reports whether it had one.
   Each file's text is marked as its own, so its rows carry its file
   prefix. Diagnostics locate the block in this file. */
static int _file(
  Splice &s, String path, String text, String prefix, String file_prefix) {
  with (s.path = path,
        s.text = text,
        s.prefix = prefix,
        s.file_prefix = file_prefix,
        s.c.filename = path,
        s.c.text = text,
        s.c.line_markers = NULL) {
    _mark(s, 1, 0);
    Tokenizer tokens = NULL;
    Token block = _block(s, tokens), close = NULL;
    if (!block) {
      _own(s, 0, text.len(), 1);
      return 0;
    }
    List members = _members(s, block, close);
    Token before = _expansion_first(tokens, block);
    Token after = _expansion_end(tokens, close);
    int resume = after ? after.pos : close.pos + close.len;
    int line = after ? after.line : close.line;
    _own(s, 0, block.pos, 1);
    if (before) _expanded(s, before, block);
    _end_line(s);
    foreach (String spelling in members) _member(s, spelling, block);
    if (after) _expanded(s, close + 1, after);
    _mark(s, line, resume);
    _own(s, resume, text.len(), line);
    return 1;
  }
}

/* Appends a member relative to the file that names it. A file being
   spliced cannot be spliced again inside itself. */
static void _member(Splice &s, String spelling, Token site) {
  String dir = Path.dirname(s.path), text = NULL;
  String path = Path.join(dir, spelling);
  String resolved = Path.absolute(path);
  if (resolved in s.splicing)
    $fail.collect_module_cycle(s.c, site, spelling, resolved);
  if (!s.c.read_source(path, text))
    $fail.collect_module_read(s.c, site, path);
  s.members[_canonical_path(path)] = _content_hash(text);
  String prefix = s.prefix ? Path.join(s.prefix, spelling) : spelling;
  String relative = _relative_member(s.root, resolved);
  String own = _file_prefix(
    Path.join(Path.dirname(relative), Path.stem(relative)));
  if (own in s.prefixes)
    $fail.collect_module_prefix(s.c, site, spelling, s.prefixes[own]);
  s.prefixes[own] = spelling;
  s.splicing[resolved] = 1;
  _file(s, path, text, Path.dirname(prefix), own);
  s.splicing.del(resolved);
  _end_line(s);
}

/* The `module` that opens the file's file-scope block, or NULL. The word
   opens a block where `{` follows it and no word precedes it, so
   `struct module {` declares a tag. */
static Token _block(Splice &s, Tokenizer &tokenizer) {
  tokenizer = Tokenizer.new(s.text, <x2c>);
  tokenizer.layout = Path.is_layout_source(s.path);
  tokenizer.scan();
  Compiler scan = Compiler.new_shared(s.c);
  defer s.c.close_child(scan);
  scan.filename = s.path;
  scan.text = s.text;
  scan.tokenizer = tokenizer;
  scan.cpp = Cpp.isolated(scan.initial_macros(s.path));
  scan.preprocess_tokens();
  Token block = NULL, previous = NULL;
  int depth = 0;
  for (Token token = Token.skip_trivia(tokenizer.tokens);
       token.type != <eof>; token = Token.skip_trivia(token + 1)) {
    if (!depth && token.text == "module" &&
        Token.skip_trivia(token + 1).type == <"{"> &&
        !(previous && _is_word(previous.text))) {
      if (block) $fail.collect_module_second(s.c, token);
      block = token;
    }
    if (token.type == <"}">) depth--;
    else if (token.type.str().endswith("{")) depth++;
    previous = token;
  }
  return block;
}

static int _is_word(String text) =>
  isalnum((unsigned char) text[0]) || text[0] == '_';

/* Expansion tokens keep their invocation's diagnostic position. The next
   token after the recorded expansion resumes the original source after
   that whole invocation, including a function-like use's arguments. */
static List _expansion(Tokenizer tokenizer, Token token) {
  long index = token - (Token) tokenizer.tokens;
  foreach (List row in tokenizer.expansions)
    if (index >= row.car().integer() && index < row.cadr().integer())
      return row;
  return NULL;
}

static Token _expansion_first(Tokenizer tokenizer, Token token) {
  List row = _expansion(tokenizer, token);
  return row ? (Token) tokenizer.tokens + row.car().integer() : NULL;
}

static Token _expansion_end(Tokenizer tokenizer, Token token) {
  List row = _expansion(tokenizer, token);
  return row ? (Token) tokenizer.tokens + row.cadr().integer() : NULL;
}

/* Preserve other declarations emitted by the same macro as the module
   block. Separating tokens keeps neighboring operators from coalescing. */
static void _expanded(Splice &s, Token first, Token end) {
  if (first == end) return;
  _mark(s, first.line, first.pos);
  for (Token token = first; token < end; token++) {
    _write(s, token.text, (const char *) token.text + token.text.len());
    s.out.write_char(' ');
  }
  _end_line(s);
}

/* The member paths of the block `block` opens, whose closing brace becomes
   `close`. */
static List _members(Splice &s, Token block, Token &close) {
  Array members = [];
  Token token = Token.skip_trivia(Token.skip_trivia(block + 1) + 1);
  while (token.type != <"}">) {
    if (token.type != <"lit-char*"> || token.text[0] != '"')
      $fail.collect_module_block(s.c, token);
    members.push(token.text[1:token.len - 1].unescape());
    token = Token.skip_trivia(token + 1);
    if (token.type == <",">) token = Token.skip_trivia(token + 1);
    else if (token.type != <"}">) $fail.collect_module_block(s.c, token);
  }
  close = token;
  return members.list_free();
}

/* Spell a resolved member relative to the entry directory, including
   members outside it, without putting the checkout path in C names. */
static String _relative_member(String root, String path) {
  String base = root.endswith("/") ? root : %"$root/";
  int shared = 0;
  for (int i = 0; i < base.len() && i < path.len() && base[i] == path[i]; i++)
    if (base[i] == '/') shared = i + 1;
  Buffer out = auto Buffer.new(0);
  for (int i = shared; i < base.len(); i++)
    if (base[i] == '/') out.write("../");
  out.write(path[shared:]);
  return out;
}

/* The prefix of a file's statics: its path relative to the entry's
   directory, or the entry's stem, without the extension, with each
   character that cannot continue a C identifier made `_` and trailing `_`
   dropped, then `___`. The spelling starts with `f`, its length, and `_`.
   Dropping trailing underscores keeps `foo_` and `foo` on one prefix,
   so their statics cannot meet past the separator unreported. A package
   prefix ends in `__`, so a package entry's statics never share a spelling
   with the package's public names. A leading digit gets a leading `x`,
   since C reserves file-scope names that begin with `_`. */
static String _file_prefix(String path) {
  if (path.startswith("./")) path = path[2:];
  Buffer spelling = auto Buffer.new(0);
  if (isdigit((unsigned char) path[0])) spelling.write_char('x');
  foreach (char ch in path)
    spelling.write_char(isalnum((unsigned char) ch) ? ch : '_');
  String stem = spelling;
  int keep = stem.len();
  while (keep > 1 && stem[keep - 1] == '_') keep--;
  return %"f$(keep)_$(stem[:keep])___";
}

/* Appends the file's text from byte `start` to `end`, which begins its
   line `line`. A member's include of a file beside it moves under its
   prefix. */
static void _own(Splice &s, int start, int end, int line) {
  if (start == end) return;
  const char *run = s.text + start, *limit = s.text + end;
  if (s.prefix)
    for (const char *at = run; at < limit; line++) {
      const char *stop = memchr(at, '\n', limit - at);
      stop = stop ? stop + 1 : limit;
      String moved = _moved_include(s, at, stop);
      if (moved) {
        _write(s, run, at);
        _write(s, moved, (const char *) moved + moved.len());
        _mark(s, line + 1, stop - (const char *) s.text);
        run = stop;
      }
      at = stop;
    }
  _write(s, run, limit);
}

/* The line from `at` to `stop` with its quoted include of a file beside
   this one spelled under the prefix, or NULL for any other line. */
static String _moved_include(Splice &s, const char *at, const char *stop) {
  const char *hash = at + strspn(at, " \t");
  if (hash >= stop || *hash != '#') return NULL;
  int angle = 0;
  String target =
    Compiler.preproc_include_target(String.new_len(hash, stop - hash), angle);
  if (!target || angle || target.startswith("/") ||
      !s.c.sources.exists(%"$(Path.dirname(s.path))/$target")) return NULL;
  return String.new_len(at, stop - at).replace(
    %"\"$target\"", %"\"$(s.prefix)/$target\"");
}

/* From here on the text comes from this file, at its line `line` and byte
   `offset`, continuing that line's text before `offset`. */
static void _mark(Splice &s, int line, int offset) {
  int start = offset;
  while (start > 0 && s.text[start - 1] != '\n') start--;
  String before = s.text[start:offset];
  s.markers.push(
    $((int) s.out.len(), s.line, s.path, line, offset, before, s.file_prefix));
}

// Each file's text ends its last line before the next file's begins.
static void _end_line(Splice &s) {
  if (!s.out.len() || s.out[-1] == '\n') return;
  s.out.newline();
  s.line++;
}

static void _write(Splice &s, const char *start, const char *end) {
  s.out.write_len(start, end - start);
  for (const char *ch = start; ch < end; ch++) if (*ch == '\n') s.line++;
}
