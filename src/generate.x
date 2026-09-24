/*  generate.x -- generate C headers and source files

    Turns a normalized AST into formatted header and source files. It splits
    the header from the source, adds once-only translation-unit
    initialization and include guards, and writes the files. Filesystem
    failures retain their target and host error as compiler diagnostic
    notes.
*/
#pragma once
#include "compiler.x"
#pragma private

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cache.x"
#include "collect.x"
#include "format.x"
#include "emit.x"
#include "utils.x"

// init staging

static List _make_init_call(String initializer, List guard) => %(
    if (expr (int) (op ! (expr (int) (ident $guard))))
       (stmnt (expr (void) (call $initializer (args) )))
  );

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
  Array output = [];
  foreach (List arms, found)
    foreach (List item, preproc_within_arms(arms, statements))
      output.push(item);
  return output.list_free();
}

static List _make_shutdown_registration(Compiler compiler, List source) {
  String shutdown = compiler.fini_fn;
  if (!shutdown) return NULL;
  List binding = compiler.sym.reference(%($shutdown), NULL);
  return _within_definitions(_definition_arms(source, shutdown), %((
    stmnt
      (expr (void)
        (call "Scope_shutdown_hook"
          (args (expr ((func ((void))) void) (ident $binding)))))
  )));
}

static List _patch_func_with_init(
  List type, List bind, List statements, String initializer, List guard) => %(
    function $type $bind
    (block ${_make_init_call(initializer, guard)} @statements)
  );

/* Wrap the type-owned initializer with file and literal initialization.
   Cache graphs that require the initializer's own String/List canonicalizer
   are queued late; all other cache and static setup retains its pre-body
   order. */
static List _wrap_initializer_function(
  Compiler compiler, List type, List bind, List statements, List guard,
  List shutdown) => %(
    function $type $bind
    (block (if (expr (int) (ident $guard)) (return))
      (stmnt(expr (int) (op = (expr (int) (ident $guard))
          (expr (int) (literal (int) "1")))))
      @{compiler.init_statements(<early>)}
      @{compiler.init_statements(<mid>)}
      @statements
      @{compiler.init_statements(<late>)}
      @shutdown
    )
  );

/* Construct the synthetic file-level init function, which runs `entry`
   first. As a constructor it runs in the root epoch, before main. Literal
   statics last for the whole process, so they must never be created inside
   a caller's allocation bracket. The lazy entry guards remain as the
   portable fallback. */
static List _make_file_init_func(
  Compiler compiler, List type, List entry, List guard, List initializer,
  List shutdown) => %(
    function $type
      ( bind $initializer (( fnmod (params (param (void) (bind () ()))))))
      ( block
        @entry
        ( if (expr (int) (ident $guard)) (return) )
        (stmnt
          ( expr (int) (op = (expr (int) (ident $guard))
                             (expr (int) (literal (int) "1")))))
        @{compiler.init_statements(<early>)}
        @{compiler.init_statements(<mid>)}
        @{compiler.init_statements(<late>)}
        @shutdown
      )
  );

// Install generated built-in protocol methods before any ordinary file
// constructor can create a String- or List-backed cache.
static List _wrap_protocol_initializer_function(
  Compiler compiler, List type, List bind, List statements) {
  List guard = compiler.sym.introduce("_x2c_protocol_guard_");
  return %(
    function $type $bind
      (block
        (declare (static int)
          (bindings (op = (bind $guard ()) (expr (int) (literal (int) "0")))))
        (if (expr (int) (ident $guard)) (return))
        (stmnt
          (expr (int)
            (op = (expr (int) (ident $guard))
                  (expr (int) (literal (int) "1")))))
        @{compiler.init_statements(<protocol>)}
        @statements)
  );
}

// Declare the guard that protects file initialization.
static List _make_init_guard(List guard) => %( declare (static int)
    ( bindings ( op = ( bind $guard ()) (expr (int) (literal (int) "0")))) );

static inline int _has_file_init_blocks(Compiler compiler) =>
  compiler.inits.len() || compiler.fini_fn;

/* `Compiler.transform` owns the early-declaration queue and appends its
   drained declarations after the unit, so the queue is empty here. */
static List _prepend_init_prelude(
  List result, List init_guard, List init_func) {
  result = cons(init_guard, result);
  if (init_func) result = cons(init_func, result);
  return result;
}

/* The position of the first function definition in `source`, or of the
   directive opening the outermost conditional group around it, so the
   prelude is declared whichever arms the C compiler selects. A unit without
   a function definition gives -1. */
static int _init_prelude_position(List source) {
  int position = 0, depth = 0, opening = 0;
  foreach (List item, source) {
    match (item) {
      case %(function (*) (bind (binding ? ?) ?) (block *)):
        return depth ? opening : position;
      case %(preproc ?(String content)): {
        Symbol kind = preproc_conditional_kind(content);
        if (kind == <open>) {
          if (!depth) opening = position;
          depth++;
        }
        else if (kind == <close> && depth) depth--;
      }
    }
    position++;
  }
  return -1;
}

static int _is_protocol_bootstrap_function(String spelling) =>
  spelling == "x2c_initialize_protocols" ||
  spelling == "x2c_register_builtin_descriptor" ||
  spelling == "x2c_try_register_tagged_descriptor";

/* Functions are keyed by binding number, which names one live declaration
   in the unit. */
static void _collect_cache_function_refs(
  Var value, Var caller, Map callers, int *uses_cache) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(cache ?): {
      *uses_cache = 1;
      return;
    }
    case %(ident (binding ?callee ?)): {
      List found = callee in callers ? callers[callee] : NULL;
      callers[callee] = cons(caller, found);
      return;
    }
  }
  foreach (Var child, node)
    _collect_cache_function_refs(child, caller, callers, uses_cache);
}

/* Find every function that directly or transitively reaches a source cache.
   A cache-only file patches only these entries. Its eager constructor
   already runs the initializers, and unrelated foundational calls then
   cannot recursively materialize literals during String/List pool setup. */
static Map _cache_reachable_function_ids(List source) {
  Map callers = {}, reachable = {}, Array queue = [];
  foreach (List func, source)
    match (func)
      case %(!set ?definition
             (function ? (bind (binding ?identity ?) ?) ?)): {
        int uses_cache = 0;
        _collect_cache_function_refs(
          definition, identity, callers, &uses_cache);
        if (uses_cache) queue.push(identity);
      }
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

/* Consume the initialization state completed by cache setup. The constructor
   form of the synthetic file initializer calls protocol setup before early and
   middle work. A type-owned initializer wraps its own body between
   early/middle and late work, while the protocol initializer prepends its
   protocol queue. Shutdown registration is last in synthetic and type-owned
   initializers, under the arms that compile the shutdown. A type initializer
   in conditional groups may be compiled out, so the entries call a lazy
   synthetic initializer instead. It calls the type initializer under those
   arms, which sets the guard, and otherwise runs the file's own
   initialization. initblock and initstmt markers do not reach generated
   output; the compiler's initialization queues hold those statements. */
static List _file_init(Compiler c, List source) {
  int has_init_blocks = _has_file_init_blocks(c);
  String initializer = c.init_fn;
  if (!has_init_blocks && !initializer) return source;

  List guard = c.sym.reference(%("_init_guard_"), NULL), init_func = NULL;
  List shutdown = _make_shutdown_registration(c, source);
  List initializer_arms =
    initializer ? _definition_arms(source, initializer) : NULL;
  if (!initializer || initializer_arms) {
    List file_init = c.sym.introduce("_file_init_");
    List type = %(("__attribute__((constructor))") static void);
    String entry = "x2c_initialize_protocols";
    if (initializer) {
      type = %(static void);
      entry = initializer;
    }
    List call = %((stmnt (expr (void) (call $entry (args)))));
    init_func = _make_file_init_func(
      c, type, _within_definitions(initializer_arms, call), guard,
      file_init, shutdown);
  }
  List init_guard = _make_init_guard(guard);
  String initializer_name = init_func ? "_file_init_" : initializer;
  int cache_only =
    !initializer && c.init_statements(<early>) &&
    !c.init_statements(<mid>) && !c.init_statements(<late>);
  Map cache_reachable_ids = cache_only
                          ? _cache_reachable_function_ids(source) : NULL;
  int prelude = _init_prelude_position(source), position = 0;
  List result = NULL;

  foreach (List item, source) {
    if (position++ == prelude)
      result = _prepend_init_prelude(result, init_guard, init_func);
    match (item) {
      case %((!or initblock initstmt) *): continue;
      case %(!set ?function
             (function (!set ?type (*))
               (!set ?declarator
               (bind (binding ?identity ?spelling) ?))
               (block *statements))): {
        String name = spelling;
        if (name == "x2c_initialize_protocols")
          function = _wrap_protocol_initializer_function(
            c, type, declarator, statements);
        else if (initializer && name == initializer)
          function = _wrap_initializer_function(
            c, type, declarator, statements, guard, shutdown);
        // Non-static entries initialize their static helpers.
        else if (!type.type().is_static() &&
                 !_is_protocol_bootstrap_function(name) &&
                 (!cache_only ||
                  identity in cache_reachable_ids))
          function = _patch_func_with_init(
            type, declarator, statements, initializer_name, guard);
        item = function;
      }
    }
    result = cons(item, result);
  }

  /* The prelude normally goes before the first function, or before the
     outermost conditional group containing it. A unit of only declarations
     has no such function. The constructor is then the only thing that runs
     the initializers the loop above dropped, so it goes after the
     declarations it assigns. */
  if (prelude < 0)
    result = _prepend_init_prelude(result, init_guard, init_func);

  return result.reverse();
}

// header/source partitioning

// Normalize declarations for header emission.
static List _header_declaration(List node, Type type, List bindings) {
  if (type.is_extern()) {
    bindings = bindings.match_replace(
      %(bindings (op = ?bind ?init)),
      %(bindings ?bind));
    return %( declare $type $bindings );
  }
  if (type.is_enum_tag_body() || type.is_aggregate_tag_body())
    return %(declare $type (bindings (bind () ())));
  return node;
}

// Promote inline functions into header prototypes.
static List _header_function(Type type, List bind, List body) {
  if (type.is_inline()) return %( function ( static @type ) $bind $body );
  return %( declare $type ${ast_prototype_declarator(bind)} );
}

// The generator writes the header guard. Source pragmas serve only the CPP
// compatibility path and must not duplicate the generated directive.
static int _is_pragma_once(String content) =>
  content.strip(" \t\r\n") == "#pragma once";

// A positioned prototype remains visible to symbol collection, but the
// completed definition is what reaches generated C and H output.
static int _is_completed_function_prototype(Compiler compiler, List binding) {
  Var stored;
  if (!compiler.semantic_binding_facts().try_get(
    %(completion $binding), &stored))
    return 0;
  match (stored) case %(completed *): return 1;
  return 0;
}

/* A public prototype that names `struct tag` before the header declares it
   would give the tag prototype scope in C. A forward declaration of each
   tag the prototype spells keeps it the file-scope type. */
static void _forward_tags(List node, Map forwarded, Array header) {
  match (node)
    case %((!set ?tag (!or struct union)) ?(String name)): {
      if (name in forwarded) return;
      forwarded[name] = 1;
      header.push(%(declare ($tag $name) (bindings (bind () ()))));
      return;
    }
  foreach (Var item, node)
    if (item is <list>) _forward_tags(item, forwarded, header);
}

static void _partition_function(
  Array header, Array source, Type type, List declarator, Ast body,
  Map forwarded) {
  /* C sees only the prototype of a helper that always raises, so a caller
     whose last statement is that call looks like a missing return. Marking
     the type here reaches every generated form of the function. C forbids
     `_Noreturn` on `main`. */
  if (body.never_returns() && !type.list().contains(%("_Noreturn")) &&
      binding_identity_spelling(declarator.cadr()) != "main")
    type = %(("_Noreturn") @type);
  List function = %(function $type $declarator $body);
  if (type.is_static()) {
    source.push(function);
    return;
  }
  _forward_tags(%($type $declarator), forwarded, header);
  header.push(_header_function(type, declarator, body));
  if (!type.is_inline()) source.push(function);
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

/* `struct b { ... } g;` at public file scope publishes the body and an
   `extern` declaration of `g`, and defines `g` in the source. */
static int _partition_tagged_object(
  Array header, Array source, Type type, List bindings) {
  Type core = type.base_type();
  String tag = NULL;
  match (core)
    case %((!or struct union enum) ?(String found) (*)): tag = found;
  if (!tag || !_declares_object(bindings)) return 0;
  List tagged = type.list()[:type.len() - core.len()]
                  .append(%(${core.car()} $tag));
  header.push(%(declare $type (bindings (bind () ()))));
  header.push(_header_declaration(NULL, %(extern @tagged), bindings));
  source.push(%(declare $tagged $bindings));
  return 1;
}

/* A public file-scope object has one definition, in the source, and an
   `extern` declaration in the header. Defining it in the header would give
   every including unit its own copy, and a runtime initializer there is not
   a C constant expression. */
static int _partition_object(
  Array header, Array source, List declaration, Type type, List bindings) {
  if (type.is_extern() || !_declares_object(bindings)) return 0;
  header.push(_header_declaration(NULL, %(extern @type), bindings));
  source.push(declaration);
  return 1;
}

static void _partition_declaration(
  Array header, Array source, List declaration, Type type, List bindings,
  int private) {
  if (private) source.push(declaration);
  else if (!_partition_tagged_object(header, source, type, bindings) &&
           !_partition_object(header, source, declaration, type, bindings))
    header.push(_header_declaration(declaration, type, bindings));
}

static void _partition_alias(
  Array header, Array source, List alias, Type type) {
  (type.is_static() ? source : header).push(alias);
}

static void _partition_preproc(
  Array header, Array source, List node, String content, int *private) {
  if (_is_pragma_once(content)) return;
  if (content.contains("pragma public")) *private = 0;
  else if (content.contains("pragma private")) *private = 1;
  else (*private ? source : header).push(node);
}

/* Partition a normalized unit without changing source order. Non-inline
   public functions publish a header declaration and keep their body in the
   source; public inline definitions remain header-only. A function definition,
   static declaration, or foreign alias begins source-private output until an
   explicit public pragma changes visibility. */
/* True when `node` spells the typedef name `name` anywhere, as a
   single-string type atom such as `("Point")`. */
static int _mentions_type(List node, String name) {
  if (!node) return 0;
  if (node.car() is <string> && !node.cdr()) return node.car() == name;
  if (node.car() is <symbol> && node.car().symbol().is_type_qualifier())
    return _mentions_type(node.cdr(), name);
  for (List rest = node; rest; rest = rest.cdr())
    if (rest.car() is <list> && _mentions_type(rest.car(), name)) return 1;
  return 0;
}

static List _typedef_names(List typedef_node) {
  match (typedef_node)
    case %(typedef ? (bindings *declarations)): {
      Array names = [];
      foreach (List declaration, declarations)
        match (declaration) {
          case %(bind (binding ? ?name) ?): names.push(name);
          case %(bind (?name) ?): names.push(name);
        }
      return names.list_free();
    }
  return NULL;
}

/* A typedef that follows a function definition is source-private unless a
   later header item names it and no earlier header typedef already
   declares that name; a public prototype must be able to spell its
   parameter types, while an opaque forward typedef keeps a private body
   private. Markers hold each such typedef's position in both files until
   the whole unit has been partitioned. */
static List _resolve_typedef_markers(Array items, Array pending, int header) {
  Array output = [];
  int count = items.len();
  if (header) for (int i = count - 1; i >= 0; i--) {
    match (items[i])
      case %(pending ?index): {
        int at = index;
        (List names, List node, int promoted) = pending[at];
        foreach (String name, names) {
          int declared = 0;
          for (int j = 0; j < i && !declared; j++)
            declared = items[j] is <list> &&
                       name in _typedef_names(items[j]);
          for (int j = i + 1; j < count && !promoted && !declared; j++)
            promoted = items[j] is <list> &&
                       _mentions_type(items[j], name);
          if (promoted) break;
        }
        pending[at] = %($names $node $promoted);
        if (promoted) items[i] = node;
      }
  }
  foreach (Var item, items) {
    match (item)
      case %(pending ?index): {
        (List names, List node, int promoted) = pending[index];
        (void) names;
        if (promoted == header) output.push(node);
        continue;
      }
    output.push(item);
  }
  return output.list_free();
}

/* A completed aggregate typedef can supply its alias before an earlier
   field needs it. The forward uses the final declarator, preserving pointer
   and value identity; an incomplete by-value field remains a native error. */
static List _aggregate_typedef_forwards(List items, List earlier) {
  Array candidates = [];
  foreach (List node, items)
    match (node)
      case %(typedef ?base ?bindings): {
        Type type = base, core = type.base_type();
        match (core)
          case %((!set ?tag (!or struct union)) ?name (fields *)): {
            if (!name.truth()) continue;
            List forward_type = type.list()[:type.len() - core.len()]
                                  .append(%($tag $name));
            List forward = %(typedef $forward_type $bindings);
            foreach (String alias, _typedef_names(node))
              candidates.push(%($alias $forward));
          }
      }
  Map available = {};
  foreach (List node, earlier)
    foreach (String name, _typedef_names(node)) available[name] = 1;
  Array output = [];
  foreach (List node, items) {
    match (node)
      case %(typedef ?base ?):
        foreach (List candidate, candidates) {
          (String name, List forward) = candidate;
          if (available.contains(name) || !_mentions_type(base, name))
            continue;
          output.push(forward);
          foreach (String declared, _typedef_names(forward))
            available[declared] = 1;
        }
    output.push(node);
    foreach (String name, _typedef_names(node)) available[name] = 1;
  }
  candidates.free();
  return output.list_free();
}

/* The groups among `items` that contain an item other than a conditional
   directive, including through a nested group. */
static Map _filled_conditionals(List items) {
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

/* A conditional group's directives go to each file that holds one of its
   items, so a group whose items divide between header and source stays
   balanced in both. A group without items stays on the side it opened on,
   as `opened` records. */
static List _place_conditionals(
  List items, Map filled, Map other, Array opened, int header) {
  Array output = [];
  foreach (List item, items) {
    match (item)
      case %(conditional ?group ? ?node): {
        int placed = opened[group].int() != header;
        if (filled.contains(group) || (!other.contains(group) && placed))
          output.push(node);
        continue;
      }
    output.push(item);
  }
  return output.list_free();
}

static List _header_and_source(Compiler compiler, List ast) {
  Array header = [], source = [], pending = [], int private = 0;
  Array opened = [], open = [], Map forwarded = {};
  foreach (Ast node, ast) {
    match (node) {
      case %((!or protocol adopt macrodef) *): continue;
      case %(typedef ? (bindings *)): {
        List names = private ? _typedef_names(node) : NULL;
        if (!names) {
          (private ? source : header).push(node);
          continue;
        }
        List marker = %(pending ${pending.len()});
        pending.push(%($names $node 0));
        header.push(marker);
        source.push(marker);
        continue;
      }
      case %(function (!set ?type (*)) ?declarator
             (!set ?body (block *))): {
        Type function_type = type;
        match (declarator) case %(bind ?binding *): {
          Var attributes;
          if (compiler.semantic_binding_facts().try_get(
                %(attributes $binding), &attributes))
            function_type = %( @{attributes.list()} @function_type );
        }
        _partition_function(
          header, source, function_type, declarator, body, forwarded);
        private = 1;
        continue;
      }
      case %(!set ?declaration
             (declare (!set ?type (*))
               (!set ?bindings (bindings *)))): {
        match (bindings)
          case %(bindings (bind (!set ?binding (*)) ?))
            if (_is_completed_function_prototype(compiler, binding)):
              continue;
        Type declaration_type = type;
        if (declaration_type.is_static()) private = 1;
        if (!private) match (declaration_type.base_type())
          case %((!or struct union) ?(String tag) *): forwarded[tag] = 1;
        _partition_declaration(
          header, source, declaration, declaration_type, bindings, private);
        continue;
      }
      case %(!set ?alias (falias (declare (!set ?type (*)) ?) ?)): {
        _partition_alias(header, source, alias, type);
        private = 1;
        continue;
      }
      // The consumer's types name the package's, so the include belongs to
      // the header; the source reaches it through the generated header.
      case %(import ?unit *): {
        header.push(%(preproc "#include \"${unit.string()}.x\""));
        continue;
      }
      case %(preproc ?content): {
        Symbol kind = preproc_conditional_kind(content);
        if (kind == <open>) {
          open.push(opened.len());
          opened.push(private);
        }
        if (kind && open.len()) {
          List marker = %(conditional ${open[open.len() - 1]} $kind $node);
          header.push(marker);
          source.push(marker);
          if (kind == <close>) open.take_last();
          continue;
        }
        _partition_preproc(header, source, node, content, &private);
        continue;
      }
    }
    (private ? source : header).push(node);
  }
  List header_list = _resolve_typedef_markers(header, pending, 1);
  List source_list = _resolve_typedef_markers(source, pending, 0);
  Map header_filled = _filled_conditionals(header_list);
  Map source_filled = _filled_conditionals(source_list);
  header_list = _place_conditionals(
    header_list, header_filled, source_filled, opened, 1);
  source_list = _place_conditionals(
    source_list, source_filled, header_filled, opened, 0);
  header_list = _aggregate_typedef_forwards(header_list, NULL);
  source_list = _aggregate_typedef_forwards(source_list, header_list);
  return %( $header_list $source_list );
}

/* Project definitions that survived expansion and binding. Prototypes and
   imported units have no local function node; file-static bodies are private. */
static List _public_parameter_names(Compiler c, List modifiers) {
  Array names = [];
  match (modifiers)
    case %((fnmod (params *parameters)) *):
      foreach (List parameter, parameters) match (parameter)
        case %(param ? (bind ?binding ?)): {
          String name = binding_identity_spelling(binding);
          Var spelling;
          if (c.semantic_binding_facts().try_get(
                %(source-spelling $binding), &spelling))
            name = spelling;
          names.push(name ? name : "");
        }
  return names.list_free();
}

static List _public_definition_rows(Compiler c, List ast) {
  Array rows = [];
  foreach (List node, ast) match (node)
    case %(function ?type (bind ?binding ?modifiers) ?): {
      String name = binding_identity_spelling(binding);
      if (!name || type.type().is_static())
        continue;
      Type signature = %(declare $type
        (bindings (bind $binding $modifiers))).type_from_ast();
      List parameter_names = _public_parameter_names(c, modifiers);
      Var source = c.semantic_binding_facts()[%(api-definition $binding)];
      int line = 1;
      Var doc = "";
      String display = name;
      match (c.semantic_binding_facts()[%(method $binding)])
        case %(?(String owner) ?(String member)):
          display = %"$owner.$member";
      match (source) case %(?(int recorded) ?text): {
        line = recorded;
        doc = text;
      }
      rows.push(%($name $display $signature $parameter_names $line $doc));
    }
  return rows.list_free();
}

static List _declaration_binding(List declarator) {
  match (declarator) {
    case %(bind (!set ?binding (binding ? ?)) ?): return binding;
    case %(op = (bind (!set ?binding (binding ? ?)) ?) ?): return binding;
  }
  return NULL;
}

static void _collect_declared_bindings(Var value, Map bindings) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    case %(function ? (!set ?declarator (bind (binding ? ?) ?)) ?): {
      List binding = _declaration_binding(declarator);
      bindings[binding] = 1;
      bindings[%(native ${binding_identity_spelling(binding)})] = 1;
      return;
    }
    case %(declare ? (!set ?declarator (bind (binding ? ?) ?))): {
      if (node.type_from_ast().is_function()) {
        List binding = _declaration_binding(declarator);
        bindings[binding] = 1;
        bindings[%(native ${binding_identity_spelling(binding)})] = 1;
      }
      return;
    }
    case %((!or declare typedef) (!set ?base (*))
           (bindings *declarators)): {
      foreach (List declarator, declarators) {
        List binding = _declaration_binding(declarator);
        if (!binding) continue;
        bindings[binding] = 1;
        if (node.car() == <typedef>)
          bindings[binding_identity_spelling(binding)] = 1;
      }
      return;
    }
  }
  foreach (Var child, node) _collect_declared_bindings(child, bindings);
}

static void _forward_declaration(
  Compiler c, Var key, Map available, Map declarations, Map seen,
  Array output) {
  Var declaration;
  if (key in available || key in seen ||
      !declarations.try_get(key, &declaration)) return;
  seen[key] = 1;
  seen[declaration] = 1;
  _collect_declared_bindings(declaration, available);
  _collect_forward_dependencies(
    c, declaration, available, declarations, seen, output);
  output.push(declaration);
}

static void _forward_types(
  Compiler c, List type, Map available, Map declarations, Map seen,
  Array output) {
  foreach (Var part, type) {
    if (part is <string>)
      _forward_declaration(c, part, available, declarations, seen, output);
    else if (part is <list>)
      _forward_types(c, part, available, declarations, seen, output);
  }
}

/* Pending sibling suffixes stay off the C stack. Only declaration
   dependencies recurse; ordinary expressions share the same worklist. */
static void _collect_forward_dependencies(
  Compiler compiler, Var value, Map locals, Map statics, Map seen,
  Array prototypes) {
  if (value is not <list> || value.is_nil()) return;
  Array resume = $auto([]);
  List node = value;
  for (;;) {
    match (node) {
      case %(!set ?binding (binding ? ?)): {
        String spelling = binding_identity_spelling(binding);
        List native = %(native $spelling);
        if (binding in statics)
          _forward_declaration(
            compiler, binding, locals, statics, seen, prototypes);
        else if (native in statics)
          _forward_declaration(
            compiler, native, locals, statics, seen, prototypes);
        else {
          Type type = NULL;
          List global = spelling
            ? compiler.sym.resolve_global(%($spelling), &type) : NULL;
          /* A generated protocol symbol is declared by the header that
             published it. A native alias among them is a macro over the
             host function, and newlib spells some of those as function-like
             macros, so a prototype of the alias would not even parse. */
          if (global && global.equal(binding) && type.is_function() &&
              !locals.contains(global) && !seen.contains(global) &&
              !compiler.sym.get(%("generated-protocol" $spelling))) {
            seen[global] = 1;
            _forward_types(compiler, type, locals, statics, seen, prototypes);
            prototypes.push(
              ast_prototype_declarator(type.declaration_ast(global)));
          }
        }
      }
      case %(vcompound ? ? ? ?name):
        _forward_declaration(compiler, %(native $name),
          locals, statics, seen, prototypes);
      case %(vpostfix ? ? ?name):
        _forward_declaration(compiler, %(native $name),
          locals, statics, seen, prototypes);
      case %((!or expr declare typedef function cast param) ?type *):
        if (type is <list>)
          _forward_types(compiler, type, locals, statics, seen, prototypes);
    }
    List rest = node;
    for (;;) {
      while (!rest) {
        if (!resume.len()) return;
        rest = resume.take_last();
      }
      Var child = rest.car();
      rest = rest.cdr();
      if (child is <list> && !child.is_nil()) {
        if (rest) resume.push(rest);
        node = child;
        break;
      }
    }
  }
}

static void _static_declarations(Var value, Map declarations) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function ?type (!set ?signature (bind ?binding ?)) ?): {
      if (type.list().type().is_static()) {
        List declaration =
          %(declare $type ${ast_prototype_declarator(signature)});
        declarations[binding] = declaration;
        declarations[%(native ${binding_identity_spelling(binding)})] =
          declaration;
      }
      return;
    }
    case %((!or declare typedef) ?base (bindings *bindings)): {
      if (base.list().type().is_static() || node.car() == <typedef>)
        foreach (List declarator, bindings) {
          List binding = _declaration_binding(declarator);
          if (!binding) continue;
          match (declarator)
            case %(op = ?target ?): declarator = target;
          List declaration = node.car() == <typedef>
            ? node : %(declare $base (bindings $declarator));
          declarations[binding] = declaration;
          if (node.car() == <typedef>)
            declarations[binding_identity_spelling(binding)] = declaration;
        }
      return;
    }
  }
  foreach (Var child, node)
    _static_declarations(child, declarations);
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
      else if (preproc_directive(content).startswith("undef")) {
        positions[position] = 1;
        foreach (Var group, open) positions[group] = 1;
      }
    }
    position++;
  }
  return positions;
}

/* Moves to `output` each pending body written under the open `arms`,
   reopening the groups it was written in beyond those. A body from another
   arm stays pending. */
static void _place_functions(Array output, Array functions, List arms) {
  size_t kept = 0;
  unsigned open = arms.len();
  foreach (List pending, functions) {
    List written = pending.cdr();
    if (written.tail(open) != arms) {
      functions[kept++] = pending;
      continue;
    }
    List reopened = written.head(written.len() - open);
    foreach (List item, preproc_within_arms(reopened, %(${pending.car()})))
      output.push(item);
  }
  functions.resize(kept);
}

/* Native directives and initializer inputs keep their source order.
   Ordinary function bodies follow the file's declarations and directives,
   preserving their existing access to later private includes and macros,
   but precede a later `#undef` and any conditional group containing one,
   as C requires of a body that uses the macro. Source initializer helpers
   stay at their capture positions. */
static List _static_prototypes(Compiler compiler, List source, List header) {
  Array output = [], declarations = [], functions = $auto([]);
  Map undefs = $auto(_undef_positions(source)), List arms = NULL;
  int position = 0;
  foreach (List node, source) {
    if (undefs.contains(position++))
      _place_functions(declarations, functions, arms);
    match (node) {
      case %(function ?type ?signature ?): {
        functions.push(%($node @arms));
        if (type.list().type().is_static())
          declarations.push(
            %(declare $type ${ast_prototype_declarator(signature)}));
        continue;
      }
      case %(preproc ?content): arms = preproc_track_arms(arms, content);
    }
    declarations.push(node);
  }
  _place_functions(declarations, functions, NULL);
  source = declarations.list_free();
  Map statics = {}, available = {}, seen = {};
  _collect_declared_bindings(header, available);
  _static_declarations(source, statics);
  foreach (List node, source) {
    if (node.car() == <typedef> && node in seen) continue;
    _collect_declared_bindings(node, available);
    _collect_forward_dependencies(
      compiler, node, available, statics, seen, output);
    output.push(node);
  }
  return output.list_free();
}

// formatting

// Emit the standard auto-generated banner.
static List _header(void) => %(
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

static List _include_directive(String fname) =>
  %((preproc "#include \"$fname\"") (space "\n") (space "\n"));

static List _vertical_spacing(List code) {
  Array values = [];
  foreach (Var elem, code) {
    values.push(elem);
    values.push(%(space "\n"));
  }
  return values.list_free();
}

static int _has_runtime_include(List content) {
  foreach (List unit, content) {
    if (!unit) continue;
    Var (kind, payload) = unit;
    if (kind != <preproc>) continue;
    String text = payload.string().strip(" \t\r\n");
    if (text == "#include \"x2c.x\"" || text == "#include <x2c.x>") return 1;
  }
  return 0;
}

static List _include_guard(Compiler compiler, List content, String filename) {
  if (compiler.runtime_inc && !_has_runtime_include(content))
    content = cons(%(preproc "#include \"x2c.x\""), content);
  String guard = x2c_filename_hash(filename), List header = _header();
  List guarded_code = _header_guard(content, guard);
  return %( @header @guarded_code );
}

// Insert the generated header include at the top of the source file.
static List _primary_include(Compiler compiler, List content) {
  String hname = %"${Path.stem(compiler.filename)}.h";
  List header = _header();
  List include = _include_directive(hname);
  List error = ast_contains_head(content, <raise>)
             ? _include_directive("error.h") : NULL;
  /* A cleanup region spells `X2CCleanup` and its push and leave calls, which
     `exception.x` declares. */
  List exception = compiler.needs_exception
                 ? _include_directive("exception.h") : NULL;
  return %( @header @include @error @exception @content );
}

// source finalization

// Inject compiler bootstrap invocation into main when present.
static List _modify_main(Compiler compiler, List source) {
  List initializer = compiler.sym.reference(%("x2c_initialize"), NULL);
  return source.map(%!(List unit) => {
    match (unit)
      case %(function ?rtype
             (bind (!set ?binding (*)) ?params)
             (block *vbody)):
        if (binding_identity_spelling(binding) == "main")
          return %(
            function $rtype (bind $binding $params)
            (block
              (stmnt (expr (void) (call
                (expr ((func ((void))) void) (ident $initializer))
                (args (expr (void) ())))))
              @vbody)
          );
    return unit;
  });
}

// public entry point

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
  ast = ast.filter(
    %!(unit) => !unit.list().match(%((!or space comment empty) *)));

  List (header, source) = _header_and_source(c, ast);
  String hash = x2c_filename_hash(c.filename);
  (header, source) = c.setup_cache_init(
    header, source,
    %"_x2c_hcache_${hash}_",
    %"_x2c_hcache_guard_$hash",
    %"_x2c_hcache_init_$hash");

  List header_declarations = header;
  header = _vertical_spacing(header);
  header = _include_guard(c, header, c.filename);
  header = c.emit(header);

  source = _file_init(c, source);
  source = _static_prototypes(c, source, header_declarations);
  source = _vertical_spacing(source);
  source = _primary_include(c, source);
  source = _modify_main(c, source);
  source = c.emit(source);

  String basename = %"${dir.rstrip("/")}/${Path.stem(c.filename)}";
  String hfile = %"$basename.h", cfile = %"$basename.c";
  List outputs = %(
    $hfile ${c.code_pretty_string(header, hfile)}
    $cfile ${c.code_pretty_string(source, cfile)}
  );
  String interface = c.source_facts
                   ? NULL : interface_text(c, _public_definition_rows(c, ast));
  if (interface) outputs = outputs.append(%("$basename.xi" $interface));
  List failure = NULL;
  try file_publish(outputs);
  catch %(not-found *detail): failure = Error.snapshot(detail);
  catch %(io-fail *detail): failure = Error.snapshot(detail);
  if (failure) {
    String reason = String.new(strerror((int) failure.assoc(<errno>)));
    c.report_error(
      <emit>, "failed to write generated file", c.token,
      %("file: ${failure.assoc(<path>)}" "reason: $reason"));
  }
}

/** Returns the statements queued for `phase`, in the order they were added. */
List Compiler.init_statements(Compiler compiler, Symbol phase) {
  Array selected = [];
  foreach (List entry, compiler.inits)
    if (entry.car() == phase) selected.push(entry.cadr());
  return selected.list_free();
}
