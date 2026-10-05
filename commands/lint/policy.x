#pragma indent
/*  policy.x -- source signals for the standard's adoption campaign

    Tokens identify spelling candidates. Bound AST references exclude
    called static functions and function values before corpus spelling
    guards exclude names visible in macros, strings, or another input.
*/
#include "lint.x"

#pragma private

static int _runtime(Lint l) =>
  l.path.startswith("src/") || l.path.contains("/src/") ||
  l.path.startswith("lib/") || l.path.contains("/lib/")

static int _empty_constructor(Lint l, int at):
  String name = l.tokens[at].text
  if name != "String" && name != "Array" && name != "Map": return 0
  int dot = l.next(at)
  if !l.token_is(dot, "."): return 0
  int method = l.next(dot)
  if !l.token_is(method, "new"): return 0
  int open = l.next(method)
  if !l.token_is(open, "("): return 0
  int first = l.next(open), close = l.partner[open]
  return name == "String" ? l.token_is(first, "\"\"") &&
    l.next(first) == close : first == close

/* DG-1 permits a qualified report macro in its caller's source file. */
static int _report_macro_end(Lint l, int at):
  if l.quoted[at] || !l.token_is(at, "macro"): return -1
  int open = l.next(at), report = 0
  for (; open < l.count && !l.token_is(open, "("); open = l.next(open)):
    if l.token_is(open, "report") && l.token_is(l.prev(open), "$"):
      report = 1
  if !report || open >= l.count || l.partner[open] < 0: return -1
  int body = l.next(l.partner[open])
  if l.token_is(body, "{"): return l.partner[body]
  if !l.token_is(body, ":"): return -1
  for (int line = l.tokens[body].line + 1; line <= l.lines; line++):
    int first = l.first[line]
    if first >= 0 && l.tokens[first].col <= l.tokens[at].col:
      return l.prev(first)
  return l.count - 1

static void _spellings(Lint l):
  int report_end = -1
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    int end = _report_macro_end(l, at)
    if end > report_end: report_end = end
    int next = l.next(at)
    if !l.quoted[at] && t.text == "}" && l.token_is(next, "else") &&
       l.tokens[next].line == t.line:
      l.add("same-line-else", t.line, "put else on its own line")
    if t.type != <ident>: continue
    if !l.quoted[at] && _empty_constructor(l, at):
      l.add("empty-constructor", t.line, "use the empty value literal")
    if t.text == "x2c.ident" && l.token_is(l.prev(at), "$("):
      l.add("x2c-ident", t.line, "review compile-time name construction")
    if t.text == "defun" && l.token_is(l.prev(at), "$(") && _runtime(l):
      l.add("lisp-defun", t.line, "review Lisp work in compiler or runtime")
    if t.text == "report_error" && !l.quoted[at] && at > report_end &&
       !l.path.endswith("-reports.xmacro") && l.token_is(next, "("):
      int stop = l.partner[next]
      for (int k = l.next(next); k < stop; k = l.next(k)):
        if l.tokens[k].type == <lit-char*> || lint_string(l.at(k)):
          l.add("literal-report-error", t.line,
                "move the literal diagnostic to its report macro owner")
          break

static void _conditions(Lint l):
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    if l.quoted[at] || (t.text != "if" && t.text != "while" &&
                        t.text != "for"): continue
    int open = l.next(at), close = l.partner[open]
    if !l.token_is(open, "(") || close < 0: continue
    int from = l.next(open), to = close
    if t.text == "for":
      for (int k = from; k < close; k = l.next(k)):
        if lint_opens(l.at(k)): k = l.partner[k]
        else if l.token_is(k, ";"):
          from = l.next(k)
          for (to = from; to < close && !l.token_is(to, ";");
               to = l.next(to)) {}
          break
    int assign = 0, read = 0
    for (int k = from; k < to; k = l.next(k)):
      if l.quoted[k] || !lint_code(l.at(k)): continue
      if l.tokens[k].text in %("=" "+=" "-=" "*=" "/=" "%=" "&="
                              "|=" "^=" "<<=" ">>="): assign = 1
      String word = l.tokens[k].text
      if (word == "read" || word.startswith("read_") ||
          word in %("fread" "fgets" "getline" "getdelim" "getc"
                    "getc_unlocked" "fgetc" "getchar" "readdir"
                    "readdir_r")) &&
         l.token_is(l.next(k), "("): read = 1
    if assign && !(t.text != "if" && read):
      l.add("assignment-condition", t.line,
            "review assignment in a condition outside a read loop")

static void _section(Lint l, int start, int end):
  int size = end - start + 1
  if size > 400:
    l.add("long-section", start, %"labeled section spans $size lines")

static void _metrics(Lint l):
  if l.lines > 1500:
    l.add("long-file", 1, %"file spans ${l.lines} lines; review above 1500")
  int start = 0
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    if t.type != <comment> || t.col != 1 ||
       !t.text.startswith("//") || t.text.contains("lint:"): continue
    if t.line > 1 && l.first[t.line - 1] >= 0 ||
       l.first[t.line + 1] >= 0: continue
    String label = t.text[2:].strip(NULL)
    int plain = label.len() > 0
    for (char *ch = label; plain && *ch; ch++):
      if !islower((unsigned char) *ch) && *ch != ' ': plain = 0
    if !plain: continue
    if start: _section(l, start, t.line - 1)
    start = t.line
  if start: _section(l, start, l.lines)

/* Direct switch or match arms stop at the next label at the same bracket
   depth. Nested arms belong to their own dispatcher. */
static void _dispatchers(Lint l):
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    if l.quoted[at] || (t.text != "switch" && t.text != "match"): continue
    int open = l.next(at)
    if l.token_is(open, "("): open = l.next(l.partner[open])
    if !l.token_is(open, "{") || l.partner[open] < 0: continue
    int close = l.partner[open], arm = -1, last = -1
    for (int k = l.next(open); k <= close; k = l.next(k)):
      int label = l.token_is(k, "case") || l.token_is(k, "default")
      if label || k == close:
        if arm >= 0 && last >= arm:
          int lines = l.end_line(last) - l.tokens[arm].line + 1
          if lines > 3:
            l.add("long-dispatch-arm", l.tokens[arm].line,
                  %"dispatcher arm spans $lines lines; review above 3")
        arm = label ? k : -1
      if k == close: break
      if l.tokens[k].type == <comment>: continue
      if lint_opens(l.at(k)) && l.partner[k] >= 0: k = l.partner[k]
      last = k

static void _layout_dispatchers(Lint l):
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    if l.quoted[at] || (t.text != "switch" && t.text != "match"): continue
    int arm = 0, last = 0, column = 0
    for (int line = t.line + 1; line <= l.lines + 1; line++):
      int first = l.first[line]
      if first < 0 && line <= l.lines: continue
      Token next = l.at(first < 0 ? l.count : first)
      int end = line > l.lines || next.col <= t.col
      int label = !end && !l.quoted[first] &&
        (next.text == "case" || next.text == "default")
      if label && !column: column = next.col
      label = label && next.col == column
      if end || label:
        int lines = last - arm + 1
        if arm && lines > 3:
          l.add("long-dispatch-arm", arm,
                %"dispatcher arm spans $lines lines; review above 3")
        arm = label ? line : 0
      if end: break
      if next.type != <comment>: last = l.end_line(l.line_end(first))

/** Runs the adoption signals over authored tokens and function spans. */
void Lint.policy_rules(Lint l):
  _spellings(l)
  _conditions(l)
  _metrics(l)
  if l.layout: _layout_dispatchers(l)
  else: _dispatchers(l)

/* Spelling presence only prevents a candidate; it is not reference proof. */
static int _mentioned(Lint *lints, int count, int owner, List function):
  Var (name, source, emitted, line, start, end) = function
  String display = source
  String member = display.rpartition(".").caddr()
  for (int index = 0; index < count; index++):
    Lint l = lints[index]
    for (int at = 0; at < l.count; at++):
      Token t = l.at(at)
      if index == owner && t.line >= start.int() && t.line <= end.int():
        continue
      if t.type == <space> || t.type == <comment>: continue
      if t.text.contains(emitted) || t.text.contains(display) ||
         member && t.text.contains(member): return 1
  return 0

/** Reports static definitions with no bound reference or corpus spelling. */
void lint_unused_rules(Lint *lints, int count):
  for (int index = 0; index < count; index++):
    foreach List function in lints[index].unused:
      if _mentioned(lints, count, index, function): continue
      Var (name, source, emitted, line, start, end) = function
      lints[index].add("uncalled-static-function", line.int(),
        %"$source has no bound reference in this parsed unit; review " +
        "macro, protocol, native, and other-file uses")
