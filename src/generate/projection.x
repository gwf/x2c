/*  projection.x -- select ordered header and source declarations */

// header and source

/* One unit's split into header and source. `pending` holds each late
   native include as `(names node)`, `open` the conditional groups still
   open, `forwarded` the struct and union tags the header declares,
   `included` the files its includes reach, and `statics` the bindings
   static declarations declare. The source projection writes the source;
   `source_started` records that it holds an item, and `source_groups` the
   conditional groups that hold one. */
static typedef struct Partition {
  Compiler c, Array header, pending, open;
  Map forwarded, included, statics, source_groups;
  int source_started;
} Partition;

/* The header items the markers are decided against. `declared` maps each
   typedef name to the first header position declaring it, and `spelled`
   holds the type names the items from position `walked` on spell. */
static typedef struct HeaderNeeds {
  Array header;
  Map declared, spelled;
  int walked;
} HeaderNeeds;

/* Partition a normalized unit without changing source order. Non-inline
   public functions publish a header declaration and keep their body in the
   source; public inline definitions also publish their bodies. Static
   functions and objects stay in the source. Static types enter the header
   when a public declaration or inline body needs them. */
module List _header_and_source(
  Compiler c, List ast, Map inline_bodies) {
  Partition p = {
    .c = c, .header = [], .pending = [], .open = [], .forwarded = {},
    .included = {}, .statics = {}, .source_groups = {}};
  foreach (Ast node in ast) _add(p, node);
  return %(${_finish(p)} ${_source_projection(c, ast, inline_bodies)});
}

/* The unit consumes its declarations where they were written, independently
   of the public projection. In particular, a promoted include must not
   change the native macro state before its source position. */
static List _source_projection(
  Compiler c, List ast, Map inline_bodies) {
  Array source = [];
  foreach (List node in ast) {
    match (node) {
      case %((!or protocol adopt macrodef) *): continue;
      case %(preproc ?(String content)):
        if (_is_pragma_once(content)) continue;
      case %(import ?unit *):
        node = %(preproc "#include \"${unit.string()}.x\"");
      case %(function ?type (!set ?declarator (bind ?binding *)) ?body): {
        type = _with_attributes(c.semantic_binding_facts(), type, binding);
        type = _noreturn(type, declarator, body);
        Type function_type = type;
        if (function_type.is_inline() && !function_type.is_static()) {
          inline_bodies[binding] = 1;
          node = _header_function(type, declarator, body);
        }
        else node = %(function $type $declarator $body);
      }
      case %(declare ?type (bindings *declarators)): {
        List kept = declarators.filter(
          %!(item) => !_completed_prototype(c, _declaration_binding(item)));
        if (!kept && !_body_tag(type)) continue;
        node = %(declare $type (bindings @kept));
      }
    }
    node = _without_static_type(node);
    source.push(node);
  }
  return _typedef_forwards(source.list_free(), NULL, c);
}

static void _add(Partition &p, Ast node) {
  match (node) {
    case %((!or protocol adopt macrodef c-assert) *): return;
    case %(typedef ? (bindings *)): _add_typedef(p, node);
    case %(function (!set ?type (*)) ?declarator (!set ?body (block *))):
      _add_function(p, type, declarator, body);
    case %(!set ?decl
           (declare (!set ?type (*)) (!set ?bindings (bindings *)))):
      _add_declaration(p, decl, type, bindings);
    case %(!set ?alias (falias (declare (!set ?type (*)) ?) ?)):
      _add_alias(p, alias, type);
    /* The public projection exposes the imported package's types. */
    case %(import ?unit *):
      p.header.push(%(preproc "#include \"${unit.string()}.x\""));
    case %(preproc ?content): _add_preproc(p, node, content);
    default: _publish_node(p, node);
  }
}

/* A public node that names a static declaration could not compile in the
   header, so it stays in the source, and what it declares stays there as
   if it were static. */
static void _publish_node(Partition &p, List node) {
  if (!_names_static(node, p.statics)) {
    p.header.push(node);
    return;
  }
  _add_declared(node, p.statics);
  _keep(p);
}

/* Both walks keep pending parts off the C stack, since an expression can
   nest deeply. */
static int _names_static(List node, Map statics) {
  if (!statics.len()) return 0;
  Array pending = auto [node];
  while (pending.len()) {
    Var item = pending.take_last();
    if (item is not <list>) continue;
    match (item) {
      case %(binding ? ?): if (item in statics) return 1;
      default: foreach (Var part in item) pending.push(part);
    }
  }
  return 0;
}

/* Adds to `statics` each binding `node` declares: each one it holds other
   than through an `ident` reference. */
static void _add_declared(List node, Map statics) {
  Array pending = auto [node];
  while (pending.len()) {
    Var item = pending.take_last();
    if (item is not <list>) continue;
    match (item) {
      case %(ident *): continue;
      case %(binding ? ?): statics[item] = 1;
      default: foreach (Var part in item) pending.push(part);
    }
  }
}

/* Records the objects or function a static declaration declares. */
static void _add_statics(Partition &p, List declarators) {
  foreach (List declarator in declarators) {
    List binding = _declaration_binding(declarator);
    if (binding) p.statics[binding] = 1;
  }
}

/* An item the source keeps fills each group open around it. */
static void _keep(Partition &p) {
  p.source_started = 1;
  foreach (Var group in p.open) p.source_groups[group] = 1;
}

/* Settle pending includes and conditional groups in the public projection.
   A marker left after promotion leaves its include to the source. */
static List _finish(Partition &p) {
  _promote_typedefs(p.header, p.pending);
  List header = p.header.list().filter(
    %!(item) => !item.list().match(%(pending ?)));
  header = _place_groups(header, _filled_groups(header), p.source_groups);
  return _typedef_forwards(header, NULL, p.c);
}

/* The collected interface selects static types for both projections.
   Late native includes wait for the header's spelling dependencies. */

static void _add_typedef(Partition &p, List node) {
  Type type = node.cadr();
  node = _without_static_type(node);
  List forward = type.is_static()
    ? _typedef_forward(node.cadr(), node.caddr()) : NULL;
  Type core = type.base_type();
  int body = 0;
  match (core) case %((!or struct union enum) ?name (*)):
    body = p.c.publishes_type_family(%(${core.car()} $name));
  if (type.is_static() && !_publishes_typedefs(p, _typedef_names(node))) {
    _keep(p);
    if (body) _publish_node(p, %(declare $core (bindings (bind () ()))));
    return;
  }
  if (forward && !body) {
    _keep(p);
    _publish_node(p, forward);
    return;
  }
  _publish_node(p, node);
}

static int _publishes_typedefs(Partition &p, List names) {
  foreach (String name in names)
    if (p.c.publishes_typedef(name)) return 1;
  return 0;
}

/* Bare types have no C storage role. Object and function declarations
   retain `static` because it controls their linkage. */
static List _without_static_type(List node) {
  match (node) {
    case %(typedef ?type ?bindings):
      return %(typedef ${_without_static(type)} $bindings);
    case %(declare ?type (!set ?bindings (bindings *))):
      if (!_declared_bindings(bindings))
        return %(declare ${_without_static(type)} $bindings);
  }
  return node;
}

static List _without_static(List type) =>
  type.filter(%!(specifier) => specifier != <static>);

/* A late include declaring `names` waits as a `pending` marker in the
   header until the whole unit has been partitioned. It fills the source
   groups open around it. A promoted include fills the same groups in the
   header, which then keeps them, so this changes no header placement. */
static void _hold(Partition &p, List names, List node) {
  p.header.push(%(pending ${p.pending.len()}));
  p.pending.push(%($names $node));
  foreach (Var group in p.open) p.source_groups[group] = 1;
}

static List _typedef_names(List node) {
  match (node)
    case %(typedef ? (bindings *declarators)): {
      Array names = [];
      foreach (List declarator in declarators)
        match (declarator) {
          case %(bind (binding ? ?name) ?): names.push(name);
          case %(bind (?name) ?): names.push(name);
        }
      return names.list_free();
    }
  return NULL;
}

static List _declared_type_names(List node) {
  List names = _typedef_names(node);
  if (names) return names;
  match (node) case %(declare ?type ?): {
    List base = type.list().type().base_type();
    match (base) case %((!set ?kind (!or struct union enum)) ?name (*)):
      return %(($kind $name));
  }
  return NULL;
}

/* The markers are decided from last to first, so a promoted typedef counts
   as a later header item for the markers before it. */
static void _promote_typedefs(Array header, Array pending) {
  HeaderNeeds needs = {.header = header, .walked = header.len()};
  for (int i = header.len() - 1; i >= 0; i--)
    match (header[i]) case %(pending ?index): {
      (List names, List node) = pending[index];
      if (_at(needs, i, names)) header[i] = node;
    }
}

/* A header item after position `i` spells one of `names` that no header
   typedef before `i` declares. */
static int _at(HeaderNeeds &n, int i, List names) {
  foreach (String name in names)
    if (!_declared_before(n, i, name) && _spelled_after(n, i, name)) return 1;
  return 0;
}

/* Only positions after the marker being decided have changed, so the first
   declarations come from the header as it is when first needed. */
static int _declared_before(HeaderNeeds &n, int i, Var name) {
  if (!n.declared) {
    n.declared = {};
    int count = n.header.len();
    for (int j = 0; j < count; j++)
      if (n.header[j] is <list>)
        foreach (Var declared in _declared_type_names(n.header[j]))
          if (!(declared in n.declared)) n.declared[declared] = j;
  }
  Var first;
  return n.declared.try_get(name, first) && first.int() < i;
}

/* Every item after `i` is decided, so each is read once, as it stands. */
static int _spelled_after(HeaderNeeds &n, int i, Var name) {
  if (!n.spelled) n.spelled = {};
  while (n.walked > i + 1) {
    Var item = n.header[--n.walked];
    if (item is <list>) _spelled_types(item, n.spelled);
  }
  return name in n.spelled;
}

/* Adds each typedef name `node` spells anywhere to `names`, as a
   single-string type atom such as `("Point")`, alone or after qualifiers
   and storage, as in `(extern "Point")`. */
module void _spelled_types(List node, Map names) {
  List item;
  $ast.walk(node, item) {
    List base = item;
    while (base.car() is <symbol> &&
           (base.car().symbol().is_type_qualifier() ||
            base.car().symbol().is_storage_class()))
      base = base.cdr();
    if (base.car() is <string> && !base.cdr()) names[base.car()] = 1;
    match (base)
      case %((!set ?kind (!or struct union enum)) ?name *):
        names[%($kind $name)] = 1;
  }
}

// functions

static void _add_function(
  Partition &p, List type, List declarator, Ast body) {
  match (declarator) case %(bind ?binding *):
    type = _with_attributes(p.c.semantic_binding_facts(), type, binding);
  _place_function(p, type, declarator, body);
}

static List _with_attributes(Map facts, List type, Var binding) {
  Var attributes;
  if (!facts.try_get(%(attributes $binding), attributes)) return type;
  return %(@{attributes.list()} @type);
}

/* A static definition stays in the source. A public one publishes its
   prototype, or its whole body when inline, after forward declarations of
   the tags the prototype spells. */
static void _place_function(
  Partition &p, Type type, List declarator, Ast body) {
  type = _noreturn(type, declarator, body);
  if (type.is_static()) {
    _add_statics(p, %($declarator));
    _keep(p);
    return;
  }
  _forward_tags(p, %($type $declarator));
  p.header.push(_header_function(type, declarator, body));
  if (!type.is_inline()) _keep(p);
}

/* C sees only the prototype of a helper that always raises, so a caller
   whose last statement is that call looks like a missing return. Marking
   the type here reaches every generated form of the function. C forbids
   `_Noreturn` on `main`. */
static Type _noreturn(Type type, List declarator, Ast body) {
  if (body.never_returns() && !(%("_Noreturn") in type.list()) &&
      Ast.binding_spelling(declarator.cadr()) != "main")
    return %(("_Noreturn") @type);
  return type;
}

/* A public inline function goes into the header whole, as static; any
   other public function publishes its prototype. */
static List _header_function(Type type, List declarator, List body) {
  if (type.is_inline()) return %(function (static @type) $declarator $body);
  return _prototype(type, declarator);
}

module List _prototype(List type, List declarator) =>
  %(declare $type ${Ast.prototype_declarator(declarator)});

/* A public prototype that names `struct tag` before the header declares it
   would give the tag prototype scope in C. A forward declaration of each
   tag the prototype spells keeps it the file-scope type. */
static void _forward_tags(Partition &p, List node) {
  match (node)
    case %((!set ?tag (!or struct union)) ?(String name)): {
      if (name in p.forwarded) return;
      p.forwarded[name] = 1;
      p.header.push(%(declare ($tag $name) (bindings (bind () ()))));
      return;
    }
  foreach (Var item in node) if (item is <list>) _forward_tags(p, item);
}

// declarations

/* A nonstatic declaration belongs to the header, apart from an object of
   an anonymous type. A static aggregate body waits for type promotion.
   A public struct or
   union declaration puts its tag in the header, so no prototype forwards it
   again. */
static void _add_declaration(
  Partition &p, List decl, Type type, List bindings) {
  if (type.is_static()) _add_statics(p, bindings.cdr());
  if (!type.is_static()) {
    Compiler c = p.c;
    Map statics = p.statics;
    List public = bindings.cdr().filter(
      %!(item) => !_names_static(item, statics) &&
                 !_completed_prototype(c, _declaration_binding(item)));
    if (!public && !_body_tag(type)) return;
    bindings = %(bindings @public);
    decl = %(declare $type $bindings);
  }
  if ((type.is_static() && !_body_tag(type)) ||
      (_anonymous_body(type) && _declares_object(bindings))) {
    _keep(p);
    return;
  }
  if (type.is_static() && _body_tag(type)) {
    List core = type.base_type();
    List family = %(${core.car()} ${core.cadr()});
    if (p.c.publishes_type_family(family))
      _publish_node(p, %(declare $core (bindings (bind () ()))));
    else _keep(p);
    if (_declares_object(bindings)) _keep(p);
    return;
  }
  match (type.base_type())
    case %((!or struct union) ?(String tag) *): p.forwarded[tag] = 1;
  if (!_place_tagged_object(p, decl, type, bindings) &&
      !_place_object(p, decl, type, bindings))
    _publish_node(p, _header_declaration(decl, type, bindings));
}

/* A positioned prototype remains visible to symbol collection, but the
   completed definition is what reaches generated C and H output. */
static int _completed_prototype(Compiler c, List binding) {
  Var stored;
  if (!c.semantic_binding_facts().try_get(%(completion $binding), stored))
    return 0;
  match (stored) case %(completed *): return 1;
  return 0;
}

/* `struct b { ... } g;` at public file scope publishes the body, without
   the qualifiers of `g`, and an `extern` declaration of `g` unless `g` is
   static, and defines `g` in the source. */
static int _place_tagged_object(
  Partition &p, List decl, Type type, List bindings) {
  String tag = _body_tag(type);
  if (!tag || !_declares_object(bindings)) return 0;
  Type core = type.base_type();
  List tagged = _tag_only(type, core, tag);
  _publish_node(p, %(declare $core (bindings (bind () ()))));
  if (!type.is_static())
    _publish_node(p, _object_header(p, decl, tagged, bindings));
  _keep(p);
  return 1;
}

/* Anonymous or bare tags return NULL; named bodies yield their tag. */
static String _body_tag(Type type) {
  match (type.base_type())
    case %((!or struct union enum) ?(String tag) (*)): return tag;
  return NULL;
}

/* `type` with its tag body `core` replaced by the bare tag `name`. */
static List _tag_only(Type type, Type core, Var name) =>
  type.list()[:type.len() - core.len()].append(%(${core.car()} $name));

/* A public file-scope object has one definition, in the source, and an
   `extern` declaration in the header. Defining it in the header would give
   every including unit its own copy, and a runtime initializer there is not
   a C constant expression. A definition whose initializer has to run loses
   `const` in C, so its declaration loses it too. */
static int _place_object(
  Partition &p, List decl, Type type, List bindings) {
  if (type.is_extern() || !_declares_object(bindings)) return 0;
  _publish_node(p, _object_header(p, decl, type, bindings));
  _keep(p);
  return 1;
}

/* Both forms of public object use the qualifiers their C definition keeps. */
static List _object_header(
  Partition &p, List decl, Type type, List bindings) {
  if (p.c.static_value_is_runtime(decl, NULL)) {
    type = _without_const(type);
    bindings = _runtime_without_const(p.c, bindings);
  }
  return _header_declaration(NULL, %(extern @type), bindings);
}

static List _without_const(List specifiers) =>
  specifiers.filter(%!(specifier) => specifier != <const>);

/* `bindings` with `const` removed from each const declarator whose
   initializer has to run. */
static List _runtime_without_const(Compiler c, List bindings) {
  Array declarators = [];
  foreach (List declarator in bindings.cdr()) {
    match (declarator)
      case %(op = (bind ?name (!set ?mods (const *))) ?value)
        if (c.static_value_is_runtime(value, NULL)):
        declarator = %(bind $name ${_without_const(mods)});
    declarators.push(declarator);
  }
  return %(bindings @{declarators.list_free()});
}

/* Objects and functions have linkage; a bare type declaration does not. */
static int _declared_bindings(List bindings) {
  foreach (List declarator in bindings.cdr())
    if (_declaration_binding(declarator)) return 1;
  return 0;
}

/* A binding list with an object declarator owns storage. */
static int _declares_object(List bindings) {
  match (bindings) case %(bindings *declarators):
    foreach (List declarator in declarators)
      match (declarator) {
        case %(bind ? ((fnmod *) *)): continue;
        case %(bind ?name *): if (name) return 1;
        case %(op = * *): return 1;
      }
  return 0;
}

/* `struct { ... } name;` gives `name` a type that no other declaration can
   repeat, so it has no `extern` declaration to publish. */
static int _anonymous_body(Type type) {
  match (type.base_type())
    case %((!or struct union enum) (gensym *) (*)): return 1;
  return 0;
}

/* The header form of a declaration: an `extern` declaration without its
   initializers, a tag body alone, or the declaration as written. */
static List _header_declaration(List node, Type type, List bindings) {
  if (type.is_extern()) {
    Array declarators = [];
    foreach (List declarator in bindings.cdr()) {
      match (declarator) case %(op = ?bind ?): declarator = bind;
      declarators.push(declarator);
    }
    return %(declare $type (bindings @{declarators.list_free()}));
  }
  if (type.is_enum_tag_body() || type.is_aggregate_tag_body())
    return %(declare $type (bindings (bind () ())));
  return node;
}

static void _add_alias(Partition &p, List alias, Type type) {
  if (type.is_static()) _keep(p);
  else p.header.push(alias);
}

/* directives

   A conditional directive inside an open group becomes a `conditional`
   marker in the header until the unit is partitioned. */

/* Each conditional group takes the position where its first marker opens. */
static void _add_preproc(Partition &p, List node, String content) {
  Symbol kind = Compiler.preproc_conditional_kind(content);
  if (kind == <open>) p.open.push(p.header.len());
  if (kind && p.open.len()) _mark_conditional(p, node, kind);
  else _place_directive(p, node, content);
}

static void _mark_conditional(Partition &p, List node, Symbol kind) {
  p.header.push(%(conditional ${p.open[-1]} $kind $node));
  if (kind == <close>) p.open.take_last();
}

/* The generator writes the header guard. Includes follow their source
   position in each projection. */
static void _place_directive(
  Partition &p, List node, String content) {
  if (_is_pragma_once(content)) return;
  int angle = 0;
  String target = Compiler.preproc_include_target(content, angle);
  if (target) _add_include(p, node, target, angle);
  else _publish_directive(p, node);
}

/* A public directive belongs to the header. */
static void _publish_directive(Partition &p, List node) {
  p.header.push(node);
}

/* A late include waits under its typedef names and is promoted when a
   public declaration needs one. The source keeps it at its position. */
static void _add_include(
  Partition &p, List node, String target, int angle) {
  if (!p.source_started) {
    p.c.include_typedef_names(target, angle, p.included);
    p.header.push(node);
    return;
  }
  List names = p.c.include_typedef_names(target, angle, p.included.copy());
  if (names) _hold(p, names, node);
  else _keep(p);
}

static int _is_pragma_once(String content) =>
  content.strip(" \t\r\n") == "#pragma once";

/* The groups among `items` that contain an item other than a conditional
   directive, including through a nested group. */
static Map _filled_groups(List items) {
  Map filled = {};
  Array open = [];
  foreach (List item in items) {
    match (item)
      case %(conditional ?group ?kind ?): {
        if (kind == <open>) open.push(group);
        else if (kind == <close>) open.take_last();
        continue;
      }
    foreach (Var group in open) filled[group] = 1;
  }
  return filled;
}

/* A group enters the header when it contains a public item, or no item.
   The independent source projection keeps its original conditional groups. */
static List _place_groups(
  List items, Map filled, Map other) {
  Array out = [];
  foreach (List item in items) {
    match (item)
      case %(conditional ?group ? ?node): {
        if (group in filled || !(group in other))
          out.push(node);
        continue;
      }
    out.push(item);
  }
  return out.list_free();
}

/* typedef forwards

   A completed aggregate typedef can supply its alias before an earlier
   field needs it. The forward uses the final declarator, preserving pointer
   and value identity; an incomplete by-value field remains a native error. */

static List _typedef_forwards(List items, List earlier, Compiler c) {
  Array candidates = _forward_candidates(items, c != NULL), out = [];
  Map available = {}, first = {}, included = {}, moved = {};
  foreach (List node in earlier) _add_names(available, node);
  for (int i = candidates.len() - 1; i >= 0; i--)
    first[candidates[i].car()] = i;
  foreach (List node in items) {
    if (node in moved) continue;
    match (node) {
      case %(typedef ?base ?):
        _add_forwards(out, candidates, first, available, base, moved);
      case %(preproc ?(String text)) if (c): {
        int angle = 0;
        String target = Compiler.preproc_include_target(text, angle);
        if (target) _add_forwards(
          out, candidates, first, available,
          c.include_type_dependencies(target, angle, included), moved);
      }
    }
    out.push(node);
    _add_names(available, node);
  }
  candidates.free();
  return out.list_free();
}

/* Each alias is paired with its tag-only typedef. A header must declare
   an enum completely before an included field can use it by value. */
static Array _forward_candidates(List items, int complete_enums) {
  Array candidates = [];
  foreach (List node in items)
    match (node) case %(typedef ?base ?bindings): {
      List forward = _typedef_forward(base, bindings);
      if (!forward && complete_enums)
        match (base.list().type().base_type())
          case %(enum ? (*)): forward = node;
      if (!forward) continue;
      foreach (String alias in _typedef_names(node))
        candidates.push(%($alias $forward));
    }
  return candidates;
}

/* The same typedef over the bare tag, or NULL unless `type` is a struct or
   union body with a tag. */
static List _typedef_forward(Type type, List bindings) {
  Type core = type.base_type();
  match (core)
    case %((!or struct union) ?(String name) (fields *)):
      return %(typedef ${_tag_only(type, core, name)} $bindings);
  return NULL;
}

/* A typedef whose base spells a candidate alias not yet declared follows
   that alias's forward, in candidate order. `first` maps each alias to its
   first candidate; a later one for the same alias always finds it
   declared. */
static void _add_forwards(
  Array out, Array candidates, Map first, Map available, Var base,
  Map moved) {
  Map spelled = {};
  _spelled_types(base, spelled);
  Array found = [];
  foreach (Var name in spelled.keys()) {
    Var at;
    if (!(name in available) && first.try_get(name, at)) found.push(at);
  }
  foreach (int at in found.sort()) {
    (String name, List forward) = candidates[at];
    if (name in available) continue;
    out.push(forward);
    if (forward.cadr().list().type().is_enum()) moved[forward] = 1;
    _add_names(available, forward);
  }
}

static void _add_names(Map available, List node) {
  foreach (String name in _typedef_names(node)) available[name] = 1;
}
