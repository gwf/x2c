/*  templates.x -- replacement template instantiation */

/* Where a named binder finds its value: the committed `captures` of a plan,
   or the association List `bindings` when `captures` is null. */
module typedef struct ReplacementSource {
  MatchCaptureLayout layout;
  MatchCaptureBuffer *captures;
  List bindings;
} ReplacementSource;

static typedef struct ReplacementCell {
  Var value;
  int splice;
} ReplacementCell;

/* templates

   Instantiation replaces each named binder with its value. A sequence
   binder at a List's head splices its captured List; a binder the match
   left unbound is retained as one element, so no result is ever void.
   `!quote` yields its operand unchanged. */

/** Executes `plan` and writes the instantiated `template` on success.
    Returns 1 after writing any `Var` result, 0 on a miss, and -1 for an
    unusable plan, null output, or machine error. Non-success leaves `out`
    unchanged.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    materializing captures or replacing.
*/
int MatchPlan.try_match_replace(
  MatchPlan plan, List input, Var template, Var &?out) {
  if (!_prepared(plan, "MatchPlan.try_match_replace") || !out) return -1;
  return _replace_match(plan, input, template, out);
}

static int _replace_match(
  MatchPlan plan, List input, Var template, Var &out) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  int result = _capture(plan, input, &captures, NULL);
  if (result != 1) return result;
  ReplacementSource source = { plan.layout, &captures, NULL };
  out = _replace(template, source);
  return 1;
}

/* An absent binding leaves `binder` unchanged. */
static Var _value(ReplacementSource &source, Var binder) {
  if (source.captures)
    return _captured(source.layout, source.captures, binder);
  Var bound = source.bindings.assoc(binder);
  return bound is void ? binder : bound;
}

/* The value captured for `binder`, or the binder when the match left it
   unbound. */
static Var _captured(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures, Var binder) {
  int index = layout.index(binder);
  if (index < 0 || !_capture_bit(captures.present, index)) return binder;
  return captures.values[index];
}

/** Replaces named binders in `template` according to `bindings`.
    A sequence binder in list-head position splices its captured `List`;
    `!quote` removes itself and leaves its operand literal. Missing binders are
    retained. A null template returns `nil`, and null bindings return
    `template` unchanged. New structure follows the module pool-chain lifetime
    above.
    Raises: `<alloc-fail>` while constructing replacement `List`s.
*/
meta native List List.replace(List template, List bindings) {
  if (!template) return NULL;
  if (!bindings) return template;
  ReplacementSource source = { NULL, NULL, bindings };
  return _replace(template, source);
}

/* Instantiates `input`, taking each named binder's value from `source`. */
module Var _replace(Var input, ReplacementSource &source) {
  if (_named_binder(input)) return _value(source, input);
  if (input is not <list>) return input;
  List list = input;
  if (!list) return input;
  if (list.car() == <!quote>) return list.cadr();
  Block spine = $auto(Block.new(sizeof(ReplacementCell)));
  Var tail = (List) NULL;
  for (; list; list = list.cdr()) {
    Var head = list.car();
    if (head == <!quote>) {
      tail = list.cadr();
      break;
    }
    ReplacementCell row = {
      _replace(head, source),
      head.is_list_binder() && head != <*> && head != <?>
    };
    spine.push(&row);
  }
  for (size_t i = spine.length; i > 0; i--) {
    ReplacementCell row = ((ReplacementCell *) spine.bytes)[i - 1];
    Var head = row.value;
    if (row.splice && head is <list>) tail = %(@head @tail);
    else tail = %($head @tail);
  }
  return tail;
}
