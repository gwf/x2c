#pragma indent
/*  declarations.x -- rules over the declarations the compiler parsed

    A unit's top-level forms, their token spans, and its function
    definitions come from the compiler's parse of the unit, so a declaration
    is what the parser read, never a pattern in the text. The compiler's
    tokens for a unit in brace syntax are the tokens `Lint` scanned, so a
    span indexes both.
*/
#include "generate.x"
#include "lint.x"
#include <ctype.h>
#include <string.h>

#pragma private

static const SymbolSet qualifier_words =
  %<<const volatile restrict register struct union enum>>

/* Whether `path` has a directory component named `name`. */
static int _under(String path, String name) =>
  path.startswith(%"$name/") || path.contains(%"/$name/")

/* The line of the first `(` among the compiler's tokens `start` to `end`.
   Returns 0 for a macro invocation, whose declarations are generated, and
   for a `meta` declaration, which declares a compile-time operation. */
static int _prototype_line(Compiler c, int start, int end):
  struct Token *tokens = c.tokenizer.tokens
  while tokens[start].type == <space> || tokens[start].type == <comment>:
    start++
  if tokens[start].text == "meta" || tokens[start].text[0] == '$': return 0
  for (int at = start; at < end; at++):
    if tokens[at].type == <"(">: return tokens[at].line
  return tokens[start].line

/* x2c collects the whole unit, so a prototype of a function the unit
   defines is redundant; `lib/` keeps the style guide's runtime exceptions
   for review. A prototype of another unit's function is repository policy:
   `src/` relies on complete-unit collection. */
static void _prototype(Lint l, int line, int defined):
  if defined && _under(l.path, "lib"):
    l.add("same-file-forward-declaration", line,
          "retain only for genuine co-recursion or literal shallow "
          "collection")
  else if defined:
    l.add("forward-declaration", line,
          "the unit defines this function and x2c collects the whole unit")
  else if _under(l.path, "src"):
    l.add("src-forward-declaration", line,
          "user-space src code must rely on complete-unit collection")
  else:
    l.add("runtime-forward-declaration", line,
          "retain only for cross-unit co-recursion or literal shallow "
          "collection")

/* Reports each written function prototype. */
static void _prototypes(Lint l, Compiler c, List ast):
  Map defined = {}, facts = c.semantic_binding_facts()
  foreach List node in ast:
    match node:
      case %(function ? (bind ?binding ?) ?): defined[binding] = 1
  foreach List node in ast:
    Var span
    if !facts.try_get(%(definition-span $node), &span): continue
    match node:
      case %(declare ?type (bindings *items)):
        Var (start, end) = span.list()
        int line = _prototype_line(c, start.int(), end.int())
        foreach List item in items:
          match item:
            case %(bind ?binding ?):
              List single = %(declare $type (bindings $item))
              if line && single.type_from_ast().is_function():
                _prototype(l, line, binding in defined)

/* Facts about each line of one function that a rename leaves unchanged,
   read from the code that remains once comments and literals are masked:
   the change in `(` and `[` depth, whether a comment touches the line, the
   first code character, whether the code ends a statement, opens a
   continuation, or closes with `)`, and whether the line starts a control
   header. */
typedef struct Lines:
  int count
  int *delta, *comment, *code, *ends, *opener, *closer, *control
  char *lead
Lines

static inline int _masked(Token t) =>
  t.type == <space> || t.type == <comment> || lint_text(t)

static int *_ints(int n) => Scope.calloc(n, sizeof(int))

/* Collects the facts of lines `first_line` onward from the tokens `from`
   up to `to`. */
static Lines _lines(Lint l, int from, int to, int first_line):
  int n = l.tokens[to - 1].line - first_line + 1
  Lines lines = {n, _ints(n), _ints(n), _ints(n), _ints(n), _ints(n),
                 _ints(n), _ints(n), Scope.calloc(n, 1)}
  for (int at = from; at < to; at++):
    Token t = l.at(at)
    int line = t.line - first_line
    if t.type == <comment>:
      int end = l.end_line(at) - first_line
      for (; line <= end && line < n; line++):
        lines.comment[line] = 1
      continue
    if _masked(t): continue
    if lint_opens(t) && strchr("([", t.text[t.len - 1]): lines.delta[line]++
    if t.type == <")"> || t.type == <"]">: lines.delta[line]--
    if !lines.code[line]:
      int next = l.next(at)
      lines.lead[line] = t.text[0]
      lines.control[line] = lint_control(t) ||
        t.text == "else" && next < to && lint_control(l.at(next))
    lines.code[line] = 1
    lines.ends[line] = strchr(";{}:", t.text[t.len - 1]) != NULL
    lines.closer[line] = t.type == <")">
    lines.opener[line] = t.text == "else" ||
      strchr("([=", t.text[t.len - 1]) != NULL ||
      t.text == ">" && l.tokens[at - 1].text == "="
  return lines

static String _join(String left, String right):
  int n = left.len()
  if n && (left[n - 1] == '(' || left[n - 1] == '['): return left + right
  return %"$left $right"

/* The number of lines that `text[start, stop)` takes when each line joins
   its predecessor wherever the result stays within 79 columns. A line that
   opens a call, an expression body, an assignment, or a control body joins
   its successor only when that completes the statement. */
static int _rejoined(Lines lines, Array text, int start, int stop):
  String first = text[start], whole = first.strip(NULL)
  int indent = first.len() - first.lstrip(NULL).len()
  for (int at = start + 1; at < stop; at++):
    String line = text[at]
    whole = _join(whole, line.strip(NULL))
  if indent + whole.len() <= 79: return 1
  String previous = first.rstrip(NULL)
  int result = 1, depth = 0, control = lines.control[start]
  int opener = lines.opener[start], closer = lines.closer[start]
  for (int at = start + 1; at < stop; at++):
    String line = text[at]
    depth += lines.delta[at - 1]
    int head = control && !depth && closer
    String joined = _join(previous, line.strip(NULL))
    if joined.len() <= 79 && !(head && result > 1) &&
       (at == stop - 1 || !(head || opener)):
      previous = joined
      if !lines.code[at]: continue
    else:
      previous = line.rstrip(NULL)
      result++
    opener = lines.opener[at]
    closer = lines.closer[at]
  return result

/* The lines saved when the text `before` becomes `after`: each wrapped
   statement without a comment is rejoined both ways. */
static int _saved(Lines lines, Array before, Array after):
  int saved = 0, start = 0, depth = 0
  for (int at = 0; at < lines.count; at++):
    depth += lines.delta[at]
    int open = lines.code[at] && lines.lead[at] != '#' && !lines.ends[at]
    if depth > 0 || open: continue
    int clean = at > start
    for (int line = start; clean && line <= at; line++):
      if lines.comment[line]: clean = 0
      if line > start && strchr(")]}#", lines.lead[line]): clean = 0
    if clean:
      int shrink = _rejoined(lines, before, start, at + 1) -
                   _rejoined(lines, after, start, at + 1)
      if shrink > 0: saved += shrink
    start = at + 1
    depth = 0
  return saved

/* Whether the token at `at` refers to the variable `name`: an identifier
   that is not a member name, in code or unquoted in a Lisp form. */
static int _reference(Lint l, int at, String name):
  Token t = l.at(at)
  if t.type != <ident> || t.text != name: return 0
  String before = at ? l.tokens[at - 1].text : NULL
  if l.quoted[at]: return before == "$" || before == "@"
  return before != "." && before != "->"

static int _referenced(Lint l, int from, int to, String name):
  for (int at = from; at < to; at++):
    if _reference(l, at, name): return 1
  return 0

/* The identifier words of each parameter between `open` and `close`,
   without qualifiers. */
static List _parameter_words(Lint l, int open, int close):
  Array parameters = [], words = []
  int depth = 0
  for (int at = open + 1; at < close; at++):
    Token t = l.at(at)
    if !depth && t.type == <",">:
      parameters.push(words.list_free())
      words = []
      continue
    if lint_opens(t): depth++
    else if lint_closes(t): depth--
    if lint_word(t) && !qualifier_words.contains(t.type):
      words.push(t.text)
  parameters.push(words.list_free())
  return parameters.list_free()

static Array _split(String text):
  Array lines = []
  foreach String line in text.split("\n"): lines.push(line)
  return lines

/* The subject's short name: the first letter of `owner`, lower case,
   repeated until no reference among the tokens `from` to `to` uses it. */
static String _short_name(Lint l, String owner, int from, int to):
  char letter = 0
  for (char *ch = owner; !letter && *ch; ch++):
    if isalpha((unsigned char) *ch): letter = tolower((unsigned char) *ch)
  int length = 1
  while _referenced(l, from, to, String.new_fill(letter, length)): length++
  return String.new_fill(letter, length)

/* Reports a method definition `Owner.member(Owner name, ...)` whose subject
   parameter would save lines under the style guide's short name. The
   declarator is the tokens `start` to `body`, and the definition ends
   before `end`. A symmetric operation, whose other parameters include an
   `Owner`, has no subject. */
static void _subject(Lint l, int start, int body, int end):
  int open = start
  while open < body && l.tokens[open].type != <"(">: open++
  if open >= body || open < 3 || l.tokens[open - 2].type != <"."> ||
     l.tokens[open - 1].type != <ident> || l.tokens[open - 3].type != <ident>:
    return
  String owner = l.tokens[open - 3].text
  List parameters = _parameter_words(l, open, l.partner[open])
  List subject = parameters.car()
  if subject.len() != 2 || subject.car().string() != owner: return
  foreach List other in parameters.cdr():
    if other && other.car().string() == owner: return
  String old = subject.cadr()
  int from = l.first[l.tokens[open].line]
  String name = _short_name(l, owner, from, end)
  if old == String.new_fill(name[0], old.len()): return
  int line_start = l.tokens[from].pos - (l.tokens[from].col - 1)
  int stop = l.tokens[end - 1].pos + l.tokens[end - 1].len
  String before = String.new_len(l.text + line_start, stop - line_start)
  Buffer after = $auto(Buffer.new(0))
  after.write_len(l.text + line_start, l.tokens[from].pos - line_start)
  for (int at = from; at < end; at++):
    Token t = l.at(at)
    if _reference(l, at, old): after.write(name)
    else: after.write_len(l.text + t.pos, t.len)
  Lines lines = _lines(l, from, end, l.tokens[from].line)
  int saved = _saved(lines, _split(before), _split(after))
  if saved <= 0: return
  String plural = saved > 1 ? "s" : ""
  l.add("subject-parameter-name", l.tokens[open].line,
        %"name the $owner subject $name to save $saved line$plural " +
        %"(found $old)")

/* The bindings the functions of `ast` declare as plain values: locals and
   parameters without pointer or array modifiers, which callers own. */
static Map _plain_locals(List ast):
  Map locals = {}
  foreach List node in ast:
    match node:
      case %(function *):
        foreach List hit in node.search(%(bind (binding ?id ?) ())):
          locals[hit.assoc(<?id>)] = 1
  return locals

/* Whether the body uses the pointer parameter `p` only through `*p` and
   `p->field`, so it never tests, stores, indexes, or passes the address. */
static int _alias_uses(List body, Var p):
  int uses = body.search(%(ident (binding $p ?))).len()
  int through =
    body.search(%(op (!quote *) (expr ? (ident (binding $p ?))))).len() +
    body.search(%(op -> (expr ? (ident (binding $p ?))) ?)).len()
  return uses && uses == through

/* Whether argument `index` of every call is `&v` for a caller's plain
   variable `v`. */
static int _alias_arguments(List calls, int index, Map locals):
  foreach List call in calls:
    List args = call.assoc(<*args>)
    Var argument = args[index]
    match argument:
      case %(expr ? (op & (expr ? (ident (binding ?v ?))))):
        if !(v in locals): return 0
      default:
        return 0
  return 1

/* Reports a `T *p` parameter of a static function that `&` of one caller
   variable always supplies and that the body only dereferences. Buffers
   (`char` and `void` pointees), functions used other than by a direct call,
   and functions other units can call keep their pointer spelling. */
static void _reference_parameters(Lint l, Compiler c, List ast):
  Map locals = _plain_locals(ast), lines = {}
  foreach List row in c.definition_rows(ast):
    match row:
      case %(function ?name ? ? ? ?line *): lines[name] = line
  foreach List node in ast:
    match node:
      case %(function ?modifiers
             (bind (binding ?fn ?function) ((fnmod (params *params))))
             ?body):
        if !(<static> in modifiers) || !(function in lines): continue
        List calls = ast.search(%(call (expr ? (ident (binding $fn ?)))
                                        (args *args)))
        if !calls || ast.search(%(ident (binding $fn ?))).len() != calls.len():
          continue
        int index = 0
        foreach List param in params:
          match param:
            case %(param ?type (bind (binding ?p ?name) (*))):
              if !(<char> in type) && !(<void> in type) &&
                 _alias_uses(body, p) &&
                 _alias_arguments(calls, index, locals):
                l.add("reference-parameter", lines[function].int(),
                      %"`$name` aliases one caller variable; declare it " +
                      "as a `&` reference parameter")
          index++

/** Runs the rules that read the compiler's parse of the unit: `ast` and
    the facts `c` recorded while parsing it.
*/
void Lint.declaration_rules(Lint l, Compiler c, List ast):
  _prototypes(l, c, ast)
  if l.selected.contains("reference-parameter"):
    _reference_parameters(l, c, ast)
  foreach List row in c.definition_rows(ast):
    match row:
      case %(function ? ?name ? ? ? ? ? source (?(int start) ?(int body))
             (? ?(int end) *)):
        if l.layout: continue
        l.functions.push(%($name $start $body $end))
        if l.selected.contains("subject-parameter-name"):
          _subject(l, start, body, end)
