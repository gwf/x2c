/*  rewrites.x -- rewrite registration and application */

module typedef struct RewriteRule {
  String name;
  Symbol point;
  Var kind;
  MacroMatcher matcher;
  int builtin, prepared;
} *RewriteRule;

/* prepared replacements

   A translator's replacement is its quotation's template filled with Code
   values it captured from the source, which are already bound, typed when
   they resolved, as an undeclared C function's name does not.
   Binding, conversion, and lowering treat the template's own syntax alike
   for every use with the same template and slot signatures, so the first
   lowering in a unit keeps that syntax as a skeleton with a slot for each
   captured value. A later use lowers only its values and fills the slots.
   A slot's signature is its value's type and the part of its content that
   conversion and lowering read (`_slot_shape`). The skeleton holds the
   unit's binding identities, so it lives with the unit, as a shipped rule
   whose row is bound to its unit does; a lowering inside a semantic
   transaction prepares nothing.

   The first lowering watches the captured values. Lowering must reach each
   exactly once through `Compiler.normalize`, the result must hold that
   lowering's output exactly once, and the template's own syntax must
   introduce no binding and add no generated name, origin, pending code,
   placement, or diagnostic. A template whose lowering adds such state
   tries again on its next use; one that fails otherwise, or that holds
   pending code or a carrier, lowers as written on every use. A lowered
   carrier holds no template to prepare, so it lowers as written at once. */

/* Counts compiler state that lowering adds and a skipped lowering would
    not add. A name a scope resolves binds once, so it is not counted. */
static typedef struct Effects {
  int bindings, names, origins, pending, placements, diagnostics;
} Effects;

/* A first lowering's outputs and effects, used only to prepare a skeleton. */
static typedef struct Preparation {
  Array outputs, order;
  Effects inner;
  int repeated;
} Preparation;

/** Records the source values a replacement's lowering watches. A watched
    value is source the translator captured, so it lowers under the `outer` rules,
    those active outside the translator's own. A first lowering's
    `preparation` records the outputs for a reusable skeleton.
    A replacement lowered as written within another's has that one as its
    `parent`, whose source it may hold
    as well. A shipped rule's replacement, a statement the kernel wrote,
    and any replacement lowered within either are `shipped`, as is a
    written definition while its function rules are chosen: their own
    code is not source, so no user rule sees it, while the values the
    watch holds are. A watch whose values are
    lowered already has them `kept` as they are. */
struct SlotWatch {
  List values;
  Preparation *preparation;
  int shipped, kept;
  List outer;
  SlotWatch parent;
};

module Var RewriteRule.var(RewriteRule rule) => Var.new(<p48>, rule);

module RewriteRule Var.rewrite_rule(Var value) => value.pointer();

/* A rule derives a macro's matcher now, or else on the first probe of its
   family; a Match pattern is its own. */
module RewriteRule _rewrite_rule(
  Symbol point, Var kind, String name, List pattern, List holes,
  int builtin, int prepared) {
  RewriteRule rule = xcalloc(1, sizeof(struct RewriteRule));
  MacroMatcher matcher = {NULL, NULL, pattern};
  if (pattern.car() == <macrodef>) {
    Macro shape = pattern;
    matcher = prepared ? shape.matcher(holes) : (MacroMatcher){shape, holes};
  }
  *rule = (struct RewriteRule){name, point, kind, matcher, builtin, prepared};
  return rule;
}

/* Rules the compiler prelude installs, by frozen row. Each is thawed once
   per process and shared by every unit; its matcher is derived on the first
   probe of its family. A row whose thawing records a cache key, binding, or
   origin in its unit is thawed for each unit instead. */
static Map shipped_rules = NULL, static Scope shipped_scope = NULL;

static void _shipped_shutdown(void) {
  shipped_scope.destroy();
  shipped_scope = NULL;
  shipped_rules = NULL;
}

/* Registers an installed rewrite row. A prelude rule whose translator
   this compiler does not link was added after it was built, so the form
   keeps this compiler's own lowering, as a prelude component added after
   it would. */
module void _install_rewrite(Compiler c, List row) {
  Var shared = shipped_rules ? shipped_rules[row] : void;
  if (shared is void && c.builtin_defs) shared = _ship_rewrite(c, row);
  if (shared is <p48>) {
    _register_rewrite(c, shared.rewrite_rule());
    return;
  }
  match (row) case %(compile-time rewrite ?point ?kind ?name ?shape ?holes): {
    if (c.builtin_defs && !Compiler.links_meta_function(name)) return;
    RewriteRule rule = _rewrite_rule(
      point, c.thaw_declaration_syntax(kind), name,
      c.thaw_declaration_syntax(shape), c.thaw_declaration_syntax(holes),
      c.builtin_defs, 1);
    _register_rewrite(c, rule);
  }
}

/* The shared rule for a prelude row, or 0 when the row is bound to its
   unit or names a translator the compiler does not link. The shared rule
   derives its matcher on first use. */
static Var _ship_rewrite(Compiler c, List row) {
  auto (&shipped_scope) {
    if (!shipped_rules) {
      Scope.shutdown_hook(_shipped_shutdown);
      shipped_rules = {};
    }
    _require_owned(row.try_own());
    Var shared = 0;
    match (row)
      case %(compile-time rewrite ?point ?kind ?name ?shape ?holes): {
        if (_unit_bound(row) || !Compiler.links_meta_function(name)) break;
        List thawed = %(${c.thaw_declaration_syntax(kind)}
          ${c.thaw_declaration_syntax(shape)}
          ${c.thaw_declaration_syntax(holes)});
        _require_owned(thawed.try_own());
        Var (own_kind, own_shape, own_holes) = thawed;
        shared = _rewrite_rule(
          point, own_kind, name, own_shape, own_holes, 1, 0);
      }
    shipped_rules[row] = shared;
    return shared;
  }
}

module void _require_owned(int owned) {
  if (owned) return;
  fprintf(stderr, "x2c: could not retain a shipped rewrite rule\n");
  abort();
}

static int _unit_bound(Var syntax) {
  if (syntax is not <list>) return 0;
  match (syntax)
    case %((!or declaration-cache declaration-binding declaration-origin) *):
      return 1;
  foreach (Var child in syntax.list()) if (_unit_bound(child)) return 1;
  return 0;
}

/* The first probe of a shared rule's family derives its matcher with the
   process lifetime of the rule. */
static MacroMatcher *_prepared_matcher(RewriteRule rule) {
  if (!rule.prepared && rule.matcher.shape) {
    auto (&shipped_scope) {
      MacroMatcher matcher = rule.matcher.shape.matcher(rule.matcher.holes);
      _require_owned(matcher.pattern.try_own());
      rule.matcher = matcher;
    }
    rule.prepared = 1;
  }
  return &rule.matcher;
}

/* A coarse category selects candidates; each retained pattern decides whether
   the translator applies. Only the active translator is excluded while its
   replacement binds, so independent translations can compose. User rules
   retain registration order ahead of builtin defaults. */
module void _register_rewrite(Compiler c, RewriteRule rule) {
  if (!c.rewrite_rules) c.rewrite_rules = {};
  Var stored;
  Map kinds;
  if (c.rewrite_rules.try_get(rule.point, stored)) kinds = stored;
  else c.rewrite_rules[rule.point] = kinds = {};
  List rows = kinds.try_get(rule.kind, stored) ? stored.list() : NULL;
  foreach (RewriteRule prior in rows)
    if (prior.name == rule.name &&
        prior.matcher.shape == rule.matcher.shape &&
        prior.matcher.holes == rule.matcher.holes &&
        (rule.matcher.shape || prior.matcher.pattern == rule.matcher.pattern))
      return;
  Array ordered = [];
  int inserted = 0;
  foreach (RewriteRule prior in rows) {
    if (!rule.builtin && prior.builtin && !inserted) {
      ordered.push(rule);
      inserted = 1;
    }
    ordered.push(prior);
  }
  if (!inserted) ordered.push(rule);
  kinds[rule.kind] = ordered.list_free();
}

static List _rewrite_candidates(Compiler c, Symbol point, Var kind) {
  Var stored;
  if (!c.rewrite_rules || !c.rewrite_rules.try_get(point, stored)) return NULL;
  Map kinds = stored;
  return kinds.try_get(kind, stored) ? stored.list() : NULL;
}

/** Matches the member rules registered for each field keyword that
    `aggregate` declares a field with, as `Compiler.rewrite` matches those
    keyed by a receiver type. */
List Compiler.marked_rewrite(
  Compiler c, Type aggregate, List source, Token site) {
  Var stored;
  if (!c.rewrite_rules.try_get(<member>, stored)) return NULL;
  foreach (Var (mark, _) in stored.map()) {
    if (mark is not <symbol> || !c.sym.get(%(@aggregate $mark))) continue;
    List rewritten = c.rewrite(
      <member>, mark, source, <expression>, NULL, site);
    if (rewritten) return rewritten;
  }
  return NULL;
}

/** Tests one operation's registry without invoking a translator. */
int Compiler.has_rewrites(Compiler c, Symbol point, Var kind) =>
  !!_rewrite_candidates(c, point, kind);

/** Matches registered patterns for one operation, then binds the first
    replacement. A translator declines with void, null, or its input itself.
    Active rules cannot re-enter. A statement of the same kind that a
    statement replacement writes or copies, such as its source, takes the
    rules after the one that replaced it. */
List Compiler.rewrite(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, Token site) =>
  _rewrite(c, point, kind, source, position, expected, site, 0);

/** Matches registered patterns for the statement `source`, which the
    transform has lowered, then binds the first replacement as
    `Compiler.rewrite` does. Binding keeps the source, and each part of it
    the replacement holds, as lowered. */
List Compiler.rewrite_lowered(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, Token site) =>
  _rewrite(c, point, kind, source, position, expected, site, -1);

/** Lowers `replacement`, which `Compiler.rewrite_lowered` bound for the
    lowered statement `source`, and keeps each part of `source` it holds as
    it is, so no statement rule is offered that part again. */
List Compiler.lower_replacement(Compiler c, List replacement, List source) {
  Array parts = auto [];
  _held_parts(source, <node>, parts);
  struct SlotWatch kept = {parts.list()};
  kept.kept = 1;
  with (c.slot_watch = &kept) { return c.normalize(replacement); }
}

/** Binds the replacement a shipped rule gives the lowered statement
    `source` of `kind`, which the kernel wrote while lowering, as
    `Compiler.rewrite_lowered` does. A statement the kernel writes is not
    source, so no program rule sees it. */
List Compiler.rewrite_written(
  Compiler c, Symbol kind, List source, Type expected) {
  struct SlotWatch written = {.shipped = 1};
  with (c.slot_watch = &written) {
    return c.rewrite_lowered(
      <node>, kind, source, <statement>, expected, NULL);
  }
}

/** Binds and lowers a replacement while its rule remains active. The
    source expressions the replacement holds lower outside the rule, so a
    nested use of the rule applies again. A statement replacement, or a
    lowered one, also lowers the statements its source held outside the
    rule, and lowers once, so a new statement it writes stays outside the
    rule. Code a shipped rule's replacement writes, such as the support call
    an interpolated String or a collection literal lowers to, is not source,
    so only shipped rules see it. An expression retains the result type
    already established for its parent. A replacement whose template and
    slot signatures an earlier use in the unit prepared lowers only its
    captured values. */
List Compiler.lower_rewrite(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, Token site) =>
  _rewrite(c, point, kind, source, position, expected, site, 1);

/* `lower` is 1 to lower the replacement, 0 to bind it, and -1 to bind it
   around a lowered source. */
static List _rewrite(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, Token site, int lower) {
  // A meta body still completes and formats the calls it makes.
  if (c.macro_holes || (c.meta_body && point != <member> && point != <call>))
    return NULL;
  // Code that a shipped rule or the kernel writes is not source.
  int shipped = c.slot_watch && c.slot_watch.shipped;
  foreach (RewriteRule rule in _rewrite_candidates(c, point, kind)) {
    if (c.active_rewrites.contains(rule) || (shipped && !rule.builtin))
      continue;
    if (lower > 0 && rule.builtin && point == <function>) {
      List lifted = c.lift_lambda_types(source);
      if (lifted !== source)
        with (c.applying = cons(rule, c.active_rewrites)) {
          return _lowered_definition(c, lifted);
        }
    }
    MacroMatcher *matcher = _prepared_matcher(rule);
    if (matcher.shape ? !c.matches_macro(*matcher, source)
                      : !source.match(matcher.pattern)) continue;
    Var result = _applied(c, rule, source, site);
    if (result is void ||
        (result is <list> && (!result.list() || result.list() === source)))
      continue;
    with (c.active_rewrites = cons(rule, c.active_rewrites)) {
      if (lower <= 0)
        return _bound(
          c, point, kind, source, result, position, expected, site, lower);
      if (position == <unit>) return _lowered_definition(c, result);
      int held = point == <node>;
      match (result) case %(code-value "lowered" *): held = 1;
      if (held) {
        Array parts = auto [];
        _held_parts(source, point, parts);
        return _watched(c, result, parts, position, expected, site);
      }
      return _prepared(c, source, result, position, expected, site);
    }
  }
  return NULL;
}

/* What `rule` answers for `source`. The code its meta function places
   while it runs is that rule's, as its replacement is. */
static Var _applied(
  Compiler c, RewriteRule rule, List source, Token site) {
  with (c.applying = cons(rule, c.active_rewrites)) {
    return c.apply_meta_function(rule.name, %($source), site);
  }
}

/* Pushes the parts of `source` that its replacement may hold onto
   `found`, to lower outside its rule: each expression, or for a statement
   each statement and outermost expression beneath it, such as a match's
   subject, patterns, and arm bodies. A nested statement of the same kind
   in one of them applies the rule again. */
static void _held_parts(List source, Symbol point, Array found) {
  if (point != <node>) {
    foreach (Var part in source) _expression_nodes(part, found);
    return;
  }
  List node;
  $ast.walk(source.cdr(), node) {
    if (node.car() is <symbol>) found.push(node);
    if (node.car() == <expr>) continue;
  }
}

/* A replacement bound without lowering. A statement of the rule's kind
   that a statement replacement holds, such as its source, and that is not
   a part its source held, takes the rules after this one now, so lowering
   never offers it to this rule again. With `lower` -1 the source is
   lowered, so binding keeps it and the parts of it the replacement holds.
   File-scope code that a shipped rule gives is written. */
static List _bound(
  Compiler c, Symbol point, Var kind, List source, Var result,
  Symbol position, Type expected, Token site, int lower) {
  if (point != <node>)
    return _bind_replacement(c, result, position, expected);
  Array parts = auto [];
  _held_parts(source, point, parts);
  if (lower) result = _kept_lowered(result, source, parts);
  List bound = _bind_replacement(c, result, position, expected);
  if (position == <unit>) bound = _written_support(c, bound);
  struct SlotWatch held = {parts.list()};
  return _bound_held(c, &held, kind, bound, position, expected, site, lower);
}

/* Binds a replacement at `position`. Outside any local scope, as when the
   transform lowers a function, a statement or expression replacement
   declares its names in a scope of its own, so no other function sees
   them. */
static List _bind_replacement(
  Compiler c, Var result, Symbol position, Type expected) {
  int own = position != <unit> && c.sym.at_file_scope();
  if (own) c.sym.push_new_scope();
  defer if (own) c.sym.pop_scope();
  return c.bind_syntax(result, position, expected);
}

/* `result` with `source` and each of its `parts` that it holds marked as
   lowered code, which binding keeps as it is. A lowered carrier binds as it
   is already. */
static Var _kept_lowered(Var result, List source, Array parts) {
  match (result) case %(code-value "lowered" *): return result;
  Map kept = auto {};
  kept[(void *) source] = Code.lowered(source, NULL);
  foreach (List part in parts) kept[(void *) part] = Code.lowered(part, NULL);
  return Ast.replace_nodes(result, kept);
}

static Var _bound_held(
  Compiler c, SlotWatch held, Symbol kind, Var ast, Symbol position,
  Type expected, Token site, int lower) {
  if (!Ast.contains_head(ast, kind) || _find_slot(held, ast) >= 0) return ast;
  List node = ast;
  if (node.car() == kind) {
    List rewritten =
      _rewrite(c, <node>, kind, node, position, expected, site, lower);
    return rewritten ? rewritten : node;
  }
  Var child;
  $ast.rewrite_children(
    node, child,
    _bound_held(c, held, kind, child, position, expected, site, lower));
}

/* A replacement definition binds at file scope and lowers as written,
   unless it is a lowered carrier. It lowers outside the watch that chose
   its rule, as any definition does, and a shipped rule's is written. */
static List _lowered_definition(Compiler c, Var result) {
  List bound = c.bind_syntax(result, <unit>, NULL);
  match (bound) case %(seq ?only): bound = only;
  match (result) case %(code-value "lowered" *): return bound;
  with (c.slot_watch = NULL) {
    return c.normalize(_written_support(c, bound));
  }
}

/* The bound file-scope code `bound` that the rule now writing gives,
   written as the kernel's when that rule is shipped. A rule writes while
   its meta function runs, until a rule it reaches binds, and while its
   replacement binds and lowers. What a program writes, or a placement
   outside any rule, is source. */
module List _written_support(Compiler c, List bound) {
  List writers = c.applying && c.applying.cdr() === c.active_rewrites
    ? c.applying : c.active_rewrites;
  RewriteRule writer = writers ? writers.car() : NULL;
  return writer && writer.builtin ? Ast.written_definitions(bound) : bound;
}

/** Whether the rule whose meta function now runs is shipped, so that the
    names it calls resolve to the copies the compiler links. */
int Compiler.applying_shipped(Compiler c) {
  RewriteRule applying = c.applying ? c.applying.car() : NULL;
  return applying && applying.builtin;
}

/* Binds, converts, and lowers a replacement as written. */
static List _lowered(
  Compiler c, Var result, Symbol position, Type expected, Token site) {
  List bound = _bind_replacement(c, result, position, expected);
  if (position == <expression>) {
    bound = c.convert_expression(bound, expected);
    Type actual = bound.cadr();
    if (actual.canonicalize() != expected.canonicalize())
      $fail.macros_result_type(c, site, expected, actual);
  }
  return c.normalize(bound);
}

static Effects _effects(Compiler c) {
  PendingMark mark = c.pending.checkpoint();
  int pending = 0;
  for (int i = 0; i < PENDING_AREAS; i++) pending += mark.lengths[i];
  return (Effects){
    c.sym.introduced(), c.names.issued, c.origins.len(), pending,
    c.placements.len(), c.diagnostics.entries.len()};
}

static Effects _since(Effects after, Effects before) => (Effects){
  after.bindings - before.bindings, after.names - before.names,
  after.origins - before.origins, after.pending - before.pending,
  after.placements - before.placements,
  after.diagnostics - before.diagnostics};

static Effects _add(Effects a, Effects b) => (Effects){
  a.bindings + b.bindings, a.names + b.names, a.origins + b.origins,
  a.pending + b.pending, a.placements + b.placements,
  a.diagnostics + b.diagnostics};

static int _same(Effects a, Effects b) =>
  !memcmp(&a, &b, sizeof(Effects));

/* Lowers `result` from the skeleton its template and slot signatures
   prepared in this unit, preparing one on their first use. The source's
   own expressions lower outside the active rule, as they would have
   without it, so a rule applies again to a nested use. A carrier, such as
   a lowered result, never prepares and lowers as written. */
static List _prepared(
  Compiler c, List source, Var result, Symbol position, Type expected,
  Token site) {
  auto Array sources = [], values = [];
  _expression_nodes(source, sources);
  match (result) case %(code-value *):
    return _watched(c, result, sources, position, expected, site);
  int refused = 0;
  Var shape = _template(c, result, sources, values, refused);
  if (refused) return _watched(c, result, sources, position, expected, site);
  RewriteRule rule = c.active_rewrites.car();
  List key = %(${(int) position} ${rule.builtin} $expected $shape);
  if (!c.prepared_rewrites) c.prepared_rewrites = {};
  Var stored;
  if (c.prepared_rewrites.try_get(key, stored))
    return stored is <list>
      ? _fill_values(c, stored, values)
      : _watched(c, result, sources, position, expected, site);
  if (_carries(shape)) {
    c.prepared_rewrites[key] = 0;
    return _watched(c, result, sources, position, expected, site);
  }
  if (c.sym.transacting())
    return _watched(c, result, sources, position, expected, site);
  Preparation preparation = {[], []};
  struct SlotWatch watch = {values.list(), &preparation};
  watch.outer = c.active_rewrites.cdr();
  watch.shipped = rule.builtin;
  foreach (List value in values) preparation.outputs.push(NULL);
  Effects before = _effects(c);
  List lowered;
  with (c.slot_watch = &watch) {
    lowered = _lowered(c, result, position, expected, site);
  }
  // A memo the template fills adds state only on its first lowering.
  if (!_same(_since(_effects(c), before), preparation.inner)) return lowered;
  List skeleton =
    !preparation.repeated && preparation.order.len() == values.len()
    ? _skeleton(lowered, preparation.outputs) : NULL;
  c.prepared_rewrites[key] =
    skeleton ? %($skeleton ${preparation.order.list()}) : 0;
  return lowered;
}

/* Lowers `result` as written, with the source parts in it lowered outside
   the active rule. */
static List _watched(
  Compiler c, Var result, Array sources, Symbol position, Type expected,
  Token site) {
  struct SlotWatch watch = {sources.list()};
  watch.outer = c.active_rewrites.cdr();
  if (c.slot_watch && !c.slot_watch.preparation) watch.parent = c.slot_watch;
  RewriteRule rule = c.active_rewrites.car();
  watch.shipped = rule.builtin || (watch.parent && watch.parent.shipped);
  with (c.slot_watch = &watch) {
    return _lowered(c, result, position, expected, site);
  }
}

/* Pushes each expression within `source`, which a translator may insert
   whole, onto `found`. A chain nests as deeply as it is long, so the walk
   keeps its pending work off the C stack. */
static void _expression_nodes(List source, Array found) {
  List syntax;
  $ast.walk(source, syntax)
    if (syntax !== source && syntax.car() == <expr>) found.push(syntax);
}

/* `node` with each expression from `sources` replaced by its slot
   signature `("x2c.slot" TYPE SHAPE)` and pushed onto `values`. A literal
   stays in the template, which then lowers it as written. Sets
   `refused` for a value inserted twice or a value whose content conversion
   or lowering reads beyond its signature. */
static Var _template(
  Compiler c, Var node, Array sources, Array values, int &refused) {
  if (node is not <list> || node.is_nil()) return node;
  List syntax = node;
  match (syntax) case %(expr ?type ?content):
    foreach (List value in sources)
      if (value === syntax)
        return _capture_slot(c, syntax, type, content, values, refused);
  Var child;
  $ast.rewrite_children(
    syntax, child, _template(c, child, sources, values, refused));
}

static Var _capture_slot(
  Compiler c, List value, Var type, Var content, Array values,
  int &refused) {
  match (content) case %(literal *): return value;
  Var shape = _slot_shape(c, content);
  foreach (List prior in values) if (prior === value) shape = void;
  if (shape is void) {
    refused = 1;
    return value;
  }
  values.push(value);
  return %("x2c.slot" $type $shape);
}

/* What conversion and lowering read of a slot value's content besides its
   type: a literal's value, whether a name is a lambda's snapshot, an
   operator with its single operand or a member access with its base, a
   group's content, or else the content's head. Void for content they read
   further, such as a conditional or a composite. */
static Var _slot_shape(Compiler c, Var content) {
  match (content) {
    case %(literal *): return content;
    case %(ident ?binding):
      return %(lambda-snapshot $binding) in c.semantic_binding_facts()
        ? %(ident snapshot) : <ident>;
    case %((!or ?head call index getindex postfix cast cache) *):
      return head;
    case %(parens (expr ? ?inner)): return _nested_shape(c, <parens>, inner);
    case %(op . (expr ? ?base) ?): return _nested_shape(c, %(op .), base);
    case %(op ?operator (expr ? ?operand)):
      return _nested_shape(c, %(op $operator), operand);
    case %(op ?operator ? ?):
      return operator == <,> ? void : %(op $operator);
  }
  return void;
}

/* `prefix` followed by the shape of `content`, or void when it has none. */
static Var _nested_shape(Compiler c, Var prefix, Var content) {
  Var shape = _slot_shape(c, content);
  return shape is void ? void : %($prefix $shape);
}

/* Whether a template holds pending code or a carrier, which binding expands
   with its slot values. */
static int _carries(Var shape) {
  if (shape is not <list>) return 0;
  match (shape)
    case %((!or code-value macro-invoke "x2c.template" "x2c.quoted") *):
      return 1;
  foreach (Var child in shape.list()) if (_carries(child)) return 1;
  return 0;
}

/* `lowered` with each watched output replaced by its `("x2c.slot" I)`
   marker, or NULL unless each occurs exactly once and the code holds no
   anchor, block, sequence, statement, or declaration, whose lowering gives
   a slot a context that lowering the value alone would not. */
static List _skeleton(List lowered, Array outputs) {
  Array found = auto [];
  foreach (List output in outputs) found.push(0);
  int refused = 0;
  List skeleton = _marked(lowered, outputs, found, refused);
  foreach (int count in found) if (count != 1) refused = 1;
  return refused ? NULL : skeleton;
}

static Var _marked(Var node, Array outputs, Array found, int &refused) {
  if (node is not <list> || node.is_nil()) return node;
  List syntax = node;
  for (int i = 0; i < (int) outputs.len(); i++)
    if (outputs[i].list() === syntax) {
      found[i] = found[i].int() + 1;
      return %("x2c.slot" $i);
    }
  match (syntax)
    case %((!or at block seq stmnt decl declare) *): refused = 1;
  List child;
  $ast.rewrite_children(
    syntax, child, _marked(child, outputs, found, refused));
}

/* Lowers each slot's value, outside the active rule, in the order the
   first lowering reached them and fills the skeleton with the results. */
static List _fill_values(Compiler c, List prepared, Array values) {
  (List skeleton, List order) = prepared;
  Array lowered = auto values.copy();
  with (c.active_rewrites = c.active_rewrites.cdr()) {
    foreach (int slot in order)
      lowered[slot] = c.normalize(values[slot]);
  }
  return _filled(skeleton, lowered);
}

static Var _filled(Var node, Array lowered) {
  if (node is not <list> || node.is_nil()) return node;
  List syntax = node;
  Var head = syntax.car();
  if (head is <string> && head == "x2c.slot")
    return lowered[syntax.cadr().int()];
  Var child;
  $ast.rewrite_children(syntax, child, _filled(child, lowered));
}

/* The index of `ast` among the values `watch` watches, or -1. A statement
   that binding the replacement built again from a value keeps the value's
   origin. */
static int _find_slot(SlotWatch watch, Ast ast) {
  int slot = 0, at = ast.car() == <at>;
  for (List v = watch.values; v; v = v.cdr(), slot++) {
    List value = v.car();
    if (value === ast ||
        (at && value.car() == <at> && value.cadr() == ast.cadr()))
      return slot;
  }
  return -1;
}

/** Records that binding built the statement `bound` again from `source`,
    a value the active lowering watches, so it watches `bound` as well. A
    statement without an origin, such as an unbraced body, keeps nothing
    else that identifies it when a binder it uses binds again. */
void Compiler.rebound(Compiler c, Var source, List bound) {
  SlotWatch watch = c.slot_watch;
  if (!watch || watch.preparation || bound === source ||
      _find_slot(watch, source) < 0)
    return;
  watch.values = watch.values.append(%($bound));
}

/** Lowers `ast` when it is a value the active lowering watches; NULL otherwise.
    A preparing watch also records what lowering produced. A value that an
    enclosing replacement's source held as well lowers outside that
    replacement's rule too, and that replacement still watches its own
    values within it. */
Ast Compiler.watched_step(Compiler c, Ast ast) {
  SlotWatch watch = c.slot_watch, owner = watch;
  int slot = _find_slot(watch, ast);
  if (slot < 0) return NULL;
  while (owner.parent && _find_slot(owner.parent, ast) >= 0)
    owner = owner.parent;
  if (owner.kept) return ast;
  Preparation *preparation = watch.preparation;
  Effects before = {0};
  if (preparation) before = _effects(c);
  Ast lowered;
  with (c.slot_watch = owner.parent, c.active_rewrites = owner.outer) {
    lowered = c.normalize(ast);
  }
  if (preparation) {
    preparation.inner = _add(preparation.inner, _since(_effects(c), before));
    if (preparation.outputs[slot].list_payload()) preparation.repeated = 1;
    preparation.outputs[slot] = lowered;
    preparation.order.push(slot);
  }
  return lowered;
}
