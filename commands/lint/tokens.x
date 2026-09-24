#pragma indent
/*  tokens.x -- rules over written tokens and the lines they occupy

    Each rule reads the token stream of one `Lint`. Comment and string
    tokens are exact, so prose rules read only comments and literals, and
    layout rules never mistake a quoted parenthesis for a bracket.
*/
#include "lint.x"
#include <ctype.h>
#include <string.h>

#pragma private

static const SymbolSet type_words =
  %<<void char short int long float double signed unsigned>>
static const SymbolSet qualifier_words =
  %<<static const unsigned signed long short>>

/* A binary or assignment operator, which the style guide spaces once. */
static int _operator(Token t) =>
  lint_code(t) && strchr("|&+*/=-", t.text[t.len - 1])

/* Returns the text of the line at `*cursor` and advances past it. */
static String _next_line(char **cursor):
  char *start = *cursor, *end = strchr(start, '\n')
  if !end: end = start + strlen(start)
  *cursor = *end ? end + 1 : end
  return String.new_len(start, end - start)

/* Whether a token starting on `line` is a literal. */
static int _line_has_literal(Lint l, int line):
  for (int at = l.first[line]; at >= 0 && at < l.count &&
       l.tokens[at].line == line; at++):
    if lint_text(l.at(at)): return 1
  return 0

/* A row of a stable initializer table: braces around several fields on one
   line, some of them literals. */
static int _table_row(Lint l, int line):
  int at = l.first[line]
  if at < 0 || l.tokens[at].type != <"{">: return 0
  int last = l.line_end(at)
  if l.tokens[last].type == <comment>: last = l.prev(last)
  if l.tokens[last].type == <","> || l.tokens[last].type == <;>:
    last = l.prev(last)
  if l.tokens[last].type != <"}">: return 0
  int commas = 0, literal = 0
  for (int next = at; next <= last; next++):
    Token t = l.at(next)
    if t.type == <",">: commas++
    if lint_text(t) || t.type == <lit-symbol>: literal = 1
  return commas >= 2 && literal

/* Tabs, trailing space, blank runs, width, and ASCII, line by line. */
static void _lines(Lint l):
  char *cursor = l.text ? l.text : ""
  int blank = 0
  for (int line = 1; line <= l.lines; line++):
    String text = _next_line(&cursor)
    int width = text.len()
    if width && strchr(text, '\t'): l.add("tab", line, "tab character")
    if width && isspace((unsigned char) text[width - 1]):
      l.add("trailing-whitespace", line, "trailing whitespace")
    if !text.strip(NULL):
      if blank: l.add("blank-line-stack", line, "consecutive blank line")
      blank = 1
    else:
      blank = 0
    for (int at = 0; at < width; at++):
      if (unsigned char) text[at] > 127:
        l.add("non-ascii", line, "non-ASCII character")
        break
    if width <= 79: continue
    if _table_row(l, line):
      l.add("over-width-table-row", line,
            "verify that indivisible literal fields require this stable row")
    else if _line_has_literal(l, line):
      l.add("over-width-literal", line,
            "verify that preserving observable literal text requires this "
            "width")
    else:
      l.add("over-width", line, %"$width columns")

/* An operator followed by a run of spaces and more code on its line. */
static void _operator_spacing(Lint l):
  int reported = 0
  for (int at = 0; at + 2 < l.count; at++):
    Token t = l.at(at), gap = l.at(at + 1), after = l.at(at + 2)
    if !_operator(t) || gap.type != <space> || gap.len < 2: continue
    if strchr(gap.text, '\n') || strchr(gap.text, '\t'): continue
    if after.type == <comment> || t.line == reported: continue
    l.add("operator-spacing", t.line, "doubled operator spacing")
    reported = t.line

/* A comment line that starts with a run of eight or more `-` or `=`. */
static int _ruler(String text):
  char *ch = text ? text : ""
  int run = 0
  while isspace((unsigned char) *ch): ch++
  for (; *ch == '-' || *ch == '='; ch++): run++
  return run >= 8

static inline int _word_char(int ch) => isalnum(ch) || ch == '_'

/* Whether lower-case `text` contains `phrase` as whole words. */
static int _phrase(String text, String phrase):
  for (int at = text.find(phrase); at >= 0;
       at = text.find_within(phrase, at + 1, -1)):
    int end = at + phrase.len()
    if (!at || !_word_char((unsigned char) text[at - 1])) &&
       !_word_char((unsigned char) text[end]):
      return 1
  return 0

static const List narration_words = %(
  "function to" "convert" "check if" "return" "get" "set" "create" "handle"
  "skip" "remove" "extract" "add" "initialize" "free" "parse" "write" "copy"
  "find" "determine" "update" "open" "close"
)

static const List prose_phrases = %(
  "load bearing" "load-bearing" "it is important to note" "note that"
  "keep in mind" "in order to" "serves to" "leverage" "utilize" "robust"
  "powerful" "seamless" "comprehensive" "elegant" "clearly" "simply"
  "obviously" "just" "deliberately" "honest" "honestly" "on purpose"
  "rather than" "this ensures" "as mentioned above" "we can see"
)

static int _prose(String text):
  String lower = text.lower()
  foreach String phrase in prose_phrases:
    if _phrase(lower, phrase): return 1
  int only = lower.find("not only")
  return only >= 0 && lower.find_within("but also", only, -1) >= 0

/* A line comment that opens with a verb restating the code below it. */
static int _narrates(String body):
  String lower = body.strip(NULL).lower()
  foreach String word in narration_words:
    if lower.startswith(word) &&
       !_word_char((unsigned char) lower[word.len()]):
      return 1
  return 0

/* Narration, stock phrases, and decorated rulers in comments. String
   literals are prose too, for the stock phrases. */
static void _prose_rules(Lint l):
  int reported = 0
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    int comment = t.type == <comment>
    if !comment && !lint_string(t): continue
    if comment && t.text.startswith("//"):
      String body = String.new(t.text + 2)
      if _narrates(body):
        l.add("narration", t.line, "narrates the code; state a decision")
      if _ruler(body): l.add("decorated-ruler", t.line, "decorated ruler")
      if _prose(body) && t.line != reported:
        l.add("prohibited-prose", t.line, "stock phrase")
        reported = t.line
      continue
    int line = t.line
    char *cursor = t.text + (comment ? 2 : 0)
    while *cursor:
      String text = _next_line(&cursor)
      if comment && _ruler(text):
        l.add("decorated-ruler", line, "decorated ruler")
      if _prose(text) && line != reported:
        l.add("prohibited-prose", line, "stock phrase")
        reported = line
      line++

/* The parentheses of a call or signature: a `(` after a name that is not
   a macro invocation. */
static int _call(Lint l, int at):
  if l.tokens[at].type != <"(">: return 0
  int name = l.prev(at)
  if name < 1 || l.tokens[name].text == "foreach": return 0
  String before = l.tokens[name - 1].text
  if l.tokens[name].type != <ident> && before != "." && before != "->":
    return 0
  while name >= 2 && before == "." && l.tokens[name - 2].type == <ident>:
    name -= 2
    before = name ? l.tokens[name - 1].text : NULL
  return before != "$" && before != "@" && before != "%"

/* Whether an argument or parameter between `open` and `close` spans more
   than one line. */
static int _multiline_argument(Lint l, int open, int close):
  int start = -1, depth = 0
  for (int at = open + 1; at <= close; at++):
    Token t = l.at(at)
    if at == close || !depth && t.type == <",">:
      if start >= 0 && l.tokens[start].line != l.end_line(l.prev(at)):
        return 1
      start = -1
      continue
    if lint_opens(t): depth++
    else if lint_closes(t): depth--
    if t.type != <space> && start < 0: start = at
  return 0

/* The width of `open` through `close`, counting each run of space as
   one. */
static int _collapsed(Lint l, int open, int close):
  int width = 0
  for (int at = open; at <= close; at++):
    width += l.tokens[at].type == <space> ? 1 : l.tokens[at].len
  return width

/* The width of the code after `close` on its line, with its separating
   space. */
static int _suffix(Lint l, int close):
  int first = -1, last = -1, line = l.tokens[close].line
  for (int at = l.next(close); at < l.count && l.tokens[at].line == line;
       at = l.next(at)):
    if l.tokens[at].type == <comment>: continue
    if first < 0: first = at
    last = at
  if first < 0: return 0
  return l.tokens[last].pos + l.tokens[last].len - l.tokens[first].pos + 1

static int _has_comment(Lint l, int open, int close):
  for (int at = open; at <= close; at++):
    if l.tokens[at].type == <comment>: return 1
  return 0

/* A wrapped call or signature starts every argument on a continuation line
   two spaces in and keeps the close with the last argument. Quoted Lisp
   forms are data, not calls. */
static void _wrapping(Lint l):
  for (int at = 0; at < l.count; at++):
    if l.quoted[at] || !_call(l, at): continue
    Token t = l.at(at)
    int close = l.partner[at]
    if close < 0 || t.line == l.tokens[close].line: continue
    int open_line = t.line, close_line = l.tokens[close].line
    int next = l.next(at)
    if l.tokens[next].line == open_line:
      l.add("wrapped-opening-line", open_line,
            "move all arguments or parameters to the continuation line")
    else if l.tokens[next].col - 1 != l.indent(open_line) + 2:
      l.add("continuation-indent", l.tokens[next].line,
            "arguments or parameters use a two-space continuation")
    int multiline = _multiline_argument(l, at, close)
    if l.first[close_line] == close && !multiline:
      l.add("standalone-closer", close_line,
            "keep the close and trailer with the final argument or "
            "parameter")
    if multiline || _has_comment(l, at, close): continue
    if t.col - 1 + _collapsed(l, at, close) + _suffix(l, close) <= 79:
      l.add("horizontal-form", open_line,
            "complete call or signature appears to fit horizontally")

/* Returns the name of the declaration that starts at `at`: optional
   qualifiers, a type word, pointer stars, and a name. Returns -1 when the
   tokens are not one. */
static int _declared_name(Lint l, int at):
  while at < l.count && qualifier_words.contains(l.tokens[at].type):
    at = l.next(at)
  if at >= l.count: return -1
  Symbol type = l.tokens[at].type
  if type != <ident> && !type_words.contains(type): return -1
  at = l.next(at)
  while at < l.count && (l.tokens[at].text == "*" ||
                         l.tokens[at].text == "&"):
    at = l.next(at)
  return at < l.count && l.tokens[at].type == <ident> ? at : -1

/* The control header or `else` that owns the brace at `at`, on its line. */
static int _control_brace(Lint l, int at):
  int head = l.prev(at)
  if head < 0 || l.tokens[head].line != l.tokens[at].line: return 0
  Token h = l.at(head)
  if h.text == "else" || h.text == "do": return 1
  if h.type != <")"> || l.partner[head] < 0: return 0
  int word = l.prev(l.partner[head])
  return word >= 0 && l.tokens[word].line == l.tokens[at].line &&
         lint_control(l.at(word))

/* A brace pair around one executable statement after a control header. */
static void _braces(Lint l):
  for (int at = 0; at < l.count; at++):
    int close = l.partner[at]
    if l.tokens[at].type != <"{"> || close < 0 || !_control_brace(l, at):
      continue
    int semicolons = 0, clean = 1
    for (int inner = at + 1; inner < close && clean; inner++):
      Token t = l.at(inner)
      if t.type == <comment> || t.type == <preproc>: clean = 0
      else if t.type == <;>: semicolons++
      else if lint_opens(t) && t.text[t.len - 1] == '{':
        clean = l.quoted[inner] == 2
    if !clean || semicolons != 1 || l.tokens[l.prev(close)].type != <;>:
      continue
    int first = l.next(at), name = _declared_name(l, first)
    if l.tokens[first].text == "if" && l.tokens[l.next(close)].text == "else":
      continue
    if name >= 0 && (l.tokens[l.next(name)].type == <;> ||
                     l.tokens[l.next(name)].text == "="):
      continue
    l.add("one-statement-braces", l.tokens[at].line,
          "omit braces around one executable statement")

/* A declaration without an initializer, assigned on the next line. */
static void _deferred_initialization(Lint l):
  for (int line = 1; line < l.lines; line++):
    int at = l.first[line], next = l.first[line + 1]
    if at < 0 || next < 0: continue
    int name = _declared_name(l, at)
    if name < 0 || l.tokens[l.next(name)].type != <;>: continue
    int after = l.next(l.next(name))
    if after < l.count && l.tokens[after].line == line &&
       l.tokens[after].type != <comment>:
      continue
    Token target = l.at(next)
    if target.col != l.tokens[at].col || target.text != l.tokens[name].text:
      continue
    if l.tokens[l.next(next)].text != "=": continue
    l.add("deferred-initialization", line,
          %"initialize ${target.text} where it becomes meaningful")

/* A control header whose one-statement body would fit on its line. */
static void _short_control_flow(Lint l):
  for (int line = 1; line < l.lines; line++):
    int at = l.first[line], body = l.first[line + 1]
    if at < 0 || body < 0 || !lint_control(l.at(at)): continue
    int open = l.next(at), end = l.line_end(at)
    if l.tokens[open].type != <"("> || l.partner[open] != end: continue
    Token first = l.at(body)
    int last = l.line_end(body)
    if first.type == <comment> || first.type == <preproc>: continue
    if l.tokens[last].type != <;> || first.col <= l.tokens[at].col: continue
    int head = l.tokens[end].pos + 1 - l.tokens[at].pos
    int tail = l.tokens[last].pos + 1 - first.pos
    if l.tokens[at].col - 1 + head + 1 + tail <= 79:
      l.add("short-control-flow", line,
            "the header and its one statement fit on one line")

/* The same zero-argument accessor three times within twelve lines at one
   brace depth. */
static void _repeated_accessors(Lint l):
  Map seen = {}, reported = {}
  int depth = 0, line_depth = 0, line = 0
  for (int at = 0; at + 4 < l.count; at++):
    Token t = l.at(at)
    if t.line != line:
      line = t.line
      line_depth = depth
    if lint_opens(t) && t.text[t.len - 1] == '{': depth++
    else if t.type == <"}"> && depth: depth--
    if l.quoted[at] == 2 || t.type != <ident> ||
       l.tokens[at + 1].type != <"."> || !lint_word(l.at(at + 2)) ||
       l.tokens[at + 3].type != <"("> || l.tokens[at + 4].type != <")">:
      continue
    String call = %"${t.text}.${l.tokens[at + 2].text}()"
    List key = %($line_depth $call)
    if reported.contains(key): continue
    if !seen.contains(key): seen[key] = []
    Array lines = seen[key]
    lines.push(line)
    int count = lines.len()
    if count >= 3 && line - lines[count - 3].int() <= 12:
      l.add("repeated-accessor", lines[count - 3].int(),
            %"$call repeats three times; cache only if pure and stable")
      reported[key] = 1

/* Whether `line` is exactly `puts(STRING);` or `fputs(STRING, stdout);`. */
static int _constant_output(Lint l, int line):
  int at = l.first[line]
  if at < 0: return 0
  String name = l.tokens[at].text
  int open = l.next(at), literal = l.next(open), next = l.next(literal)
  if name != "puts" && name != "fputs" || next >= l.count: return 0
  if l.tokens[open].type != <"("> || l.tokens[literal].type != <lit-char*>:
    return 0
  if name == "fputs":
    if l.tokens[next].type != <","> ||
       l.tokens[l.next(next)].text != "stdout":
      return 0
    next = l.next(l.next(next))
  if l.tokens[next].type != <")"> || l.partner[next] != open: return 0
  int end = l.next(next)
  return end < l.count && l.tokens[end].type == <;> &&
         l.line_end(at) == end

static void _constant_output_runs(Lint l):
  int start = 0, run = 0
  for (int line = 1; line <= l.lines + 1; line++):
    if line <= l.lines && _constant_output(l, line):
      if !run: start = line
      run++
      continue
    if run >= 2:
      l.add("constant-output-run", start,
            %"$run adjacent static output calls; preserve emitted bytes")
    run = 0

/* `!(value is Type)`, which the language spells `value is not Type`. */
static void _negated_is(Lint l):
  for (int at = 0; at + 1 < l.count; at++):
    if l.tokens[at].text != "!" || l.tokens[at + 1].type != <"(">: continue
    int close = l.partner[at + 1], depth = 0, is = 0, other = 0
    for (int inner = at + 2; inner < close; inner++):
      Token t = l.at(inner)
      if lint_opens(t): depth++
      else if lint_closes(t): depth--
      else if depth: continue
      else if t.type == <ident> && t.text == "is": is = 1
      else if t.text == "&&" || t.text == "||" || t.text == "?": other = 1
    if is && !other:
      l.add("negated-is", l.tokens[at].line, "spell the test `is not`")

/** Runs every token rule over `l`. Rules about written braces,
    semicolons, and wrapped statements skip the indentation syntax.
*/
void Lint.token_rules(Lint l):
  _lines(l)
  _operator_spacing(l)
  _prose_rules(l)
  _negated_is(l)
  if l.layout: return
  _wrapping(l)
  _braces(l)
  _deferred_initialization(l)
  _short_control_flow(l)
  _repeated_accessors(l)
  _constant_output_runs(l)
