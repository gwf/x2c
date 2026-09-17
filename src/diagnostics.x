/*  diagnostics.x -- structured compiler diagnostics collection

    Maintains a bounded, ordered collection of compiler diagnostics with
    optional streaming to one emitter.

    Entries are stored chronologically and exposed as immutable `List`
    snapshots.
    A zero limit disables the stopping threshold without disabling collection.
    The store and its mutable `Array` belong to the caller's active `Scope`;
    entry
    `List`s and `String`s belong to their producing canonical-value pools.
 */

#pragma once
#include "common.x"

/** Receives one borrowed diagnostic entry when the store publishes it.
    `Diagnostics` retains the callback and borrowed `owner`, invokes the
    callback synchronously, and never releases `owner`.
*/
typedef void (*DiagnosticEmitter)(void *owner, List entry);

/** Collects diagnostic entries and optionally streams them.
    A value is valid after `Diagnostics.new`. The store and backing `Array` are
    `Scope`-owned; entry `List`s and immutable children retain the lifetime of
    their producing canonical-value pools. A borrowed `owner` must remain valid
    while its emitter is installed.
*/
typedef struct Diagnostics {
  Array entries;          // Stored chronologically; entries() is a snapshot
  DiagnosticEmitter emit; // Destination for streaming output (optional)
  void *owner;            // Handed back to emit
  int limit;              // 0 disables limiting
  int count, limit_notified;
} *Diagnostics;

#include "compiler.x"
#include "type.x"
#pragma private

#include "report.x"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

// The JSON Lines descriptor that replaces stderr text, or -1.
static int diagnostics_json = -1;

static void _emit_entry(Diagnostics diag, List entry) {
  if (diag.emit) diag.emit(diag.owner, entry);
}

// lifecycle

/** Creates an empty diagnostic store with an optional emitter.
    A negative `limit` is treated as zero; zero collects without a stopping
    threshold. The emitter and `owner` are borrowed.
*/
Diagnostics Diagnostics.new(DiagnosticEmitter emit, void *owner, int limit) {
  Diagnostics diag = Scope.malloc(sizeof(struct Diagnostics));
  diag.entries = [];
  diag.emit = emit;
  diag.owner = owner;
  diag.limit = (limit < 0) ? 0 : limit;
  diag.count = 0;
  diag.limit_notified = 0;
  return diag;
}

/** Clears stored entries and limit state while preserving configuration. */
void Diagnostics.reset(Diagnostics diag) {
  diag.entries.clear();
  diag.count = 0;
  diag.limit_notified = 0;
}

/** Replaces the borrowed emitter and owner without replaying stored entries.
    A NULL emitter disables streaming.
*/
void Diagnostics.set_emitter(
  Diagnostics diag, DiagnosticEmitter emit, void *owner) {
  diag.emit = emit;
  diag.owner = owner;
}

// state queries

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

/** Returns whether `diag` currently has an emitter. */
int Diagnostics.has_emitter(Diagnostics diag) => diag.emit != NULL;

/** Returns whether counted reports have reached the positive limit.
    A zero limit never reports that it has been reached.
*/
int Diagnostics.reached_limit(Diagnostics diag) {
  if (diag.limit <= 0) return 0;
  return diag.count >= diag.limit;
}

// reporting

/* Diagnostic entries always carry code, severity, message, location, and
   notes rows. The severity is the submitting operation's, not the code's: a
   category such as `literal` or `region` reports both errors and warnings.
   Entry cells are canonicalized through the active pool hierarchy and retain
   their actual producing-pool lifetime. Message, location, and notes remain
   shared with their producers and retain those pool lifetimes, which must
   outlive every store or snapshot use. A missing location or notes value
   remains a typed empty List rather than an omitted row. */
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

/* The limit notice follows the report that reaches the threshold. It is
   stored and streamed like an entry but is not included in `count`. */
static void _publish_limit_notice(Diagnostics diag) {
  if (diag.limit == 1) return;
  String note = "too many errors, stopping";
  List entry = _build_entry(<limit>, <note>, note, NULL, NULL);
  diag.entries.push(entry);
  _emit_entry(diag, entry);
}

/** Records and synchronously emits one diagnostic unless already limited.
    Entries retain publication order. NULL `code` becomes `<driver>`. Reaching
    a limit greater than one publishes a following `<limit>` notice; a limit
    of one stops after the first error. Later reports are ignored. Supplied
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
  diag.entries.push(entry);
  diag.count += 1;
  _emit_entry(diag, entry);

  if (diag.limit > 0 && diag.count >= diag.limit && !diag.limit_notified) {
    diag.limit_notified = 1;
    _publish_limit_notice(diag);
  }
}

/* Warnings share publication order and emitter delivery with reports, but
   never change `count` or publish the limit notice. */
static void Diagnostics._warn(
  Diagnostics diag, Symbol code, String message, List location, List notes) {
  List entry = _build_entry(code, <warning>, message, location, notes);
  diag.entries.push(entry);
  _emit_entry(diag, entry);
}

// diagnostics & error reporting

/* A diagnostic's text notes form one line, such as `token: ; kind: ;`. */
static String _note_line(List notes) {
  List strings = notes.filter(%!(entry) => entry is <string>);
  return strings ? " ".join(strings) : NULL;
}

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

/* Text names a source under the x2c root relative to that root and leaves
   another relative path as given. JSON resolves both against the working
   directory: a relative path that is not there came from the root. A source
   inside the working directory stays relative to it; any other is absolute.
*/
static String Compiler._json_path(Compiler compiler, String path) {
  if (!path || path.startswith("<")) return path;
  if (!path.startswith("/") && !Path.exists(path))
    path = Path.join(compiler.root_dir, path);
  path = Path.absolute(path);
  String directory = %"${Path.absolute(".")}/";
  return path.startswith(directory) ? path.remove_prefix(directory) : path;
}

static void Compiler._write_json(Compiler compiler, List entry) {
  Symbol code = entry.assoc(<code>);
  List location = entry.assoc(<location>), notes = entry.assoc(<notes>);
  Buffer out = $auto(Buffer.new(0));
  out.write("{\"code\":");
  report_json_string(out, code);
  out.write(",\"message\":");
  report_json_string(out, entry.assoc(<message>));
  out.write(",\"severity\":");
  report_json_string(out, entry.assoc(<severity>).symbol());
  foreach (Symbol key, %(file line column length position)) {
    Var value = location.assoc(key);
    out.printf(",\"%s\":", key.str());
    if (value is void) out.write("null");
    else if (value is <string>)
      report_json_string(out, compiler._json_path(value));
    else out.printf("%d", value.int());
  }
  out.write(",\"notes\":[");
  String note = _note_line(notes);
  if (note) report_json_string(out, note);
  out.write("]}\n");
  while (write(diagnostics_json, out.content.bytes, out.content.length) < 0 &&
         errno == EINTR) {}
}

/** Writes one structured diagnostic entry and source context to stderr, or
    one JSON line after `diagnostics_write_json`.
    NULL is ignored. A present location supplies `file`, one-based `line` and
    `column`, and token `length`; `String` notes are joined into one note line.
*/
void Compiler.print_diagnostic(Compiler compiler, List entry) {
  if (!entry) return;
  if (diagnostics_json >= 0) {
    compiler._write_json(entry);
    return;
  }
  Var v;
  Symbol code = entry.assoc(<code>), String message = entry.assoc(<message>);
  v = entry.assoc(<location>);
  List location = v is <list> ? v : NULL;
  v = entry.assoc(<notes>);
  List notes = v is <list> ? v : NULL;
  if (location) {
    String text = "<input>";
    v = location.assoc(<file>);
    if (v is <string>) text = v;
    int line = location.assoc(<line>);
    int column = location.assoc(<column>);
    fprintf(
      stderr, "%s:%d:%d: %s: %s\n",
      text, line, column, code.str(), message);
    compiler._show_source_context(location);
  }
  else fprintf(stderr, "%s: %s\n", code.str(), message);
  String note = _note_line(notes);
  if (note) fprintf(stderr, "  note: %s\n", note);
  fprintf(stderr, "\n");
  fflush(stderr);
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

/** Returns a physical source path for semantic facts, otherwise a path
    relative to the compiler root. Pseudo paths and NULL stay unchanged.
*/
String Compiler.display_path(Compiler compiler, String path) {
  if (!path || path.startswith("<")) return path;
  if (compiler.source_facts) return Path.absolute(path);
  String root = compiler.root_dir;
  if (root && path && path.startswith(root) &&
      path.len() > root.len() && path[root.len()] == '/')
    return path[root.len() + 1:];
  return path;
}

/** Builds the diagnostic location for `token` or the current token.
    If neither exists, returns the current file at line 1, column 1, and byte
    position 0 with zero length. Semantic facts use physical paths; ordinary
    token locations use `Compiler.display_path`.
    Location cells and a derived path
    are canonicalized through the active pool hierarchy and retain their actual
    producing-pool lifetimes; an unchanged filename retains the compiler's
    producing-pool lifetime.
*/
List Compiler.token_location(Compiler compiler, Token token) {
  String file = compiler.filename ? compiler.filename : "<stdin>";
  if (compiler.source_facts) file = compiler.display_path(file);
  // Unreadable input fails before tokenization; anchor it at the file start.
  if (!token) token = compiler.token;
  if (!token)
    return %( (file $file) (line 1) (column 1) (length 0) (position 0) );
  file = compiler.display_path(file);
  return %( (file $file) (line ${token.line})
            (column ${token.col}) (length ${token.len})
            (position ${token.pos})
          );
}

static List _compiler_location(Compiler compiler, Token token) {
  if (!token && compiler.origin) {
    List location = compiler.origin_location(compiler.origin);
    if (location) return location;
  }
  return compiler.token_location(token);
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
  Diagnostics diag = compiler.diagnostics;
  message = message ? message : "compiler error";
  List loc = _compiler_location(compiler, token);
  diag.report(code, message, loc, notes);
  if (compiler.recovery_depth > 0) raise %(malformed (category $code));
  exit(1);
}

/** Records and emits a located warning without consuming the error limit.
    Location selection matches `Compiler.report_error`; NULL code becomes
    `<warning>` and NULL message becomes `"compiler warning"`. This operation
    returns without raising or changing the process exit status.
*/
void Compiler.report_warning(
  Compiler compiler, Symbol code, String message, Token token, List notes) {
  compiler.report_warning_at(
    code, message, _compiler_location(compiler, token), notes);
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
  diag._warn(code ? code : <warning>, message, location, notes);
}

/* Locations use one-based coordinates while source indexing is zero-based.
   Clamp a stale column or width to the current line, retain tabs before the
   token, and render at least one caret. */
static void Compiler._show_source_context(Compiler compiler, List location) {
  if (!location || !compiler.text) return;
  Var line_var = location.assoc(<line>);
  Var col_var = location.assoc(<column>);
  Var len_var = location.assoc(<length>);
  int line = line_var is void ? 0 : line_var;
  int column = col_var is void ? 0 : col_var;
  int length = len_var is void ? 1 : len_var, char *text = compiler.text;
  int current_line = 1, char *line_start = text, *line_end = text;
  // A script's first line reads as an include, but the reader wrote it.
  if (line <= 1 && compiler.script) {
    line_start = compiler.script.shebang;
    line_end = line_start + strlen(line_start);
  }
  else if (line <= 1) while (*line_end && *line_end != '\n') line_end++;
  else {
    for (char *p = text; *p; p++) {
      if (*p == '\n') {
        current_line++;
        if (current_line == line) {
          line_start = p + 1;
          line_end = line_start;
          while (*line_end && *line_end != '\n') line_end++;
          break;
        }
      }
    }
  }
  if (current_line == line) {
    int line_len = line_end - line_start, start = column > 0 ? column - 1 : 0;
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

// debug utilities

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
  foreach (Var (key, value), map) printf("%s ==>\n%s\n", key, value);
}

/** Prints each cached numeric identifier and its key to stdout. */
void Compiler.dump_cache(Compiler compiler) {
  foreach (Var (key, value), compiler.key_ids)
    printf("%s\t==>\t%s\n", value.repr(), key.repr());
}
