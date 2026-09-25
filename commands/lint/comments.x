#pragma indent
/*  comments.x -- rules over comment prose and the code it sits beside

    A comment is one comment token, or a run of `//` tokens on consecutive
    lines with only space between them. Its prose drops the delimiters and
    each line's leading `*`. The rules compare that prose with what follows
    it: the name of the next definition, or the next line of code.
*/
#include "lint.x"
#include <ctype.h>
#include <string.h>

#pragma private

typedef struct Comment:
  Symbol kind
  int start, end, first, last
  String text
Comment

static const List verbs = %(
  "add" "append" "apply" "build" "check" "close" "collect" "compare"
  "compute" "convert" "copy" "create" "decode" "decide" "emit" "encode"
  "expect" "find" "format" "generate" "get" "handle" "initialize" "insert"
  "load" "lower" "make" "normalize" "open" "parse" "print" "process" "read"
  "remove" "resolve" "return" "save" "scan" "set" "store" "test" "tokenize"
  "transform" "update" "validate" "write"
)

static const List reason_words = %(
  "because" "cannot" "consequence" "except" "invariant" "must" "never"
  "only" "otherwise" "owner" "owns" "preserve" "requires" "so" "unless"
  "until" "why" "without"
)

static const List stop_words = %(
  "a" "an" "and" "as" "at" "by" "for" "from" "in" "into" "is" "it" "of" "on"
  "one" "or" "the" "this" "to" "when" "with"
)

static const List history_phrases = %(
  "todo" "fixme" "bug" "nb:" "moved verbatim" "recently" "formerly"
  "used to" "old logic" "added this" "added the" "for now"
)

static const List catalog_labels = %(
  "private helpers" "public interface" "public entry points"
  "helper functions" "utility functions"
)

static int _among(String word, List words):
  foreach String each in words:
    if each == word: return 1
  return 0

/* The lower-case words of `text`: runs of letters and digits, split where
   a capital follows a lower-case letter or digit. */
static Array _words(String text):
  Array words = []
  Buffer word = $auto(Buffer.new(0))
  for (char *ch = text ? text : ""; ; ch++):
    int c = (unsigned char) *ch
    int split = isupper(c) && word.len() &&
      (islower((unsigned char) ch[-1]) || isdigit((unsigned char) ch[-1]))
    if isalnum(c) && !split:
      word.write_char(tolower(c))
      continue
    if word.len():
      words.push(word.str())
      word.clear()
    if !c: return words
    if isalnum(c): word.write_char(tolower(c))

/* The distinct words of `text` longer than one letter, without stop words. */
static Map _content(String text):
  Map content = {}
  foreach String word in _words(text):
    if word.len() > 1 && !_among(word, stop_words): content[word] = 1
  return content

static int _shared(Map a, Map b):
  int shared = 0
  foreach Var word in a.keys():
    if word in b: shared++
  return shared

/* `text` with each run of space collapsed to one space and trimmed. */
static String _normal(String text):
  Buffer out = $auto(Buffer.new(0))
  int gap = 0
  for (char *ch = text ? text : ""; *ch; ch++):
    if isspace((unsigned char) *ch):
      gap = out.len() > 0
      continue
    if gap: out.write_char(' ')
    gap = 0
    out.write_char(*ch)
  return out

/* The prose of a comment's `raw` text: the delimiters and each line's
   leading space, `//` or `*`, and one space removed. */
static String _prose(String raw, Symbol kind):
  char *body = raw
  if kind != <line>: body += raw.startswith("/**") ? 3 : 2
  String text = kind == <line> ? String.new(body) :
    String.new_len(body, strlen(body) - 2)
  Array lines = []
  foreach String each in text.split("\n"):
    String trimmed = each.lstrip(NULL)
    char *at = trimmed ? trimmed : ""
    if kind == <line> && !strncmp(at, "//", 2): at += 2
    else if kind != <line> && *at == '*': at++
    if isspace((unsigned char) *at): at++
    lines.push(String.new(at).rstrip(NULL))
  return lines.join("\n").strip(NULL)

/* Collects the comments of `l` into `all` and returns their number. */
static int _collect(Lint l, Comment *all):
  int n = 0
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    if t.type != <comment>: continue
    int line = t.text.startswith("//")
    Comment *last = n ? &all[n - 1] : NULL
    if line && last && last.kind == <line> && t.line == last.end + 1 &&
       l.prev(at) == last.last:
      last.end = t.line, last.last = at
      last.text = %"${last.text}\n${t.text}"
      continue
    Symbol kind = line ? <line> : t.text.startswith("/**") ? <doc> : <block>
    all[n++] = (Comment) {kind, t.line, l.end_line(at), at, at, t.text}
  for (int at = 0; at < n; at++):
    all[at].text = _prose(all[at].text, all[at].kind)
  return n

/* The name of the function whose declarator starts on `line`: the last
   `name(` or `Owner.name(` before a `{` or `=>` within eight lines, or
   NULL when a `;` comes first. */
static String _declared(Lint l, int line):
  String name = NULL
  for (int at = line <= l.lines ? l.first[line] : -1;
       at >= 0 && at < l.count && l.tokens[at].line < line + 8;
       at = l.next(at)):
    Token t = l.at(at)
    if t.type == <;>: return NULL
    if t.type == <"{"> || t.text == "=" && l.tokens[at + 1].text == ">":
      return name
    int open = l.next(at)
    if t.type != <ident> || t.text == "match" || open >= l.count ||
       l.tokens[open].type != <"(">:
      continue
    name = t.text
    if at >= 2 && l.tokens[at - 1].text == "." && lint_word(l.at(at - 2)):
      name = %"${l.tokens[at - 2].text}.$name"
  return NULL

/* Whether any of `phrases` occurs in `text` as whole words. */
static int _mentions(String text, List phrases):
  foreach String phrase in phrases:
    if lint_phrase(text, phrase): return 1
  return 0

/* The number of backquoted spans in `text`. */
static int _code_spans(String text):
  int spans = 0
  for (char *open = strchr(text ? text : "", '`'); open;
       open = strchr(open + 1, '`')):
    char *close = strchr(open + 1, '`')
    if !close: break
    if close > open + 1:
      spans++
      open = close
  return spans

/* The tier `docs/library-manifest.txt` gives the module at `path`, or NULL
   when the manifest does not list it. */
static String _tier(String path):
  static Map tiers
  if !tiers:
    tiers = {}
    Path manifest = "docs/library-manifest.txt"
    String text = manifest.exists() ? manifest.read_text() : ""
    foreach String row in text.split("\n"):
      List fields = row.split("|")
      if row && row[0] != '#' && fields.len() >= 2:
        tiers[fields.car()] = fields.cadr()
  Var tier
  return tiers.try_get(path, &tier) ? tier : NULL

/* Rules that read one comment, the line after it, and the next function
   name. `next` is the first non-blank line after the comment. */
static void _comment(Lint l, Comment c, Array lines, int next):
  String text = _normal(c.text), lower = text.lower()
  Array words = _words(text)
  int count = words.len(), reason = 0
  foreach String word in words:
    if _among(word, reason_words): reason = 1
  String code = next <= lines.len() ? lines[next - 1] : NULL
  code = code.strip(NULL)
  String name = _declared(l, next)
  if _mentions(lower, history_phrases):
    l.add("comment-history", c.start, "history or unfinished work")
  if lower.contains("prevent null pointer dereference") ||
     lower.contains("check null") || lower.contains("check for null"):
    l.add("comment-null-guard", c.start, "narrates an obvious null guard")
  int letters = 0, upper = 1
  for (char *ch = text ? text : ""; *ch; ch++):
    if isalpha((unsigned char) *ch):
      letters++
      if islower((unsigned char) *ch): upper = 0
  int decorated = text.contains("----") || text.contains("====")
  if c.kind == <line> && (decorated || letters >= 4 && upper && count <= 8):
    l.add("section-label", c.start, "decorative or all-capitals label")
  else if count <= 4 && _among(lower, catalog_labels):
    l.add("catalog-label", c.start, "catalog-style section label")
  if c.kind != <doc> && name && count:
    Map function = _content(name), prose = _content(text)
    int shared = _shared(function, prose), size = function.len()
    String first = words[0]
    int verb = _among(first, verbs) && first in function
    if !reason && count <= 12 && (verb || shared >= (size < 2 ? size : 2)):
      l.add("restates-name", c.start, %"restates the name $name")
  if c.kind != <doc> && !name && count <= 12 && code:
    Map prose = _content(text)
    int size = prose.len()
    if !reason && size >= 2 && _shared(prose, _content(code)) * 4 >= size * 3:
      l.add("restates-code", c.start, "translates the next statement")
  if c.kind == <block> && c.start <= 20:
    int verb_count = 0
    foreach String word in words:
      if _among(word, verbs): verb_count++
    if verb_count >= 5 || _code_spans(text) >= 5:
      l.add("module-header-inventory", c.start,
            "the module header inventories the implementation")
  if c.kind != <doc>: return
  String tier = _tier(l.path)
  if tier == "contract" || tier == "internal":
    l.add("doc-comment-tier", c.start, %"doc comment in a $tier module")
  if text.contains("@param") || text.contains("@return") ||
     lint_phrase(text, "Parameters:") || lint_phrase(text, "Returns:"):
    l.add("doc-boilerplate", c.start, "parameter or return boilerplate")
  if code && code.startswith("static") && !isalnum((unsigned char) code[6]) &&
     code[6] != '_':
    l.add("doc-on-static", c.start, "doc comment on a private static helper")
  if next > c.end + 1:
    l.add("detached-doc", c.start, "doc comment detached from its declaration")

/* Paragraphs of six or more words that recur in the file's comments. A doc
   comment's first paragraph, its summary, is not compared. */
static void _repeated_prose(Lint l, Comment *all, int n):
  Map owners = {}
  for (int at = 0; at < n; at++):
    List parts = all[at].text.split("\n\n")
    if all[at].kind == <doc>: parts = parts.cdr()
    foreach String part in parts:
      String normal = _normal(part).lower()
      if _words(normal).len() < 6: continue
      if !(normal in owners): owners[normal] = []
      Array starts = owners[normal]
      starts.push(all[at].start)
  foreach Var (part, starts) in owners:
    Array each = starts
    if each.len() < 2: continue
    foreach Var start in each:
      l.add("repeated-prose", start.int(),
            "repeats prose elsewhere in the file")

/** Runs the comment rules over `l`. */
void Lint.comment_rules(Lint l):
  Comment *all = Scope.calloc(l.count + 1, sizeof(Comment))
  int n = _collect(l, all)
  Array lines = []
  foreach String line in l.text.split("\n"):
    lines.push(line)
  for (int at = 0; at < n; at++):
    int next = all[at].end + 1
    for (; next <= lines.len(); next++):
      String text = lines[next - 1]
      if text.strip(NULL): break
    _comment(l, all[at], lines, next)
    if at + 1 < n && all[at].kind == <doc> && all[at + 1].kind == <doc> &&
       l.prev(all[at + 1].first) == all[at].last:
      l.add("stacked-doc", all[at].start, "stacked doc comments")
  _repeated_prose(l, all, n)
