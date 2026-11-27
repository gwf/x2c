/*  tweak.x -- adjust a running program's literal options (probe)

    Every `name: 3` option a form receives as a numeric literal reaches
    CUI through `Ui.tweak_value`, which reports the literal's call site and
    returns it, or the value set for that site and name while tweaking.
    A box whose call names no id gets one made from its call site, so
    its rectangle can be found. `ui.tweak_marks()` paints the box under
    the pointer and the chosen one; `ui.tweak_panel()` lists the chosen
    box's literals with editors, and writes one back to its source line.
    Tweaking is on when the environment sets X2CUI_TWEAK; otherwise each
    call returns its value and records nothing.
*/

#include "path.x"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// A call site's literals, by name, and where it is: (file line column).
static Map _tweak_sites = NULL;
// Values set while tweaking, by "file:line:column:name".
static Map _tweak_set = NULL;
// The boxes drawn this frame, as (id site), and each site's count.
static Array _tweak_boxes = NULL;
// The boxes the last whole frame drew, for a choice between frames.
static List _tweak_last = NULL;
static Map _tweak_counts = NULL;
static Array _tweak_ids = NULL;
static cui_ctx *_tweak_ui = NULL;
static int _tweak_on = -1;
static String _tweak_chosen = NULL;
static cui_id _tweak_chosen_id = 0, _tweak_hovered = 0;
static String _tweak_note = NULL;

static bool _tweaking(void) {
  if (_tweak_on < 0) {
    _tweak_on = getenv("X2CUI_TWEAK") != NULL;
    _tweak_sites = {};
    _tweak_set = {};
    _tweak_boxes = [];
    _tweak_counts = {};
    _tweak_ids = [];
  }
  return _tweak_on;
}

static String _site(const char *file, int line, int column) =>
  %"$(String.new(file)):$line:$column";

/** Returns `value`, the literal option `name` written at `file`, `line`,
    and `column`, or the value set for it while tweaking.
*/
double Ui.tweak_value(Ui ui, const char *file, int line, int column, const char *name,
                   double value) {
  if (!_tweaking()) return value;
  _tweak_ui = (cui_ctx *) ui;
  String site = _site(file, line, column), key = %"$site:$(String.new(name))";
  Var set = _tweak_set[key], known = _tweak_sites[site];
  double used = set.is_void() ? value : set.double();
  Map literals = known.is_void() ? NULL : (Map) known;
  if (!literals) {
    literals = {};
    _tweak_sites[site] = literals;
  }
  literals[String.new(name)] = %( $value $used );
  return used;
}

/** Returns an id for a box written at `file`, `line`, and `column` whose
    call names none, unique among this frame's boxes from that site, or
    NULL when not tweaking.
*/
const char *Ui.tweak_id(Ui ui, const char *file, int line, int column) {
  if (!_tweaking()) return NULL;
  _tweak_ui = (cui_ctx *) ui;
  String site = _site(file, line, column);
  Var seen = _tweak_counts[site];
  int n = seen.is_void() ? 0 : seen.int();
  _tweak_counts[site] = n + 1;
  String id = %"tweak:$site#$n";
  _tweak_ids.push(id);
  _tweak_boxes.push(%( $((double) cui_make_id(_tweak_ui, id)) $site ));
  return id;
}

static cui_rect _box_rect(Ui ui, List box) =>
  ui.get_rect((cui_id) box[0].double());

// The smallest box drawn under the pointer, or NULL.
static List _box_under(Ui ui) {
  cui_vec2 p = ui.mouse_pos();
  List best = NULL;
  float area = 0;
  foreach (List box in _tweak_boxes) {
    cui_rect r = _box_rect(ui, box);
    if (r.w <= 0 || p.x < r.x || p.y < r.y || p.x >= r.x + r.w ||
        p.y >= r.y + r.h)
      continue;
    if (!best || r.w * r.h < area) {
      best = box;
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

/** Paints, over what was drawn before it in a stack, the box under the
    pointer while Alt is held and the box chosen with Alt and a click.
*/
void Ui.tweak_marks(Ui ui) {
  if (!_tweaking()) return;
  _tweak_ui = (cui_ctx *) ui;
  bool alt = (ui.key_mods() & CUI_MOD_ALT) != 0;
  List under = alt ? _box_under(ui) : NULL;
  _tweak_hovered = 0;
  TweakMarks marks = { { 0 }, { 0 } };
  if (under) marks.hovered = _box_rect(ui, under);
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

/* Writes `value` over the literal of `name` in the call at `site`: the
   first `name:` followed by a number after the call's position, before
   the call's parentheses close. */
static String _write_back(String site, String name, double value) {
  List parts = _site_parts(site);
  Path path = (String) parts[0];
  if (!path.exists()) return %"No file $(parts[0])";
  String text = path.read_text();
  int line = parts[1].int(), column = parts[2].int(), at = 0;
  for (int l = 1; l < line && at >= 0; l++) {
    int next = text[at:].find("\n");
    at = next < 0 ? -1 : at + next + 1;
  }
  if (at < 0) return "The line is gone";
  at += column > 0 ? column - 1 : 0;
  int depth = 0, n = text.len(), nl = name.len();
  for (int i = at; i < n; i++) {
    char c = text[i];
    if (c == '(') depth++;
    if (c == ')' && --depth <= 0) break;
    bool word = i + nl <= n && text[i:i + nl] == name &&
                (i == 0 || !(isalnum(text[i - 1]) || text[i - 1] == '_'));
    if (!word) continue;
    int j = i + nl;
    while (j < n && text[j] == ' ') j++;
    if (j >= n || text[j] != ':') continue;
    j++;
    while (j < n && text[j] == ' ') j++;
    int k = j;
    while (k < n && (isdigit(text[k]) || text[k] == '.' || text[k] == '-'))
      k++;
    if (k == j) return %"$name is not a number at the call";
    path.write_text(text[:j] + _number_text(value) + text[k:]);
    return %"Wrote $name: $(_number_text(value)) to $(parts[0]):$line";
  }
  return %"No $name: at the call";
}

/** Lists the chosen box's literal options with an editor for each, which
    sets the value the program uses from the next frame, and a button
    that writes the value back to the call's source line. Clears what
    the frame recorded, so it is called once, after everything else.
*/
void Ui.tweak_panel(Ui ui) {
  if (!_tweaking()) return;
  ui.column (width: 300, height: fill, pad: 12, gap: 8, bg: surface) {
    ui.heading("Tweak", 4);
    ui.muted("Alt and a click chooses a box.");
    Var known = _tweak_chosen ? _tweak_sites[_tweak_chosen] : void;
    Map literals = known.is_void() ? NULL : (Map) known;
    if (_tweak_chosen) {
      List parts = _site_parts(_tweak_chosen);
      Path path = (String) parts[0];
      ui.text(%"$(path.basename()):$(parts[1])", width: fill);
      Var drawn = _tweak_counts[_tweak_chosen];
      int count = drawn.is_void() ? 0 : drawn.int();
      ui.muted(%"$count drawn from this call");
    }
    if (literals) foreach (String name in literals.keys()) {
      List pair = literals[name];
      double value = pair[1].double();
      ui.push_id(name);
      ui.row (width: fill, gap: 6, align: center) {
        ui.text(name, width: 96);
        if (ui.number(name, value, -1000, 4000, step: 1, width: 110))
          _tweak_set[%"$_tweak_chosen:$name"] = value;
        if (ui.button("Write", size: sm))
          _tweak_note = _write_back(_tweak_chosen, name, value);
      }
      ui.pop_id();
    }
    if (_tweak_chosen && !literals) ui.muted("No literal options here.");
    if (_tweak_note) ui.text(_tweak_note, width: fill);
  }
  _tweak_last = _tweak_boxes;
  _tweak_boxes = [];
  _tweak_counts = {};
  _tweak_ids = [];
}

// Scripted use, for a check that drives the probe without a pointer.

/** Chooses the first box drawn last frame from a call at `line` of a file
    whose path ends with `file`. Returns whether there was one.
*/
bool Ui.tweak_choose(Ui ui, String file, int line) {
  foreach (List box in _tweak_last ? _tweak_last : %()) {
    List parts = _site_parts(box[1]);
    if (!((String) parts[0]).endswith(file) || parts[1].int() != line)
      continue;
    _tweak_chosen = box[1];
    _tweak_chosen_id = (cui_id) box[0].double();
    return true;
  }
  return false;
}

/** Sets the chosen box's literal `name` to `value` from the next frame. */
void Ui.tweak_assign(Ui ui, String name, double value) {
  if (_tweak_chosen) _tweak_set[%"$_tweak_chosen:$name"] = value;
}

/** Writes the chosen box's value of `name` back to its source line, and
    returns what was done.
*/
String Ui.tweak_write(Ui ui, String name) {
  Var set = _tweak_set[%"$_tweak_chosen:$name"];
  return _tweak_chosen && !set.is_void()
    ? _write_back(_tweak_chosen, name, set.double()) : "Nothing to write";
}

/** Returns the chosen box's rectangle in the last frame's layout. */
cui_rect Ui.tweak_chosen_rect(Ui ui) => ui.get_rect(_tweak_chosen_id);
