/*  generate.x -- the generated header and source of one unit

    This module owns a unit's generated files: it splits the lowered AST into
    header and source without changing source order, gives the source its
    once-only initialization and static prototypes, wraps the header in its
    guard, and publishes both with the unit's interface. The definition rows
    the interface lists, and `--dump-definitions` prints, come from the same
    lowered AST.
*/
#pragma once
#include "compiler.x"
#include "grammar.x"
#include "ast-rewrite.x"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cache.x"
#include "collect.x"
#include "format.x"
#include "emit.x"
#include "utils.x"

// diagnostics

static macro Stmt $report.emit.file_write(Expr $c, Expr $failure) {
  {
    String reason = String.new(strerror((int) $failure.assoc(<"errno">)));
    $c.report_error(
      <emit>, "failed to write generated file",
      $c.token, %("file: ${$failure.assoc(<path>)}" "reason: $reason"));
  }
}

// generating a unit

/** Writes the generated C header and source for one lowered translation unit.
    `ast` must be the normalized result of `transform_ast` for this compiler;
    its filename, symbols, binding facts, cache keys, and initialization state
    must still describe that same unit. `dir` must already exist. Generation
    partitions the AST, materializes caches and once-only initialization, and
    writes or replaces `<dir>/<source-stem>.h`, `.c`, and the `.xi` interface
    of a collected unit through one `Path.publish_files`, so a failed write
    replaces none of them. It appends generated bindings and initialization
    work to the compiler and is not idempotent. Failures are reported as
    `emit` diagnostics.
*/
void Compiler.generate_code(Compiler c, List ast, String dir) {
  ast = _without_trivia(ast);
  String basename = %"${dir.rstrip("/")}/${Path.stem(c.filename)}";
  List outputs = _generated_code(c, ast, basename);
  String interface = c.source_facts ? NULL : c.interface_text();
  if (interface) outputs = outputs.append(%("$basename.xi" $interface));
  _publish_files(c, outputs);
}

/** Returns the generated header and source of the lowered `ast` as `(hfile
    htext cfile ctext)`, named from `basename`, without writing them. It
    affects the compiler as `Compiler.generate_code` does. */
List Compiler.generate_code_text(Compiler c, List ast, String basename) =>
  _generated_code(c, _without_trivia(ast), basename);

static List _without_trivia(List ast) =>
  ast.filter(%!(node) => !node.list().match(%((!or space comment empty) *)));

/* The header and source of `ast` as `(hfile htext cfile ctext)`, named from
   `basename`. */
static List _generated_code(Compiler c, List ast, String basename) {
  Map inline_bodies = $auto({});
  List (header, source) = _header_and_source(c, ast, inline_bodies);
  String hash = Path.identifier_hash(c.filename);
  Map bindings;
  (header, source, bindings) = c.setup_cache_init(
    header, source, %"_x2c_gensym_hcache_${hash}_",
    %"_x2c_gensym_hcache_guard_$hash",
    %"_x2c_gensym_hcache_init_$hash");
  defer bindings.cleanup();
  List hcode = _emit_header(c, header);
  List ccode = _emit_source(c, source, bindings, inline_bodies);
  String hfile = %"$basename.h", cfile = %"$basename.c";
  return %(
    $hfile ${c.code_pretty_string(hcode, hfile)}
    $cfile ${c.code_pretty_string(ccode, cfile)}
  );
}

static List _emit_header(Compiler c, List header) {
  header = _forward_declarations(c, header, 0);
  return c.emit(_include_guard(c, _vertical_spacing(header)), NULL);
}

/* Each source use follows the declarations it needs. */
static List _emit_source(
  Compiler c, List source, Map bindings, Map inline_bodies) {
  source = _forward_declarations(
    c, _move_bodies(_file_init(c, source), inline_bodies), 1);
  return c.emit(_source_unit(c, source), bindings);
}

/* A failed write reports its file and the host error. */
static void _publish_files(Compiler c, List outputs) {
  List failure = NULL;
  try Path.publish_files(outputs);
  catch %((!or not-found io-fail) *detail): failure = Error.snapshot(detail);
  if (!failure) return;
  $report.emit.file_write(c, failure);
}

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

/* Partition a normalized unit without changing source order. Non-inline
   public functions publish a header declaration and keep their body in the
   source; public inline definitions also publish their bodies. Static
   functions and objects stay in the source. Static types enter the header
   when a public declaration or inline body needs them. */
static List _header_and_source(
  Compiler c, List ast, Map inline_bodies) {
  Partition p = {
    .c = c, .header = [], .pending = [], .open = [], .forwarded = {},
    .included = {}, .statics = {}, .source_groups = {}};
  foreach (Ast node, ast) _add(p, node);
  return %(${_finish(p)} ${_source_projection(c, ast, inline_bodies)});
}

/* The unit consumes its declarations where they were written, independently
   of the public projection. In particular, a promoted include must not
   change the native macro state before its source position. */
static List _source_projection(
  Compiler c, List ast, Map inline_bodies) {
  Array source = [];
  foreach (List node, ast) {
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
  Array pending = $auto([node]);
  while (pending.len()) {
    Var item = pending.take_last();
    if (item is not <list>) continue;
    match (item) {
      case %(binding ? ?): if (item in statics) return 1;
      default: foreach (Var part, item) pending.push(part);
    }
  }
  return 0;
}

/* Adds to `statics` each binding `node` declares: each one it holds other
   than through an `ident` reference. */
static void _add_declared(List node, Map statics) {
  Array pending = $auto([node]);
  while (pending.len()) {
    Var item = pending.take_last();
    if (item is not <list>) continue;
    match (item) {
      case %(ident *): continue;
      case %(binding ? ?): statics[item] = 1;
      default: foreach (Var part, item) pending.push(part);
    }
  }
}

/* Records the objects or function a static declaration declares. */
static void _add_statics(Partition &p, List declarators) {
  foreach (List declarator, declarators) {
    List binding = _declaration_binding(declarator);
    if (binding) p.statics[binding] = 1;
  }
}

/* An item the source keeps fills each group open around it. */
static void _keep(Partition &p) {
  p.source_started = 1;
  foreach (Var group, p.open) p.source_groups[group] = 1;
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
  foreach (String name, names)
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
  foreach (Var group, p.open) p.source_groups[group] = 1;
}

static List _typedef_names(List node) {
  match (node)
    case %(typedef ? (bindings *declarators)): {
      Array names = [];
      foreach (List declarator, declarators)
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

/* The header items the markers are decided against. `declared` maps each
   typedef name to the first header position declaring it, and `spelled`
   holds the type names the items from position `walked` on spell. */
static typedef struct HeaderNeeds {
  Array header;
  Map declared, spelled;
  int walked;
} HeaderNeeds;

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
  foreach (Var name, names)
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
        foreach (Var declared, _declared_type_names(n.header[j]))
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
static void _spelled_types(List node, Map names) {
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

static List _prototype(List type, List declarator) =>
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
  foreach (Var item, node) if (item is <list>) _forward_tags(p, item);
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
  foreach (List declarator, bindings.cdr()) {
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
  foreach (List declarator, bindings.cdr())
    if (_declaration_binding(declarator)) return 1;
  return 0;
}

/* A binding list with an object declarator owns storage. */
static int _declares_object(List bindings) {
  match (bindings) case %(bindings *declarators):
    foreach (List declarator, declarators)
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
    foreach (List declarator, bindings.cdr()) {
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
  foreach (List item, items) {
    match (item)
      case %(conditional ?group ?kind ?): {
        if (kind == <open>) open.push(group);
        else if (kind == <close>) open.take_last();
        continue;
      }
    foreach (Var group, open) filled[group] = 1;
  }
  return filled;
}

/* A group enters the header when it contains a public item, or no item.
   The independent source projection keeps its original conditional groups. */
static List _place_groups(
  List items, Map filled, Map other) {
  Array out = [];
  foreach (List item, items) {
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
  foreach (List node, earlier) _add_names(available, node);
  for (int i = candidates.len() - 1; i >= 0; i--)
    first[candidates[i].car()] = i;
  foreach (List node, items) {
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
  foreach (List node, items)
    match (node) case %(typedef ?base ?bindings): {
      List forward = _typedef_forward(base, bindings);
      if (!forward && complete_enums)
        match (base.list().type().base_type())
          case %(enum ? (*)): forward = node;
      if (!forward) continue;
      foreach (String alias, _typedef_names(node))
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
  foreach (Var name, spelled.keys()) {
    Var at;
    if (!(name in available) && first.try_get(name, at)) found.push(at);
  }
  foreach (int at, found.sort()) {
    (String name, List forward) = candidates[at];
    if (name in available) continue;
    out.push(forward);
    if (forward.cadr().list().type().is_enum()) moved[forward] = 1;
    _add_names(available, forward);
  }
}

static void _add_names(Map available, List node) {
  foreach (String name, _typedef_names(node)) available[name] = 1;
}

// initialization syntax

/** Returns the function `type name(void)` running `body`. */
List Compiler.initializer_function(
  Compiler c, Type type, List name, List body) =>
  c.rebuild_unit_function($!Unit{ $type $name(void) { @body } });

/** Returns a run-once initializer body: `before`, then a return when
   `guard` is set that sets it otherwise, then `after`. */
List Compiler.run_once_body(Compiler c, List before, List guard, List after) {
  List flag = $!int{ $guard };
  List test = c.rebuild_statement($!{ if ($flag) return; $flag = 1; }).cdr();
  return List.concat_n(3, before, test, after);
}

/* file initialization

   Queued initialization runs once per file, behind a guard. Each function
   receives its entry setup from one decision, which the header's cache
   initialization also uses. */

/** Holds one region's initialization. `guard` is set once the region has
    initialized, and `entry` is the function a guarded entry calls. In the
    source, `initializer` names the type initializer, `shutdown` registers
    the unit's shutdown function, `synthetic` is the synthetic initializer or
    NULL, and `reachable` holds the entries a cache-only file guards, or is
    NULL when every public entry is guarded. */
typedef struct Init {
  Compiler c, String initializer, List guard, entry, shutdown, synthetic;
  Map reachable;
} Init;

/* Consume the initialization state completed by cache setup. `source`
   already holds the cache slots and batch helpers at the prelude boundary.
   The helpers are functions, so the guard and synthetic initializer follow
   the slots and precede the helpers, and cache reachability sees them. */
static List _file_init(Compiler c, List source) {
  if (!c.pending.initializes() && !c.fini_fn && !c.init_fn) return source;
  Init init = {.c = c, .initializer = c.init_fn};
  _prepare(init, source);
  Array entries = [];
  foreach (List item, source)
    entries.push(init.enter(item, _patches(init, item)));
  List guard = c.initialization_guard(init.guard);
  List prelude = init.synthetic ? %($guard ${init.synthetic}) : %($guard);
  return c.place_source_prelude(entries.list_free(), prelude);
}

/* A file without a type initializer, or with one that conditional groups
   may compile out, gets a synthetic initializer. */
static void _prepare(Init &i, List source) {
  Compiler c = i.c;
  i.guard = c.sym.reference(%("_init_guard_"), NULL);
  i.shutdown = _shutdown_registration(c, source);
  List arms = i.initializer ? _definition_arms(source, i.initializer) : NULL;
  if (!i.initializer || arms) i.synthetic = _synthesize(i, arms);
  else i.entry = c.sym.reference(%(${i.initializer}), NULL);
  if (_cache_only(c)) i.reachable = _cache_reachable(source);
}

/** Returns `function` with its entry setup: the protocol initializer and
    the type initializer run once, and a `guarded` entry calls the region's
    initializer unless its guard is set. */
List Init.enter(Init &i, List function, int guarded) {
  match (function)
    case %(function ? (bind (binding ? ?(String name)) ?) (block *body)): {
      if (name == "x2c_initialize_protocols")
        return _protocol_initializer(i.c, function, body);
      if (i.initializer && name == i.initializer)
        return _replace_body(i.c, function, _statements(i, NULL, body));
      if (guarded) return _guarded(i, function, body);
    }
  return function;
}

/* A source file guards its public entries. The protocol bootstrap
   functions are never guarded, and a cache-only file guards only the
   entries that reach a cache. */
static int _patches(Init &i, List item) {
  match (item)
    case %(function (!set ?type (*)) (bind (binding ? ?(String name)) ?)
           (block *)):
      return !type.type().is_static() && !_protocol_bootstrap(name) &&
        (i.reachable == NULL || name in i.reachable);
  return 0;
}

static int _protocol_bootstrap(String name) =>
  name == "x2c_initialize_protocols" ||
  name == "x2c_register_builtin_descriptor" ||
  name == "x2c_try_register_tagged_descriptor";

/** Places generated `declarations` after source types and includes, before
    the first function or captured initializer that can use them. An outer
    conditional containing that first use follows the declarations. A unit
    without such a use gets them at its end, after the declarations they
    may assign.
*/
List Compiler.place_source_prelude(
  Compiler c, List source, List declarations) {
  (void) c;
  Array out = [];
  int prelude = _anchors(source, 0).function, position = 0;
  foreach (List node, source) {
    if (position++ == prelude)
      foreach (List declaration, declarations) out.push(declaration);
    out.push(node);
  }
  if (prelude < 0)
    foreach (List declaration, declarations) out.push(declaration);
  return out.list_free();
}

/* Where generated code must precede its first use in a unit's source:
   `function` before the first function or captured initializer, and
   `error` before the first raise or declaration that needs the lowered
   catch ABI. Each position moves out to the directive opening the outermost
   conditional group around its item, so the code is declared whichever
   arms the C compiler selects. A missing use gives -1. */
static typedef struct Anchors { int function, error; } Anchors;

/* The anchors of `source`; `error` is sought only with `errors`. */
static Anchors _anchors(List source, int errors) {
  Anchors at = {-1, -1};
  int position = 0, depth = 0, opening = 0;
  foreach (List item, source) {
    int here = depth ? opening : position;
    if (at.function < 0 && _is_function(item)) at.function = here;
    if (errors && at.error < 0 && _needs_errors(item)) at.error = here;
    if (at.function >= 0 && (!errors || at.error >= 0)) break;
    match (item) case %(preproc ?(String content)): {
      Symbol kind = Compiler.preproc_conditional_kind(content);
      if (kind == <open> && !depth) opening = position;
      if (kind == <open>) depth++;
      else if (kind == <close> && depth) depth--;
    }
    position++;
  }
  return at;
}

static int _is_function(List item) {
  List function = item.car() == <sourceinit> ? item.cadr() : item;
  match (function)
    case %(function (*) (bind (binding ? ?) ?) (block *)): return 1;
  return 0;
}

static int _needs_errors(List item) {
  Map types = $auto({});
  _spelled_types(item, types);
  return Ast.contains_head(item, <raise>) ||
    "ErrorCatchSite" in types || "ErrorHandler" in types;
}

// initializers

static macro Decorator $initializer_body(Function $function,
    Stmt @body) {
  @body
}

static macro Decorator $initialized_entry(
  Function $function, Expr $guard, Expr $entry, Stmt @body) {
  if (!$guard) $entry();
  @body
}

/* The synthetic initializer runs `entry` before its guard. Without a type
   initializer it is a constructor that runs protocol setup; as a
   constructor it runs in the root epoch, before main. Literal statics last
   for the whole process, so they must never be created inside a caller's
   allocation bracket, and the lazy entry guards remain as the portable
   fallback. A type initializer in conditional groups may be compiled out,
   so the synthetic initializer calls it under the arms that compile it,
   which sets the guard, and otherwise runs the file's own initialization.
   Every public entry checks the guard before calling it, so it stays out
   of line and cold: a small initializer inlined into each entry costs
   every call its frame setup. */
static List _synthesize(Init &i, List arms) {
  List binding = i.entry = i.c.sym.introduce("_file_init_");
  List type =
    %(("__attribute__((constructor, noinline, cold))") static void);
  String entry = "x2c_initialize_protocols";
  if (i.initializer) {
    type = %(("__attribute__((noinline, cold))") static void);
    entry = i.initializer;
  }
  List statements =
    _statements(i, _within_definitions(arms, Ast.entry_call(entry)), NULL);
  return i.c.initializer_function(type, binding, statements);
}

/* An initializer runs `entry` and its run-once test, then the `<prepare>`
   and `<statics>` areas, its own `body`, the `<finish>` area, and the
   shutdown registration. Cache graphs that require the initializer's own
   String/List canonicalizer go in `<finish>`; all other cache and static
   setup keeps its pre-body order. */
static List _statements(Init &i, List entry, List body) {
  Compiler c = i.c;
  List queued = List.concat_n(
    5, c.init_statements(<prepare>), c.init_statements(<statics>), body,
    c.init_statements(<finish>), i.shutdown);
  return c.run_once_body(entry, i.guard, queued);
}

/* `function` calls the region's initializer unless its guard is set. */
static List _guarded(Init &i, List function, List body) {
  Macro shape = $initialized_entry;
  List guard = i.guard, condition = $!int{ $guard };
  List callee = %(expr ((func ((void))) void) (ident ${i.entry}));
  return i.c.rebuild_function(function, shape(condition, callee, body));
}

static List _replace_body(
  Compiler c, List function, List statements) {
  Macro shape = $initializer_body;
  return c.rebuild_function(function, shape(statements));
}

/* Install generated built-in protocol methods before any ordinary file
   constructor can create a String- or List-backed cache. */
static List _protocol_initializer(
  Compiler c, List function, List body) {
  List guard = c.sym.introduce("_x2c_gensym_protocol_guard_");
  List declaration = c.initialization_guard(guard);
  List queued = c.init_statements(<protocol>).append(body);
  return _replace_body(
    c, function, c.run_once_body(%($declaration), guard, queued));
}

/* The registration of the unit's shutdown function, under the arms that
   compile its definition. */
static List _shutdown_registration(Compiler c, List source) {
  String shutdown = c.fini_fn;
  if (!shutdown) return NULL;
  List binding = c.sym.reference(%($shutdown), NULL);
  return _within_definitions(
    _definition_arms(source, shutdown), %((
    stmnt
      (expr (void)
        (call "Scope_shutdown_hook"
          (args (expr ((func ((void))) void) (ident $binding)))))
  )));
}

/* The conditional arms around each definition of the function `name`, in
   source order, each as `Compiler.preproc_track_arms` keeps them. A definition
   outside every conditional group is always compiled, which gives NULL. */
static List _definition_arms(List source, String name) {
  List arms = NULL, found = NULL;
  foreach (List item, source)
    match (item) {
      case %(function (*) (bind (binding ? ?(String spelling)) ?) (block *)):
        if (spelling == name) {
          if (!arms) return NULL;
          found = cons(arms, found);
        }
      case %(preproc ?(String content)):
        arms = Compiler.preproc_track_arms(arms, content);
    }
  return found.reverse();
}

/* `statements` under the arms that compile each definition in `found`, or
   unconditionally when `found` is NULL. At most one definition compiles. */
static List _within_definitions(List found, List statements) {
  if (!found) return statements;
  Array out = [];
  foreach (List arms, found)
    foreach (List item, Compiler.preproc_within_arms(arms, statements))
      out.push(item);
  return out.list_free();
}

/** Returns the statements queued for `phase`, in the order they were added. */
List Compiler.init_statements(Compiler c, Symbol phase) =>
  c.pending.area(phase);

/* cache-only files

   A file without a type initializer whose only queued work is `<prepare>`
   cache setup patches only the entries that reach a cache. Its eager
   constructor already runs the initializers, and unrelated foundational
   calls then cannot recursively materialize literals during String/List
   pool setup. */

static int _cache_only(Compiler c) =>
  !c.init_fn && c.pending.area(<prepare>) &&
  !c.pending.area(<statics>) && !c.pending.area(<finish>);

/* Every function that directly or transitively reaches a source cache. */
static Map _cache_reachable(List source) {
  Map callers = {}, reachable = {}, Array queue = [];
  foreach (List node, source)
    match (node)
      case %(!set ?definition
             (function ? (bind (binding ? ?spelling) ?) ?)):
        if (_record_calls(definition, spelling, callers)) queue.push(spelling);
  for (int i = 0; i < queue.len(); i++) {
    Var key = queue[i];
    if (key in reachable) continue;
    reachable[key] = 1;
    if (key in callers)
      foreach (Var caller, callers[key].list()) queue.push(caller);
  }
  queue.free();
  return reachable;
}

/* Records in `callers` each function `caller` calls within `value`, and
   returns whether `value` uses a cache. Functions are keyed by spelling,
   which names one file-scope function in the unit. Binding numbers do not:
   class defaults selected during macro-library preload are numbered apart
   from the unit's own walk. */
static int _record_calls(Var value, Var caller, Map callers) {
  if (value is not <list>) return 0;
  List node = value;
  match (node) {
    case %(cache ?): return 1;
    case %(ident (binding ? ?callee)): {
      List found = callee in callers ? callers[callee] : NULL;
      callers[callee] = cons(caller, found);
      return 0;
    }
  }
  int uses = 0;
  foreach (Var child, node)
    if (_record_calls(child, caller, callers)) uses = 1;
  return uses;
}

// prototypes and bodies

/* A source starts with only its own header guarded and can use the complete
   includes it emits. A header can be entered through a cycle with any
   enclosing header guarded, so its inline bodies still need forwards. */
static List _forward_declarations(
  Compiler c, List source, int source_includes) {
  Forward f = {
    .c = c, .available = {}, .statics = {}, .seen = {},
    .out = []};
  if (c.runtime_inc && source_includes)
    c.runtime_function_declarations(f.available);
  _source_declarations(source, f.statics);
  foreach (List node, source) {
    node = _inline_prototype(c, node);
    if (node.car() == <typedef> && node in f.seen) continue;
    if (source_includes) match (node) case %(preproc ?(String text)): {
      int angle = 0;
      String target = Compiler.preproc_include_target(text, angle);
      if (target)
        c.include_function_declarations(target, angle, f.available);
    }
    _collect_declared(node, f.available);
    _dependencies(f, node);
    f.out.push(node);
  }
  return f.out.list_free();
}

/* Every public inline definition has C internal linkage, including the
   authored prototypes in a file that reaches its defining source. */
static List _inline_prototype(Compiler c, List node) {
  match (node) {
    case %(declare ?type (!set ?declarator
             (bind ?binding ((fnmod *) *)))):
      if (!type.type().is_static() && _inline_binding(c, binding))
        return %(declare (static @type) $declarator);
    case %(declare ?type (bindings *declarators))
      if (!type.type().is_static()): {
      Array rows = [], int changed = 0;
      foreach (List declarator, declarators) {
        List base = type;
        match (declarator) case %(bind ?binding ((fnmod *) *)):
          if (_inline_binding(c, binding)) {
            base = %(static @type);
            changed = 1;
          }
        rows.push(%(declare $base (bindings $declarator)));
      }
      if (changed) return rows.list_free();
      rows.free();
    }
  }
  return node;
}

static int _inline_binding(Compiler c, List binding) =>
  c.sym.get(%("function-inline" ${Ast.binding_spelling(binding)}))
    != NULL;

/* Native directives and initializer inputs keep their source order.
   Public inline definitions keep their macro state at their positions.
   Ordinary function bodies follow the file's declarations and directives,
   preserving their existing access to later private includes and macros,
   but precede a later `#undef` and any conditional group containing one,
   as C requires of a body that uses the macro. Source initializer helpers
   stay at their capture positions. */
static List _move_bodies(List source, Map inline_bodies) {
  Array out = [], bodies = $auto([]);
  Map undefs = $auto(_undef_positions(source)), List arms = NULL;
  int position = 0;
  foreach (List node, source) {
    if (position in undefs) _place_bodies(out, bodies, arms);
    position++;
    match (node) case %(function ?type ?signature ?): {
      if (signature.cadr() in inline_bodies) {
        out.push(node);
        continue;
      }
      bodies.push(%($node @arms));
      if (type.list().type().is_static())
        out.push(_prototype(type, signature));
      continue;
    }
    match (node) case %(preproc ?content):
      arms = Compiler.preproc_track_arms(arms, content);
    out.push(node);
  }
  _place_bodies(out, bodies, NULL);
  return out.list_free();
}

/* The positions in `source` of each `#undef` and of the directive opening
   each conditional group that contains one. */
static Map _undef_positions(List source) {
  Map positions = {};
  Array open = $auto([]);
  int position = 0;
  foreach (List node, source) {
    match (node) case %(preproc ?(String content)): {
      Symbol kind = Compiler.preproc_conditional_kind(content);
      if (kind == <open>) open.push(position);
      else if (kind == <close> && open.len()) open.take_last();
      else if (Compiler.preproc_directive(content).startswith("undef"))
        _mark_undef(positions, open, position);
    }
    position++;
  }
  return positions;
}

static void _mark_undef(Map positions, Array open, int position) {
  positions[position] = 1;
  foreach (Var group, open) positions[group] = 1;
}

/* Moves to `out` each pending body written under the open `arms`,
   reopening the groups it was written in beyond those. A body from another
   arm stays pending. */
static void _place_bodies(Array out, Array bodies, List arms) {
  size_t kept = 0;
  unsigned open = arms.len();
  foreach (List pending, bodies) {
    List written = pending.cdr();
    if (written.tail(open) != arms) {
      bodies[kept++] = pending;
      continue;
    }
    List reopened = written.head(written.len() - open);
    List statement = %(${pending.car()});
    foreach (List item, Compiler.preproc_within_arms(reopened, statement))
      out.push(item);
  }
  bodies.resize(kept);
}

// declared names

/* Adds to `available` each binding `value` declares, with each function's
   native spelling and each typedef's spelling. */
static void _collect_declared(Var value, Map available) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    case %(function ? (!set ?declarator (bind (binding ? ?) ?)) ?):
      _set_function(available, _declaration_binding(declarator), 1);
    case %(declare ? (!set ?declarator (bind (binding ? ?) ?))):
      if (node.type_from_ast().is_function())
        _set_function(available, _declaration_binding(declarator), 1);
    case %((!or declare typedef) (*) (bindings *declarators)):
      foreach (List declarator, declarators)
        _set_declared(available, node, declarator);
    default: foreach (Var child, node) _collect_declared(child, available);
  }
}

/* A function is found by its binding and by its native spelling. */
static void _set_function(Map names, Var binding, Var value) {
  names[binding] = value;
  names[%(native ${Ast.binding_spelling(binding)})] = value;
}

static void _set_declared(Map available, List node, List declarator) {
  List binding = _declaration_binding(declarator);
  if (!binding) return;
  available[binding] = 1;
  if (node.car() == <typedef>)
    available[Ast.binding_spelling(binding)] = 1;
}

static List _declaration_binding(List declarator) {
  match (declarator)
    case $source_declarator_row(%((!set ?binding (binding ? ?)) ?)):
      return binding;
  return NULL;
}

/* Records source declarations by binding: every defined function's
   prototype, also under its native spelling, static objects without their
   initializers, and typedefs, also under their spellings. */
static void _source_declarations(Var value, Map statics) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function ?type (!set ?signature (bind ?binding ?)) ?):
      _set_function(statics, binding, _prototype(type, signature));
    case %((!or declare typedef) ?base (bindings *declarators)):
      if (base.list().type().is_static() || node.car() == <typedef>)
        foreach (List declarator, declarators)
          _set_static(statics, node, declarator);
    default: foreach (Var child, node) _source_declarations(child, statics);
  }
}

static void _set_static(Map statics, List node, List declarator) {
  List binding = _declaration_binding(declarator);
  if (!binding) return;
  match (declarator) case %(op = ?target ?): declarator = target;
  List declaration = node.car() == <typedef>
    ? node : %(declare ${node.cadr()} (bindings $declarator));
  statics[binding] = declaration;
  if (node.car() == <typedef>)
    statics[Ast.binding_spelling(binding)] = declaration;
}

/* forward declarations

   Each node follows the declarations it needs: the static declarations it
   references and prototypes of the global functions nothing declares. */

/* `available` holds what is already declared, `statics` each static
   declaration by binding and spelling, `seen` what is already forwarded,
   and `out` the ordered source. */
static typedef struct Forward {
  Compiler c, Map available, statics, seen, Array out;
} Forward;

/* Pending sibling suffixes stay off the C stack. Only declaration
   dependencies recurse; ordinary expressions share the same worklist. */
static void _dependencies(Forward &f, Var value) {
  if (value is not <list> || value.is_nil()) return;
  Array resume = $auto([]);
  for (List node = value; node; node = _next(node, resume)) _visit(f, node);
}

/* The next nonempty List after `node` in a preorder walk, or NULL at the
   end. `resume` holds the sibling suffixes still to visit. */
static List _next(List node, Array resume) {
  List rest = node;
  for (;;) {
    while (!rest) {
      if (!resume.len()) return NULL;
      rest = resume.take_last();
    }
    Var child = rest.car();
    rest = rest.cdr();
    if (child is <list> && !child.is_nil()) {
      if (rest) resume.push(rest);
      return child;
    }
  }
}

static void _visit(Forward &f, List node) {
  match (node) {
    case %(!set ?binding (binding ? ?)): _binding(f, binding);
    case %(call ?(String name) *): _declaration(f, %(native $name));
    case %((!or expr declare typedef function cast param) ?type *):
      if (type is <list>) _types(f, type);
  }
}

/* A binding needs its static declaration, found by binding or by native
   spelling, or else the prototype of the global function it names. */
static void _binding(Forward &f, Var binding) {
  String spelling = Ast.binding_spelling(binding);
  List native = %(native $spelling);
  if (binding in f.statics) _declaration(f, binding);
  else if (native in f.statics) _declaration(f, native);
  else _global(f, binding, spelling);
}

/* A helper group omits its provider's runtime header, so forward the
   ordinary adapters its typed bodies call. Native aliases still come from
   their defining headers; a host function-like macro cannot be prototyped. */
static void _global(Forward &f, Var binding, String spelling) {
  Compiler c = f.c;
  Type type = NULL;
  List global = spelling ? c.sym.resolve_global(%($spelling), type) : NULL;
  if (!global || !global.equal(binding) || !type.is_function()) return;
  if (global in f.available || %(native $spelling) in f.available ||
      global in f.seen) return;
  if (c.sym.get(%("generated-protocol" $spelling)) &&
      (!c.meta_build || c.native_protocol_alias(spelling))) return;
  f.seen[global] = 1;
  _types(f, type);
  List declaration = Ast.prototype_declarator(type.declaration_ast(global));
  f.out.push(_inline_prototype(c, declaration));
}

/* Emits prerequisites before forwarding the symbol under `key` once. */
static void _declaration(Forward &f, Var key) {
  Var declaration;
  if (key in f.available || key in f.seen ||
      !f.statics.try_get(key, declaration)) return;
  f.seen[key] = 1;
  f.seen[declaration] = 1;
  _collect_declared(declaration, f.available);
  _dependencies(f, declaration);
  f.out.push(declaration);
}

/* Source parameters and fields are visited as declarations. Only semantic
   function modifiers nest Types; tags and array bounds are not type names. */
static void _types(Forward &f, Type type) {
  Type base = type.base_type();
  if (base.is_bare_typedef_name()) _declaration(f, base.car());
  foreach (Var modifier, type)
    match (modifier) case %(func (*parameters)):
      foreach (Type parameter, parameters) _types(f, parameter);
}

/* file text

   Both files open with the generated banner. The header guards its public
   declarations; the source suppresses cyclic includes of that header and
   consumes its own ordered declarations. */

static List _vertical_spacing(List code) {
  Array out = [];
  foreach (Var node, code) _push_line(out, node);
  return out.list_free();
}

static void _push_line(Array out, Var node) {
  out.push(node);
  out.push(%(space "\n"));
}

/* A unit that uses the runtime includes it inside the header's guard. */
static List _include_guard(Compiler c, List content) {
  if (c.runtime_inc && !_has_runtime_include(content))
    content = cons(%(preproc "#include \"x2c.x\""), content);
  String guard = Path.identifier_hash(c.filename);
  return %(@{_banner()} @{_header_guard(content, guard)});
}

static int _has_runtime_include(List content) {
  foreach (List node, content) {
    if (!node) continue;
    Var (kind, payload) = node;
    if (kind != <preproc>) continue;
    String text = payload.string().strip(" \t\r\n");
    if (text == "#include \"x2c.x\"" || text == "#include <x2c.x>") return 1;
  }
  return 0;
}

static List _banner(void) => %(
    (comment "/* auto-generated by x2c.  Do not edit! */")
    (space "\n")
    (space "\n")
  );

static List _header_guard(List content, String guard) => %(
    (preproc "#pragma once")
    (space "\n\n")
    (preproc "#ifndef __GUARD_0x${guard}__")
    (space "\n")
    (preproc "#define __GUARD_0x${guard}__")
    (space "\n\n")
    @content
    (space "\n")
    (preproc "#endif /* __GUARD_0x${guard}__ */")
    (space "\n")
  );

/* The source defines its own header's guard, so a cyclic include of that
   header adds nothing; its own declarations follow in order. The runtime
   headers that lowering needs precede their first uses. */
static List _source_unit(Compiler c, List content) {
  String guard = Path.identifier_hash(c.filename);
  List runtime = c.runtime_inc ? _include_directive("x2c.x") : NULL;
  Anchors at = _anchors(content, 1);
  List error = at.error >= 0 ? _include_directive("error.h") : NULL;
  List exception =
    c.needs_exception ? _include_directive("exception.h") : NULL;
  Array lines = [];
  int position = 0;
  foreach (List node, content) {
    if (position == at.error)
      foreach (List include, error) _push_line(lines, include);
    if (position++ == at.function)
      foreach (List include, exception) _push_line(lines, include);
    _push_line(lines, _runtime_entry(c, node));
  }
  return %(@{_banner()} (preproc "#define __GUARD_0x${guard}__") @runtime
           @{lines.list_free()});
}

/* `main` initializes the runtime before anything else, including its file
   initialization guard. Its prototype comes from the runtime header, so
   the call is added after forward declarations. */
static List _runtime_entry(Compiler c, List node) {
  match (node)
    case %(function ? (bind (binding ? "main") ?) (block *body)): {
      List initializer = c.sym.reference(%("x2c_initialize"), NULL);
      List setup = %((stmnt (expr (void) (call
        (expr ((func ((void))) void) (ident $initializer))
        (args (expr (void) ()))))));
      return _replace_body(c, node, setup.append(body));
    }
  return node;
}

static List _include_directive(String fname) =>
  %((preproc "#include \"$fname\"") (space "\n") (space "\n"));

// definition rows

/** Returns one row for each function, foreign alias, and typedef that the
    lowered unit `ast` defines, in source order:
    `(function NAME DISPLAY TYPE PARAMETERS LINE DOC STATIC ORIGIN DECLARATOR
    SPAN)` or `(typedef NAME BASE MODIFIERS SPAN)`. `ORIGIN` is `<source>`,
    `<macro>` for a Unit macro or generated body, or `<alias>`. `DECLARATOR`
    is the token range of an authored function's declarator, and `SPAN` the
    token range and privacy of the top-level form that produced the
    definition; either is empty when the compiler made the definition.
    `LINE` is 1 and `DOC` empty for a definition without authored source.
*/
List Compiler.definition_rows(Compiler c, List ast) {
  Array rows = [];
  // Prototypes and imported units have no local function node.
  foreach (List node, ast) match (node) {
    case %(function ?type (bind ?binding ?modifiers) ?): {
      List row = _function_row(c, type, binding, modifiers, 0);
      if (row) rows.push(row);
    }
    case %(falias
           (declare ?type (bindings (bind ?binding ?modifiers))) ?): {
      List row = _function_row(c, type, binding, modifiers, 1);
      if (row) rows.push(row);
    }
    case %(typedef ?base (bindings *declarators)):
      foreach (List declarator, declarators) match (declarator)
        case %(bind ?binding ?modifiers):
          rows.push(
            %(typedef ${Ast.binding_spelling(binding)} $base $modifiers
              ${_span(c, node)}));
  }
  return rows.list_free();
}

/* The row of a function or foreign alias, or NULL when its binding has no
   spelling. */
static List _function_row(
  Compiler c, List type, List binding, List modifiers, int alias) {
  String name = Ast.binding_spelling(binding);
  if (!name) return NULL;
  Type signature =
    %(declare $type (bindings (bind $binding $modifiers))).type_from_ast();
  int line = 1, Var doc = "", List declarator = NULL, span = _span(c, binding);
  match (c.semantic_binding_facts()[%(api-definition $binding)])
    case %(?(int recorded) ?text ?range): {
      line = recorded;
      if (text is <string>) doc = text;
      declarator = range;
    }
  /* Authored prose precedes the whole form, before any decorator. */
  match (span)
    case %(?(int start) *): if (declarator || alias) {
      Token first = c.tokenizer.tokens;
      first += start;
      if (alias) line = first.line;
      String written = c.definition_doc(first);
      doc = written ? written : "";
    }
  Symbol origin = declarator ? <source> : <macro>;
  if (alias) origin = <alias>;
  return %(function $name ${_display(c, binding, name)} $signature
           ${_parameter_names(c, modifiers)} $line $doc
           ${type.type().is_static()} $origin $declarator $span);
}

/* A method displays as `Owner.member`. */
static String _display(Compiler c, List binding, String name) {
  match (c.semantic_binding_facts()[%(method $binding)])
    case %(?(String owner) ?(String member)): return %"$owner.$member";
  return c.unprefixed(name);
}

static List _span(Compiler c, List key) {
  Var span = NULL;
  c.semantic_binding_facts().try_get(%(definition-span $key), span);
  return span;
}

static List _parameter_names(Compiler c, List modifiers) {
  Array names = [];
  match (modifiers)
    case %((fnmod (params *parameters)) *):
      foreach (List parameter, parameters) match (parameter)
        case %(param ? (bind ?binding ?)):
          names.push(_parameter_name(c, binding));
  return names.list_free();
}

/* A parameter's source spelling, or "" for an unnamed parameter. */
static String _parameter_name(Compiler c, List binding) {
  String name = Ast.binding_spelling(binding);
  Var spelling;
  Map facts = c.semantic_binding_facts();
  if (facts.try_get(%(source-spelling $binding), spelling)) name = spelling;
  return name ? name : "";
}

// definition dump

/** Prints the `--dump-definitions` projection of the lowered unit `ast`:
    `(unit PATH)`, the module comment as `(module TEXT)` when the file opens
    with one, then one row per `Compiler.definition_rows` entry. The
    command-line reference in the book describes the fields.
*/
void Compiler.dump_definitions(Compiler c, List ast) {
  printf("%s\n", %(unit ${c.filename}).repr());
  Token tokens = c.tokenizer.tokens, first = tokens;
  while (first.type == <space> || first.type == <preproc>) first++;
  if (first.type == <comment>) printf("%s\n", %(module ${first.text}).repr());
  foreach (List row, c.definition_rows(ast)) match (row) {
    case %(function *): _print_function(c, tokens, row);
    case %(typedef *): _print_type(c, tokens, row);
  }
}

static void _print_function(Compiler c, Token tokens, List row) {
  match (row)
    case %(function ?name ?display ?type ?names ?line ?doc ?is_static
           ?origin ?declarator ?span): {
      String text = "";
      match (declarator)
        case %(?(int start) ?(int body)):
          text = _source_text(tokens + start, tokens + body);
      List location = _location(tokens, span);
      printf(
        "%s\n",
        %(function (name $name) (display $display) (line $line)
          ${_definition_source(
            c, tokens, declarator ? declarator : span, line.integer())}
          ${location.cadr()} (static $is_static) (origin $origin)
          (doc $doc) (text $text) (type $type) (params $names)).repr());
    }
}

/* A typedef with a source span prints its text without the closing `;`,
   its kind, its doc, and its privacy. */
static void _print_type(Compiler c, Token tokens, List row) {
  match (row)
    case %(typedef ?name ?base ?modifiers ?span): {
      Var doc = "", text = "", kind = <alias>;
      List location = _location(tokens, span), privacy = NULL;
      match (span)
        case %(?(int start) ?(int end) ?private): {
          Token last = tokens + end, final = last - 1;
          if (final.type == <;>) last = final;
          text = _source_text(tokens + start, last);
          kind = _type_kind(tokens + start, base, modifiers);
          String written = c.definition_doc(tokens + start);
          if (written) doc = written;
          privacy = %((private ${!c.publishes_typedef(name)}));
        }
      printf(
        "%s\n",
        %(type (name $name) (kind $kind) @location
          ${_definition_source(c, tokens, span, 0)} @privacy (doc $doc)
          (text $text)).repr());
    }
}

/* Resolve an authored range or invocation line through source markers. */
static List _definition_source(
  Compiler c, Token tokens, List range, int line) {
  Token first = tokens;
  if (range) first += range.car().integer();
  else {
    if (line <= 1) return %(source);
    while (first.type != <eof> && first.line < line) first++;
  }
  line = first.line;
  String path = c.token_source(first, line);
  return %(source $path $line);
}

/* Source text between two tokens with comments removed and each run of
   whitespace written as one space. */
static String _source_text(Token first, Token last) {
  Buffer output = $auto(Buffer.new(0));
  int gap = 0;
  for (Token token = first; token < last; token++) {
    if (token.type == <space> || token.type == <comment>) gap = 1;
    else if (token.len) {
      if (gap && output.len()) output.write_char(' ');
      output.write(token.text);
      gap = 0;
    }
  }
  return output;
}

/* The one-based line and byte range of a token range. */
static List _location(Token tokens, List range) {
  match (range)
    case %(?(int start) ?(int end) *): {
      Token first = tokens + start, last = tokens + end - 1;
      return %((line ${first.line})
               (span ${first.pos} ${last.pos + last.len}));
    }
  return %((line 0) (span));
}

static Symbol _type_kind(Token first, List base, List modifiers) {
  if (first.text == "class") return <class>;
  match (modifiers)
    case %(?pointer (fnmod *) *):
      if (pointer == <*>) return <callback>;
  match (base)
    case %((!set ?kind (!or struct union enum)) *): return kind;
  return <alias>;
}
