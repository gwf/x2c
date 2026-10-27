/*  layout.x -- binder vocabulary and capture layouts */

static typedef struct NormalizedCell {
  List original;
  Var head;
} NormalizedCell;

/* capture layouts

   A layout gives each distinct named binder a slot in lexical preorder. A
   sigil-leading `Atom` that spells no binder, a leading `*` binder inside a
   guard, or more than MACHINE_BINDER_MAX binders makes a pattern MALFORMED,
   and its layout has no slots. */

static typedef struct MatchLayoutBuilder {
  Atom binders[MACHINE_BINDER_MAX];
  int count, malformed_binder, leading_list_binder, past_capacity;
} MatchLayoutBuilder;

// The slots a pattern binds on every match and on some match.
static typedef struct MatchSlots {
  unsigned long definite, possible;
} MatchSlots;

/** Analyzes one `Match` pattern into its canonical positional layout.
    Distinct named binders receive slots in lexical preorder. `!quote` is
    opaque; alternatives contribute possible binders, while only binders in
    every alternative are definite. The caller owns the returned layout,
    including when `status` is `<malformed>`.
    Raises: `<alloc-fail>` while normalizing or allocating the layout.
*/
MatchCaptureLayout MatchCaptureLayout.analyze(Var pattern) {
  MatchLayoutBuilder builder = {0};
  _collect(builder, pattern);
  const char *malformed = _malformed(builder);
  Var normalized = pattern;
  if (malformed) builder.count = 0;
  else if (pattern is <list>) normalized = _normalize_pattern(pattern);
  MatchCaptureLayout layout = _layout(builder, normalized, malformed);
  // Binder-free patterns keep the zero-initialized slot masks.
  if (!malformed && builder.count) {
    MatchSlots slots = _slots(layout, normalized);
    layout.definite = slots.definite;
    layout.possible = slots.possible;
  }
  return layout;
}

/* pattern vocabulary

   A binder is `?` or `*`, alone or followed by an ASCII identifier: `?`
   binds one element and `*` a sequence. A guard operator is one of the
   compact Symbols `!is`, `!set`, `!or`, `!and`, `!not`, and `!quote`. */

/** Reports whether `atom` is a valid named or anonymous `?` binder. */
meta native int Var.is_atom_binder(Var atom) => _binder_kind(atom) == '?';

/** Reports whether `atom` is a valid named or anonymous `*` binder. */
meta native int Var.is_list_binder(Var atom) => _binder_kind(atom) == '*';

/** Reports whether `atom` is either valid `Match` binder form. */
meta native int Var.is_binder(Var atom) => _binder_kind(atom) > 0;

/** Reports whether `atom` is a compact built-in `Match` guard operator. */
meta native int Var.is_match_op(Var atom) {
  if (atom is not <symbol>) return 0;
  Symbol symbol = atom;
  switch (symbol) {
    case <!is>: case <!set>: case <!or>: case <!and>: case <!not>:
    case <!quote>:
      return 1;
  }
  return 0;
}

// layout queries

/** Releases one canonical `Match` capture layout.
    A null layout is ignored; every alias is invalid afterward.
*/
void MatchCaptureLayout.free(MatchCaptureLayout layout) {
  if (layout) xfree(layout);
}

/** Returns definite binders in canonical positional order.
    A null layout or no definite binders returns `nil`. The canonical result
    follows the module pool-chain lifetime above.
    Raises: `<alloc-fail>` while constructing the `List`.
*/
List MatchCaptureLayout.definite_list(MatchCaptureLayout layout) =>
  layout ? _binders(layout, layout.definite) : NULL;

/** Returns possible binders in canonical positional order.
    A null layout or no possible binders returns `nil`. The canonical result
    follows the module pool-chain lifetime above.
    Raises: `<alloc-fail>` while constructing the `List`.
*/
List MatchCaptureLayout.possible_list(MatchCaptureLayout layout) =>
  layout ? _binders(layout, layout.possible) : NULL;

/** Returns the canonical slot for `binder`, or -1 when it is absent.
    A null layout returns -1. Comparison uses exact `Atom` identity.
*/
int MatchCaptureLayout.index(MatchCaptureLayout layout, Atom binder) =>
  layout ? _find(layout, binder) : -1;

/** Reports whether a committed capture slot is present.
    A null buffer or an index outside its capacity or `Match`'s binder limit
    returns false. Presence is independent of the captured `Var` value.
*/
int MatchCaptureBuffer.has(MatchCaptureBuffer &?m, int index) {
  if (!m || index < 0 || index >= m.capacity || index >= MACHINE_BINDER_MAX)
    return 0;
  return _capture_bit(m.present, index);
}

/* pattern normalization

   Every guard except `!quote` accepts a leading binder when an operand
   follows it. `(OP BINDER PAT ...)` normalizes to
   `(!set BINDER (OP PAT ...))`, so a binder captures the same value in
   either spelling. The matcher is based on Peter Norvig's implementation at
   https://github.com/norvig/paip-lisp/blob/main/lisp/patmatch.lisp. */

static List _normalize_pattern(List pattern) {
  if (!pattern || pattern.car() == <!quote>) return pattern;
  List normalized = _normalize_elements(pattern);
  Var op = normalized.car();
  List args = normalized.cdr();
  if (!op.is_match_op() || op == <!quote> || !args) return normalized;
  Var binder = args.car();
  List rest = args.cdr();
  // `(!set BINDER PAT)` is the form this produces, so leave it alone.
  if (!binder.is_binder() || !rest || (op == <!set> && !rest.cdr()))
    return normalized;
  return %(!set $binder $(_normalize_pattern($(op, @rest))));
}

// Normalizes siblings iteratively and retains every unchanged suffix.
static List _normalize_elements(List elements) {
  Block spine = auto Block.new(sizeof(NormalizedCell));
  for (List cell = elements; cell; cell = cell.cdr()) {
    Var head = cell.car();
    NormalizedCell row = {
      cell, head is <list> ? (Var) _normalize_pattern(head) : head};
    spine.push(&row);
  }
  List out = NULL;
  for (size_t i = spine.length; i > 0; i--) {
    NormalizedCell row = ((NormalizedCell *) spine.bytes)[i - 1];
    out = row.head == row.original.car() && out == row.original.cdr()
      ? row.original : cons(row.head, out);
  }
  return out;
}

/* Collects the raw pattern's named binders in one lexical preorder walk and
   notes each malformation. `!quote` is opaque. Compact matcher predicates
   are control vocabulary only as the final operand of `!is`. The compiler's
   dynamic-value marker retains binders in its literal children without
   treating the marker as data. */
static void _collect(MatchLayoutBuilder &b, Var pattern) {
  if (pattern is not <list>) {
    _atom(b, pattern);
    return;
  }
  if (pattern.is_nil()) return;
  List list = pattern;
  Var head = list.car();
  if (head == <!quote>) return;
  if (head.is_match_op()) {
    List args = list.cdr();
    if (args && args.car().is_list_binder()) b.leading_list_binder = 1;
  }
  List parts = head == <x2c-dyn> ? list.cdr() : list;
  int predicate_form = head == <!is>;
  for (List at = parts; at; at = at.cdr()) {
    Var part = at.car();
    if (predicate_form && !at.cdr() && _reserved_predicate(part)) continue;
    _collect(b, part);
    if (b.malformed_binder) return;
  }
}

/* A compact matcher predicate, which is control vocabulary as the final
   operand of `!is`. */
static int _reserved_predicate(Var atom) =>
  atom is <symbol> &&
  (atom == <?binder?> || atom == <*binder?> || atom == <!op?>);

// A sigil-leading `Atom` must spell a binder; a named binder takes a slot.
static void _atom(MatchLayoutBuilder &b, Var atom) {
  int kind = _binder_kind(atom);
  if (kind < 0) b.malformed_binder = 1;
  else if (kind && atom != <?> && atom != <*> && _add(b, atom) < 0)
    b.past_capacity = 1;
}

// Returns the slot for `binder`, or -1 once the pattern is past capacity.
static int _add(MatchLayoutBuilder &b, Atom binder) {
  for (int i = 0; i < b.count; i++)
    if (b.binders[i].u64 == binder.u64) return i;
  if (b.count >= MACHINE_BINDER_MAX) return -1;
  b.binders[b.count] = binder;
  return b.count++;
}

/* Error priority is binder spelling, a leading list binder in a guard, then
   binder capacity. */
static const char *_malformed(MatchLayoutBuilder &b) {
  if (b.malformed_binder) return "binder-name";
  if (b.leading_list_binder) return "leading-list-binder-in-guard";
  if (b.past_capacity) return "binder-capacity";
  return NULL;
}

// The binder table shares the record's allocation.
static MatchCaptureLayout _layout(
  MatchLayoutBuilder &b, Var normalized, const char *malformed) {
  size_t bytes = sizeof(struct MatchCaptureLayout) + sizeof(Atom) * b.count;
  MatchCaptureLayout layout = xcalloc(1, bytes);
  layout.binders =
    (Atom *) ((char *) layout + sizeof(struct MatchCaptureLayout));
  layout.binder_count = b.count;
  layout.status = malformed ? <malformed> : <prepared>;
  layout.reason = malformed ? malformed : "prepared";
  layout.normalized = normalized;
  if (b.count) memcpy(layout.binders, b.binders, sizeof(Atom) * b.count);
  return layout;
}

/* definite and possible slots

   A pattern binds its definite slots on every match and its possible slots
   on some match. Analysis reads the normalized pattern, where a leading
   binder survives only as the `!set` capture form. */

static MatchSlots _slots(MatchCaptureLayout m, Var pattern) {
  if (_named_binder(pattern)) return _binder_slot(m, pattern);
  if (pattern is not <list> || pattern.is_nil()) return (MatchSlots) {0, 0};
  List list = pattern;
  Var head = list.car();
  List args = list.cdr();
  if (head == <!quote>) return (MatchSlots) {0, 0};
  if (head == <x2c-dyn>)
    return (MatchSlots) {0, _sequence_slots(m, args).possible};
  if (!head.is_match_op()) return _sequence_slots(m, list);
  return _guard_slots(m, head, args);
}

/* `(!set BINDER TEST)` binds and tests, as the matcher runs it; any other
   set is a choice. A negation binds nothing on every match. */
static MatchSlots _guard_slots(MatchCaptureLayout m, Var op, List args) {
  if (op == <!and> || (op == <!set> && _set_capture(args)))
    return _sequence_slots(m, args);
  if (op == <!or> || op == <!set>) return _choice_slots(m, args);
  if (op == <!not>) return (MatchSlots) {0, _sequence_slots(m, args).possible};
  return (MatchSlots) {0, 0};
}

/* Every element of a sequence matches, so each one's definite slots are
   definite. */
static MatchSlots _sequence_slots(MatchCaptureLayout m, List patterns) {
  MatchSlots slots = {0, 0};
  foreach (Var pattern in patterns) slots = _union(slots, _slots(m, pattern));
  return slots;
}

/* One alternative matches, so only the slots every one binds are
   definite. */
static MatchSlots _choice_slots(MatchCaptureLayout m, List patterns) {
  MatchSlots slots = {0, 0};
  int first = 1;
  foreach (Var pattern in patterns) {
    MatchSlots part = _slots(m, pattern);
    slots.possible |= part.possible;
    slots.definite = first ? part.definite : slots.definite & part.definite;
    first = 0;
  }
  return slots;
}

module int _named_binder(Var value) =>
  value.is_binder() && value != <?> && value != <*>;

static int _set_capture(List args) =>
  args && args.cdr() && !args.cddr() && args.car().is_atom_binder();

/* The valid binder's sigil, -1 for a malformed sigil-leading Atom, or 0
   otherwise. Compact bytes use stack storage; long bytes are borrowed. */
static int _binder_kind(Var atom) {
  char sigil = Atom.first(atom);
  if (sigil != '?' && sigil != '*') return 0;
  char decoded[SYMBOL_MAX_5BIT + 1];
  const char *spelling;
  if (atom is <symbol>) {
    Symbol.decode(atom, decoded);
    spelling = decoded;
  }
  else spelling = atom.pointer();
  if (!spelling[1]) return sigil;
  unsigned char first = (unsigned char) spelling[1];
  if (!scan_ascii_alpha(first) && first != '_') return -1;
  for (int i = 2; spelling[i]; i++) {
    unsigned char ch = (unsigned char) spelling[i];
    if (!scan_ascii_alpha(ch) && !scan_ascii_digit(ch) && ch != '_') return -1;
  }
  return sigil;
}

static MatchSlots _binder_slot(MatchCaptureLayout m, Var binder) {
  unsigned long bit = 1UL << _find(m, binder);
  return (MatchSlots) {bit, bit};
}

static MatchSlots _union(MatchSlots a, MatchSlots b) =>
  (MatchSlots) {a.definite | b.definite, a.possible | b.possible};

static int _find(MatchCaptureLayout layout, Atom binder) {
  for (int i = 0; i < layout.binder_count; i++)
    if (layout.binders[i].u64 == binder.u64) return i;
  return -1;
}

// Selection by `included` preserves slot order.
static List _binders(MatchCaptureLayout layout, unsigned long included) {
  List binders = NULL;
  for (int i = layout.binder_count - 1; i >= 0; i--)
    if (_capture_bit(included, i)) binders = cons(layout.binders[i], binders);
  return binders;
}

module int _capture_bit(unsigned long bits, int index) =>
  (int) ((bits >> index) & 1UL);
