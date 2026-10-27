/*  diagnostics.x -- compiler diagnostic storage and rendering

    Each report has one ordered entry. The store borrows its printer, while
    canonical entry values retain their producing-pool lifetimes.
*/

#pragma once
#include "common.x"
#include "compiler/compiler.x"

/** Collects diagnostic entries and optionally streams them.
    A value is valid after `Diagnostics.new`. The store and backing `Array` are
    `Scope`-owned; entry `List`s and immutable children retain the lifetime of
    their producing canonical-value pools. A borrowed `printer` must remain
    valid while it is installed.
*/
typedef struct Diagnostics {
  Array entries;    // Stored chronologically; entries() is a snapshot
  Map published;    // Each stored entry and its first position in entries
  Compiler printer; // Prints each published entry; NULL does not stream
  int limit;        // 0 disables limiting
  int count, limit_notified;
} *Diagnostics;

/** Records where `Diagnostics.hold` stopped streaming. */
typedef struct DiagnosticsHold {
  Compiler printer;
  int entries, count, limit_notified;
} DiagnosticsHold;

#include "type.x"

#include "json.x"
#include "report.x"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

// The JSON Lines descriptor that replaces stderr text, or -1.
static int diagnostics_json = -1;

// lifecycle

/** Creates an empty diagnostic store that streams through `printer`.
    A NULL `printer` does not stream. A negative `limit` is treated as zero;
    zero collects without a stopping threshold. The printer is borrowed.
*/
Diagnostics Diagnostics.new(Compiler printer, int limit) {
  Diagnostics diag = xmalloc(sizeof(struct Diagnostics));
  *diag = (struct Diagnostics) {
    .entries = [], .published = {}, .printer = printer,
    .limit = (limit < 0) ? 0 : limit};
  return diag;
}

/** Stops streaming until `Diagnostics.release` and records the current
    entries, count, and limit state.
*/
DiagnosticsHold Diagnostics.hold(Diagnostics diag) {
  DiagnosticsHold hold = {
    diag.printer, diag.entries.len(), diag.count, diag.limit_notified
  };
  diag.printer = NULL;
  return hold;
}

/** Restores the streaming saved by `hold`. When `keep` is set, entries
    published since the hold remain and stream now; otherwise they are
    discarded with the count and limit state they changed.
*/
void Diagnostics.release(Diagnostics diag, DiagnosticsHold hold, int keep) {
  diag.printer = hold.printer;
  if (keep) {
    for (int i = hold.entries; i < diag.entries.len(); i++)
      _emit_entry(diag, diag.entries[i]);
    return;
  }
  _forget(diag, hold.entries);
  diag.entries.resize(hold.entries);
  diag.count = hold.count;
  diag.limit_notified = hold.limit_notified;
}

// state queries

/** Returns whether counted reports have reached the positive limit.
    A zero limit never reports that it has been reached.
*/
int Diagnostics.reached_limit(Diagnostics diag) {
  if (diag.limit <= 0) return 0;
  return diag.count >= diag.limit;
}

// diagnostics & error reporting

/** Sends every later printed diagnostic to `path` as JSON Lines.
    The file is created or truncated. Each diagnostic is one append write, so
    forked translation workers sharing the descriptor never interleave lines,
    and a line is complete before any exit. Returns zero when `path` cannot be
    opened.
*/
int diagnostics_write_json(String path) {
  diagnostics_json =
    open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND | O_CLOEXEC, 0666);
  return diagnostics_json >= 0;
}

/** Returns the prefix that the statics of the module file holding the
    current token take, or NULL outside a module unit. A module's first row
    marks the start of its text, so other units return before any scan.
*/
String Compiler.file_prefix(Compiler c) {
  Array markers = c.line_markers;
  Token token = _unit_token(c);
  if (!markers || !token) return NULL;
  if (markers[0] ~= %(? ? ? ? ? ? ?) &&
      _token_region(c, token) ~= %(? ? ? ? ? ? ?(String prefix)))
    return prefix;
  return NULL;
}

/** Returns the file that a module's line markers give byte `position` of
    the compiler's text, and sets `offset` to that byte's offset in the file.
    Without such a marker, the file is the compiler's own and `offset` is
    `position`.
*/
String Compiler.text_source(Compiler c, int position, int &offset) {
  offset = position;
  if (_region(c, position) ~=
      %(?(int start) ? ?(String file) ? ?(int origin) ? ?)) {
    offset = origin + position - start;
    return file;
  }
  return c.filename;
}

/** Submits a located compiler error, then transfers or exits.
    An explicit `token` wins; otherwise an active recorded origin is resolved
    before the current token. NULL message defaults to `"compiler error"`.

    Raises: `<malformed>` with the supplied category while a recovery boundary
    is active. Without one, exits the process with status 1.
*/
void Compiler.report_error(
  Compiler compiler, Symbol code, String message, Token token, List notes) {
  report_suspend();
  compiler.report_problem(code, message, token, notes);
  Diagnostics diag = compiler.diagnostics;
  if (compiler.recovery_depth > 0) raise %(malformed (category $code));
  /* A unit that holds its diagnostics until it finishes has no printer yet.
     The floor reports what it collected before it leaves. */
  if (!diag.printer)
    foreach (List held in diag.entries()) compiler.print_diagnostic(held);
  exit(1);
}

/** Records and emits a located compiler error, then returns so the
    translation continues; it fails when it finishes. Location and the
    message default match `Compiler.report_error`.
*/
void Compiler.report_problem(
  Compiler c, Symbol code, String message, Token token, List notes) {
  message = message ? message : "compiler error";
  c.diagnostics.report(code, message, _compiler_location(c, token), notes);
}

// reporting

/** Records and synchronously emits one diagnostic unless already limited.
    Entries retain publication order. NULL `code` becomes `<driver>`. A report
    equal to a stored entry is ignored. Reaching a limit greater than one
    publishes a following `<limit>` notice; a limit of one stops after the
    first error. Later reports are ignored. Supplied
    message, location, and notes are shared; their canonical-value pools must
    outlive the store and its snapshots.
*/
void Diagnostics.report(
  Diagnostics diag, Symbol code, String message, List location, List notes) {
  if (diag.limit > 0 && diag.count >= diag.limit) {
    if (!diag.limit_notified) {
      diag.limit_notified = 1;
      _publish_limit_notice(diag);
    }
    return;
  }

  List entry = _build_entry(code, <error>, message, location, notes);
  if (!_publish(diag, entry)) return;
  diag.count += 1;

  if (diag.limit > 0 && diag.count >= diag.limit && !diag.limit_notified) {
    diag.limit_notified = 1;
    _publish_limit_notice(diag);
  }
}

/** Records and emits a located warning without consuming the error limit.
    Location selection matches `Compiler.report_error`; NULL code becomes
    `<warning>` and NULL message becomes `"compiler warning"`. This operation
    returns without raising or changing the process exit status.
*/
void Compiler.report_warning(
  Compiler c, Symbol code, String message, Token token, List notes) {
  c.report_warning_at(code, message, _compiler_location(c, token), notes);
}

/** Resolves a recorded occurrence through generated ancestry to its source.
    Returns NULL when `occurrence` is outside the origin table. The occurrence
    must come from this compiler's current parse and transform state. Returned
    location cells are canonicalized through the active pool hierarchy and
    retain their actual producing-pool lifetime. They share the recorded
    filename, which retains its own producing-pool lifetime.
*/
List Compiler.origin_location(Compiler compiler, int occurrence) {
  /* Parsing appends `(source ...)` rows; transforms append `(generated ...)`
     rows whose parent already exists. The earlier-parent rule makes ancestry
     finite, and any other row is corrupt compiler state. */
  while (occurrence > 0 && occurrence <= (int) compiler.origins.len()) {
    List origin = compiler.origins[occurrence - 1];
    match (origin) {
      case %(generated ?parent (!or splice xform)): {
        occurrence = parent;
        continue;
      }
      case %(source ?file ?line ?column ?length ?position):
        return %( (file $file) (line $line)
                  (column $column) (length $length)
                  (position $position)
                );
    }
    __builtin_unreachable();
  }
  return NULL;
}

/** Builds the diagnostic location for `token` or the current token.
    If neither exists, returns the current file at line 1, column 1, and byte
    position 0 with zero length. Semantic facts use physical paths; ordinary
    token locations use `Compiler.display_path`.
    Location cells and a derived path are canonicalized through the active
    pool hierarchy and retain their actual producing-pool lifetimes; an
    unchanged filename retains the compiler's
    producing-pool lifetime.
*/
List Compiler.token_location(Compiler compiler, Token token) {
  String file = compiler.filename ? compiler.filename : "<stdin>";
  if (compiler.source_facts) file = compiler.display_path(file);
  // Unreadable input fails before tokenization; anchor it at the file start.
  if (!token) token = compiler.token;
  if (!token)
    return %( (file $file) (line 1) (column 1) (length 0) (position 0) );
  int line = token.line, column = compiler.token_column(token);
  if (compiler.line_markers) file = compiler.token_source(token, line);
  file = compiler.display_path(file);
  return %( (file $file) (line $line)
            (column $column) (length $(token.len))
            (position $(token.pos))
          );
}

/** Returns a physical source path for semantic facts, otherwise a path
    relative to the compiler root. Pseudo paths and NULL stay unchanged.
*/
String Compiler.display_path(Compiler compiler, String path) {
  if (!path || path.startswith("<")) return path;
  if (compiler.source_facts) return Path.absolute(path);
  String root = compiler.root_dir;
  if (root && path.startswith(root) &&
      path.len() > root.len() && path[root.len()] == '/')
    return path[root.len() + 1:];
  return path;
}

/** Returns the file that the line markers of a merged text give `token`,
    and sets `line` to the token's line in that file. A token outside the
    marked regions keeps the compiler's own file and its line.
*/
String Compiler.token_source(Compiler c, Token token, int &?line) {
  if (line) line = token.line;
  List region = _token_region(c, token);
  if (!region) return c.filename;
  (int start, int text_line, String file, int file_line) = region;
  if (line) line = file_line + token.line - text_line;
  return file;
}

/** Returns `token`'s column in the file that holds it. A module region
    that begins inside a line of its file continues that line's columns.
*/
int Compiler.token_column(Compiler c, Token token) {
  if (_token_region(c, token) ~=
      %(? ?(int text_line) ? ? ? ?(String before) ?) &&
      token.line == text_line) return before.len() + token.col;
  return token.col;
}

/** Records and emits a warning at a location built earlier by
    `Compiler.token_location`, for a report raised after its token has been
    consumed. Defaults match `Compiler.report_warning`.
*/
void Compiler.report_warning_at(
  Compiler compiler, Symbol code, String message, List location,
  List notes) {
  report_suspend();
  Diagnostics diag = compiler.diagnostics;
  message = message ? message : "compiler warning";
  /* Warnings share publication and repeat handling without error counts. */
  List entry = _build_entry(
    code ? code : <warning>, <warning>, message, location, notes);
  _publish(diag, entry);
}

/** Writes one structured diagnostic entry and source context to stderr, or
    one JSON line after `diagnostics_write_json`.
    NULL is ignored. A present location supplies `file`, one-based `line` and
    `column`, and token `length`; `String` notes are joined into one note line.
*/
void Compiler.print_diagnostic(Compiler compiler, List entry) {
  if (entry ~= %((code ?code) (severity ?severity) (message ?message)
                (location ?location) (notes ?notes))) {
    String note = _note_line(notes);
    if (diagnostics_json >= 0) {
      _write_json(compiler, code, severity, message, location, note);
      return;
    }
    _write_heading(compiler, code, message, location);
    if (note) fprintf(stderr, "  note: %s\n", note);
    fprintf(stderr, "\n");
    fflush(stderr);
  }
}

/** Moves collected child reports into the caller's store without re-emitting.
    Shared stores already contain their entries. The child's separate store
    remains configured and empty after its reports have been transferred.
*/
void Compiler.take_diagnostics(Compiler c, Compiler child) {
  Diagnostics target = c.diagnostics, source = child.diagnostics;
  if (target == source) return;
  foreach (List entry in source.entries) _store(target, entry);
  target.count += source.count;
  target.limit_notified |= source.limit_notified;
  source.reset();
}

/** Clears stored entries and limit state while preserving configuration. */
void Diagnostics.reset(Diagnostics diag) {
  _forget(diag, 0);
  diag.entries.clear();
  diag.count = 0;
  diag.limit_notified = 0;
}

/** Returns the number of counted diagnostics accepted since the last reset.
    Warnings and the generated limit notice are excluded.
*/
int Compiler.error_count(Compiler compiler) => compiler.diagnostics.count;

/** Returns a report-order snapshot of all collected diagnostics.
    Snapshot cells are canonicalized through the active pool hierarchy and
    share entry values; each retains its actual producing-pool lifetime.
*/
List Compiler.diagnostics(Compiler compiler) => compiler.diagnostics.entries();



/** Returns an immutable `List` snapshot in publication order.
    Snapshot cells are canonicalized through the active pool hierarchy and
    retain their actual producing-pool lifetime. They share the stored entry
    `List`s. The snapshot includes warnings and the limit notice; changing or
    resetting `diag` does not change it.
*/
List Diagnostics.entries(Diagnostics diag) {
  if (!diag.entries.len()) return %();
  return diag.entries;
}

// debug utilities

/** Prints every non-EOF token with its position and visible content.
    `Compiler.tokenize` must have populated the compiler's tokenizer.
*/
void Compiler.dump_tokens(Compiler compiler) {
  Token tokens = compiler.tokenizer.tokens;
  for (Token token = tokens; token.type != <eof>; token++) {
    printf("(%4d, %-3d)\t%-20s", token.line, token.col, token.type.str());
    _pprint(token.text, token.len);
    putchar('\n');
  }
}

/** Prints every entry in `map` to stdout in `Map` iteration order. */
void Compiler.dump_symbol_table(Compiler compiler, Map map) {
  foreach (Var (key, value) in map) printf("%s ==>\n%s\n", key, value);
}

/** Prints each cached numeric identifier and its key to stdout. */
void Compiler.dump_cache(Compiler compiler) {
  foreach (Var (key, value) in compiler.key_ids)
    printf("%s\t==>\t%s\n", value.repr(), key.repr());
}

// diagnostic emission

static void _emit_entry(Diagnostics diag, List entry) {
  if (diag.printer) diag.printer.print_diagnostic(entry);
}

/* The entries from position `from` on leave the store, so the repeat rule
   stops seeing those first stored there. */
static void _forget(Diagnostics diag, int from) {
  for (int i = from; i < diag.entries.len(); i++) {
    Var first;
    if (diag.published.try_get(diag.entries[i], first) && first.int() >= from)
      diag.published.del(diag.entries[i]);
  }
}



/* A diagnostic's text notes form one line, such as `token: ; kind: ;`. */
static String _note_line(List l) {
  List strings = l.filter(%!(entry) => entry is <string>);
  return strings ? " ".join(strings) : NULL;
}

static void _write_json(
  Compiler c, Symbol code, Symbol severity, String message, List location,
  String note) {
  Buffer out = auto Buffer.new(0);
  out.write(%"{\"code\":$(Var.json(code))");
  out.write(%",\"message\":$(Var.json(message))");
  out.write(%",\"severity\":$(Var.json(severity))");
  _write_json_location(c, out, location);
  out.write(%",\"notes\":$(Var.json(note ? [note] : []))}\n");
  while (write(diagnostics_json, out.content.bytes, out.content.length) < 0 &&
         errno == EINTR) {}
}

/* An entry without a location writes null for each location key. */
static void _write_json_location(Compiler c, Buffer out, List location) {
  if (location ~=
      %((file ?file) (line ?line) (column ?column) (length ?length)
        (position ?position))) {
    out.write(%",\"file\":$(Var.json(_json_path(c, file)))");
    out.write(%",\"line\":$line,\"column\":$column");
    out.write(%",\"length\":$length,\"position\":$position");
    return;
  }
  out.write(",\"file\":null,\"line\":null,\"column\":null");
  out.write(",\"length\":null,\"position\":null");
}

/* Text names a source under the x2c root relative to that root and leaves
   another relative path as given. JSON resolves both against the working
   directory: a relative path that is not there came from the root. A source
   inside the working directory stays relative to it; any other is absolute.
*/
static String _json_path(Compiler compiler, String path) {
  if (!path || path.startswith("<")) return path;
  if (!path.startswith("/") && !Path.exists(path))
    path = Path.join(compiler.root_dir, path);
  path = Path.absolute(path);
  String directory = %"$(Path.absolute("."))/";
  return path.startswith(directory) ? path.remove_prefix(directory) : path;
}

/* A located heading names its source position and shows that line. */
static void _write_heading(
  Compiler c, Symbol code, String message, List location) {
  if (location ~=
      %((file ?file) (line ?line) (column ?column) (length ?length)
        (position ?position))) {
    String place = %"$file:$line:$column";
    fprintf(stderr, "%s: %s: %s\n", place, code.str(), message);
    _show_source_context(c, line, column, length, position);
    return;
  }
  fprintf(stderr, "%s: %s\n", code.str(), message);
}

/* Locations use one-based coordinates while source indexing is zero-based.
   Clamp a stale column or width to the current line, retain tabs before the
   token, and render at least one caret. A merged text shows its line that
   holds byte `position`, after the text that line continues in its file. */
static void _show_source_context(
  Compiler compiler, int line, int column, int length, int position) {
  if (!compiler.text) return;
  if (compiler.line_markers) line = _text_line(compiler, position);
  char *line_start, *line_end;
  if (!_context_line(compiler, line, line_start, line_end)) return;
  if (_region(compiler, position) ~=
      %(? ?(int text_line) ? ? ? ?(String before) ?) &&
      line == text_line && before.len()) {
    String shown =
      %"$before$(String.new_len(line_start, line_end - line_start))";
    line_start = shown;
    line_end = line_start + shown.len();
  }
  _context_caret(line_start, line_end, column, length);
}

/* The line-marker row of the region of the compiler's text that holds byte
   `position`, or NULL before the first region. */
static List _region(Compiler c, int position) {
  List region = NULL;
  if (c.line_markers)
    foreach (List row in c.line_markers) {
      if (row.car().int() > position) break;
      region = row;
    }
  return region;
}

/* A merged text's location names a line of the file it came from, and the
   context shows the line of the text that holds its byte position. */
static int _text_line(Compiler c, int position) {
  int line = 0;
  foreach (int start in _line_starts(c)) {
    if (start > position) break;
    line++;
  }
  return line;
}

/* Find the physical line, including a script's shebang at line one. */
static int _context_line(
  Compiler c, int line, char *&line_start, char *&line_end) {
  char *text = c.text;
  line_start = line_end = text;
  // A script's first line reads as an include, but the reader wrote it.
  if (line <= 1) {
    if (c.script) {
      line_start = c.script.shebang;
      line_end = line_start + strlen(line_start);
    }
    else while (*line_end && *line_end != '\n') line_end++;
    return line == 1;
  }
  Array starts = _line_starts(c);
  if (line > starts.len()) return 0;
  line_start = line_end = text + starts[line - 1].int();
  while (*line_end && *line_end != '\n') line_end++;
  return 1;
}

/* The offset where each line of the compiler's text starts, indexed once
   per text. */
static Array _line_starts(Compiler c) {
  if (c.lines_text === c.text) return c.line_starts;
  c.lines_text = c.text;
  c.line_starts.clear();
  c.line_starts.push(0);
  for (char *p = c.text; *p; p++)
    if (*p == '\n') c.line_starts.push(p + 1 - (char *) c.text);
  return c.line_starts;
}

/* Clamp the caret to the line while retaining tabs before the token. An
   empty line, such as the end of a file, shows no context. */
static void _context_caret(
  char *line_start, char *line_end, int column, int length) {
  int line_len = line_end - line_start, start = column > 0 ? column - 1 : 0;
  if (!line_len) return;
  if (start > line_len) start = line_len;
  int width = length > 0 ? length : 1;
  if (start < line_len && width > line_len - start) width = line_len - start;
  if (width < 1) width = 1;
  fprintf(stderr, "  %.*s\n", line_len, line_start);
  fprintf(stderr, "  ");
  for (int i = 0; i < start; i++)
    putc(line_start[i] == '\t' ? '\t' : ' ', stderr);
  for (int i = 0; i < width; i++) putc('^', stderr);
  fprintf(stderr, "\n");
}

// source token locations

/* The outermost active macro invocation, else the current token when it
   lies in the unit's text. A template's tokens hold positions in the file
   that defined the macro, which may be another file of this unit, and a
   free name in its body binds where the expansion lands. */
static Token _unit_token(Compiler c) {
  Token site = NULL;
  if (c.macro_stack)
    foreach (List active in c.macro_stack) {
      (Var definition, Var input, Var bindings, Token invocation) = active;
      (void) definition, (void) input, (void) bindings;
      if (_in_unit(c, invocation)) site = invocation;
    }
  if (site) return site;
  return _in_unit(c, c.token) ? c.token : NULL;
}

static int _in_unit(Compiler c, Token token) {
  if (!token || !c.tokenizer) return 0;
  Token first = c.tokenizer.tokens;
  return token >= first && token < first + c.tokenizer.tokens.len();
}

/* The region that places `token`. The host preprocessor's rows place only
   the tokens scanned from its output. A module's rows place any token of
   the spliced text, including the thawed copy of a queued effect's site. */
static List _token_region(Compiler c, Token token) {
  List region = _region(c, token.pos);
  if (region ~= %(? ? ? ? ? ? ?)) return region;
  if (!region) return NULL;
  Token first = c.tokenizer.tokens;
  return token >= first && token < first + c.tokenizer.tokens.len()
       ? region : NULL;
}

// diagnostic construction

/* Some producers derive one failure twice, so an entry equal to a stored
   one is not repeated. Reports whether the entry was published. */
static int _publish(Diagnostics diag, List entry) {
  if (entry in diag.published) return 0;
  _store(diag, entry);
  _emit_entry(diag, entry);
  return 1;
}

/* The limit notice follows the report that reaches the threshold. It is
   stored and streamed like an entry but is not included in `count`. */
static void _publish_limit_notice(Diagnostics diag) {
  if (diag.limit == 1) return;
  String note = "too many errors, stopping";
  List entry = _build_entry(<limit>, <note>, note, NULL, NULL);
  _store(diag, entry);
  _emit_entry(diag, entry);
}



/* Diagnostic entries always carry code, severity, message, location, and
   notes rows. The severity is the submitting operation's, not the code's: a
   category such as `literal` or `region` reports both errors and warnings.
   Entry cells are canonicalized through the active pool hierarchy and retain
   their actual producing-pool lifetime. Message, location, and notes remain
   shared with their producers and retain those pool lifetimes, which must
   outlive every store or snapshot use. A missing location or notes value
   stays a typed empty List in its row. */
static List _build_entry(
  Symbol code, Symbol severity, String message, List location, List notes) {
  Symbol effective_code = code ? code : <driver>;
  return %(
    (code $effective_code)
    (severity $severity)
    (message $message)
    (location $location)
    (notes $notes)
  );
}

static void _store(Diagnostics diag, List entry) {
  diag.published.setdefault(entry, diag.entries.len());
  diag.entries.push(entry);
}

static List _compiler_location(Compiler compiler, Token token) {
  if (!token && compiler.origin) {
    List location = compiler.origin_location(compiler.origin);
    if (location) return location;
  }
  return compiler.token_location(token);
}



// debug rendering

// Print text with visible symbols for whitespace characters.
static void _pprint(char *text, int len) {
  for (int i = 0; i < len; i++) {
    char c = text[i];
    switch (c) {
      case '\n': fputs("\u2424", stdout); break;
      case '\r': fputs("\u240D", stdout); break;
      case '\t': fputs("\u2409", stdout); break;
      case ' ' : fputs("\u2420", stdout); break;
      default:   putchar(c); break;
    }
  }
}
