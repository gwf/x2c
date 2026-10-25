/* declaration defaults

   A declaration producer can offer defaults: functions that bind only when
   no other declaration takes their name, and constructors that forward to
   a parent's constructor. The owning file selects them after all its
   segments. */

/* One selection of a file's defaults. `c`, a shadow compiler, binds them
   over the file's collected symbols. `sources` holds one
   `(declarations key end rows)` entry per production, and `pending` the
   children whose forwarded constructors wait for their parent's
   constructor. */
static typedef struct Defaults {
  Compiler c, Array parts, sources;
  Map definitions, pending;
} Defaults;

/** Selects the owning file's declaration defaults after all its segments.
    The selected signatures join ordinary declarations before protocol and
    body binding; discarded candidates never bind their bodies. Returns added
    signatures for the caller to retain in the header-cache lifetime.
*/
Map Compiler.select_declaration_defaults(
  Compiler c, String path, Map symbols, Array parts, Map definitions,
  Map statics) {
  Compiler shadow = Compiler.new_shared(c);
  defer c.close_child(shadow);
  _prepare_shadow(shadow, c, path, symbols);
  Array sources = [];
  Map pending = {};
  Defaults d = {
    .c = shadow, .parts = parts, .sources = sources,
    .definitions = definitions, .pending = pending};
  foreach (Var part in parts) if (part is <map>) _produce_defaults(d, part);
  _select(d);
  _forward(d);
  _store(d, symbols);
  Map additions = shadow.sym.current_symbols();
  symbols.merge(additions);
  statics.merge(shadow.sym.file_statics());
  c.merge_source_declarations(symbols, additions);
  c.fn_defs.merge(shadow.fn_defs);
  definitions.merge(shadow.fn_defs);
  return additions;
}

/* The shadow binds over the file's collected symbols in an overlay,
   without parsing, in the unit's Lisp session and meta group. */
static void _prepare_shadow(
  Compiler c, Compiler owner, String path, Map symbols) {
  c.filename = path;
  c.macro_lisp = owner.macro_lisp;
  c.borrowed_lisp = c.macro_lisp != NULL;
  c.share_meta_group(owner);
  c.sym.reset_overlay(symbols, {});
  c.rebuild_protocols(symbols);
  c.conforms = {};
  c.shallow = 1;
}

// A part's productions run in source order.
static void _produce_defaults(Defaults &d, Map declarations) {
  Array ordered = [];
  foreach (Var (key, value) in declarations)
    match (key)
      case %("source-node" (declaration ? ?position)):
        ordered.push(%($position $key $value));
  ordered.sort();
  foreach (List entry in ordered) {
    (Var position, Var key, Var value) = entry;
    (void) position;
    match (value)
      case %(declaration-source ?end (declaration-bundle (rows *rows))
               ?facts): {
        _restore_declaration_bindings(d.c, rows, facts, {});
        Array produced = [];
        _produce_rows(d.c, rows, produced);
        d.sources.push(%($declarations $key $end ${produced.list_free()}));
      }
  }
}

/* A pending row runs its recipe under the macro stack and privacy of its
   construction, and the rows it generates are produced in turn. */
static void _produce_rows(Compiler c, List rows, Array selected) {
  foreach (List row in rows) {
    match (row)
      case %(declaration-pending ?callback ?arguments
               ?construction ?privacy): {
        with (c.macro_stack = construction, c.source_private = privacy) {
          _produce_rows(c, _generated_rows(c, callback, arguments), selected);
        }
        continue;
      }
    selected.push(row);
  }
}

// A recipe's rows: the children of a sequence or bundle, or its one node.
static List _generated_rows(Compiler c, Var callback, Var arguments) {
  List generated = c.bind_syntax(
    c.evaluate_declaration_recipe(callback, arguments), <unit>, NULL);
  List additions = %($generated);
  match (generated) {
    case %(seq *children): additions = children;
    case %(declaration-bundle (rows *children)): additions = children;
  }
  return additions;
}

/* Each production selects its defaults, and a forwarded constructor
   waits for its parent's constructor. */
static void _select(Defaults &d) {
  for (size_t index = 0; index < d.sources.len(); index++) {
    (Map declarations, Var key, Var end, List rows) = d.sources[index];
    List selected = _select_rows(d, rows);
    foreach (List row in selected)
      match (row)
        case %(declaration-forward ?child *): d.pending[child] = 1;
    d.sources[index] = %($declarations $key $end $selected);
  }
}

static List _select_rows(Defaults &d, List rows) {
  Compiler c = d.c;
  Array selected = [];
  foreach (List row in rows) {
    match (row)
      case %(declaration-default ?function ?construction ?privacy): {
        with (c.macro_stack = construction, c.source_private = privacy) {
          Var syntax = _unless_taken(d, function);
          if (syntax is not void) selected.push(_bind_default(c, syntax));
        }
        continue;
      }
    selected.push(row);
  }
  return selected.list_free();
}

/* Returns the function to bind for a default, named through its macro
   slot, or void when a declaration already takes its name. */
static Var _unless_taken(Defaults &d, List syntax) {
  match (syntax)
    case %(function ?return_type (bind ?name ?modifiers) ?body): {
      name = d.c.evaluate_macro_slot(name);
      String spelling = Ast.binding_spelling(name);
      match (name) {
        case %(?(String literal)): spelling = literal;
        case %("x2c.ident" ?(String literal)): spelling = literal;
      }
      if (spelling && _taken(d, spelling)) return void;
      return %(function $return_type (bind $name $modifiers) $body);
    }
  return syntax;
}

/* A default yields to any declaration of its name except a bodyless,
   non-static function prototype in the default's own file, which the
   default then completes. */
static int _taken(Defaults &d, String spelling) {
  Compiler c = d.c;
  List key = %($spelling);
  Type declared = c.sym.get(key);
  if (!declared) return 0;
  if (!declared.is_function() || spelling in d.definitions ||
      spelling in c.fn_defs || %(function $spelling) in c.sym.file_statics())
    return 1;
  foreach (Var part in d.parts)
    if (part is <map> && key in part.map()) return 0;
  return 1;
}

static List _bind_default(Compiler c, List syntax) {
  if (c.source_private)
    match (syntax)
      case %(function ?type ?declarator ?body):
        if (!type.type().is_static())
          syntax = %(function (static @type) $declarator $body);
  return c.bind_syntax(syntax, <unit>, NULL);
}

/* Forwarded constructors bind as their parents' constructors complete; a
   round that completes none leaves a parent that never will. */
static void _forward(Defaults &d) {
  int remaining = d.pending.len();
  while (remaining) {
    int previous = remaining;
    remaining = 0;
    for (size_t index = 0; index < d.sources.len(); index++) {
      (Map declarations, Var key, Var end, List rows) = d.sources[index];
      rows = _forward_rows(d, rows, remaining);
      d.sources[index] = %($declarations $key $end $rows);
    }
    if (remaining && remaining == previous)
      $fail.compiler_ctor_parent(d.c, d.c.token);
  }
}

static List _forward_rows(Defaults &d, List rows, int &remaining) {
  Array selected = [];
  foreach (List row in rows) {
    match (row)
      case %(declaration-forward ?child ?parent ?member ?fallback ?privacy): {
        List bound = NULL;
        with (d.c.source_private = privacy) {
          bound = _forwarded(d, child, parent, member, fallback);
        }
        if (!bound) {
          remaining++;
          selected.push(row);
        }
        else {
          d.pending.del(child);
          if (bound.car() != <seq>) selected.push(bound);
        }
        continue;
      }
    selected.push(row);
  }
  return selected.list_free();
}

/* Binds the constructor `child_member` that forwards to the parent's
   `member`. It is `(seq)` when that name is already declared, the fallback
   when the parent has no such member, and NULL while the parent's own
   constructor is still pending. */
static List _forwarded(
  Defaults &d, Type child, Type parent, String member, List fallback) {
  Compiler c = d.c;
  String name = %"${child.car()}_$member";
  if (c.sym.get(%($name))) return %(seq);
  List method = c.resolve_postfix_member(parent, %($member), <.>, 1);
  if (!method) {
    if (parent in d.pending) return NULL;
    return fallback ? _bind_default(c, fallback.car()) : NULL;
  }
  List binding = NULL, Type signature = NULL;
  match (method)
    case %(method ?target ?type): {
      binding = target;
      signature = type;
    }
  if (!signature) return NULL;
  return _bind_default(c, _forwarder(c, name, child, binding, signature));
}

/* The forwarding constructor passes each argument on and casts the result.
   It is static in a private source, as `_bind_default` makes a default. */
static List _forwarder(
  Compiler c, String name, Type child, List binding, Type signature) {
  List types = NULL;
  match (signature) case %((func ?parameters) *): types = parameters;
  Array forwarded = [];
  foreach (Var type in types) {
    if (type == <...>)
      $fail.compiler_ctor_variadic(c, c.token, name);
    if (type != %(void)) forwarded.push(type);
  }
  (List params, List args) = c.forward_parameters(forwarded.list_free());
  if (!params) params = %((param (void) (bind () ())));
  Type result = c.source_private ? %(static @child) : child;
  List function = %($name), callee = $!($signature){ $binding };
  return c.rebuild_unit_function($!Unit{
    $result $function(@params) { return ($child)$callee(@args); }
  });
}

/* The selected rows replace each production's bundle in its part and in
   the unit's symbols. */
static void _store(Defaults &d, Map symbols) {
  foreach (List source in d.sources) {
    (Map declarations, Var key, Var end, List rows) = source;
    declarations[key] =
      %(declaration-source $end (declaration-bundle (rows @rows))
        ${d.c.semantic_binding_facts()});
    symbols[key] = declarations[key];
  }
}
