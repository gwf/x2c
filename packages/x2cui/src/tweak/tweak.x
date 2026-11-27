/*  tweak.x -- adjust a running program's options (probe)

    While a program is tweaked, every option of a form's record reaches
    CUI through a tweak call that names its call site and returns the
    value the program uses: the value the call writes, or for an option
    the call leaves unset the field's zero, which CUI reads as its
    default, unless the panel has set another. Numbers, sizes, members
    of an enum, theme colours, and switches can be set; other written
    values are noted with their source text. A box whose call names no
    id gets one made from its call site, and a component or a block that
    draws a control is noted with the id CUI gave it, so that their
    rectangles can be found. `ui.tweak_marks()` paints the node under the
    pointer and the chosen one; `ui.tweak_panel()` lists the chosen
    node's options in three tiers (those the call writes, those programs
    commonly set, and all others) and writes a value back to the call,
    replacing it or adding it. Tweaking is on when the environment sets
    X2CUI_TWEAK; otherwise each call returns its value and records
    nothing.
*/

#include "path.x"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Each call site's options by name, as
   `(kind state written names values tier text)`: `kind` is `number`,
   `size`, `choice`, `color`, or `computed`; `state` is `written` or
   `unset`; `written` is the number or the member's position the call
   writes; `names` and `values` are a choice's members; `tier` is 0 for
   written, 1 for common, and 2 for another option; `text` is a computed
   option's source. */
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
// The panel's "All options" switch and search.
static bool _tweak_all = false;
static TextField _tweak_search = NULL;

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

/* The value set for `name` at `site` while tweaking, or void when none is
   set. A Map holds no void, so going back to the default stores the
   Symbol `default`, which reads as void. */
static Var _setting(String site, String name) {
  Var set = _tweak_set[%"$site:$name"];
  return set.is_atom() ? void : set;
}

static Map _options_at(String site) {
  Var known = _tweak_sites[site];
  if (!known.is_void()) return known;
  Map options = {};
  _tweak_sites[site] = options;
  return options;
}

/* Records the option `name` at `site` the first time it is seen. */
static void _record(String site, String name, Symbol kind, Symbol state,
                    Var written, List names, List values, int tier,
                    String text) {
  Map options = _options_at(site);
  if (options[name].is_void())
    options[name] = %( $kind $state $written $names $values $tier $text );
}

static List _strings(const char **names, int count) {
  Array out = [];
  for (int i = 0; i < count; i++) out.push(String.new(names[i]));
  return out.list_free();
}

static List _ints(int *values, int count) {
  Array out = [];
  for (int i = 0; i < count; i++) out.push(values[i]);
  return out.list_free();
}

static int _position(const char **names, int count, const char *name) {
  for (int i = 0; i < count; i++)
    if (!strcmp(names[i], name)) return i;
  return 0;
}

/** Returns `value`, the number the call at `file`, `line`, and `column`
    writes for its option `name`, or the value set for it while tweaking.
*/
double Ui.tweak_value(Ui ui, const char *file, int line, int column,
                      const char *name, double value) {
  if (!_tweaking()) return value;
  String site = _site(file, line, column), field = String.new(name);
  _record(site, field, <number>, <written>, value, %(), %(), 0, "");
  Var set = _setting(site, field);
  return set.is_void() ? value : set.double();
}

/** Returns the value of the enum member `current` the call writes for
    its option `name`, or of the member set for it while tweaking.
    `names` and `values` are the enum's members.
*/
int Ui.tweak_choice(Ui ui, const char *file, int line, int column,
                    const char *name, const char *current,
                    const char **names, int *values, int count) {
  int written = _position(names, count, current);
  if (!_tweaking()) return values[written];
  String site = _site(file, line, column), field = String.new(name);
  _record(site, field, <choice>, <written>, written, _strings(names, count),
          _ints(values, count), 0, "");
  Var set = _setting(site, field);
  return values[set.is_void() ? written : set.int()];
}

/** Returns the theme colour `current` the call writes for its option
    `name`, or the colour set for it while tweaking. `names` and `values`
    are CUI's colour tokens.
*/
cui_color Ui.tweak_color(Ui ui, const char *file, int line, int column,
                         const char *name, const char *current,
                         const char **names, int *values, int count) {
  int written = _position(names, count, current);
  if (!_tweaking()) return CUI_TOKEN_COLOR(values[written]);
  String site = _site(file, line, column), field = String.new(name);
  _record(site, field, <color>, <written>, written, _strings(names, count),
          _ints(values, count), 0, "");
  Var set = _setting(site, field);
  return CUI_TOKEN_COLOR(values[set.is_void() ? written : set.int()]);
}

/** Notes that the call at `file`, `line`, and `column` writes its option
    `name` as an expression or a name the panel does not edit; the panel
    shows its text from the source. Returns 0, so that a comma can
    follow it.
*/
int Ui.tweak_note(Ui ui, const char *file, int line, int column,
                  const char *name) {
  if (_tweaking())
    _record(_site(file, line, column), String.new(name), <computed>,
            <written>, 0, %(), %(), 0, "");
  return 0;
}

/** Returns 0 for the number option `name` the call at `file`, `line`,
    and `column` leaves unset, or the value set for it while tweaking.
    `tier` is 1 for an option programs commonly set and 2 for another.
*/
double Ui.tweak_unset_number(Ui ui, const char *file, int line, int column,
                             const char *name, int tier) {
  if (!_tweaking()) return 0;
  String site = _site(file, line, column), field = String.new(name);
  _record(site, field, <number>, <unset>, 0, %(), %(), tier, "");
  Var set = _setting(site, field);
  return set.is_void() ? 0 : set.double();
}

/** Returns the default size for the option `name` the call leaves unset,
    or a fixed size in points set for it while tweaking.
*/
cui_size Ui.tweak_unset_size(Ui ui, const char *file, int line, int column,
                             const char *name, int tier) {
  cui_size none = { 0 };
  if (!_tweaking()) return none;
  String site = _site(file, line, column), field = String.new(name);
  _record(site, field, <size>, <unset>, 0, %(), %(), tier, "");
  Var set = _setting(site, field);
  return set.is_void() ? none : CUI_PX(set.double());
}

/** Returns 0 for the enum or switch option `name` the call leaves unset,
    or the value of the member set for it while tweaking.
*/
int Ui.tweak_unset_choice(Ui ui, const char *file, int line, int column,
                          const char *name, int tier, const char **names,
                          int *values, int count) {
  if (!_tweaking()) return 0;
  String site = _site(file, line, column), field = String.new(name);
  _record(site, field, <choice>, <unset>, -1, _strings(names, count),
          _ints(values, count), tier, "");
  Var set = _setting(site, field);
  return set.is_void() ? 0 : values[set.int()];
}

/** Returns the default colour for the option `name` the call leaves
    unset, or the theme colour set for it while tweaking.
*/
cui_color Ui.tweak_unset_color(Ui ui, const char *file, int line, int column,
                               const char *name, int tier,
                               const char **names, int *values, int count) {
  cui_color none = { 0 };
  if (!_tweaking()) return none;
  String site = _site(file, line, column), field = String.new(name);
  _record(site, field, <color>, <unset>, -1, _strings(names, count),
          _ints(values, count), tier, "");
  Var set = _setting(site, field);
  return set.is_void() ? none : CUI_TOKEN_COLOR(values[set.int()]);
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

// The offset of the call at `line` and `column` of `source`, or -1.
static int _call_at(String source, int line, int column) {
  int at = 0;
  for (int l = 1; l < line && at >= 0; l++) {
    int next = source[at:].find("\n");
    at = next < 0 ? -1 : at + next + 1;
  }
  return at < 0 ? -1 : at + (column > 0 ? column - 1 : 0);
}

/* The text of the value the call at `site` writes for `name`, up to the
   comma or parenthesis that ends it, or "" when it cannot be read. */
static Map _tweak_texts = NULL;

static String _written_text(String site, String name) {
  if (!_tweak_texts) _tweak_texts = {};
  String key = %"$site:$name";
  Var known = _tweak_texts[key];
  if (!known.is_void()) return known;
  String text = _read_written_text(site, name);
  _tweak_texts[key] = text;
  return text;
}

static String _read_written_text(String site, String name) {
  List parts = _site_parts(site);
  Path path = (String) parts[0];
  if (!path.exists()) return "";
  String source = path.read_text();
  int at = _call_at(source, parts[1].int(), parts[2].int());
  int n = source.len(), nl = name.len();
  for (int i = at < 0 ? n : at; i + nl < n; i++) {
    if (source[i:i + nl] != name || (i > 0 && _word(source[i - 1]))) continue;
    int j = i + nl;
    while (j < n && source[j] == ' ') j++;
    if (j >= n || source[j] != ':') continue;
    int k = ++j, depth = 0;
    for (; k < n; k++) {
      char c = source[k];
      if (c == '(' || c == '[' || c == '{') depth++;
      if ((c == ')' || c == ']' || c == '}') && depth-- == 0) break;
      if (c == ',' && depth == 0) break;
    }
    return source[j:k].strip().replace("\n", " ");
  }
  return "";
}

/* `source` with `text` over the value of `name` in the call at `at`: the
   number or name after the first `name:` that follows, before the call's
   parentheses close. NULL when the call writes no `name:`. */
static String _replaced(String source, int at, String name, String text) {
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
    return k == j ? NULL : source[:j] + text + source[k:];
  }
  return NULL;
}

/* `source` with `name: text` added as the last argument of the call at
   `at`, before its closing parenthesis. NULL when it has none. */
static String _added(String source, int at, String name, String text) {
  int open = source[at:].find("(");
  if (open < 0) return NULL;
  open += at;
  int depth = 0, n = source.len();
  for (int i = open; i < n; i++) {
    if (source[i] == '(') depth++;
    if (source[i] != ')' || --depth > 0) continue;
    int last = i - 1;
    while (last > open && isspace(source[last])) last--;
    String joint = last == open ? "" : ", ";
    return source[:last + 1] + joint + %"$name: $text" + source[last + 1:];
  }
  return NULL;
}

/* Writes `text` as the value of `name` in the call at `site`, replacing
   the value the call writes, or adding `name: text` when `add` is set. */
static String _write_back(String site, String name, String text, bool add) {
  List parts = _site_parts(site);
  Path path = (String) parts[0];
  if (!path.exists()) return %"No file $(parts[0])";
  String source = path.read_text();
  int at = _call_at(source, parts[1].int(), parts[2].int());
  if (at < 0) return "The line is gone";
  String written = add ? _added(source, at, name, text)
                       : _replaced(source, at, name, text);
  if (!written) return %"Could not find where $name goes in the call";
  path.write_text(written);
  _tweak_texts = {};
  return %"Wrote $name: $text to $(path.basename()):$(parts[1])";
}

/* The value set for an option while tweaking, or void. */
static Var _set_for(String name) => _setting(_tweak_chosen, name);

// The text an option is written as with the value it is set to now.
static String _option_text(List option, Var set) {
  if (option[0] == <number> || option[0] == <size>)
    return _number_text(set.is_void() ? option[2].double() : set.double());
  int at = set.is_void() ? option[2].int() : set.int();
  return ((List) option[3])[at];
}

/* One row of the panel: an editor for the option `name` of the chosen
   site, and a button that writes it back. */
static void _option_row(Ui ui, String name, List option) {
  String key = %"$_tweak_chosen:$name";
  Var set = _setting(_tweak_chosen, name);
  bool unset = option[1] == <unset>;
  ui.push_id(name);
  ui.row (width: fill, gap: 6, align: center) {
    ui.text(name, width: 110,
            color: unset && set.is_void() ? text_secondary : foreground);
    if (option[0] == <computed>)
      ui.text(_written_text(_tweak_chosen, name), width: fill,
              color: text_secondary);
    else if (option[0] == <number> || option[0] == <size>) {
      double value = set.is_void() ? option[2].double() : set.double();
      if (ui.number(name, value, -1000, 4000, step: 1, width: 150))
        _tweak_set[key] = value;
    }
    else {
      // An unset choice starts at "default", before the members.
      List names = option[3];
      int index = set.is_void() ? option[2].int() : set.int();
      int shown = unset ? index + 1 : index;
      List items = unset ? %("default" @names) : names;
      if (ui.select(name, items, shown, width: 150)) {
        int chosen = unset ? shown - 1 : shown;
        if (chosen < 0) _tweak_set[key] = <default>;
        else _tweak_set[key] = chosen;
      }
    }
    bool writable = option[0] != <computed> && (!unset || !set.is_void());
    if (writable && ui.button("Write", size: sm))
      _tweak_note = _write_back(_tweak_chosen, name, _option_text(option, set),
                                unset);
  }
  ui.pop_id();
}

// The chosen site's options of `tier`, in the order recorded.
static List _options_of(int tier) {
  Var known = _tweak_chosen ? _tweak_sites[_tweak_chosen] : void;
  if (known.is_void()) return %();
  Array names = [];
  foreach (String name in ((Map) known).keys()) {
    List option = ((Map) known)[name];
    if (option[5].int() == tier) names.push(name);
  }
  return names.list_free();
}

/** Lists the chosen node's options with an editor for each, which sets
    the value the program uses from the next frame, and a button that
    writes the value back to the call. The options the call writes come
    first, then those programs commonly set, then, under "All options",
    the rest. Clears what the frame recorded, so it is called once,
    after everything else.
*/
void Ui.tweak_panel(Ui ui) {
  if (!_tweaking()) return;
  if (!_tweak_search) _tweak_search = TextField.new(64);
  ui.column (width: 380, height: fill, bg: surface)
  ui.scroll (id: "tweak-panel", width: fill, height: fill, pad: 12, gap: 8) {
    ui.heading("Tweak", 4);
    ui.muted("Alt and a click chooses a node.");
    if (_tweak_chosen) {
      List parts = _site_parts(_tweak_chosen);
      Path path = (String) parts[0];
      ui.text(%"$(path.basename()):$(parts[1])", width: fill);
      Var drawn = _tweak_counts[_tweak_chosen];
      ui.muted(%"$(drawn.is_void() ? 0 : drawn.int()) drawn from this call");
      Map known = _tweak_sites[_tweak_chosen].is_void()
                ? {} : (Map) _tweak_sites[_tweak_chosen];
      List written = _options_of(0), common = _options_of(1);
      if (written.len()) ui.label("Written");
      foreach (String name in written) _option_row(ui, name, known[name]);
      if (common.len()) ui.label("Common");
      foreach (String name in common) _option_row(ui, name, known[name]);
      if (ui.switch("All options", _tweak_all)) _tweak_search.set("");
      if (_tweak_all) {
        ui.search("tweak-search", _tweak_search, size: sm);
        String wanted = _tweak_search.text();
        foreach (String name in _options_of(2))
          if (!wanted.len() || name.find(wanted) >= 0)
            _option_row(ui, name, known[name]);
      }
    }
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

static List _chosen_option(String name) {
  Var known = _tweak_chosen ? _tweak_sites[_tweak_chosen] : void;
  if (known.is_void() || ((Map) known)[name].is_void()) return NULL;
  return ((Map) known)[name];
}

/** Sets the chosen node's option `name` to `value`: a number, the name
    of a member, or "default" for an option the call leaves unset.
    Returns whether the node has that option.
*/
bool Ui.tweak_assign(Ui ui, String name, Var value) {
  List option = _chosen_option(name);
  if (!option || option[0] == <computed>) return false;
  String key = %"$_tweak_chosen:$name";
  if (option[0] == <number> || option[0] == <size>) {
    _tweak_set[key] = value.double();
    return true;
  }
  List names = option[3];
  if ((String) value == "default" && option[1] == <unset>) {
    _tweak_set[key] = <default>;
    return true;
  }
  for (int i = 0; i < names.len(); i++)
    if ((String) names[i] == (String) value) {
      _tweak_set[key] = i;
      return true;
    }
  return false;
}

/** Writes the chosen node's option `name`, as it is used now, back to its
    call, and returns what was done.
*/
String Ui.tweak_write(Ui ui, String name) {
  List option = _chosen_option(name);
  if (!option || option[0] == <computed>) return "Nothing to write";
  Var set = _set_for(name);
  if (option[1] == <unset> && set.is_void()) return "Nothing set to write";
  return _write_back(_tweak_chosen, name, _option_text(option, set),
                     option[1] == <unset>);
}

/** Returns the chosen node's options of `tier`: 0 for those its call
    writes, 1 for those programs commonly set, 2 for the rest.
*/
List Ui.tweak_options(Ui ui, int tier) => _options_of(tier);

/** Returns the source text the chosen node's call writes for `name`. */
String Ui.tweak_text(Ui ui, String name) =>
  _tweak_chosen ? _written_text(_tweak_chosen, name) : "";

/** Returns the chosen node's rectangle in the last frame's layout. */
cui_rect Ui.tweak_chosen_rect(Ui ui) => ui.get_rect(_tweak_chosen_id);
