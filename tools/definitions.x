#pragma indent
/*  definitions.x -- what the compiler says a source unit defines

    `gen-api-reference` and `gen-module-catalog` read the rows
    `x2c translate --dump-definitions` prints instead of scanning x2c
    source. `Unit.load` translates the units a batch at a time and keeps each
    row as a `Map` from field name to value, with `span` as a `List` of its
    two offsets. `Prose` normalizes doc comments as the book prints them.
*/
#include "scripting.x"
#include <unistd.h>

/** One unit's projection: `path`, `module` (its opening comment, or NULL),
    and `functions` and `types`, each an `Array` of row `Map`s in the order
    the compiler defines them.
*/
typedef Map Unit

/** The text of a doc comment. */
typedef String Prose

static Map _fields(List row):
  Map fields = {}
  foreach List field in row.cdr():
    Symbol key = field.car()
    fields[key.str()] = key == <span> ? field.cdr() : field.cadr()
  return fields

static Unit _unit(String path):
  Unit unit = {}
  unit["path"] = path
  unit["module"] = NULL
  unit["functions"] = []
  unit["types"] = []
  return unit

/* The units of one dump, each starting at its `unit` row. The dump is read
   as one list: each read scans the rest of its text. */
static List _units(String dump):
  Array units = []
  Unit unit = NULL
  Lisp lisp = Lisp.new()
  defer Lisp.destroy(lisp)
  unsigned cursor = 0
  Var rows = void
  Lisp.read(lisp, %"($dump)", cursor, rows)
  foreach List row in rows.list():
    Symbol kind = row.car()
    if kind == <unit>:
      unit = _unit(row.cadr())
      units.push(unit)
    else if kind == <module>: unit["module"] = row.cadr()
    else if kind == <function>: unit["functions"].array().push(_fields(row))
    else: unit["types"].array().push(_fields(row))
  return units.list_free()

/** Returns the `Unit` of each path in `paths`, in order, as the compiler
    `x2c` translates it from the directory `root`. The paths are dealt into
    one batch per processor, and the batches translate at once.
    Raises: `<cmd-fail>` when a unit does not translate.
*/
Array Unit.load(Path x2c, Path root, List paths):
  Array pending = paths, jobs = [], units = []
  int batches = (int) sysconf(_SC_NPROCESSORS_ONLN)
  if batches > pending.len(): batches = pending.len()
  Path work = Path.temp_dir()
  defer work.remove_tree()
  for (int batch = 0; batch < batches; batch++):
    Array share = []
    int first = batch * pending.len() / batches
    int last = (batch + 1) * pending.len() / batches
    for (int at = first; at < last; at++): share.push(pending[at])
    jobs.push(%($x2c translate --dump-definitions @{share.list_free()}).job()
              .options({dir: root, stdout: work.join(%"$batch"),
                        stderr: <capture>}).start())
  Map found = {}
  for (int batch = 0; batch < batches; batch++):
    Job job = jobs[batch]
    job.check()
    foreach Unit unit in _units(work.join(%"$batch").read_text()):
      found[unit["path"]] = unit
  foreach String path in paths: units.push(found[path])
  return units

/** Returns `unit`'s public definitions as the reference names them, in line
    order: `(name signature line doc)`, where a written definition keeps its
    declarator and a Unit macro's product is spelled from its type. A
    definition without authored source is omitted. `doc` is normalized, or
    NULL.
*/
List Unit.callables(Unit unit):
  Array found = []
  foreach Map row in unit["functions"].array():
    if row["static"].integer(): continue
    String display = row["display"], doc = row["doc"]
    int line = row["line"].integer()
    if row["origin"] == <alias>: continue
    if row["origin"] == <source>:
      found.push(%($display ${row["text"]} $line ${Prose.normalize(doc)}))
      continue
    if line == 1 && !doc: continue
    found.push(%($display ${Unit.signature(display, row["type"], row["params"])}
                 $line ${Prose.normalize(doc)}))
  return found.sort_by(%!(List item) => item.caddr()).list_free()

// Type rendering follows the canonical Type lists of unit interfaces.

static int _base_word(Var part) =>
  %(void char short int long unsigned signed float double const volatile)
    .contains(part)

static String _joined(String left, String right) =>
  %"$left $right".strip(NULL)

static int _needs_parens(Var target):
  if target is not <list>: return 0
  List node = target
  if !node || node.car() is not <list>: return 0
  List inner = node.car()
  return inner && (inner.car() == <func> || inner.car() == <dim>)

static String _render(Var node, String declarator)

static String _parameters(List entries):
  Array rendered = []
  foreach Var entry in entries:
    if entry == <void> || List.equal(entry, %(void)): return "void"
    if List.equal(entry, %(...)): rendered.push("...")
    else: rendered.push(_render(entry, ""))
  return String.join(", ", rendered.list_free())

static Var _target(List rest) => rest.cdr() ? rest : rest.car()

static String _render(Var node, String declarator):
  if node is not <list>: return _joined(node.str(), declarator)
  List parts = node
  if !parts: raise %(api-fatal (why "empty type node"))
  if !parts.cdr(): return _render(parts.car(), declarator)
  int words = 1
  foreach Var part in parts:
    if !_base_word(part): words = 0
  if words:
    return _joined(String.join(" ", parts.map(%!(Var part) => part.str())),
                   declarator)
  Var head = parts.car()
  List rest = parts.cdr()
  if head == <*>:
    String inner = "*" + declarator
    Var target = _target(rest)
    if _needs_parens(target): inner = %"($inner)"
    return _render(target, inner)
  if head == <&> || head == <opt-ref>:
    String mark = head == <&> ? "&" : "&?"
    return _render(_target(rest), mark + declarator)
  if head == <const> || head == <volatile>:
    return _joined(head.str(), _render(_target(rest), declarator))
  if head == <struct> || head == <union> || head == <enum>:
    return _joined(%"$head ${rest.car()}", declarator)
  List form = head is <list> ? head : NULL
  if !form || (form.car() != <func> && form.car() != <dim>):
    raise %(api-fatal (why ${%"unknown type node: ${node.repr()}"}))
  if form.car() == <func>:
    return _render(_target(rest),
                   %"$declarator(${_parameters(form.cadr())})")
  List extent = form.cadr()
  return _render(_target(rest), %"$declarator[${extent ? extent.car() : ""}]")

/** Spells a function from its canonical `type` and parameter `names`, as
    `RETURN DISPLAY(PARAMETERS)`.
*/
String Unit.signature(String display, List type, List names):
  List form = type.car(), parameters = form.cadr()
  List tail = type.cdr()
  while tail.car() == <inline> || tail.car() == <static> ||
        tail.car() == <extern>:
    tail = tail.cdr()
  Array spelled = []
  List name = names
  foreach Var parameter in parameters:
    if !List.equal(parameter, %(void)):
      spelled.push(_render(parameter, name ? name.car().str() : ""))
    name = name ? name.cdr() : NULL
  String text = String.join(", ", spelled.list_free())
  if !text: text = "void"
  return %"${_render(tail, "")} $display($text)"

/** Returns the body of a doc comment with an optional `*` gutter removed
    and its lines dedented, never reflowed. Returns NULL for an empty body.
*/
String Prose.normalize(String body):
  if !body: return NULL
  Array lines = []
  foreach String line in body.split("\n"):
    String text = line.strip(NULL)
    if text == "*": lines.push("")
    else if text && text.startswith("* "): lines.push(text[2:])
    else: lines.push(line)
  int cut = -1
  for (int at = 1; at < lines.len(); at++):
    String line = lines[at]
    if !line.strip(NULL): continue
    int indent = line.len() - line.lstrip(NULL).len()
    if cut < 0 || indent < cut: cut = indent
  Array kept = []
  for (int at = 0; at < lines.len(); at++):
    String line = lines[at]
    if !at: line = line.strip(NULL)
    else if cut > 0 && line.len() >= cut: line = line[cut:]
    kept.push(line ? line.rstrip(NULL) : "")
  while kept.len() && !kept[0].string().strip(NULL): kept.remove(0)
  while kept.len() && !kept[-1].string().strip(NULL): kept.pop()
  if !kept.len(): return NULL
  return String.join("\n", kept.list_free())

/** Returns the lines of `text` wrapped greedily at `width` columns at its
    spaces, never breaking a word.
*/
List Prose.wrap(String text, int width):
  Array lines = []
  String line = NULL
  foreach String word in text.split(" "):
    if !word: continue
    if line && line.len() + 1 + word.len() <= width: line = %"$line $word"
    else:
      if line: lines.push(line)
      line = word
  if line: lines.push(line)
  return lines.list_free()

/** Returns the paragraphs of a module's opening comment, without its
    delimiters.
*/
List Prose.paragraphs(String comment):
  if !comment: return NULL
  int opener = comment.startswith("/**") ? 3 : 2
  String body = Prose.normalize(comment[opener:comment.len() - 2])
  if !body: return NULL
  Array paragraphs = [], lines = []
  foreach String line in body.split("\n"):
    if line.strip(NULL): lines.push(line)
    else if lines.len():
      paragraphs.push(String.join("\n", lines.list_free()))
      lines = []
  if lines.len(): paragraphs.push(String.join("\n", lines.list_free()))
  return paragraphs.list_free()

/** Returns the one-line summary of `unit` that the catalog and reference
    print: the first paragraph of its module comment after any ` -- `.
*/
String Unit.summary(Unit unit):
  List paragraphs = Prose.paragraphs(unit["module"])
  if !paragraphs:
    return %"Current source module `${Path.new(unit["path"]).basename()}`."
  String first = Regex.compile("\\s+").replace_all(paragraphs.car(), " ")
  first = first.strip(NULL)
  List divided = first.partition(" -- ")
  if divided.cadr(): first = divided.caddr()
  return first.rstrip(". ") + "."
