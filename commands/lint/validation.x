#pragma indent
/*  validation.x -- rules for validation that repeats an established fact

    Each rule reads the tokens of the functions the compiler parsed,
    `Lint.functions`. Five rules find a check after an operation that never
    returns on failure: a `return` after `report_error`, a `return` after
    raising a shared Error cause from `lib/error-macros.xmacro`, a fallback
    around such a raise, a null test of a fresh `[]` or `{}`, and a length
    test after growth. The scored rules weigh a function's manual List
    shape tests, diagnostics, and validator name; a function is reported
    when its strongest reason scores 3 or more. `validation-framework`
    joins validator helpers that call each other, and `silent-shape-guard`
    reports a shape test that quietly skips or substitutes a value.
*/
#include "lint.x"
#include <ctype.h>
#include <string.h>

#pragma private

static const List validator_words = %(
  "check" "compatible" "require" "valid" "validate" "validator" "verify"
  "well_formed"
)

static const List trust_boundaries = %(
  "Ast.try_sequence" "Compiler.rebuild_protocols" "_transform_cast"
  "_transform_defer_stmt" "_transform_return"
)

static int _among(String word, List words):
  foreach String each in words:
    if each == word: return 1
  return 0

static int _is(Lint l, int at, String text) =>
  at >= 0 && at < l.count && l.tokens[at].text == text

/* The causes `lib/error-macros.xmacro` lists as never returning, the
   atoms of its `error.nonreturning.causes` list. */
static Map _shared_causes(void):
  static Map causes
  if causes: return causes
  causes = {}
  Path file = "lib/error-macros.xmacro"
  String text = file.exists() ? file.read_text() : ""
  int at = text.find("error.nonreturning.causes '(")
  if at < 0: return causes
  int open = text.find_within("(", at, -1)
  int close = text.find_within(")", open, -1)
  String list = String.new_len((char *) text + open + 1, close - open - 1)
  foreach String line in list.split("\n"):
    foreach String cause in line.split(" "):
      if cause: causes[cause] = 1
  return causes

/* The word that starts the quoted form opened at `open`. */
static String _cause(Lint l, int open):
  char *start = l.text + l.tokens[open].pos + l.tokens[open].len
  while isspace((unsigned char) *start): start++
  char *end = start
  while isalnum((unsigned char) *end) || *end == '_' || *end == '-': end++
  return String.new_len(start, end - start)

/* The first `;` at or after `at`, or `end`. */
static int _semicolon(Lint l, int at, int end):
  while at < end && l.tokens[at].type != <;>: at = l.next(at)
  return at

/* Whether the statement that holds `at` is followed by `return`. */
static int _then_return(Lint l, int at, int end):
  int semi = _semicolon(l, at, end)
  return semi < end && _is(l, l.next(semi), "return")

/* The shared cause a `raise` at `at` names, or NULL. */
static String _raised(Lint l, int at):
  int open = l.next(at)
  if !_is(l, at, "raise") || !_is(l, open, "%("): return NULL
  String cause = _cause(l, open)
  return cause in _shared_causes() ? cause : NULL

/* Whether the tokens at `at` start a manual shape test: `.car(`, `.cdr(`,
   `.cadr(` and its relatives, `.len(`, `.is(<list>)`, `is <list>` or
   `is List` with or without `not`, or a `try_...parts(` call. */
static int _shape(Lint l, int at):
  Token t = l.at(at)
  int open = l.next(at)
  if t.type != <ident>: return 0
  if at && l.tokens[at - 1].text == "." && _is(l, open, "("):
    String name = t.text
    int n = name.len(), letters = n >= 3 && n <= 6 && name[0] == 'c' &&
      name[n - 1] == 'r'
    for (int k = 1; letters && k < n - 1; k++):
      letters = name[k] == 'a' || name[k] == 'd'
    if letters || name == "len": return 1
    if name == "is": return _is(l, l.next(open), "<list>")
  if t.text == "is" && !(at && l.tokens[at - 1].text == "."):
    int next = _is(l, open, "not") ? l.next(open) : open
    return _is(l, next, "<list>") || _is(l, next, "List")
  return t.text.startswith("try_") && t.text.endswith("parts") &&
    _is(l, open, "(")

/* Whether the tokens at `at` test a List's head tag: `.car()` then `==`,
   `!=`, `is`, or `is not`, then a Symbol literal. */
static int _tag_check(Lint l, int at):
  if !_is(l, at, "car") || !_is(l, at - 1, ".") ||
     !_is(l, l.next(at), "(") || !_is(l, l.next(l.next(at)), ")"):
    return 0
  int op = l.next(l.next(l.next(at)))
  if _is(l, op, "is") && _is(l, l.next(op), "not"): op = l.next(op)
  if !_is(l, op, "==") && !_is(l, op, "!=") && !_is(l, op, "is") &&
     !_is(l, op, "not"):
    return 0
  return l.tokens[l.next(op)].type == <lit-symbol>

/* Whether the word at `at` calls a name that holds `fail` or `error` after
   its first letter. */
static int _report(Lint l, int at):
  Token t = l.at(at)
  if !lint_word(t) || !_is(l, l.next(at), "("): return 0
  char *rest = t.text
  rest++
  return strcasestr(rest, "fail") || strcasestr(rest, "error")

/* Returns the index after the tokens at `at` that spell `name`, which may
   be `Owner.member`, or -1. */
static int _spells(Lint l, int at, String name):
  List parts = name.split(".")
  foreach String part in parts:
    if !_is(l, at, part): return -1
    at = l.next(at)
    if part != parts.last().string():
      if !_is(l, at, "."): return -1
      at = l.next(at)
  return at

/* Whether the tokens `from` to `to` call `name`, not as a member. */
static int _calls(Lint l, int from, int to, String name):
  for (int at = from; at < to; at++):
    if at && (l.tokens[at - 1].text == "." || l.tokens[at - 1].text == "->"):
      continue
    int after = _spells(l, at, name)
    if after > 0 && _is(l, after, "("): return 1
  return 0

/* A word counts only between `.`, `_`, or the ends of `name`. */
static int _validator_name(String name):
  foreach String word in validator_words:
    int n = word.len()
    for (char *at = name; at && *at; at++):
      if strncasecmp(at, word, n): continue
      if (at == name || at[-1] == '.' || at[-1] == '_') &&
         (!at[n] || at[n] == '_'):
        return 1
  return 0

/* The source text of the tokens from `from` to `to` without spaces. */
static String _compact(Lint l, int from, int to):
  String text = ""
  for (int at = from; at <= to; at = l.next(at)): text += l.tokens[at].text
  return text

/* A test `if (owner.len() != n) return` after `n = owner.len() + 1;` and
   growth of `owner`. */
static int _growth_check(Lint l, int from, int to):
  String code = _compact(l, from, l.prev(to))
  for (int at = from; at < to; at = l.next(at)):
    if !_is(l, at, "if") || !_is(l, l.next(at), "("): continue
    int close = l.partner[l.next(at)]
    if close < 0 || !_is(l, l.next(close), "return"): continue
    String test = _compact(l, l.next(at), close)
    foreach String size in %("len()" "length"):
      int op = test.find(%".$size!=")
      if op < 0: continue
      int begin = op
      while begin > 0 && (isalnum((unsigned char) test[begin - 1]) ||
                          test[begin - 1] == '_' || test[begin - 1] == '.'):
        begin--
      char *name = test + op + size.len() + 3, *stop = name
      while isalnum((unsigned char) *stop) || *stop == '_': stop++
      String owner = String.new_len(test + begin, op - begin)
      String expected = String.new_len(name, stop - name)
      if !owner || !expected ||
         !code.contains(%"$expected=$owner.$size+1;"):
        continue
      foreach String grow in %("append" "push" "insert"):
        if code.contains(%"$owner.$grow("): return 1
  return 0

/* A fresh `[]` or `{}` assigned to a name that a later
   `if ((void *) name == NULL)` tests. */
static int _fresh_null_guard(Lint l, int from, int to):
  for (int at = from; at < to; at++):
    Token t = l.at(at)
    if t.type != <ident> || !_is(l, l.next(at), "="): continue
    int open = l.next(l.next(at))
    String text = l.tokens[open].text
    if text != "[" && text != "{" && text != "%[" && text != "%{": continue
    int close = l.partner[open]
    if close < 0 || l.next(open) != close || !_is(l, l.next(close), ";"):
      continue
    String guard = %"if((void*)${t.text}==NULL)"
    for (int k = close; k < to; k = l.next(k)):
      if _is(l, k, "if") && _is(l, l.next(k), "(") &&
         _compact(l, k, l.partner[l.next(k)]) == guard:
        return 1
  return 0

/* Whether the token at `at` begins an unconditional statement. */
static int _statement_start(Lint l, int at):
  String before = l.tokens[l.prev(at)].text
  return before == ";" || before == "{" || before == "}" || before == ":"

/* The reasons one function earns, with the score of each, as
   `(SCORE CODE MESSAGE)` rows. */
static List _reasons(Lint l, List function):
  Var (key, start, body, end) = function
  String name = lint_name(function)
  int from = start.int(), to = end.int()
  Array rows = []
  int shapes = 0, branches = 0, reports = 0
  int report_return = 0, raise_return = 0, fallback = 0
  for (int at = from; at < to; at = l.next(at)):
    Token t = l.at(at)
    shapes += _shape(l, at)
    reports += _report(l, at)
    if t.text == "if" && _is(l, l.next(at), "("): branches++
    if t.text == "report_error" && _is(l, at - 1, ".") &&
       _is(l, l.next(at), "("):
      int receiver = at
      while _is(l, l.prev(receiver), "."):
        receiver = l.prev(l.prev(receiver))
      int semi = _semicolon(l, at, to)
      report_return |= _is(l, l.prev(semi), ")") &&
        _is(l, l.next(semi), "return") && _statement_start(l, receiver)
    if _raised(l, at) && _then_return(l, at, to) && _statement_start(l, at):
      raise_return = 1
    if t.text == "fallback" && _is(l, at - 1, ".") && _is(l, at - 2, "error"):
      int open = l.next(at)
      if _is(l, open, "(") && l.partner[open] > 0 &&
         _raised(l, l.next(l.partner[open])):
        fallback = 1
  if report_return:
    rows.push(%(7 "return-after-report-error"
                "return follows non-returning report_error"))
  if raise_return:
    rows.push(%(7 "return-after-raise"
                "return follows a non-returning shared Error cause"))
  if fallback:
    rows.push(%(7 "fallback-shared-cause"
                "fallback wraps a non-returning shared Error cause"))
  if _fresh_null_guard(l, from, to):
    rows.push(%(7 "fresh-literal-null-guard"
                "null guard checks a fresh Array or Map literal"))
  if _growth_check(l, from, to):
    rows.push(%(7 "growth-check"
                "checks whether a non-returning growth operation succeeded"))
  int validator = _validator_name(name)
  if reports && shapes >= 3 && branches >= 2:
    String why = "diagnostics are built around manual List or AST shape "
      "checks"
    rows.push(%(4 "shape-diagnostics" $why))
  else if shapes >= 3 && branches >= 2:
    rows.push(%(2 "manual-shape-checks"
                "manual List or AST shape checks may be one static match"))
  if validator && reports:
    rows.push(%(2 "validator-diagnostics"
                "validator-like helper emits diagnostics"))
  else if validator && shapes >= 2:
    rows.push(%(1 "validator-shape"
                "validator-like helper inspects structural shape"))
  if reports && _calls(l, body.int(), to, name):
    rows.push(%(3 "recursive-validator"
                "diagnostic validator recursively walks its input"))
  return rows.list_free()

static int _line(Lint l, Var at) => l.tokens[at.int()].line

static int _last_line(Lint l, Var end) => l.end_line(l.prev(end.int()))

static List _rows(Map reasons, String name):
  Var rows
  return reasons.try_get(name, &rows) ? rows : NULL

/* Validator helpers that call each other, joined into components; each
   component of 40 or more lines that is named like a validator and is
   either several functions or recursive is reported at its first line. */
static void _frameworks(Lint l, Map reasons):
  Array names = []
  Map member = {}
  foreach List function in l.functions:
    String name = lint_name(function)
    foreach List row in _rows(reasons, name):
      Var code = row.cadr()
      if _among(code, %("shape-diagnostics" "validator-diagnostics"
                        "validator-shape" "recursive-validator")):
        member[name] = function
    if name in member: names.push(name)
  Map component = {}
  foreach String name in names:
    component[name] = name
  foreach String name in names:
    List function = member[name]
    Var (name2, start, body, end) = function
    foreach String other in names:
      if other == name || !_calls(l, start.int(), end.int(), other): continue
      String a = component[name], b = component[other]
      if a == b: continue
      foreach String each in names:
        if component[each].string() == b: component[each] = a
  Map done = {}
  foreach String name in names:
    String root = component[name]
    if root in done: continue
    done[root] = 1
    Array group = []
    int lines = 0, first = 0, recursive = 0, validator = 0
    foreach String other in names:
      if component[other].string() != root: continue
      List function = member[other]
      Var (name2, start, body, end) = function
      int line = _line(l, start)
      lines += _last_line(l, end) - line + 1
      if !first || line < first: first = line
      validator |= _validator_name(other)
      foreach List row in _rows(reasons, other):
        recursive |= row.cadr().string() == "recursive-validator"
      group.push(other)
    if !validator || lines < 40 || group.len() < 2 && !recursive: continue
    l.add("validation-framework", first,
          %"$lines lines of connected validators: ${group.join(", ")}")

/* The action a silent guard's consequence takes, or NULL. */
static String _action(Lint l, int from, int to):
  for (int at = from; at < to; at = l.next(at)):
    if _is(l, at, "continue") && _is(l, l.next(at), ";"): return "continue"
  foreach String constant in %("NULL" "0"):
    for (int at = from; at < to; at = l.next(at)):
      int value = l.next(at)
      if _is(l, at, "return") && _is(l, value, constant) &&
         _is(l, l.next(value), ";"):
        return %"return $constant"
  for (int at = from; at < to; at = l.next(at)):
    int value = l.next(at), semi = _semicolon(l, at, to)
    if !_is(l, at, "return") || semi >= to || value == semi: continue
    if l.next(value) == semi && lint_word(l.at(value)):
      return %"return ${l.tokens[value].text}"
    return "return fallback"
  for (int at = from; at < to; at = l.next(at)):
    int next = l.next(at)
    if l.tokens[at].type == <ident> && _is(l, next, "=") &&
       !_is(l, l.next(next), "=") && _semicolon(l, next, to) < to:
      return "use default"
  return NULL

/* A push, append, insert, or indexed store: state a skip leaves half built. */
static int _partial(Lint l, int from, int to):
  for (int at = from; at < to; at = l.next(at)):
    Token t = l.at(at)
    if _is(l, at - 1, ".") && _among(t.text, %("push" "append" "insert")) &&
       _is(l, l.next(at), "("):
      return 1
    if t.text == "]" && l.tokens[l.next(at)].text[0] == '=' &&
       l.partner[at] >= 0 && l.partner[at] + 1 < at:
      return 1
  return 0

/* Shape guards whose consequence continues, returns a fallback, or uses a
   default, outside the functions that trust external input. */
static void _silent_guards(Lint l, List function):
  Var (key, start, body, end) = function
  String name = lint_name(function)
  String text = name
  if _among(text, trust_boundaries) || text.startswith("_macro_sdk_") ||
     l.path.endswith("src/collect.x") && text.contains("artifact"):
    return
  int to = end.int()
  for (int at = start.int(); at < to; at = l.next(at)):
    if !_is(l, at, "if") || !_is(l, l.next(at), "("): continue
    int open = l.next(at), close = l.partner[open], shape = 0
    if close < 0: continue
    for (int k = open; k < close; k = l.next(k)):
      shape |= _shape(l, k) || _tag_check(l, k)
    if !shape: continue
    int first = l.next(close), last = _semicolon(l, first, to) + 1
    if _is(l, first, "{"): last = l.partner[first]
    String action = _action(l, first, last < 0 ? to : last)
    if !action: continue
    if action == "continue" && _partial(l, start.int(), to):
      action = "continue with partial state"
    l.add("silent-shape-guard", l.tokens[at].line,
          %"impossible shape can silently $action in $text")

/* Static `List.match` results read through `assoc` in the same branch:
   `binding = ...match(%(...))` whose binding never escapes. */
static void _static_match_captures(Lint l, List function):
  Var (key, start, body, end) = function
  String name = lint_name(function)
  int from = start.int(), to = end.int(), reads = 0, line = 0
  Map seen = {}
  for (int at = from; at < to; at = l.next(at)):
    if !_is(l, at, "match") || !_is(l, at - 1, ".") ||
       !_is(l, l.next(at), "(") || !_is(l, l.next(l.next(at)), "%("):
      continue
    int assign = at
    while assign > from && !_is(l, assign, "=") &&
          l.tokens[assign].type != <;> && !_is(l, assign, "{") &&
          !_is(l, assign, "}"):
      assign = l.prev(assign)
    int bind = l.prev(assign)
    if !_is(l, assign, "=") || l.tokens[bind].type != <ident>: continue
    String binding = l.tokens[bind].text
    if binding in seen: continue
    seen[binding] = 1
    int count = 0, escapes = 0
    for (int k = at; k < to; k = l.next(k)):
      if !_is(l, k, binding) || _is(l, k - 1, "."): continue
      int before = l.prev(k), after = l.next(k)
      if _is(l, after, ".") && _is(l, l.next(after), "assoc") &&
         l.tokens[l.next(l.next(l.next(after)))].text.startswith("<?"):
        count++
      if _is(l, before, "return") || _is(l, before, "=") && _is(l, after, ";"):
        escapes = 1
      if (_is(l, before, "(") || _is(l, before, ",")) &&
         (_is(l, after, ")") || _is(l, after, ",")):
        escapes = 1
    if !count || escapes: continue
    reads += count
    int binding_line = l.tokens[bind].line
    if !line || binding_line < line: line = binding_line
  if reads:
    l.add("static-match-capture", line,
          %"$reads local assoc read(s) unpack static List.match bindings")

/** Runs the validation rules over the functions of `l`. */
void Lint.validation_rules(Lint l):
  Map reasons = {}
  foreach List function in l.functions:
    String name = lint_name(function)
    Var start = function.cadr()
    List rows = _reasons(l, function)
    reasons[name] = rows
    int score = 0
    foreach List row in rows:
      if row.car().int() > score: score = row.car().int()
    if score >= 3:
      foreach List row in rows:
        Var (score, code, message) = row
        l.add(code, _line(l, start), %"$message in $name")
    _silent_guards(l, function)
    _static_match_captures(l, function)
  _frameworks(l, reasons)
