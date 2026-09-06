/*  pcre2.x -- PCRE2-8 values for ordinary x2c programs.

    The Regexp wrapper is Scope-owned; Regexp.free releases its compiled
    PCRE2 code and reusable match-data block. RegexpMatch and RegexpCapture
    are immutable x2c Lists; their Strings and offsets remain valid after the
    next match and do not borrow PCRE2 memory.
 */

#include "pcre2-8.h"

typedef struct Regexp *Regexp;
typedef List RegexpCapture;
typedef List RegexpMatch;

protocol RegexpMatchIndex(T) {
  associated Key = Var;
  associated Value = String;

  Value T.getindex(T, Key);
}

protocol RegexpMatchIndex(RegexpMatch);

typedef enum RegexpLisp {
  REGEXPLISP_NAMESPACE
} RegexpLisp;

#pragma private

#include <ctype.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct Regexp {
  pcre2_code *code;
  pcre2_match_data *match_data;
  pcre2_match_context *match_context;
  String pattern;
  uint32_t capture_count;
  String *capture_names;
};

static PCRE2_SPTR _pcre2_bytes(String string) {
  return (PCRE2_SPTR) (string ? string : "");
}

static String _pcre2_error_message(int code) {
  PCRE2_UCHAR bytes[256] = { 0 };
  int length = pcre2_get_error_message(code, bytes, sizeof(bytes));
  if (length < 0) return %"unknown PCRE2 error";
  return String.new_len((char *) bytes, length);
}

static void _pcre2_compile_error(String pattern, int code, PCRE2_SIZE offset) {
  String message = _pcre2_error_message(code);
  ulong byte_offset = (ulong) offset;
  raise %(malformed (library "PCRE2") (operation "compile")
          (code $code) (message $message) (offset $byte_offset)
          (pattern $pattern));
}

static void _pcre2_match_error(String operation, int code) {
  String message = _pcre2_error_message(code);
  raise %(bad-state (library "PCRE2") (operation $operation)
          (code $code) (message $message));
}

static void _regexp_live(Regexp regexp, String operation) {
  if (regexp && regexp.code && regexp.match_data && regexp.match_context)
    return;
  raise %(bad-state (library "PCRE2") (operation $operation)
          (reason "freed or null Regexp"));
}

static int _regexp_load_names(Regexp regexp) {
  uint32_t name_count = 0, entry_size = 0;
  PCRE2_SPTR table = NULL;
  int result = pcre2_pattern_info(
    regexp.code, PCRE2_INFO_NAMECOUNT, &name_count
  );

  if (result < 0 || !name_count) return result;
  result = pcre2_pattern_info(
    regexp.code, PCRE2_INFO_NAMEENTRYSIZE, &entry_size
  );
  if (result < 0) return result;
  result = pcre2_pattern_info(regexp.code, PCRE2_INFO_NAMETABLE, &table);
  if (result < 0) return result;

  for (uint32_t i = 0; i < name_count; i++, table += entry_size) {
    uint32_t number = ((uint32_t) *table << 8) | *(table + 1);
    if (number <= regexp.capture_count)
      regexp.capture_names[number] = String.new((char *) table + 2);
  }
  return 0;
}

Regexp Regexp.compile_context(
  String pattern, uint32_t options, pcre2_compile_context *context) {
  int error_code = 0;
  PCRE2_SIZE error_offset = 0;
  pcre2_code *code = pcre2_compile(
    _pcre2_bytes(pattern), pattern.len(), options,
    &error_code, &error_offset, context
  );
  if (!code) {
    _pcre2_compile_error(pattern, error_code, error_offset);
    return NULL;
  }

  Regexp regexp = Scope.calloc(1, sizeof(struct Regexp));
  regexp.code = code;
  regexp.pattern = pattern.intern();
  regexp.match_data = pcre2_match_data_create_from_pattern(code, NULL);
  if (!regexp.match_data) {
    regexp.free();
    raise %(alloc-fail (library "PCRE2")
            (operation "match_data_create_from_pattern"));
  }
  regexp.match_context = pcre2_match_context_create(NULL);
  if (!regexp.match_context) {
    regexp.free();
    raise %(alloc-fail (library "PCRE2") (operation "match_context_create"));
  }

  uint32_t captures = pcre2_get_ovector_count(regexp.match_data);
  regexp.capture_count = captures ? captures - 1 : 0;
  regexp.capture_names = Scope.calloc(captures, sizeof(*regexp.capture_names));
  int info_result = _regexp_load_names(regexp);
  if (info_result < 0) {
    regexp.free();
    _pcre2_match_error(%"pattern_info", info_result);
  }
  return regexp;
}

Regexp Regexp.compile(String pattern, uint32_t options) {
  return Regexp.compile_context(pattern, options, NULL);
}

Regexp Regexp.free(Regexp regexp) {
  if (!regexp) return NULL;
  if (regexp.match_context) {
    pcre2_match_context_free(regexp.match_context);
    regexp.match_context = NULL;
  }
  if (regexp.match_data) {
    pcre2_match_data_free(regexp.match_data);
    regexp.match_data = NULL;
  }
  if (regexp.code) {
    pcre2_code_free(regexp.code);
    regexp.code = NULL;
  }
  return NULL;
}

String Regexp.pattern(Regexp regexp) {
  _regexp_live(regexp, %"pattern");
  return regexp.pattern;
}

uint32_t Regexp.capture_count(Regexp regexp) {
  _regexp_live(regexp, %"capture_count");
  return regexp.capture_count;
}

/*  These pointers are borrowed until `free()`. Ordinary matching reuses the
    match-data block, so a raw match through it replaces the same ovector. */
pcre2_code *Regexp.native(Regexp regexp) {
  _regexp_live(regexp, %"native");
  return regexp.code;
}

pcre2_match_data *Regexp.native_match_data(Regexp regexp) {
  _regexp_live(regexp, %"native_match_data");
  return regexp.match_data;
}

pcre2_match_context *Regexp.native_match_context(Regexp regexp) {
  _regexp_live(regexp, %"native_match_context");
  return regexp.match_context;
}

/*  Lists the names this pattern declares, in capture-group order. Unnamed
    groups contribute nothing, so a pattern with no named group returns the
    empty List. A name declared twice under (?J) appears once per group.
*/
List Regexp.capture_names(Regexp regexp) {
  if (!regexp || !regexp.code) {
    raise %(bad-state (library "PCRE2") (operation "capture_names")
            (reason "freed or null Regexp"));
  }
  List names = NULL;
  if (!regexp.capture_names) return NULL;
  for (uint32_t i = 0; i <= regexp.capture_count; i++)
    if (regexp.capture_names[i]) names = cons(regexp.capture_names[i], names);
  return names.reverse();
}

/*  Quotes `literal` so PCRE2 matches it as ordinary text. Every ASCII byte
    that is not a letter, digit, or underscore is backslash-escaped; bytes
    above ASCII pass through so UTF-8 sequences survive intact.
*/
String Regexp.escape(String literal) {
  if (!literal) return NULL;
  Buffer out = Buffer.new(0);
  foreach (char value, literal) {
    if (!(value & 0x80) && !isalnum((unsigned char) value) && value != '_')
      out.write_char('\\');
    out.write_char(value);
  }
  return out.str_free();
}

static Regexp _regexp_limit_result(
  Regexp regexp, String operation, int result) {
  if (result < 0) {
    _pcre2_match_error(operation, result);
  }
  return regexp;
}

Regexp Regexp.set_match_limit(Regexp regexp, uint32_t limit) {
  if (!regexp || !regexp.match_context) {
    raise %(bad-state (library "PCRE2") (operation "set_match_limit")
            (reason "freed or null Regexp"));
  }
  return _regexp_limit_result(
    regexp, %"set_match_limit",
    pcre2_set_match_limit(regexp.match_context, limit)
  );
}

Regexp Regexp.set_depth_limit(Regexp regexp, uint32_t limit) {
  if (!regexp || !regexp.match_context) {
    raise %(bad-state (library "PCRE2") (operation "set_depth_limit")
            (reason "freed or null Regexp"));
  }
  return _regexp_limit_result(
    regexp, %"set_depth_limit",
    pcre2_set_depth_limit(regexp.match_context, limit)
  );
}

Regexp Regexp.set_heap_limit(Regexp regexp, uint32_t limit) {
  if (!regexp || !regexp.match_context) {
    raise %(bad-state (library "PCRE2") (operation "set_heap_limit")
            (reason "freed or null Regexp"));
  }
  return _regexp_limit_result(
    regexp, %"set_heap_limit",
    pcre2_set_heap_limit(regexp.match_context, limit)
  );
}

Regexp Regexp.set_offset_limit(Regexp regexp, ulong limit) {
  if (!regexp || !regexp.match_context) {
    raise %(bad-state (library "PCRE2") (operation "set_offset_limit")
            (reason "freed or null Regexp"));
  }
  return _regexp_limit_result(
    regexp, %"set_offset_limit",
    pcre2_set_offset_limit(regexp.match_context, (PCRE2_SIZE) limit)
  );
}

Regexp Regexp.jit_compile(Regexp regexp, uint32_t options) {
  if (!regexp || !regexp.code) {
    raise %(bad-state (library "PCRE2") (operation "jit_compile")
            (reason "freed or null Regexp"));
  }
  int result = pcre2_jit_compile(regexp.code, options);
  if (result < 0) {
    _pcre2_match_error(%"jit_compile", result);
  }
  return regexp;
}

ulong Regexp.jit_size(Regexp regexp) {
  if (!regexp || !regexp.code) return 0;
  PCRE2_SIZE size = 0;
  int result = pcre2_pattern_info(regexp.code, PCRE2_INFO_JITSIZE, &size);
  if (result < 0) {
    _pcre2_match_error(%"pattern_info", result);
  }
  return (ulong) size;
}

int RegexpCapture.index(RegexpCapture capture) {
  return capture ? capture.getindex(0).int() : -1;
}

String RegexpCapture.name(RegexpCapture capture) {
  return capture ? capture.getindex(1).string() : NULL;
}

int RegexpCapture.matched(RegexpCapture capture) {
  return capture && capture.getindex(2).truth();
}

String RegexpCapture.text(RegexpCapture capture) {
  return capture ? capture.getindex(3).string() : NULL;
}

ulong RegexpCapture.start(RegexpCapture capture) {
  return capture ? capture.getindex(4).ulong() : 0;
}

ulong RegexpCapture.end(RegexpCapture capture) {
  return capture ? capture.getindex(5).ulong() : 0;
}

static RegexpCapture _regexp_capture(
  Regexp regexp, String subject, uint32_t index, PCRE2_SIZE *ovector) {
  PCRE2_SIZE start = ovector[index * 2], end = ovector[index * 2 + 1];
  int matched = start != PCRE2_UNSET, capture_index = (int) index;
  String name = regexp.capture_names[index];
  String text = matched ? String.new_len(
    (char *) subject + start, (int) (end - start)
  ) : NULL;
  ulong first = matched ? (ulong) start : 0, last = matched ? (ulong) end : 0;
  return %($capture_index $name $matched $text $first $last);
}

static RegexpMatch _regexp_result(Regexp regexp, String subject) {
  PCRE2_SIZE *ovector = pcre2_get_ovector_pointer(regexp.match_data);
  uint32_t count = pcre2_get_ovector_count(regexp.match_data);
  List captures = NULL;

  for (uint32_t i = 0; i < count; i++) {
    RegexpCapture capture = _regexp_capture(regexp, subject, i, ovector);
    captures = cons(capture, captures);
  }
  return (RegexpMatch) captures.reverse();
}

static RegexpMatch _regexp_match_at(
  Regexp regexp, String subject, PCRE2_SIZE offset, uint32_t options,
  int *result) {
  *result = pcre2_match(
    regexp.code, _pcre2_bytes(subject), subject.len(), offset, options,
    regexp.match_data, regexp.match_context
  );
  if (*result == PCRE2_ERROR_NOMATCH) return NULL;
  if (*result < 0) {
    _pcre2_match_error(%"match", *result);
  }
  return _regexp_result(regexp, subject);
}

RegexpMatch Regexp.match_from(
  Regexp regexp, String subject, ulong offset, uint32_t options) {
  if (!regexp || !regexp.code || !regexp.match_data) {
    raise %(bad-state (library "PCRE2") (operation "match_from")
            (reason "freed or null Regexp"));
  }
  if (offset > (ulong) subject.len()) {
    raise %(bad-arg (library "PCRE2") (operation "match_from")
            (offset $offset) (length ${subject.len()}));
  }
  int result = 0;
  return _regexp_match_at(
    regexp, subject, (PCRE2_SIZE) offset, options, &result
  );
}

RegexpMatch Regexp.match(Regexp regexp, String subject) {
  return regexp.match_from(subject, 0, 0);
}

List Regexp.find_all_from(
  Regexp regexp, String subject, ulong start, uint32_t match_options) {
  if (!regexp || !regexp.code || !regexp.match_data) {
    raise %(bad-state (library "PCRE2") (operation "find_all_from")
            (reason "freed or null Regexp"));
  }
  if (start > (ulong) subject.len()) {
    raise %(bad-arg (library "PCRE2") (operation "find_all_from")
            (offset $start) (length ${subject.len()}));
  }

  List found = NULL;
  PCRE2_SIZE offset = (PCRE2_SIZE) start;
  uint32_t global_options = 0;
  while (1) {
    int result = 0;
    RegexpMatch current = _regexp_match_at(
      regexp, subject, offset, match_options | global_options, &result
    );
    if (result == PCRE2_ERROR_NOMATCH) break;
    found = cons(current, found);
    if (!pcre2_next_match(regexp.match_data, &offset, &global_options)) break;
  }
  return found.reverse();
}

List Regexp.find_all(Regexp regexp, String subject) {
  return regexp.find_all_from(subject, 0, 0);
}

String Regexp.substitute(
  Regexp regexp, String subject, String replacement, uint32_t options) {
  if (!regexp || !regexp.code || !regexp.match_data) {
    raise %(bad-state (library "PCRE2") (operation "substitute")
            (reason "freed or null Regexp"));
  }

  PCRE2_SIZE length = 0;
  options |= PCRE2_SUBSTITUTE_OVERFLOW_LENGTH;
  int result = pcre2_substitute(
    regexp.code, _pcre2_bytes(subject), subject.len(), 0, options,
    regexp.match_data, regexp.match_context,
    _pcre2_bytes(replacement), replacement.len(),
    NULL, &length
  );
  if (result != PCRE2_ERROR_NOMEMORY || !length || length == PCRE2_UNSET) {
    if (result < 0) _pcre2_match_error(%"substitute", result);
    return NULL;
  }
  if (length >= INT_MAX) {
    ulong bytes = (ulong) length;
    raise %(size-limit (library "PCRE2") (operation "substitute")
            (bytes $bytes));
  }

  String output = String.malloc((int) length + 1);
  PCRE2_SIZE capacity = length + 1;
  result = pcre2_substitute(
    regexp.code, _pcre2_bytes(subject), subject.len(), 0, options,
    regexp.match_data, regexp.match_context,
    _pcre2_bytes(replacement), replacement.len(),
    (PCRE2_UCHAR *) output, &capacity
  );
  if (result < 0) {
    output.free();
    _pcre2_match_error(%"substitute", result);
  }
  char *bytes = output;
  *(bytes + capacity) = '\0';
  return output.intern_free();
}

String Regexp.replace(Regexp regexp, String subject, String replacement) {
  return regexp.substitute(subject, replacement, 0);
}

String Regexp.replace_all(Regexp regexp, String subject, String replacement) {
  return regexp.substitute(subject, replacement, PCRE2_SUBSTITUTE_GLOBAL);
}

/*  Splits `subject` on every match and returns the text between matches. A
    match against the first or last byte contributes the empty String, and a
    pattern that never matches returns the whole subject as one element.
*/
List Regexp.split(Regexp regexp, String subject) {
  List parts = NULL;
  int cursor = 0;
  foreach (RegexpMatch found, regexp.find_all(subject)) {
    RegexpCapture whole = found.capture(0);
    parts = cons(subject.getslice(cursor, (int) whole.start(), 1), parts);
    cursor = (int) whole.end();
  }
  return cons(subject.getslice(cursor, subject.len(), 1), parts).reverse();
}

/*  Replaces every match with the String `fn` returns for it. The callback
    receives the whole RegexpMatch, so it can read captures and offsets.
    PCRE2 does not inspect the result, so a `$1` inside it stays literal;
    use Regexp.replace_all with a plain C literal such as "$2:$1" when you
    want PCRE2 to expand backreferences. `%"..."` reserves `$` for x2c
    interpolation.
*/
String Regexp.replace_fn(
  Regexp regexp, String subject, String (*fn)(RegexpMatch)) {
  if (!fn) {
    raise %(bad-arg (library "PCRE2") (operation "replace_fn")
            (reason "null callback"));
  }
  List parts = NULL;
  int cursor = 0;
  foreach (RegexpMatch found, regexp.find_all(subject)) {
    RegexpCapture whole = found.capture(0);
    parts = cons(subject.getslice(cursor, (int) whole.start(), 1), parts);
    parts = cons(fn(found), parts);
    cursor = (int) whole.end();
  }
  parts = cons(subject.getslice(cursor, subject.len(), 1), parts);
  return %"".join(parts.reverse());
}

RegexpCapture RegexpMatch.capture(RegexpMatch found, Var key) {
  int numbered = key.is_integer(), number = numbered ? key.int() : -1;
  String name = numbered ? NULL : key.str();
  RegexpCapture first_named = NULL;

  foreach (RegexpCapture capture, found) {
    if (numbered && capture.index() == number) return capture;
    if (!numbered && capture.name() == name) {
      if (capture.matched()) return capture;
      if (!first_named) first_named = capture;
    }
  }
  return first_named;
}

List RegexpMatch.captures(RegexpMatch found, Var key) {
  int numbered = key.is_integer(), number = numbered ? key.int() : -1;
  String name = numbered ? NULL : key.str();
  List captures = NULL;

  foreach (RegexpCapture capture, found) {
    if (numbered && capture.index() == number)
      captures = cons(capture, captures);
    if (!numbered && capture.name() == name)
      captures = cons(capture, captures);
  }
  return captures.reverse();
}

String RegexpMatch.getindex(RegexpMatch found, Var key) {
  RegexpCapture capture = found.capture(key);
  return capture && capture.matched() ? capture.text() : NULL;
}

RegexpCapture Var.regexpcapture(Var value) {
  return (RegexpCapture) value.list();
}

RegexpMatch Var.regexpmatch(Var value) {
  return (RegexpMatch) value.list();
}

/*  The Lisp surface is value-oriented on purpose: every binding takes and
    returns String and List, and each compiles and frees its own Regexp, so
    no native handle and no borrowed storage ever enters a Lisp session.
    A caller that wants a compiled pattern to persist stays in x2c.
*/

$lisp.binding(pcre2_lisp, "regex-match")
static List _lisp_regex_match(String pattern, String subject) {
  Regexp regexp = Regexp.compile(pattern, 0);
  defer regexp.free();
  RegexpMatch found = regexp.match(subject);
  if (!found) return NULL;
  List texts = NULL;
  foreach (RegexpCapture capture, found)
    texts = cons(capture.matched() ? capture.text() : NULL, texts);
  return texts.reverse();
}

$lisp.binding(pcre2_lisp, "regex-find-all")
static List _lisp_regex_find_all(String pattern, String subject) {
  Regexp regexp = Regexp.compile(pattern, 0);
  defer regexp.free();
  List texts = NULL;
  foreach (RegexpMatch found, regexp.find_all(subject))
    texts = cons(found[0], texts);
  return texts.reverse();
}

$lisp.binding(pcre2_lisp, "regex-split")
static List _lisp_regex_split(String pattern, String subject) {
  Regexp regexp = Regexp.compile(pattern, 0);
  defer regexp.free();
  return regexp.split(subject);
}

$lisp.binding(pcre2_lisp, "regex-replace")
static String _lisp_regex_replace(
  String pattern, String subject, String replacement) {
  Regexp regexp = Regexp.compile(pattern, 0);
  defer regexp.free();
  return regexp.replace_all(subject, replacement);
}

$lisp.binding(pcre2_lisp, "regex-escape")
static String _lisp_regex_escape(String literal) {
  return Regexp.escape(literal);
}

/*  Installs regex-match, regex-find-all, regex-split, regex-replace, and
    regex-escape into `lisp`. A bad pattern raises out of the binding as the
    same <malformed> an x2c caller would see.
*/
void RegexpLisp.install(Lisp lisp) {
  $lisp.install(lisp, pcre2_lisp);
}
