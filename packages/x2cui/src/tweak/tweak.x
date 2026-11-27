/*  tweak.x -- adjust a running program's literal options (probe)

    Each option a form receives as a literal reaches CUI through a tweak
    call that reports the literal's call site and returns it, or the
    value set for that site and name while tweaking: `Ui.tweak_value`
    for a number, `Ui.tweak_choice` for a member of an enum such as
    `variant: primary`, and `Ui.tweak_color` for a theme colour such as
    `bg: surface`. A box whose call names no id gets one made from its
    call site, and a component is noted with the id CUI gave it, so that
    their rectangles can be found. `ui.tweak_marks()` paints the node
    under the pointer and the chosen one; `ui.tweak_panel()` lists the
    chosen node's literals with editors, and writes one back to its
    source. Tweaking is on when the environment sets X2CUI_TWEAK;
    otherwise each call returns its value and records nothing.
*/

#include "path.x"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* A call site's literals by name, each `(number original used)` or
   `(choice original used names values)` or the same with `color`, where
   `used` is the member's position. */
static Map _tweak_sites = NULL;
// Values set while tweaking, by "file:line:column:name".
static Map _tweak_set = NULL;
/* The nodes drawn this frame and the last whole frame, as (id site), and
   how many each site drew this frame. */
static Array _tweak_nodes = NULL;
static List _tweak_last = NULL;
static Map _tweak_counts = NULL;
static Array _tweak_ids = NULL;
static int _tweak_on = -1;
static String _tweak_chosen = NULL;
static cui_id _tweak_chosen_id = 0;
static String _tweak_note = NULL;

static bool _tweaking(void) {
  if (_tweak_on < 0) {
    _tweak_on = getenv("X2CUI_TWEAK") != NULL;
    _tweak_sites = {};
    _tweak_set = {};
    _tweak_nodes = [];
    _tweak_counts = {};
    _tweak_ids = [];
  }
  return _tweak_on;
}

static String _site(const char *file, int line, int column) =>
  %"$(String.new(file)):$line:$column";

static Var _setting(String site, String name) =>
  _tweak_set[%"$site:$name"];

static Map _literals(String site) {
  Var known = _tweak_sites[site];
  if (!known.is_void()) return known;
  Map literals = {};
  _tweak_sites[site] = literals;
  return literals;
}

/** Returns `value`, the numeric literal option `name` written at `file`,
    `line`, and `column`, or the value set for it while tweaking.
*/
double Ui.tweak_value(Ui ui, const char *file, int line, int column,
                      const char *name, double value) {
  if (!_tweaking()) return value;
  String site = _site(file, line, column), field = String.new(name);
  Var set = _setting(site, field);
  double used = set.is_void() ? value : set.double();
  _literals(site)[field] = %( number $value $used );
  return used;
}

/* The position of the member a choice uses: the one set while tweaking,
   or the one written, `current`. Records the choice. */
static int _choose(Symbol kind, const char *file, int line, int column,
                   const char *name, const char *current, const char **names,
                   int *values, int count) {
  String site = _site(file, line, column), field = String.new(name);
  int written = 0;
  for (int i = 0; i < count; i++)
    if (!strcmp(names[i], current)) written = i;
  Var set = _setting(site, field);
  int used = set.is_void() ? written : set.int();
  Map literals = _literals(site);
  if (literals[field].is_void()) {
    Array spelled = [], numbers = [];
    for (int i = 0; i < count; i++) {
      spelled.push(String.new(names[i]));
      numbers.push(values[i]);
    }
    literals[field] = %( $kind $written $used $(spelled.list())
                         $(numbers.list()) );
  }
  else {
    List old = literals[field];
    literals[field] = %( $kind $written $used $(old[3]) $(old[4]) );
  }
  return used;
}

/** Returns the value of the enum member `current`, the literal option
    `name` written at `file`, `line`, and `column`, or of the member set
    for it while tweaking. `names` and `values` are the enum's members.
*/
int Ui.tweak_choice(Ui ui, const char *file, int line, int column,
                    const char *name, const char *current,
                    const char **names, int *values, int count) {
  int written = 0;
  for (int i = 0; i < count; i++)
    if (!strcmp(names[i], current)) written = i;
  if (!_tweaking()) return values[written];
  return values[_choose(<choice>, file, line, column, name, current, names,
                        values, count)];
}

/** Returns the theme colour `current`, the literal option `name` written
    at `file`, `line`, and `column`, or the colour set for it while
    tweaking. `names` and `values` are CUI's colour tokens.
*/
cui_color Ui.tweak_color(Ui ui, const char *file, int line, int column,
                         const char *name, const char *current,
                         const char **names, int *values, int count) {
  int at = 0;
  for (int i = 0; i < count; i++)
    if (!strcmp(names[i], current)) at = i;
  if (_tweaking())
    at = _choose(<color>, file, line, column, name, current, names, values,
                 count);
  return CUI_TOKEN_COLOR(values[at]);
}

static void _note_node(cui_id id, String site) {
  Var seen = _tweak_counts[site];
  _tweak_counts[site] = (seen.is_void() ? 0 : seen.int()) + 1;
  _tweak_nodes.push(%( $((double) id) $site ));
}

/** Returns an id for a box written at `file`, `line`, and `column` whose
    call names none, unique among this frame's boxes from that site, or
    NULL when not tweaking.
*/
const char *Ui.tweak_id(Ui ui, const char *file, int line, int column) {
  if (!_tweaking()) return NULL;
  String site = _site(file, line, column);
  Var seen = _tweak_counts[site];
  String id = %"tweak:$site#$(seen.is_void() ? 0 : seen.int())";
  _tweak_ids.push(id);
  _note_node(ui.make_id(id), site);
  return id;
}

/** Notes the component a form at `file`, `line`, and `column` has just
    drawn, when CUI gave it an id other than `before`, the last id before
    the call. A component CUI gives no id, such as text, is not noted.
*/
void Ui.tweak_component(Ui ui, const char *file, int line, int column,
                        cui_id before) {
  if (!_tweaking()) return;
  cui_id id = ui.last_id();
  if (id && id != before) _note_node(id, _site(file, line, column));
}

static cui_rect _node_rect(Ui ui, List node) =>
  ui.get_rect((cui_id) node[0].double());

// The smallest node drawn under the pointer, or NULL.
static List _node_under(Ui ui) {
  cui_vec2 p = ui.mouse_pos();
  List best = NULL;
  float area = 0;
  foreach (List node in _tweak_nodes) {
    cui_rect r = _node_rect(ui, node);
    if (r.w <= 0 || p.x < r.x || p.y < r.y || p.x >= r.x + r.w ||
        p.y >= r.y + r.h)
      continue;
    if (!best || r.w * r.h < area) {
      best = node;
      area = r.w * r.h;
    }
  }
  return best;
}

typedef struct TweakMarks { cui_rect hovered, chosen; } TweakMarks;

static void _paint_marks(cui_ctx *ui, cui_rect area, void *user) {
  TweakMarks *marks = user;
  cui_color pink = { 230, 40, 140, 255 }, faint = { 230, 40, 140, 110 };
  if (marks.hovered.w > 0)
    cui_draw_rect_border(ui, marks.hovered, CUI_CORNERS(2), (cui_color){ 0 },
                         faint, 1);
  if (marks.chosen.w > 0)
    cui_draw_rect_border(ui, marks.chosen, CUI_CORNERS(2), (cui_color){ 0 },
                         pink, 2);
}

/** Paints, over what was drawn before it in a stack, the node under the
    pointer while Alt is held and the node chosen with Alt and a click.
*/
void Ui.tweak_marks(Ui ui) {
  if (!_tweaking()) return;
  bool alt = (ui.key_mods() & CUI_MOD_ALT) != 0;
  List under = alt ? _node_under(ui) : NULL;
  TweakMarks marks = { { 0 }, { 0 } };
  if (under) marks.hovered = _node_rect(ui, under);
  if (under && ui.mouse_clicked(CUI_MOUSE_LEFT)) {
    _tweak_chosen = under[1];
    _tweak_chosen_id = (cui_id) under[0].double();
    _tweak_note = NULL;
  }
  if (_tweak_chosen_id) marks.chosen = ui.get_rect(_tweak_chosen_id);
  ui.canvas("tweak-marks", CUI_FILL, CUI_FILL, _paint_marks, &marks,
            sizeof marks);
}

// The parts of a site: its file, line, and column.
static List _site_parts(String site) {
  int last = site.rfind(":"), before = site[:last].rfind(":");
  return %( $(site[:before]) $(atoi(site[before + 1:last]))
            $(atoi(site[last + 1:])) );
}

static String _number_text(double value) =>
  value == (long) value ? %"$((long) value)" : %"$value";

static bool _word(char c) => isalnum(c) || c == '_' || c == '-' || c == '.';

/* Writes `text` over the value of `name` in the call at `site`: the
   number or name after the first `name:` that follows the call's
   position, before the call's parentheses close. */
static String _write_back(String site, String name, String text) {
  List parts = _site_parts(site);
  Path path = (String) parts[0];
  if (!path.exists()) return %"No file $(parts[0])";
  String source = path.read_text();
  int line = parts[1].int(), column = parts[2].int(), at = 0;
  for (int l = 1; l < line && at >= 0; l++) {
    int next = source[at:].find("\n");
    at = next < 0 ? -1 : at + next + 1;
  }
  if (at < 0) return "The line is gone";
  at += column > 0 ? column - 1 : 0;
  int depth = 0, n = source.len(), nl = name.len();
  for (int i = at; i < n; i++) {
    char c = source[i];
    if (c == '(') depth++;
    if (c == ')' && --depth <= 0) break;
    bool word = i + nl <= n && source[i:i + nl] == name &&
                (i == 0 || !_word(source[i - 1]));
    if (!word) continue;
    int j = i + nl;
    while (j < n && source[j] == ' ') j++;
    if (j >= n || source[j] != ':') continue;
    j++;
    while (j < n && source[j] == ' ') j++;
    int k = j;
    while (k < n && _word(source[k])) k++;
    if (k == j) return %"$name is not a literal at the call";
    path.write_text(source[:j] + text + source[k:]);
    return %"Wrote $name: $text to $(path.basename()):$line";
  }
  return %"No $name: at the call";
}

// The text a literal is written as now.
static String _literal_text(List literal) {
  if (literal[0] == <number>) return _number_text(literal[2].double());
  return ((List) literal[3])[literal[2].int()];
}

/* One row of the panel: an editor for the literal `name` of the chosen
   site, and a button that writes it back. */
static void _literal_row(Ui ui, String name, List literal) {
  String key = %"$_tweak_chosen:$name";
  ui.push_id(name);
  ui.row (width: fill, gap: 6, align: center) {
    ui.text(name, width: 96);
    if (literal[0] == <number>) {
      double value = literal[2].double();
      if (ui.number(name, value, -1000, 4000, step: 1, width: 150))
        _tweak_set[key] = value;
    }
    else {
      int index = literal[2].int();
      if (ui.select(name, literal[3], index, width: 150))
        _tweak_set[key] = index;
    }
    if (ui.button("Write", size: sm))
      _tweak_note = _write_back(_tweak_chosen, name, _literal_text(literal));
  }
  ui.pop_id();
}

/** Lists the chosen node's literal options with an editor for each, which
    sets the value the program uses from the next frame, and a button
    that writes the value back to the call's source. Clears what the
    frame recorded, so it is called once, after everything else.
*/
void Ui.tweak_panel(Ui ui) {
  if (!_tweaking()) return;
  ui.column (width: 360, height: fill, pad: 12, gap: 8, bg: surface) {
    ui.heading("Tweak", 4);
    ui.muted("Alt and a click chooses a node.");
    Var known = _tweak_chosen ? _tweak_sites[_tweak_chosen] : void;
    Map literals = known.is_void() ? NULL : (Map) known;
    if (_tweak_chosen) {
      List parts = _site_parts(_tweak_chosen);
      Path path = (String) parts[0];
      ui.text(%"$(path.basename()):$(parts[1])", width: fill);
      Var drawn = _tweak_counts[_tweak_chosen];
      ui.muted(%"$(drawn.is_void() ? 0 : drawn.int()) drawn from this call");
    }
    if (literals)
      foreach (String name in literals.keys())
        _literal_row(ui, name, literals[name]);
    if (_tweak_chosen && !literals) ui.muted("No literal options here.");
    if (_tweak_note) ui.text(_tweak_note, width: fill);
  }
  _tweak_last = _tweak_nodes;
  _tweak_nodes = [];
  _tweak_counts = {};
  _tweak_ids = [];
}

// Scripted use, for a check that drives the probe without a pointer.

/** Chooses the `nth` node drawn last frame from a call at `line` of a
    file whose path ends with `file`. Returns whether there was one.
*/
bool Ui.tweak_choose(Ui ui, String file, int line, int nth) {
  int seen = 0;
  foreach (List node in _tweak_last ? _tweak_last : %()) {
    List parts = _site_parts(node[1]);
    if (!((String) parts[0]).endswith(file) || parts[1].int() != line)
      continue;
    if (seen++ < nth) continue;
    _tweak_chosen = node[1];
    _tweak_chosen_id = (cui_id) node[0].double();
    return true;
  }
  return false;
}

/** Sets the chosen node's literal `name` to `value`: a number, or the
    name of a member. Returns whether the node has that literal.
*/
bool Ui.tweak_assign(Ui ui, String name, Var value) {
  Var known = _tweak_chosen ? _tweak_sites[_tweak_chosen] : void;
  if (known.is_void() || ((Map) known)[name].is_void()) return false;
  List literal = ((Map) known)[name];
  if (literal[0] == <number>) {
    _tweak_set[%"$_tweak_chosen:$name"] = value.double();
    return true;
  }
  List names = literal[3];
  for (int i = 0; i < names.len(); i++)
    if ((String) names[i] == (String) value) {
      _tweak_set[%"$_tweak_chosen:$name"] = i;
      return true;
    }
  return false;
}

/** Writes the chosen node's literal `name`, as it is used now, back to
    its source, and returns what was done.
*/
String Ui.tweak_write(Ui ui, String name) {
  Var known = _tweak_chosen ? _tweak_sites[_tweak_chosen] : void;
  if (known.is_void() || ((Map) known)[name].is_void())
    return "Nothing to write";
  return _write_back(_tweak_chosen, name, _literal_text(((Map) known)[name]));
}

/** Returns the names of the chosen node's literals. */
List Ui.tweak_literals(Ui ui) {
  Var known = _tweak_chosen ? _tweak_sites[_tweak_chosen] : void;
  return known.is_void() ? %() : ((Map) known).keys().list();
}

/** Returns the chosen node's rectangle in the last frame's layout. */
cui_rect Ui.tweak_chosen_rect(Ui ui) => ui.get_rect(_tweak_chosen_id);
