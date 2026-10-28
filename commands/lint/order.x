#pragma indent
/*  order.x -- conservative function reading-order candidates

    Ordinary authored definitions can exchange places within a run whose
    gaps contain only comments and whitespace. Every other source form is
    a boundary. The compiler supplies identities, references and spans;
    tokens only locate those spans and the boundaries between them.
*/
#include "lint.x"
#include "generate/generate.x"
#include <stdlib.h>
#include <string.h>

static typedef struct OrderFunction:
  String path, display
  Var identity
  Map references
  int start, end, line, public, unit, movable
OrderFunction

static typedef struct OrderGraph:
  OrderFunction *functions
  int count
  char *edges, *reach
OrderGraph

/** Checks physical source files in each configured view, including members of
    a parsed module. Member findings keep their own path and suppressions.
    Missing source/meta spans never become guessed definitions or edges.
*/
void Lint.order_rules(Lint l, Compiler c, List ast, List rows, Map seen):
  if !("function-reading-order" in l.selected): return
  OrderGraph unit = {0}
  OrderFunction *all = unit.functions =
    xcalloc(ast.len() + 1, sizeof(OrderFunction))
  int count = unit.count = _order_functions(c, ast, rows, all)
  char *edges = unit.edges = xcalloc(count * count, 1)
  char *reach = unit.reach = xcalloc(count * count, 1)
  for (int from = 0; from < count; from++):
    for (int to = 0; to < count; to++):
      edges[from * count + to] = all[to].identity in all[from].references
      reach[from * count + to] = from == to || edges[from * count + to]
  _order_closure(reach, count)
  String own = Path.resolved_absolute(l.path)
  Map paths = {}
  paths[own] = 1
  for (int at = 0; at < count; at++):
    if all[at].path: paths[all[at].path] = 1
  foreach List marker in c.line_markers:
    if marker ~= %(? ? ?(String file) ? ? ? ?):
      paths[Path.resolved_absolute(file)] = 1
  Array ordered = []
  foreach String path in paths.keys(): ordered.push(path)
  ordered.sort()
  foreach String path in ordered:
    int member = path != own
    Lint target = l
    if member:
      target = Lint.new(path, ((Path) path).read_text(),
                        { "function-reading-order": 1 })
    OrderFunction *functions = xcalloc(count + 1, sizeof(OrderFunction))
    int included = 0
    for (int at = 0; at < count; at++):
      if all[at].path == path && all[at].movable:
        functions[included++] = all[at]
    _order_findings(target, functions, included, unit, seen)
    if member:
      target.suppression_rules()
      target.print()
    xfree(functions)
  xfree(edges)
  xfree(reach)
  xfree(all)

/* Definitions are joined by their compiler binding spelling; dependency
   edges below use the binding identity itself, including function values. */
static int _order_functions(Compiler c, List ast, List rows,
                            OrderFunction *functions):
  Map indexes = {}
  int count = 0
  foreach List node in ast:
    match node:
      case %(function ? (bind (binding ?identity ?name) ?) ?value):
        OrderFunction fn = {0}
        fn.display = c.unprefixed(name)
        fn.identity = identity
        fn.references = {}
        Ast.collect_binding_references(value, fn.references)
        fn.unit = count
        indexes[name] = count
        functions[count++] = fn
  foreach List row in rows:
    if row ~= %(function ?(String name) ?(String display) *):
      if name in indexes: functions[indexes[name].int()].display = display
    match row:
      case %(function ?(String name) ?(String display) ? ? ? ? ?private
          source (?(int declared) ?(int body))
          (?(int start) ?(int end) ?hidden)):
        if start < 0 || end <= start || end > c.tokenizer.tokens.len():
          continue
        struct Token *tokens = c.tokenizer.tokens
        if !tokens[declared].len: continue
        int at = indexes[name]
        OrderFunction *fn = functions + at
        if !_order_span(c, start, end, *fn): continue
        fn.display = display
        fn.public = !private.int() && !hidden.int()
        fn.movable = _order_ordinary(c, start, body, end)
  return count

/* The physical interval of a source definition, without synthetic layout
   tokens at either end. A definition cannot straddle source files. */
static int _order_span(Compiler c, int start, int end, OrderFunction &fn):
  struct Token *tokens = c.tokenizer.tokens
  while start < end && (!tokens[start].len ||
      tokens[start].type == <space> || tokens[start].type == <comment>):
    start++
  while end > start && (!tokens[end - 1].len ||
      tokens[end - 1].type == <space> || tokens[end - 1].type == <comment>):
    end--
  if start == end: return 0
  fn.path = Path.resolved_absolute(c.text_source(tokens[start].pos, fn.start))
  String last = Path.resolved_absolute(c.text_source(
    tokens[end - 1].pos + tokens[end - 1].len - 1, fn.end))
  fn.end++
  if c.unit_script && !c.line_markers &&
      fn.path == Path.resolved_absolute(c.unit_script.path):
    int newline = c.text.find("\n")
    int shift = c.unit_script.shebang.len() -
      (newline < 0 ? c.text.len() : newline)
    fn.start += shift
    fn.end += shift
  return fn.path == last && fn.end > fn.start

/* Meta definitions and decorated/generated forms are not ordinary moves.
   Directives inside a body can also change later source interpretation. */
static int _order_ordinary(Compiler c, int start, int body, int end):
  struct Token *tokens = c.tokenizer.tokens
  int parameters = 0
  for (int at = start; at < end; at++):
    Token token = tokens + at
    if token.type == <preproc>: return 0
    if at >= body || token.type == <space> || token.type == <comment>:
      continue
    if token.type == <"(">: parameters = 1
    if token.text == "meta": return 0
    if !parameters && (token.text[0] == '$' || token.text[0] == '@'):
      return 0
  return 1

static void _order_closure(char *reach, int count):
  for (int via = 0; via < count; via++):
    for (int from = 0; from < count; from++):
      if !reach[from * count + via]: continue
      for (int to = 0; to < count; to++):
        if reach[via * count + to]: reach[from * count + to] = 1

/* One placement finding per run and at most one finding per caller.
   A recursive component has no internal dependency order to enforce. */
static void _order_findings(Lint l, OrderFunction *fn, int count,
                             OrderGraph &unit, Map seen):
  qsort(fn, count, sizeof(OrderFunction), _order_compare)
  int *regions = xcalloc(count, sizeof(int))
  char *reported = xcalloc(count, 1)
  for (int at = 0; at < count; at++):
    for (int token = 0; token < l.count; token++):
      if l.tokens[token].pos >= fn[at].start:
        fn[at].line = l.tokens[token].line
        break
    if at:
      regions[at] = regions[at - 1] +
        !_order_gap(l, fn[at - 1].end, fn[at].start)
  int private_at = -1, placed = 0
  for (int at = 0; at < count; at++):
    if !at || regions[at] != regions[at - 1]:
      private_at = -1
      placed = 0
    if !fn[at].public && private_at < 0: private_at = at
    if fn[at].public && private_at >= 0 && !placed:
      _order_add(l, seen, fn[at].line,
        %"public $(fn[at].display) follows private " +
        %"$(fn[private_at].display) in the same ordinary-function run")
      reported[at] = 1
      placed = 1
  for (int from = 0; from < count; from++):
    if reported[from]: continue
    for (int to = 0; to < from; to++):
      int forward = fn[from].unit * unit.count + fn[to].unit
      int reverse = fn[to].unit * unit.count + fn[from].unit
      if regions[from] != regions[to] || unit.reach[reverse]: continue
      int public_path = fn[from].public && fn[to].public && unit.reach[forward]
      int private_edge = !fn[from].public && !fn[to].public &&
        unit.edges[forward] &&
        !_order_introduced(unit, fn[from], fn[to])
      if !public_path && !private_edge: continue
      _order_add(l, seen, fn[from].line,
        %"caller $(fn[from].display) follows dependency $(fn[to].display): " +
        _order_path(unit, fn[from].unit, fn[to].unit))
      break
  fprintf(stderr, "%s: function-reading-order coverage: %d ordinary "
          "definitions, %d runs; cross-boundary and compile-time order "
          "unassessed\n",
          l.path, count, count ? regions[count - 1] + 1 : 0)
  xfree(regions)
  xfree(reported)

static int _order_compare(const void *left, const void *right):
  const OrderFunction *a = left, *b = right
  return a.start - b.start

/* A source run has no intervening declarations, expansions, directives,
   or executable statements. Section labels do not impose order. */
static int _order_gap(Lint l, int start, int end):
  for (int at = 0; at < l.count; at++):
    Token token = l.at(at)
    if token.pos >= end: break
    if token.pos + token.len <= start: continue
    if token.type != <space> && token.type != <comment>: return 0
  return 1

/* Repeated configured views still run; deduplicate only identical findings,
   so an earlier incomplete view never hides a later file's definitions. */
static void _order_add(Lint l, Map seen, int line, String message):
  if !l.add("function-reading-order", line, message): return
  List key = $(Path.resolved_absolute(l.path), line, message)
  if key in seen:
    l.findings.pop()
  else:
    key.promote()
    seen[key] = 1

/* An earlier reader already explains a shared helper, including another
   member of its recursive group. Self-reference alone does not. Nonmovable
   meta definitions may still be known users. */
static int _order_introduced(OrderGraph &unit, OrderFunction from,
                             OrderFunction to):
  for (int at = 0; at < unit.count; at++):
    if at == to.unit || !unit.functions[at].path ||
        unit.functions[at].path != from.path ||
        unit.functions[at].start >= from.start ||
        !unit.edges[at * unit.count + to.unit]:
      continue
    return 1
  return 0

/* Reports the actual bound path, including private intermediates. */
static String _order_path(OrderGraph &unit, int from, int to):
  int count = unit.count
  OrderFunction *fn = unit.functions
  char *edges = unit.edges
  int *prior = xcalloc(count, sizeof(int))
  int *queue = xcalloc(count, sizeof(int))
  for (int at = 0; at < count; at++): prior[at] = -1
  int head = 0, tail = 0
  queue[tail++] = from
  prior[from] = from
  while head < tail && prior[to] < 0:
    int next = queue[head++]
    for (int at = 0; at < count; at++):
      if edges[next * count + at] && prior[at] < 0:
        prior[at] = next
        queue[tail++] = at
  List names = NULL
  for (int at = to; at != from; at = prior[at]):
    names = cons(fn[at].display, names)
  names = cons(fn[from].display, names)
  String path = String.join(" -> ", names)
  xfree(prior)
  xfree(queue)
  return path
