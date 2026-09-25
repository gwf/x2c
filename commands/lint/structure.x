#pragma indent
/*  structure.x -- rules for source structure worth a deletion review

    Each rule marks a place to read, not a defect: a switch that repeats a
    table's order, identifiers an enum, a table, and a switch all repeat,
    field-by-field and whole-struct copies, paired lifecycle functions,
    functions dense with counters or cleanup calls, and functions whose
    control and call sequences nearly repeat another's. Two rules compare
    every file on the command line: a type no other file mentions, and a
    function body that another file repeats.
*/
#include "lint.x"
#include <ctype.h>
#include <string.h>

#pragma private

static const List pair_words = %(
  ("acquire" "release") ("begin" "commit") ("begin" "rollback")
  ("pin" "unpin") ("open" "dispose")
)

static const List stat_words = %(
  "stat" "stats" "statistics" "count" "counter" "hits" "misses" "total"
)

static const List cleanup_words = %(
  "free" "dispose" "release" "cleanup" "close" "unpin" "rollback"
)

static const List route_words = %(
  "if" "else" "for" "while" "switch" "case" "match" "return"
)

static const List branch_words = %("if" "for" "while" "switch" "match")

static int _among(String word, List words):
  foreach String each in words:
    if each == word: return 1
  return 0

static int _among_folded(String word, List words):
  foreach String each in words:
    if !strcasecmp(each, word): return 1
  return 0

static int _is(Lint l, int at, String text) =>
  at >= 0 && at < l.count && l.tokens[at].text == text

static int _line(Lint l, Var at) => l.tokens[at.int()].line

static int _last_line(Lint l, Var end) => l.end_line(l.prev(end.int()))

/* Same-named field transfers `a.f = b.f;` and whole copies through a
   pointer, `*a = b;` or `a = *b;`. */
static void _copies(Lint l, List function):
  Var (key, start, body, end) = function
  String name = lint_name(function)
  int transfers = 0, whole = 0
  for (int at = body.int(); at < end.int(); at = l.next(at)):
    int dot = l.next(at), field = l.next(dot), eq = l.next(field)
    int right = l.next(eq), dot2 = l.next(right), field2 = l.next(dot2)
    if l.tokens[at].type == <ident> && _is(l, dot, ".") &&
       l.tokens[field].type == <ident> && _is(l, eq, "=") &&
       l.tokens[right].type == <ident> && _is(l, dot2, ".") &&
       _is(l, field2, l.tokens[field].text) && _is(l, l.next(field2), ";"):
      transfers++
    int left = _is(l, at, "*") ? l.next(at) : at
    int assign = l.next(left)
    int value = _is(l, l.next(assign), "*") ? l.next(l.next(assign)) :
      l.next(assign)
    if (left != at || value != l.next(assign)) && !_is(l, l.prev(at), "*") &&
       l.tokens[left].type == <ident> && _is(l, assign, "=") &&
       l.tokens[value].type == <ident> && _is(l, l.next(value), ";"):
      whole++
  if transfers || whole:
    l.add("struct-copy", _line(l, start),
          %"$transfers field transfers and $whole whole copies in $name")

/* The counter updates and cleanup calls in one function: a counter word
   before an assignment on its line, and a call to a release-like name. */
static void _bookkeeping(Lint l, List function):
  Var (key, start, body, end) = function
  String name = lint_name(function)
  int stats = 0, cleanup = 0
  for (int at = body.int(); at < end.int(); at = l.next(at)):
    Token t = l.at(at)
    if !lint_word(t): continue
    if _among(t.text, cleanup_words) && _is(l, l.next(at), "("): cleanup++
    if !_among_folded(t.text, stat_words): continue
    int last = -1
    for (int k = l.next(at); k < end.int() && l.tokens[k].type != <;> &&
         l.tokens[k].line == t.line; k = l.next(k)):
      String op = l.tokens[k].text
      if lint_code(l.at(k)) && (op.contains("=") || op == "++" || op == "--"):
        last = k
    if last < 0: continue
    stats++
    at = last
  if stats >= 5 || cleanup >= 5:
    l.add("manual-bookkeeping", _line(l, start),
          %"$stats statistics sites and $cleanup cleanup calls in $name")

/* The id of `word` in `ids`, which numbers words as they first appear. */
static int _id(Map ids, String word):
  if !(word in ids): ids[word] = ids.len()
  return ids[word]

/* The control words, then the called names, of one function body, as ids
   from `ids`. */
static Array _route(Lint l, List function, Map ids):
  Var (key, start, body, end) = function
  String name = lint_name(function)
  Array controls = [], calls = []
  for (int at = body.int(); at < end.int(); at = l.next(at)):
    Token t = l.at(at)
    if !lint_word(t): continue
    if _among(t.text, route_words): controls.push(_id(ids, t.text))
    if _is(l, l.next(at), "(") && !_among(t.text, branch_words):
      calls.push(_id(ids, t.text))
  foreach Var call in calls:
    controls.push(call)
  return controls

/* The number of elements `difflib.SequenceMatcher` matches between `a`
   and `b`: the longest common run, earliest first, then recursively the
   runs to either side. */
static int _matched(Array a, int alo, int ahi, Array b, int blo, int bhi):
  if alo >= ahi || blo >= bhi: return 0
  int best = 0, besti = alo, bestj = blo
  int *lengths = Scope.calloc(bhi - blo + 1, sizeof(int))
  int *next = Scope.calloc(bhi - blo + 1, sizeof(int))
  for (int i = alo; i < ahi; i++):
    for (int j = blo; j < bhi; j++):
      int k = a[i] == b[j] ? (j > blo ? lengths[j - blo - 1] : 0) + 1 : 0
      next[j - blo] = k
      if k > best:
        best = k
        besti = i - k + 1
        bestj = j - k + 1
    int *swap = lengths
    lengths = next, next = swap
  if !best: return 0
  return best + _matched(a, alo, besti, b, blo, bestj) +
    _matched(a, besti + best, ahi, b, bestj + best, bhi)

/* Whether two routes share at least 80% of their elements in order. */
static int _similar(Array a, Array b):
  int total = a.len() + b.len()
  return a.len() && b.len() &&
    _matched(a, 0, a.len(), b, 0, b.len()) * 10 >= total * 4

/* Groups of three or more functions whose routes are similar, joined
   through similar pairs. */
static void _routes(Lint l):
  Array functions = [], routes = []
  Map ids = {}
  foreach List function in l.functions:
    Array route = _route(l, function, ids)
    if route.len() < 3: continue
    functions.push(function)
    routes.push(route)
  int n = functions.len()
  int *group = Scope.calloc(n + 1, sizeof(int))
  for (int i = 0; i < n; i++): group[i] = i
  for (int i = 0; i < n; i++):
    for (int j = i + 1; j < n; j++):
      if group[i] == group[j] || !_similar(routes[i], routes[j]): continue
      int from = group[j], to = group[i]
      for (int k = 0; k < n; k++):
        if group[k] == from: group[k] = to
  for (int root = 0; root < n; root++):
    Array names = []
    int first = 0, shortest = 0
    for (int k = 0; k < n; k++):
      if group[k] != root: continue
      List function = functions[k]
      Var (key, start, body, end) = function
      String name = lint_name(function)
      int lines = _last_line(l, end) - _line(l, body) + 1
      if !first: first = _line(l, start)
      if !shortest || lines < shortest: shortest = lines
      names.push(name)
    if names.len() < 3: continue
    l.add("repeated-routes", first,
          %"${names.len()} functions share at least 80% of control and " +
          %"call tokens: ${names.join(", ")}")

/* Functions of one file named as the two halves of a lifecycle, such as
   `acquire` and `release`. */
static void _lifecycles(Lint l):
  Map lowered = {}, seen = {}
  foreach List function in l.functions:
    lowered[lint_name(function).lower()] = function
  foreach List pair in pair_words:
    String left = pair.car(), right = pair.cadr()
    foreach List function in l.functions:
      String name = lint_name(function), low = name.lower()
      int at = low.rfind(left)
      if at < 0: continue
      char *rest = low
      rest += at + left.len()
      String mate = String.new_len(low, at) + right + String.new(rest)
      if !(mate in lowered): continue
      List other = lowered[mate]
      String other_name = lint_name(other)
      List key = name < other_name ? %($name $other_name) :
        %($other_name $name)
      if key in seen: continue
      seen[key] = 1
      Var start = function.cadr(), other_start = other.cadr()
      int line = _line(l, start), other_line = _line(l, other_start)
      l.add("lifecycle-pair", line < other_line ? line : other_line,
            %"paired $left/$right functions ${key.car()} and ${key.cadr()}")

/* A top-level `struct`, `enum`, or `protocol` definition at `at`, with an
   optional `static` or `typedef` before it. Returns the index of its name,
   or -1. */
static int _type_name(Lint l, int at):
  while _is(l, at, "static") || _is(l, at, "typedef"): at = l.next(at)
  Token t = l.at(at)
  if !_is(l, at, "struct") && !_is(l, at, "enum") && !_is(l, at, "protocol"):
    return -1
  int name = l.next(at)
  if l.tokens[name].type != <ident> || !_is(l, l.next(name), "{"): return -1
  return name

/* An `enum` table, an array table, and a switch that share three or more
   identifiers, and a switch of eight or more sequential cases that assign
   an index into a table declared above it. */
static void _tables(Lint l):
  Array enums = [], tables = [], switches = []
  int depth = 0
  for (int at = 0; at < l.count; at = l.next(at)):
    Token t = l.at(at)
    if t.type == <"{"> && !l.quoted[at]: depth++
    else if t.type == <"}"> && !l.quoted[at] && depth: depth--
    if l.quoted[at]: continue
    int first = l.first[t.line] == at
    int name = first && depth == 0 ? _type_name(l, at) : -1
    if name >= 0 && _is(l, l.prev(name), "enum"):
      enums.push(%($name ${l.next(name)}))
    if t.type == <ident> && _is(l, l.next(at), "[") &&
       _is(l, l.next(l.partner[l.next(at)]), "=") &&
       _is(l, l.next(l.next(l.partner[l.next(at)])), "{") && first == 0:
      tables.push(%($at ${l.next(l.next(l.partner[l.next(at)]))}))
    if t.text == "switch" && _is(l, l.next(at), "("):
      int open = l.next(l.partner[l.next(at)])
      if _is(l, open, "{"): switches.push(%($at $open))
  foreach List entry in enums:
    Var (name, open) = entry
    Map words = _words(l, open.int())
    foreach List table in tables:
      Var (table_name, table_open) = table
      Map shared = {}
      foreach Var (word, value) in _words(l, table_open.int()):
        if word in words: shared[word] = 1
      if shared.len() < 3: continue
      foreach List sw in switches:
        Var (switch_at, switch_open) = sw
        int count = 0
        foreach Var (word, value) in _case_words(l, switch_open.int()):
          if word in shared: count++
        if count < 3: continue
        int line = l.tokens[name.int()].line
        int others = l.tokens[table_name.int()].line
        l.add("enum-table-switch", line < others ? line : others,
              %"$count identifiers recur in enum " +
              %"${l.tokens[name.int()].text}, table " +
              %"${l.tokens[table_name.int()].text}, and a switch")

/* The identifiers between the bracket at `open` and its partner. */
static Map _words(Lint l, int open):
  Map words = {}
  for (int at = open; at <= l.partner[open]; at = l.next(at)):
    if l.tokens[at].type == <ident>: words[l.tokens[at].text] = 1
  return words

/* The names after `case` in the switch body opened at `open`. */
static Map _case_words(Lint l, int open):
  Map words = {}
  for (int at = open; at <= l.partner[open]; at = l.next(at)):
    int name = l.next(at)
    if _is(l, at, "case") && l.tokens[name].type == <ident> &&
       _is(l, l.next(name), ":"):
      words[l.tokens[name].text] = 1
  return words

/** Runs the structure rules that read one file. */
void Lint.structure_rules(Lint l):
  foreach List function in l.functions:
    _copies(l, function)
    _bookkeeping(l, function)
  _routes(l)
  _lifecycles(l)
  _tables(l)

/* A function body with comments and literals as spaces and each run of
   space as one, as the duplicate-body rule compares it. */
static String _body_text(Lint l, List function):
  Var (key, start, body, end) = function
  Buffer out = $auto(Buffer.new(0))
  for (int at = body.int() + 1; at < end.int() - 1; at++):
    Token t = l.at(at)
    int blank = t.type == <space> || t.type == <comment> || lint_text(t)
    if blank:
      if out.len() && out.get(out.len() - 1) != ' ': out.write_char(' ')
      continue
    out.write_len(l.text + t.pos, t.len)
  return out.str().strip(NULL)

/** Runs the rules that compare the `count` files in `lints`: a top-level
    type that no other file mentions, and a function body of five or more
    lines that another file repeats word for word.
*/
void lint_corpus_rules(Lint *lints, int count):
  Map mentions = {}, bodies = {}
  for (int index = 0; index < count; index++):
    Lint l = lints[index]
    for (int at = 0; at < l.count; at++):
      if l.tokens[at].type != <ident>: continue
      String word = l.tokens[at].text
      if !(word in mentions): mentions[word] = {}
      Map files = mentions[word]
      files[l.path] = 1
  for (int index = 0; index < count; index++):
    Lint l = lints[index]
    for (int at = 0; at < l.count; at = l.next(at)):
      if l.first[l.tokens[at].line] != at: continue
      int name = _type_name(l, at)
      if name < 0: continue
      Map files = mentions[l.tokens[name].text]
      if files.len() > 1: continue
      int close = l.partner[l.next(name)], members = 0
      String kind = l.tokens[l.prev(name)].text
      for (int k = l.next(name); k < close; k = l.next(k)):
        members += kind == "enum" ? l.tokens[k].type == <","> :
          l.tokens[k].type == <;>
      l.add("internal-type", l.tokens[at].line,
            %"$kind ${l.tokens[name].text} has $members members and no " +
            "use outside its file")
    foreach List function in l.functions:
      Var (key, start, body, end) = function
      String name = lint_name(function)
      String text = _body_text(l, function)
      if text.len() < 80 || _last_line(l, end) - _line(l, start) + 1 < 5:
        continue
      if !(text in bodies): bodies[text] = []
      Array owners = bodies[text]
      owners.push(%($index $name ${_line(l, start)}))
  foreach Var (text, owners) in bodies:
    Array entries = owners
    Map files = {}
    foreach List entry in entries:
      files[lints[entry.car().int()].path] = 1
    if files.len() < 2: continue
    foreach List entry in entries:
      Var (index, name, line) = entry
      lints[index.int()].add("duplicate-function-body", line.int(),
        %"${entries.len()} functions in ${files.len()} files have the " +
        %"same body as $name")
