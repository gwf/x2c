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
#pragma private
$(import "../src/grammar.xmacro")

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cache.x"
#include "collect.x"
#include "format.x"
#include "emit.x"
#include "utils.x"

// generating a unit

/** Writes the generated C header and source for one lowered translation unit.
    `ast` must be the normalized result of `transform_ast` for this compiler;
    its filename, symbols, binding facts, cache keys, and initialization state
    must still describe that same unit. `dir` must already exist. Generation
    partitions the AST, materializes caches and once-only initialization, and
    writes or replaces `<dir>/<source-stem>.h`, `.c`, and the `.xi` interface
    of a collected unit through one `file_publish`, so a failed write
    replaces none of them. It appends generated bindings and initialization
    work to the compiler and is not idempotent. Failures are reported as
    `emit` diagnostics.
*/
void generate_code(Compiler c, List ast, String dir) {
  ast = _without_trivia(ast);
  String basename = %"${dir.rstrip("/")}/${Path.stem(c.filename)}";
  List outputs = c._generated_code(ast, basename);
  String interface = c.source_facts ? NULL : interface_text(
    c, _public_rows(c.definition_rows(ast)));
  if (interface) outputs = outputs.append(%("$basename.xi" $interface));
  c._publish(outputs);
}

/** Returns the generated header and source of the lowered `ast` as `(hfile
    htext cfile ctext)`, named from `basename`, without writing them. It
    affects the compiler as `generate_code` does. */
List generate_code_text(Compiler c, List ast, String basename) =>
  c._generated_code(_without_trivia(ast), basename);

static List _without_trivia(List ast) =>
  ast.filter(%!(node) => !node.list().match(%((!or space comment empty) *)));

/* The header and source of `ast` as `(hfile htext cfile ctext)`, named from
   `basename`. */
static List Compiler._generated_code(Compiler c, List ast, String basename) {
  List (header, source) = c._header_and_source(ast);
  String hash = filename_hash(c.filename);
  (header, source) = c.setup_cache_init(
    header, source, %"_x2c_hcache_${hash}_", %"_x2c_hcache_guard_$hash",
    %"_x2c_hcache_init_$hash");
  List hcode = c._emit_header(header);
  List ccode = c._emit_source(source, header);
  String hfile = %"$basename.h", cfile = %"$basename.c";
  return %(
    $hfile ${c.code_pretty_string(hcode, hfile)}
    $cfile ${c.code_pretty_string(ccode, cfile)}
  );
}

static List Compiler._emit_header(Compiler c, List header) =>
  c.emit(c._include_guard(_vertical_spacing(header)));

/* Static prototypes see the header's declarations as already declared. */
static List Compiler._emit_source(Compiler c, List source, List header) {
  source = c._static_prototypes(c._file_init(source), header);
  source = c._primary_include(_vertical_spacing(source));
  return c.emit(c._patch_main(source));
}

macro Statement $report.emit_file_write(Expr $c, Expr $failure) {
  {
    String reason = String.new(strerror((int) $failure.assoc(<"errno">)));
    $c.report_error(
      <emit>, "failed to write generated file",
      $c.token, %("file: ${$failure.assoc(<path>)}" "reason: $reason"));
  }
}

/* A failed write reports its file and the host error. */
static void Compiler._publish(Compiler c, List outputs) {
  List failure = NULL;
  try file_publish(outputs);
  catch %((!or not-found io-fail) *detail): failure = Error.snapshot(detail);
  if (!failure) return;
  $report.emit_file_write(c, failure);
}

// header and source

/* One unit's split into header and source. `private` is the visibility at
   the current node; `pending` holds each private typedef or x2c include as
   `(names node promoted)`, `opened` the visibility each conditional group
   opened at, `open` the groups still open, `forwarded` the struct and union
   tags the header declares, and `included` the files its includes reach. */
typedef struct Partition {
  Compiler c, Array header, source, pending, opened, open;
  Map forwarded, included, int private;
} Partition;

/* Partition a normalized unit without changing source order. Non-inline
   public functions publish a header declaration and keep their body in the
   source; public inline definitions remain header-only. A function
   definition, static declaration, or foreign alias begins source-private
   output until an explicit public pragma changes visibility. */
static List Compiler._header_and_source(Compiler c, List ast) {
  Partition p = {
    .c = c, .header = [], .source = [], .pending = [], .opened = [],
    .open = [], .forwarded = {}, .included = {}};
  foreach (Ast node, ast) p.add(node);
  return p.finish();
}

static void Partition.add(Partition &p, Ast node) {
  match (node) {
    case %((!or protocol adopt macrodef) *): return;
    case %(typedef ? (bindings *)): p.add_typedef(node);
    case %(function (!set ?type (*)) ?declarator (!set ?body (block *))):
      p.add_function(type, declarator, body);
    case %(!set ?decl
           (declare (!set ?type (*)) (!set ?bindings (bindings *)))):
      p.add_declaration(decl, type, bindings);
    case %(!set ?alias (falias (declare (!set ?type (*)) ?) ?)):
      p.add_alias(alias, type);
    /* The consumer's types name the package's, so the include belongs to
       the header; the source reaches it through the generated header. */
    case %(import ?unit *):
      p.header.push(%(preproc "#include \"${unit.string()}.x\""));
    case %(preproc ?content): p.add_preproc(node, content);
    default: p.side().push(node);
  }
}

/* The file that takes a node at the current visibility. */
static Array Partition.side(Partition &p) => p.private ? p.source : p.header;

/* A marker holds a node's place in both files until the partition ends. */
static void Partition.mark(Partition &p, List marker) {
  p.header.push(marker);
  p.source.push(marker);
}

/* Once the whole unit is seen, the pending typedefs settle, then the
   conditional groups, then the typedef forwards each file needs. */
static List Partition.finish(Partition &p) {
  _promote_typedefs(p.header, p.pending);
  List header = _place_typedefs(p.header, p.pending, 1);
  List source = _place_typedefs(p.source, p.pending, 0);
  Map header_filled = _filled_groups(header);
  Map source_filled = _filled_groups(source);
  header = _place_groups(header, header_filled, source_filled, p.opened, 1);
  source = _place_groups(source, source_filled, header_filled, p.opened, 0);
  header = _typedef_forwards(header, NULL);
  source = _typedef_forwards(source, header);
  return %($header $source);
}

/* private typedefs

   A typedef that follows a function definition is source-private unless a
   later header item names it and no earlier header typedef already declares
   that name; a public prototype must be able to spell its parameter types,
   while an opaque forward typedef keeps a private body private. A private
   include of x2c source follows the same rule for the typedefs it
   declares. */

static void Partition.add_typedef(Partition &p, List node) =>
  p.hold(p.private ? _typedef_names(node) : NULL, node);

/* A private node declaring `names` waits as a `pending` marker in both
   files until the whole unit has been partitioned. A node without names
   takes the current side. */
static void Partition.hold(Partition &p, List names, List node) {
  if (!names) {
    p.side().push(node);
    return;
  }
  p.mark(%(pending ${p.pending.len()}));
  p.pending.push(%($names $node 0));
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

/* The markers are decided from last to first, so a promoted typedef counts
   as a later header item for the markers before it. */
static void _promote_typedefs(Array header, Array pending) {
  int count = header.len();
  for (int i = count - 1; i >= 0; i--)
    match (header[i]) case %(pending ?index): {
      int at = index;
      (List names, List node, int promoted) = pending[at];
      if (!promoted) promoted = _header_needs(header, i, names);
      pending[at] = %($names $node $promoted);
      if (promoted) header[i] = node;
    }
}

/* A header item after position `i` spells one of `names` that no header
   typedef before `i` declares. */
static int _header_needs(Array header, int i, List names) {
  foreach (String name, names)
    if (!_declared_before(header, i, name) && _spelled_after(header, i, name))
      return 1;
  return 0;
}

static int _declared_before(Array header, int i, String name) {
  for (int j = 0; j < i; j++)
    if (header[j] is <list> && name in _typedef_names(header[j])) return 1;
  return 0;
}

static int _spelled_after(Array header, int i, String name) {
  int count = header.len();
  for (int j = i + 1; j < count; j++)
    if (header[j] is <list> && _mentions_type(header[j], name)) return 1;
  return 0;
}

/* True when `node` spells the typedef name `name` anywhere, as a
   single-string type atom such as `("Point")`. */
static int _mentions_type(List node, String name) {
  if (!node) return 0;
  Var head = node.car();
  if (head is <string> && !node.cdr()) return head == name;
  if (head is <symbol> && head.symbol().is_type_qualifier())
    return _mentions_type(node.cdr(), name);
  foreach (Var part, node)
    if (part is <list> && _mentions_type(part, name)) return 1;
  return 0;
}

/* Each remaining marker becomes its typedef in the file the typedef settled
   in, and disappears from the other. */
static List _place_typedefs(Array items, Array pending, int header) {
  Array out = [];
  foreach (Var item, items) {
    match (item) case %(pending ?index): {
      (List names, List node, int promoted) = pending[index];
      (void) names;
      if (promoted == header) out.push(node);
      continue;
    }
    out.push(item);
  }
  return out.list_free();
}

// functions

/* A function definition makes the rest of the unit private, unless it is a
   generated declaration default. */
static void Partition.add_function(
  Partition &p, List type, List declarator, Ast body) {
  int generated = 0;
  match (declarator) case %(bind ?binding *): {
    Map facts = p.c.semantic_binding_facts();
    type = _with_attributes(facts, type, binding);
    String name = binding_identity_spelling(binding);
    generated = %(declaration-default $name) in facts;
  }
  p.place_function(type, declarator, body);
  if (!generated) p.private = 1;
}

static List _with_attributes(Map facts, List type, Var binding) {
  Var attributes;
  if (!facts.try_get(%(attributes $binding), attributes)) return type;
  return %(@{attributes.list()} @type);
}

/* A static definition stays in the source. A public one publishes its
   prototype, or its whole body when inline, after forward declarations of
   the tags the prototype spells. */
static void Partition.place_function(
  Partition &p, Type type, List declarator, Ast body) {
  type = _noreturn(type, declarator, body);
  List function = %(function $type $declarator $body);
  if (type.is_static()) {
    p.source.push(function);
    return;
  }
  p.forward_tags(%($type $declarator));
  p.header.push(_header_function(type, declarator, body));
  if (!type.is_inline()) p.source.push(function);
}

/* C sees only the prototype of a helper that always raises, so a caller
   whose last statement is that call looks like a missing return. Marking
   the type here reaches every generated form of the function. C forbids
   `_Noreturn` on `main`. */
static Type _noreturn(Type type, List declarator, Ast body) {
  if (body.never_returns() && !type.list().contains(%("_Noreturn")) &&
      binding_identity_spelling(declarator.cadr()) != "main")
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
  %(declare $type ${ast_prototype_declarator(declarator)});

/* A public prototype that names `struct tag` before the header declares it
   would give the tag prototype scope in C. A forward declaration of each
   tag the prototype spells keeps it the file-scope type. */
static void Partition.forward_tags(Partition &p, List node) {
  match (node)
    case %((!set ?tag (!or struct union)) ?(String name)): {
      if (name in p.forwarded) return;
      p.forwarded[name] = 1;
      p.header.push(%(declare ($tag $name) (bindings (bind () ()))));
      return;
    }
  foreach (Var item, node) if (item is <list>) p.forward_tags(item);
}

// declarations

/* A static declaration makes the rest of the unit private. A public struct
   or union declaration puts its tag in the header, so no prototype forwards
   it again. */
static void Partition.add_declaration(
  Partition &p, List decl, Type type, List bindings) {
  match (bindings)
    case %(bindings (bind (!set ?binding (*)) ?))
      if (p.c._completed_prototype(binding)): return;
  if (type.is_static()) p.private = 1;
  if (p.private) {
    p.source.push(decl);
    return;
  }
  match (type.base_type())
    case %((!or struct union) ?(String tag) *): p.forwarded[tag] = 1;
  if (!p.place_tagged_object(type, bindings) &&
      !p.place_object(decl, type, bindings))
    p.header.push(_header_declaration(decl, type, bindings));
}

/* A positioned prototype remains visible to symbol collection, but the
   completed definition is what reaches generated C and H output. */
static int Compiler._completed_prototype(Compiler c, List binding) {
  Var stored;
  if (!c.semantic_binding_facts().try_get(%(completion $binding), stored))
    return 0;
  match (stored) case %(completed *): return 1;
  return 0;
}

/* `struct b { ... } g;` at public file scope publishes the body and an
   `extern` declaration of `g`, and defines `g` in the source. */
static int Partition.place_tagged_object(
  Partition &p, Type type, List bindings) {
  Type core = type.base_type();
  String tag = NULL;
  match (core)
    case %((!or struct union enum) ?(String found) (*)): tag = found;
  if (!tag || !_declares_object(bindings)) return 0;
  List tagged = _tag_only(type, core, tag);
  p.header.push(%(declare $type (bindings (bind () ()))));
  p.header.push(_header_declaration(NULL, %(extern @tagged), bindings));
  p.source.push(%(declare $tagged $bindings));
  return 1;
}

/* `type` with its tag body `core` replaced by the bare tag `name`. */
static List _tag_only(Type type, Type core, Var name) =>
  type.list()[:type.len() - core.len()].append(%(${core.car()} $name));

/* A public file-scope object has one definition, in the source, and an
   `extern` declaration in the header. Defining it in the header would give
   every including unit its own copy, and a runtime initializer there is not
   a C constant expression. */
static int Partition.place_object(
  Partition &p, List decl, Type type, List bindings) {
  if (type.is_extern() || !_declares_object(bindings)) return 0;
  p.header.push(_header_declaration(NULL, %(extern @type), bindings));
  p.source.push(decl);
  return 1;
}

/* A binding list with a named object declarator, as opposed to a bare tag
   body or a function prototype. A prototype names no storage, so it stays
   whole in the header. */
static int _declares_object(List bindings) {
  match (bindings) case %(bindings *declarators):
    foreach (List declarator, declarators)
      match (declarator) {
        case %(bind ? ((fnmod *) *)): return 0;
        case %(bind ?name *): if (name.truth()) return 1;
        case %(op = * *): return 1;
      }
  return 0;
}

/* The header form of a declaration: an `extern` declaration without its
   initializers, a tag body alone, or the declaration as written. */
static List _header_declaration(List node, Type type, List bindings) {
  if (type.is_extern()) {
    bindings = bindings.match_replace(
      %(bindings (op = ?bind ?init)), %(bindings ?bind));
    return %(declare $type $bindings);
  }
  if (type.is_enum_tag_body() || type.is_aggregate_tag_body())
    return %(declare $type (bindings (bind () ())));
  return node;
}

/* A foreign alias makes the rest of the unit private. */
static void Partition.add_alias(Partition &p, List alias, Type type) {
  (type.is_static() ? p.source : p.header).push(alias);
  p.private = 1;
}

/* directives

   A conditional directive inside an open group becomes a `conditional`
   marker in both files. Once the unit is partitioned, the group's
   directives go to each file that holds one of its items. */

/* A group records the visibility at which it opened. A conditional
   directive outside every group is placed as any other directive is. */
static void Partition.add_preproc(Partition &p, List node, String content) {
  Symbol kind = preproc_conditional_kind(content);
  if (kind == <open>) {
    p.open.push(p.opened.len());
    p.opened.push(p.private);
  }
  if (kind && p.open.len()) p.mark_conditional(node, kind);
  else p.place_directive(node, content);
}

static void Partition.mark_conditional(Partition &p, List node, Symbol kind) {
  p.mark(%(conditional ${p.open[-1]} $kind $node));
  if (kind == <close>) p.open.take_last();
}

/* The generator writes the header guard. Source pragmas serve only the CPP
   compatibility path and must not duplicate the generated directive. The
   visibility pragmas switch sides, and any other directive stays on the
   current side. */
static void Partition.place_directive(
  Partition &p, List node, String content) {
  if (_is_pragma_once(content)) return;
  int visibility = preproc_visibility(content);
  if (visibility >= 0) p.private = visibility;
  else p.hold(p.include_names(content), node);
}

/* An include of x2c source below `#pragma private` waits, as a private
   typedef does, under the typedef names of the files it reaches that no
   earlier header include reaches. Any other directive names nothing. */
static List Partition.include_names(Partition &p, String content) {
  int angle = 0;
  String target = preproc_include_target(content, angle);
  if (!target) return NULL;
  if (p.private)
    return p.c.include_typedef_names(target, angle, p.included.copy());
  p.c.include_typedef_names(target, angle, p.included);
  return NULL;
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

/* A group's directives go to each file that holds one of its items, so a
   group whose items divide between header and source stays balanced in
   both. A group without items stays on the side it opened on, as `opened`
   records. */
static List _place_groups(
  List items, Map filled, Map other, Array opened, int header) {
  Array out = [];
  foreach (List item, items) {
    match (item)
      case %(conditional ?group ? ?node): {
        int placed = opened[group].int() != header;
        if (group in filled || (!other.contains(group) && placed))
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

static List _typedef_forwards(List items, List earlier) {
  Array candidates = _forward_candidates(items), out = [];
  Map available = {};
  foreach (List node, earlier) _add_names(available, node);
  foreach (List node, items) {
    match (node) case %(typedef ?base ?):
      _add_forwards(out, candidates, available, base);
    out.push(node);
    _add_names(available, node);
  }
  candidates.free();
  return out.list_free();
}

/* Each alias of a named struct or union typedef, paired with the forward
   typedef that declares it. */
static Array _forward_candidates(List items) {
  Array candidates = [];
  foreach (List node, items)
    match (node) case %(typedef ?base ?bindings): {
      List forward = _typedef_forward(base, bindings);
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
    case %((!or struct union) ?name (fields *)):
      if (name.truth())
        return %(typedef ${_tag_only(type, core, name)} $bindings);
  return NULL;
}

/* A typedef whose base spells a candidate alias not yet declared follows
   that alias's forward. */
static void _add_forwards(
  Array out, Array candidates, Map available, Var base) {
  foreach (List candidate, candidates) {
    (String name, List forward) = candidate;
    if (name in available || !_mentions_type(base, name)) continue;
    out.push(forward);
    _add_names(available, forward);
  }
}

static void _add_names(Map available, List node) {
  foreach (String name, _typedef_names(node)) available[name] = 1;
}

/* file initialization

   Queued initialization runs once per file, behind a guard. initblock and
   initstmt markers do not reach generated output; the compiler's
   initialization queues hold those statements. */

/* One unit's file initialization. `guard` is set once the file has
   initialized, `shutdown` registers the unit's shutdown function,
   `synthetic` is the synthetic initializer or NULL, and `entry` names the
   function a patched entry calls. `reachable` holds the entries a
   cache-only file patches, or is NULL when every public entry is patched. */
typedef struct Init {
  Compiler c, String initializer, entry, List guard, shutdown;
  List synthetic, Map reachable;
} Init;

/* Consume the initialization state completed by cache setup. */
static List Compiler._file_init(Compiler c, List source) {
  if (!c.inits.len() && !c.fini_fn && !c.init_fn) return source;
  Init init = {.c = c, .initializer = c.init_fn};
  init.prepare(source);
  int prelude = _prelude_position(source), position = 0;
  List out = NULL;
  foreach (List item, source) {
    if (position++ == prelude) out = init.prelude(out);
    match (item) case %((!or initblock initstmt) *): continue;
    out = cons(init.patch(item), out);
  }
  /* The prelude normally goes before the first function, or before the
     outermost conditional group containing it. A unit of only declarations
     has no such function. The constructor is then the only thing that runs
     the initializers the loop above dropped, so it goes after the
     declarations it assigns. */
  if (prelude < 0) out = init.prelude(out);
  return out.reverse();
}

/* A file without a type initializer, or with one that conditional groups
   may compile out, gets a synthetic initializer. */
static void Init.prepare(Init &i, List source) {
  Compiler c = i.c;
  i.guard = c.sym.reference(%("_init_guard_"), NULL);
  i.shutdown = c._shutdown_registration(source);
  List arms = i.initializer ? _definition_arms(source, i.initializer) : NULL;
  if (!i.initializer || arms) i.synthetic = i.synthesize(arms);
  i.entry = i.synthetic ? "_file_init_" : i.initializer;
  if (c._cache_only()) i.reachable = _cache_reachable(source);
}

/* The position of the first function definition in `source`, or of the
   directive opening the outermost conditional group around it, so the
   prelude is declared whichever arms the C compiler selects. A unit without
   a function definition gives -1. */
static int _prelude_position(List source) {
  int position = 0, depth = 0, opening = 0;
  foreach (List item, source) {
    match (item) case %(function (*) (bind (binding ? ?) ?) (block *)):
      return depth ? opening : position;
    match (item) case %(preproc ?(String content)): {
      Symbol kind = preproc_conditional_kind(content);
      if (kind == <open> && !depth) opening = position;
      if (kind == <open>) depth++;
      else if (kind == <close> && depth) depth--;
    }
    position++;
  }
  return -1;
}

/* The guard's declaration, then the synthetic initializer.
   `Compiler.transform` owns the early-declaration queue and appends its
   drained declarations after the unit, so the queue is empty here. */
static List Init.prelude(Init &i, List out) {
  out = cons(_initialization_guard(i.guard), out);
  return i.synthetic ? cons(i.synthetic, out) : out;
}

/* The protocol initializer and the type initializer wrap their own bodies.
   Other non-static entries initialize their static helpers first. */
static List Init.patch(Init &i, List item) {
  match (item)
    case %(function (!set ?type (*))
           (!set ?declarator (bind (binding ? ?spelling) ?))
           (block *body)): {
      String name = spelling;
      if (name == "x2c_initialize_protocols")
        return i.c._protocol_initializer(item, body);
      if (i.initializer && name == i.initializer)
        return i.c._replace_body(item, i.statements(NULL, body));
      if (i.patches(type, spelling)) {
        List entry = i.c.sym.reference(%(${i.entry}), NULL);
        return _patch_initialized_entry(i.c, item, body, i.guard, entry);
      }
    }
  return item;
}

/* The protocol bootstrap functions are never patched, and a cache-only
   file patches only the entries that reach a cache. */
static int Init.patches(Init &i, Var type, Var spelling) =>
  !type.type().is_static() && !_protocol_bootstrap(spelling) &&
  (i.reachable == NULL || spelling in i.reachable);

static int _protocol_bootstrap(String name) =>
  name == "x2c_initialize_protocols" ||
  name == "x2c_register_builtin_descriptor" ||
  name == "x2c_try_register_tagged_descriptor";

// initializers

macro Decorator $initializer_body(Function $function,
    Statement $body...) {
  $body...
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
static List Init.synthesize(Init &i, List arms) {
  List binding = i.c.sym.introduce("_file_init_");
  List type =
    %(("__attribute__((constructor, noinline, cold))") static void);
  String entry = "x2c_initialize_protocols";
  if (i.initializer) {
    type = %(("__attribute__((noinline, cold))") static void);
    entry = i.initializer;
  }
  List statements =
    i.statements(_within_definitions(arms, _entry_call(entry)), NULL);
  return _initializer_function(i.c, type, binding, statements);
}

/* An initializer runs `entry`, returns when its guard is set and sets it
   otherwise, then runs the early and middle queues, its own `body`, the
   late queue, and the shutdown registration. Cache graphs that require the
   initializer's own String/List canonicalizer are queued late; all other
   cache and static setup keeps its pre-body order. */
static List Init.statements(Init &i, List entry, List body) {
  Compiler c = i.c;
  return List.concat_n(
    7, entry, _run_once(c, i.guard), c.init_statements(<early>),
    c.init_statements(<mid>), body, c.init_statements(<late>), i.shutdown);
}

static List Compiler._replace_body(
  Compiler c, List function, List statements) {
  Macro shape = $initializer_body;
  return c.rebuild_function(function, shape(statements));
}

/* Install generated built-in protocol methods before any ordinary file
   constructor can create a String- or List-backed cache. */
static List Compiler._protocol_initializer(
  Compiler c, List function, List body) {
  List guard = c.sym.introduce("_x2c_protocol_guard_");
  List statements = List.concat_n(
    4, %(${_initialization_guard(guard)}), _run_once(c, guard),
    c.init_statements(<protocol>), body);
  return c._replace_body(function, statements);
}

/* The registration of the unit's shutdown function, under the arms that
   compile its definition. */
static List Compiler._shutdown_registration(Compiler c, List source) {
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
   source order, each as `preproc_track_arms` keeps them. A definition
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
        arms = preproc_track_arms(arms, content);
    }
  return found.reverse();
}

/* `statements` under the arms that compile each definition in `found`, or
   unconditionally when `found` is NULL. At most one definition compiles. */
static List _within_definitions(List found, List statements) {
  if (!found) return statements;
  Array out = [];
  foreach (List arms, found)
    foreach (List item, preproc_within_arms(arms, statements)) out.push(item);
  return out.list_free();
}

/** Returns the statements queued for `phase`, in the order they were added. */
List Compiler.init_statements(Compiler c, Symbol phase) {
  Array selected = [];
  foreach (List entry, c.inits)
    if (entry.car() == phase) selected.push(entry.cadr());
  return selected.list_free();
}

/* cache-only files

   A file without a type initializer whose only queued work is early cache
   setup patches only the entries that reach a cache. Its eager constructor
   already runs the initializers, and unrelated foundational calls then
   cannot recursively materialize literals during String/List pool setup. */

static int Compiler._cache_only(Compiler c) =>
  !c.init_fn && c.init_statements(<early>) &&
  !c.init_statements(<mid>) && !c.init_statements(<late>);

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

/* Each static function's prototype takes its definition's place, and each
   node follows the forward declarations it needs. */
static List Compiler._static_prototypes(Compiler c, List source, List header) {
  source = _move_bodies(source);
  Forward f = {
    .c = c, .available = {}, .statics = {}, .seen = {}, .out = []};
  _collect_declared(header, f.available);
  _static_declarations(source, f.statics);
  foreach (List node, source) {
    if (node.car() == <typedef> && node in f.seen) continue;
    _collect_declared(node, f.available);
    f.dependencies(node);
    f.out.push(node);
  }
  return f.out.list_free();
}

/* Native directives and initializer inputs keep their source order.
   Ordinary function bodies follow the file's declarations and directives,
   preserving their existing access to later private includes and macros,
   but precede a later `#undef` and any conditional group containing one,
   as C requires of a body that uses the macro. Source initializer helpers
   stay at their capture positions. */
static List _move_bodies(List source) {
  Array out = [], bodies = $auto([]);
  Map undefs = $auto(_undef_positions(source)), List arms = NULL;
  int position = 0;
  foreach (List node, source) {
    if (position in undefs) _place_bodies(out, bodies, arms);
    position++;
    match (node) case %(function ?type ?signature ?): {
      bodies.push(%($node @arms));
      if (type.list().type().is_static())
        out.push(_prototype(type, signature));
      continue;
    }
    match (node) case %(preproc ?content):
      arms = preproc_track_arms(arms, content);
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
      Symbol kind = preproc_conditional_kind(content);
      if (kind == <open>) open.push(position);
      else if (kind == <close> && open.len()) open.take_last();
      else if (preproc_directive(content).startswith("undef"))
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
    foreach (List item, preproc_within_arms(reopened, %(${pending.car()})))
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
  names[%(native ${binding_identity_spelling(binding)})] = value;
}

static void _set_declared(Map available, List node, List declarator) {
  List binding = _declaration_binding(declarator);
  if (!binding) return;
  available[binding] = 1;
  if (node.car() == <typedef>)
    available[binding_identity_spelling(binding)] = 1;
}

static List _declaration_binding(List declarator) {
  match (declarator)
    case $source_declarator_row(%((!set ?binding (binding ? ?)) ?)):
      return binding;
  return NULL;
}

/* Records each static declaration by binding: a static function's
   prototype, also under its native spelling, a static object's declaration
   without its initializer, and a typedef, also under its spelling. */
static void _static_declarations(Var value, Map statics) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function ?type (!set ?signature (bind ?binding ?)) ?):
      if (type.list().type().is_static())
        _set_function(statics, binding, _prototype(type, signature));
    case %((!or declare typedef) ?base (bindings *declarators)):
      if (base.list().type().is_static() || node.car() == <typedef>)
        foreach (List declarator, declarators)
          _set_static(statics, node, declarator);
    default: foreach (Var child, node) _static_declarations(child, statics);
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
    statics[binding_identity_spelling(binding)] = declaration;
}

/* forward declarations

   Each node follows the declarations it needs: the static declarations it
   references and prototypes of the global functions nothing declares. */

/* `available` holds what is already declared, `statics` each static
   declaration by binding and spelling, `seen` what is already forwarded,
   and `out` the ordered source. */
typedef struct Forward {
  Compiler c, Map available, statics, seen, Array out;
} Forward;

/* Pending sibling suffixes stay off the C stack. Only declaration
   dependencies recurse; ordinary expressions share the same worklist. */
static void Forward.dependencies(Forward &f, Var value) {
  if (value is not <list> || value.is_nil()) return;
  Array resume = $auto([]);
  for (List node = value; node; node = _next(node, resume)) f.visit(node);
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

static void Forward.visit(Forward &f, List node) {
  match (node) {
    case %(!set ?binding (binding ? ?)): f.binding(binding);
    case %(call ?(String name) *): f.declaration(%(native $name));
    case %((!or expr declare typedef function cast param) ?type *):
      if (type is <list>) f.types(type);
  }
}

/* A binding needs its static declaration, found by binding or by native
   spelling, or else the prototype of the global function it names. */
static void Forward.binding(Forward &f, Var binding) {
  String spelling = binding_identity_spelling(binding);
  List native = %(native $spelling);
  if (binding in f.statics) f.declaration(binding);
  else if (native in f.statics) f.declaration(native);
  else f.global(binding, spelling);
}

/* A generated protocol symbol is declared by the header that published it.
   A native alias among them is a macro over the host function, and newlib
   spells some of those as function-like macros, so a prototype of the alias
   would not even parse. */
static void Forward.global(Forward &f, Var binding, String spelling) {
  Compiler c = f.c;
  Type type = NULL;
  List global = spelling ? c.sym.resolve_global(%($spelling), type) : NULL;
  if (!global || !global.equal(binding) || !type.is_function()) return;
  if (global in f.available || global in f.seen) return;
  if (c.sym.get(%("generated-protocol" $spelling))) return;
  f.seen[global] = 1;
  f.types(type);
  f.out.push(ast_prototype_declarator(type.declaration_ast(global)));
}

/* Forwards the static declaration under `key` once, after what it needs. */
static void Forward.declaration(Forward &f, Var key) {
  Var declaration;
  if (key in f.available || key in f.seen ||
      !f.statics.try_get(key, declaration)) return;
  f.seen[key] = 1;
  f.seen[declaration] = 1;
  _collect_declared(declaration, f.available);
  f.dependencies(declaration);
  f.out.push(declaration);
}

/* Source parameters and fields are visited as declarations. Only semantic
   function modifiers nest Types; tags and array bounds are not type names. */
static void Forward.types(Forward &f, Type type) {
  Type base = type.base_type();
  if (base.is_bare_typedef_name()) f.declaration(base.car());
  foreach (Var modifier, type)
    match (modifier) case %(func (*parameters)):
      foreach (Type parameter, parameters) f.types(parameter);
}

/* file text

   Both files open with the generated banner. The header wraps its
   declarations in its guard, and the source includes its own header and
   the runtime headers it needs. */

static List _vertical_spacing(List code) {
  Array out = [];
  foreach (Var node, code) {
    out.push(node);
    out.push(%(space "\n"));
  }
  return out.list_free();
}

/* A unit that uses the runtime includes it inside the header's guard. */
static List Compiler._include_guard(Compiler c, List content) {
  if (c.runtime_inc && !_has_runtime_include(content))
    content = cons(%(preproc "#include \"x2c.x\""), content);
  String guard = filename_hash(c.filename);
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

/* The source includes its own header, then `error.h` when it raises. A
   cleanup region spells `X2CCleanup` and its push and leave calls, which
   `exception.x` declares. */
static List Compiler._primary_include(Compiler c, List content) {
  List own = _include_directive(%"${Path.stem(c.filename)}.h");
  List error =
    ast_contains_head(content, <raise>) ? _include_directive("error.h") : NULL;
  List exception =
    c.needs_exception ? _include_directive("exception.h") : NULL;
  return %(@{_banner()} @own @error @exception @content);
}

static List _include_directive(String fname) =>
  %((preproc "#include \"$fname\"") (space "\n") (space "\n"));

/* `main` calls the runtime initializer before anything else. */
static List Compiler._patch_main(Compiler c, List source) {
  List initializer = c.sym.reference(%("x2c_initialize"), NULL);
  List setup = %((stmnt (expr (void) (call
    (expr ((func ((void))) void) (ident $initializer))
    (args (expr (void) ()))))));
  return source.map(%!(List node) => {
    match (node)
      case %(function ? (bind (!set ?binding (*)) ?) (block *body)):
        if (binding_identity_spelling(binding) == "main")
          return c._replace_body(node, setup.append(body));
    return node;
  });
}

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
      List row = c._function_row(type, binding, modifiers, 0);
      if (row) rows.push(row);
    }
    case %(falias
           (declare ?type (bindings (bind ?binding ?modifiers))) ?): {
      List row = c._function_row(type, binding, modifiers, 1);
      if (row) rows.push(row);
    }
    case %(typedef ?base (bindings *declarators)):
      foreach (List declarator, declarators) match (declarator)
        case %(bind ?binding ?modifiers):
          rows.push(
            %(typedef ${binding_identity_spelling(binding)} $base $modifiers
              ${c._span(node)}));
  }
  return rows.list_free();
}

/* The row of a function or foreign alias, or NULL when its binding has no
   spelling. */
static List Compiler._function_row(
  Compiler c, List type, List binding, List modifiers, int alias) {
  String name = binding_identity_spelling(binding);
  if (!name) return NULL;
  Type signature =
    %(declare $type (bindings (bind $binding $modifiers))).type_from_ast();
  int line = 1, Var doc = "", List declarator = NULL, span = c._span(binding);
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
  return %(function $name ${c._display(binding, name)} $signature
           ${c._parameter_names(modifiers)} $line $doc
           ${type.type().is_static()} $origin $declarator $span);
}

/* A method displays as `Owner.member`. */
static String Compiler._display(Compiler c, List binding, String name) {
  match (c.semantic_binding_facts()[%(method $binding)])
    case %(?(String owner) ?(String member)): return %"$owner.$member";
  return name;
}

static List Compiler._span(Compiler c, List key) {
  Var span = NULL;
  c.semantic_binding_facts().try_get(%(definition-span $key), span);
  return span;
}

static List Compiler._parameter_names(Compiler c, List modifiers) {
  Array names = [];
  match (modifiers)
    case %((fnmod (params *parameters)) *):
      foreach (List parameter, parameters) match (parameter)
        case %(param ? (bind ?binding ?)):
          names.push(c._parameter_name(binding));
  return names.list_free();
}

/* A parameter's source spelling, or "" for an unnamed parameter. */
static String Compiler._parameter_name(Compiler c, List binding) {
  String name = binding_identity_spelling(binding);
  Var spelling;
  Map facts = c.semantic_binding_facts();
  if (facts.try_get(%(source-spelling $binding), spelling)) name = spelling;
  return name ? name : "";
}

/* A unit interface lists the public functions only. */
static List _public_rows(List definitions) {
  Array rows = [];
  foreach (List row, definitions) match (row)
    case %(function ?name ?display ?type ?names ?line ?doc
           ?(int is_static) *):
      if (!is_static) rows.push(%($name $display $type $names $line $doc));
  return rows.list_free();
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
    case %(function *): _print_function(tokens, row);
    case %(typedef *): c._print_type(tokens, row);
  }
}

static void _print_function(Token tokens, List row) {
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
          ${location.cadr()} (static $is_static) (origin $origin)
          (doc $doc) (text $text) (type $type) (params $names)).repr());
    }
}

/* A typedef with a source span prints its text without the closing `;`,
   its kind, its doc, and its privacy. */
static void Compiler._print_type(Compiler c, Token tokens, List row) {
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
          privacy = %((private $private));
        }
      printf(
        "%s\n",
        %(type (name $name) (kind $kind) @location @privacy (doc $doc)
          (text $text)).repr());
    }
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
