/*  cache.x -- constant caching for x2c code generation

    Copyright (c) 2025 Gary William Flake.

    Discovers and materializes cached literals between lowering and C
    emission. Immutable values share generated storage; mutable collections
    are copied at use sites, so caching does not change identity.

    `Compiler.cache` decides cache-key equality and assigns `(cache id)` nodes
    whose ids index `Compiler.id_keys`. Generation trusts that mapping. Header
    and source regions may materialize the same immutable value in separate
    static slots; `String` and `List` canonicalization preserves value identity
    across them.
  */
#pragma once
#include "compiler.x"
#pragma private
#include "type.x"
#include "var.x"
#include "string.x"
#include "transform.x"
#include "expressions.x"
#include "logger.x"
#include <stdio.h>
#include <stdint.h>
#include <assert.h>

/* Cache ids keep the identity assigned by `Compiler.cache`. Source slots use
   compact `_id` names; the generated-header prefix qualifies private slots
   with the source filename hash. */
static inline String _generate_cache_ident(Var id, String prefix) =>
  prefix ? %"$prefix$id" : %"_$id";

static List _generate_cache_declare(
  List ids, String type, Compiler compiler, String prefix) {
  if (!ids) return NULL;
  Array values = %[];
  foreach (Var id, ids) {
    List binding = compiler.sym.reference(
      %(${_generate_cache_ident(id, prefix)}), NULL);
    values.push(%(bind $binding ()));
  }
  List binds = values.list_free();
  return %(declare (static $type) (bindings @binds));
}

// literal materialization

static List _generate_cache_val(List expr, Compiler compiler, String prefix) {
  if (!expr) return NULL;
  match (expr) {
    case %(cons ?captured_head ?captured_tail): {
      List head = _generate_cache_val(captured_head, compiler, prefix);
      List tail = _generate_cache_val(captured_tail, compiler, prefix);
      List cons_binding = compiler.sym.reference(%("cons"), NULL);
      return %(expr ("List")
        (call (expr ((func (("Var") ("List")) "List")) (ident $cons_binding))
              ( args $head $tail ))
      );
    }
    case %((!or array varray) *):
      return %(expr ("Array") ${transform_array_literal(compiler, expr)});
    case %((!or map vmap) *):
      return %(expr ("Map") ${transform_map_literal(compiler, expr)});
    case %(string *):
      // Keep String initializer nodes; literal folding is handled elsewhere.
      return expr;
    case %(cache ?id): {
      List val = compiler.id_keys[id], reference = expr;
      if (prefix) {
        String ident = _generate_cache_ident(id, prefix);
        List binding = compiler.sym.reference(%($ident), NULL);
        reference = %(ident $binding);
      }
      match (val) {
        case %(string ?): return %(expr ("String") $reference);
        case %(var ?):    return %(expr ("Var") $reference);
        case %(cons *):   return %(expr ("List") $reference);
      }
      __builtin_unreachable();
    }
  }
  return expr;
}

static List _generate_cache_assignment(
  int id, List value, List type, Compiler compiler, String prefix) {
  String ident = _generate_cache_ident(id, prefix);
  List binding = compiler.sym.reference(%($ident), NULL);
  List rhs = _generate_cache_val(value, compiler, prefix);
  rhs = compiler.convert_expression(rhs, type);
  return %( stmnt (expr $type (op = (expr $type (ident $binding)) $rhs)));
}

static List _generate_cache_initializer(
  int id, Compiler compiler, String prefix) {
  List key = compiler.id_keys[id];
  match (key) {
    case %(string ?value):
      return _generate_cache_assignment(
        id, value, %("String"), compiler, prefix);
    case %(var ?value):
      return _generate_cache_assignment(
        id, value, %("Var"), compiler, prefix);
    case %(!set ?value (cons *)):
      return _generate_cache_assignment(
        id, value, %("List"), compiler, prefix);
  }
  __builtin_unreachable();
}

// static declaration utilities

static List _make_assignment_stmt(List binding, List type, List rhs) =>
  %( stmnt (expr $type (op = (expr $type (ident $binding)) $rhs)));

static inline int _is_composite_initializer(List value) {
  match (value) case %(composite *): return 1;
  return 0;
}

static List _build_static_initializer_rhs(
  List decltype, List binding, List mods, List type, List value) {
  if (!_is_composite_initializer(value)) return %(expr $type $value);
  List bound = %(bind $binding $mods);
  List decl_ast = %(declare $decltype (bindings $bound));
  Type cast_type = decl_ast.type_from_ast();
  if (cast_type) cast_type = cast_type.canonicalize();
  List decl = %(decl $cast_type (bindings (bind () ())));
  List literal = %(expr () $value), rhs_value = %(cast $decl $literal);
  return %(expr $cast_type $rhs_value);
}

// global static declaration rewrites

/* Preserve native initializer shape so C infers dimensions and checks
   designators before cached values are assigned during initialization. */
static List _zero_static_initializer(Compiler compiler, List value) {
  List zero = %(expr (int) (literal (int) "0"));
  match (value) {
    case %(expr ?type (!set ?body (initval *))): {
      List header = NULL;
      List cases = Ast.initializer_cases(body.list(), &header);
      Array zeroed = %[];
      foreach (List choice, cases) {
        (List condition, List path, Type destination, List input) = choice;
        List zero = _zero_static_initializer(compiler, input);
        match (zero)
          case %(expr ?type (!set ?body (composite *))):
            zero = _build_static_initializer_rhs(type, NULL, NULL, type, body);
        zeroed.push(%($condition $path $destination $zero));
      }
      return %(expr $type (initval @{zeroed.list_free()}));
    }
    case %(expr ?type (!set ?inner (composite *))):
      return %(expr $type ${_zero_static_initializer(compiler, inner)});
    case %(expr ?type ?): {
      Type resolved = compiler.sym.resolve_key(type);
      return resolved.is_aggregate()
        ? %(expr $type (composite (commas $zero))) : zero;
    }
    case %(composite (commas *items)): {
      Array zeroed = %[];
      foreach (List item, items)
        zeroed.push(_zero_static_initializer(compiler, item));
      return %(composite (commas @{zeroed.list_free()}));
    }
    case %((!set ?tag (!or dotinit indexinit)) ?key ?inner):
      return %($tag $key ${_zero_static_initializer(compiler, inner)});
  }
  return zero;
}

/* Reuse ordinary indexed assignments, recursing only for explicit array
   braces. C can warn and ignore excess positional values, so writes use the
   native object's actual dimensions rather than the initializer count. */
static List _build_static_array_block(
  Compiler compiler, List target, Type array, List items) {
  Array statements = %[];
  foreach (List row, compiler.initializer_rows(array, items, target)) {
    (List original, List cases) = row;
    List terminal = original, header = NULL, source = NULL;
    while (terminal.car() == <dotinit> || terminal.car() == <indexinit>)
      terminal = terminal.caddr();
    List functions = NULL;
    match (terminal)
      case %(expr ? (!set ?body (initval *))): {
        Ast.initializer_cases(body.list(), &header);
        functions = Ast.initializer_functions(body.list(), &source);
      }
    Array assigned = %[];
    List applicable = NULL;
    int unconditional = 0;
    foreach (List choice, cases) {
      (List condition, List path, Type type, List value) = choice;
      if (!type) continue;
      List slot = target, tests = NULL;
      foreach (List frame, path.reverse()) {
        (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
        List parent = slot;
        if (kind == <index>) {
          slot = %(expr $selected (index $parent $selector));
          List length = %(expr (unsigned)
            (op / (expr (unsigned) (sizeof (parens $parent)))
                  (expr (unsigned) (sizeof (parens $slot)))));
          tests = cons(%(expr (int) (op < $selector $length)), tests);
        }
        else if (selector.truth())
          slot = %(expr $selected (op . $parent ($selector)));
      }
      List inner = NULL, rhs = value, assignment;
      match (value) {
        case %(expr ? (!set ?body (composite *))): inner = body;
        case %(!set ?body (composite *)): inner = body;
      }
      Type resolved = compiler.sym.resolve_key(type);
      if (inner && resolved.is_array())
        assignment = _build_static_array_block(
          compiler, slot, resolved, inner.cadr().list().cdr());
      else {
        if (inner)
          rhs = _build_static_initializer_rhs(type, NULL, NULL, type, inner);
        if (condition) {
          List zero = _build_static_initializer_rhs(type, NULL, NULL, type,
            %(composite (commas (expr (int) (literal (int) "0")))));
          rhs = %(expr $type
            (call "__builtin_choose_expr" (args $condition $rhs $zero)));
        }
        assignment = %(stmnt (expr $type (op = $slot $rhs)));
      }
      if (condition) tests = cons(condition, tests);
      List active = NULL;
      foreach (List test, tests) {
        active = active ? %(expr (int) (op && $active $test)) : test;
        assignment = %(if $test $assignment);
      }
      if (!active) unconditional = 1;
      else applicable = applicable
        ? %(expr (int) (op || $applicable $active)) : active;
      assigned.push(assignment);
    }
    List code = assigned.list_free();
    if (functions && code) {
      Type type = source.cadr();
      List binding = compiler.sym.introduce(
        compiler.fresh_name("initializer_value"));
      List local = %(expr $type (ident $binding));
      List input = header.cadr();
      List formal = %(expr $type ${input.car()});
      code = code.search_replace(%(!quote $formal), local);
      List initial = source;
      if (!unconditional) {
        List zero = _build_static_initializer_rhs(type, NULL, NULL, type,
          %(composite (commas (expr (int) (literal (int) "0")))));
        initial = %(expr $type (op ? $applicable $source $zero));
      }
      List declaration = %(declare $type
        (bindings (op = (bind $binding ()) $initial)));
      code = %($declaration @code);
    }
    else if (header) code = %(initcode $header $code);
    statements.push(code);
  }
  return %(block @{statements.list_free()});
}

/* Strip one initialized binding and record the assignment that replaces it.
   C does not allow a non-constant static initializer, and after lowering
   most of them are calls. */
static List _record_deferred_binding(
  List name, List mods, List assign, Array initializers) {
  initializers.push(%($name $assign));
  return %(bind $name $mods);
}

static List _defer_one_binding(
  Compiler compiler, List decltype, Ast bound, Array initializers) {
  match (bound) {
    case %(bind *): return bound;
    case %(op = (bind ?name ?mods) (expr ?type ?value)): {
      List declaration = %(declare $decltype (bindings (bind $name $mods)));
      Type declared = declaration.type_from_ast().canonicalize();
      Type resolved = compiler.sym.resolve_key(declared);
      if (resolved.is_array()) {
        if (!_contains_cache_ref(value) &&
            !ast_contains_head(value, <initval>)) return bound;
        match (value)
          case %(composite (commas *items)): {
            List target = %(expr $declared (ident $name));
            List assign = _build_static_array_block(
              compiler, target, resolved, items);
            List binding = _record_deferred_binding(
              name, mods, assign, initializers);
            List zero = _zero_static_initializer(compiler, value);
            return %(op = $binding (expr $type $zero));
          }
        return bound;
      }
      List stored = _build_static_initializer_rhs(
        decltype, name, mods, type, value);
      List assign = _make_assignment_stmt(name, type, stored);
      return _record_deferred_binding(name, mods, assign, initializers);
    }
  }
  return bound;
}

static List _defer_bindings(
  Compiler compiler, List decltype, List bound_list, Array initializers) {
  Array values = %[];
  foreach (Ast bound, bound_list)
    values.push(_defer_one_binding(compiler, decltype, bound, initializers));
  return %(declare $decltype (bindings @{values.list_free()}));
}

/* Lowering turns most non-const file-static initializers into calls, so they
   run in the initializer phase. Public file statics holding cache references
   defer too; otherwise nothing assigns their slots. */
static List _rewrite_file_scope_decl(
  Compiler compiler, List decl, Array initializers) {
  match (decl)
    case %(declare (!set ?decltype (!and (static *) (!not (* const *))))
                   (bindings *bound_list)):
      return _defer_bindings(compiler, decltype, bound_list, initializers);
  if (!_contains_cache_ref(decl)) return decl;
  match (decl)
    case %(declare (!set ?decltype (!not (* const *)))
                   (bindings *bound_list)):
      return _defer_bindings(compiler, decltype, bound_list, initializers);
  return decl;
}

static void _report_static_initializer_cycle(
  Compiler compiler, Array initializers, Map state) {
  Array notes = %[], List first = NULL;
  foreach (List initializer, initializers)
    match (initializer)
      case %(?binding *): {
        Var status;
        if (!state.try_get(binding, &status) || status.integer() != 1)
          continue;
        if (!first) first = binding;
        String name = binding_identity_spelling(binding);
        if (name) notes.push(%"initializer: $name");
      }
  Token token = NULL;
  Var token_index;
  if (first && compiler.init_tokens.try_get(first, &token_index)) {
    Token tokens = compiler.tokenizer.tokens;
    token = tokens + token_index.integer();
  }
  List details = notes.list_free();
  compiler.report_error(
    <cache>, "file-static x2c initializer dependency cycle",
    token, details);
}

static void _queue_one_static_initializer(
  Compiler compiler, List binding, Map pending, Map state,
  Map phases, Array initializers, Symbol deferred_kind) {
  Var status;
  if (state.try_get(binding, &status)) {
    if (status.integer() == 2) return;
    _report_static_initializer_cycle(compiler, initializers, state);
  }
  state[binding] = 1;
  List initializer = pending[binding], assignment = initializer.cadr();
  int late = 0;
  Var stored;
  if (compiler.static_init_deps.try_get(binding, &stored)) {
    List dependencies = stored;
    foreach (List dependency, dependencies) {
      if (pending.contains(dependency)) {
        _queue_one_static_initializer(
          compiler, dependency, pending, state, phases,
          initializers, deferred_kind);
        Var phase = phases[dependency];
        if (phase is not void && phase.integer()) late = 1;
      }
    }
  }
  if (deferred_kind) {
    Array dependencies = _cache_ids_in(compiler, assignment);
    if (dependencies) {
      Array keys = compiler.id_keys;
      for (int i = 0; i < keys.len(); i++)
        if (!dependencies[i].is_null() &&
            keys[i].list().car() == deferred_kind) {
          late = 1;
          break;
        }
      dependencies.free();
    }
  }
  List helper = initializer.caddr();
  List invocation = %(stmnt (expr (void)
    (call (expr ((func ((void))) void) (ident $helper)) (args))));
  if (late) compiler.add_late_init(invocation);
  else compiler.add_mid_init(invocation);
  phases[binding] = late;
  state[binding] = 2;
}

/* Queue a stable dependency walk. Dependencies precede their consumers, and
   independent roots retain source order. A dependency queued late moves every
   consuming initializer late as well. */
static void _queue_static_initializers(
  Compiler compiler, Array initializers, Symbol deferred_kind) {
  Map pending = %{}, state = %{}, phases = %{};
  foreach (List initializer, initializers)
    pending[initializer.car()] = initializer;
  foreach (List initializer, initializers)
    _queue_one_static_initializer(
      compiler, initializer.car(), pending, state, phases,
      initializers, deferred_kind);
}

/* Apply file-scope initializer rewrites across one generated region. Both
   regions share one initializer list, so a header definition deferred into
   the source's initializer is ordered against the file statics it reads. */
static List _rewrite_file_scope_statics(
  Compiler compiler, List code, Array initializers) {
  Array output = %[];
  foreach (List item, code) {
    int first = initializers.len();
    match (item)
      case %(!set ?declaration (declare *)):
        item = _rewrite_file_scope_decl(compiler, declaration, initializers);
    output.push(item);
    for (int i = first; i < initializers.len(); i++) {
      (List binding, List assignment) = initializers[i];
      List helper = compiler.sym.introduce(
        compiler.fresh_name("static_initialize"));
      initializers[i] = %($binding $assignment $helper);
      List function = %(function (static void)
        (bind $helper ((fnmod (params (param (void) (bind () ()))))))
        (block $assignment));
      output.push(%(sourceinit $function));
    }
  }
  return output.list_free();
}

// cache key processing

/* Split the masked cache ids by declaration type. Each list keeps the
   descending id order the emitted declarations rely on. */
static List _split_ids(Array keys, Array ids) {
  List list_ids = NULL, string_ids = NULL, var_ids = NULL;
  for (int i = 0, n = keys.len(); i < n; i++) {
    if (ids[i].is_null()) continue;
    List key = keys[i];
    match (key) {
      case %(cons *): {
        list_ids = cons(i, list_ids);
        continue;
      }
      case %(string ?): {
        string_ids = cons(i, string_ids);
        continue;
      }
      case %(var ?): {
        var_ids = cons(i, var_ids);
        continue;
      }
    }
    __builtin_unreachable();
  }
  return %($list_ids $string_ids $var_ids);
}

// cache residency

/* Collect direct cache references and the immutable graph they depend on.
   Generated ASTs are canonical DAGs rather than trees, so the direct-mapped
   identity memo avoids repeatedly walking shared subgraphs. A collision only
   replaces one memo entry and may cause harmless extra work. */
static int _collect_cache_ids(
  Compiler compiler, Var value, List *seen, Array ids) {
  Array pending = %[$value];
  defer pending.free();
  int count = 0;
  while (pending) {
    Var current = pending.take_last();
    if (current is not <list>) continue;
    List node = current;
    unsigned slot = ((uintptr_t) node >> 4) & 4095;
    if (seen[slot] == node) continue;
    seen[slot] = node;
    match (node)
      case %(cache ?captured_id): {
        int id = captured_id;
        if (!ids[id].is_null()) continue;
        ids[id] = 1;
        count++;
        pending.push(compiler.id_keys[id]);
        continue;
      }
    foreach (Var child, node) if (child is <list>) pending.push(child);
  }
  return count;
}

static Array _cache_ids_in(Compiler compiler, List code) {
  List seen[4096] = { 0 };
  Array ids = %[];
  ids.resize(compiler.id_keys.len());
  if (!_collect_cache_ids(compiler, code, seen, ids)) {
    ids.free();
    return NULL;
  }
  return ids;
}

static int _contains_cache_ref(Var value) {
  if (value is not <list>) return 0;
  List node = value;
  match (node) case %(cache ?): return 1;
  foreach (Var child, node) if (_contains_cache_ref(child)) return 1;
  return 0;
}

// Replace cache nodes with the TU-local identifiers used by a header region.
static List _rewrite_header_cache_refs(
  Compiler compiler, List node, String prefix, int *replaced) {
  if (!node) return node;
  match (node)
    case %(cache ?id): {
      if (replaced) *replaced = 1;
      String ident = _generate_cache_ident(id, prefix);
      List binding = compiler.sym.reference(%($ident), NULL);
      return %(ident $binding);
    }
  Array values = %[];
  foreach (Var child, node) {
    if (child is <list>)
      child = _rewrite_header_cache_refs(compiler, child, prefix, replaced);
    values.push(child);
  }
  List result = values.list_free();
  return result;
}

static List _make_header_cache_guard(List guard) => %(declare (static int)
    (bindings (op = (bind $guard ()) (expr (int) (literal (int) "0")))));

static List _make_header_cache_init(
  List guard, List initializer, List statements) => %(
    function (("__attribute__((constructor))") static void)
      (bind $initializer ((fnmod (params (param (void) (bind () ()))))))
      (block
        (stmnt (expr (void) (call "x2c_initialize_protocols" (args))))
        (if (expr (int) (ident $guard)) (return))
        (stmnt
          (expr (int) (op = (expr (int) (ident $guard))
            (expr (int) (literal (int) "1")))))
        @statements)
  );

static List _patch_header_cache_function(
  List type, List bind, List statements, List guard, String initializer) => %(
    function $type $bind
      (block
        (if (expr (int) (op ! (expr (int) (ident $guard))))
          (stmnt (expr (void) (call $initializer (args)))))
        @statements)
  );

/* Add one translation-unit-local immutable cache to a generated header.
   The constructor eagerly establishes process-lifetime values; patched inline
   entries retain the same guard-based fallback as source-resident caches. */
static List _setup_header_cache(
  Compiler c, List header, Array ids, String prefix, String guard_name,
  String initializer_name) {
  if (!ids) return header;
  List (list_ids, string_ids, var_ids) = _split_ids(c.id_keys, ids);
  Array declarations = %[];
  List declaration = _generate_cache_declare(list_ids, "List", c, prefix);
  if (declaration) declarations.push(declaration);
  declaration = _generate_cache_declare(string_ids, "String", c, prefix);
  if (declaration) declarations.push(declaration);
  declaration = _generate_cache_declare(var_ids, "Var", c, prefix);
  if (declaration) declarations.push(declaration);
  List guard = c.sym.reference(%($guard_name), NULL);
  List initializer = c.sym.reference(%($initializer_name), NULL);
  declarations.push(_make_header_cache_guard(guard));
  Array statements = %[];
  for (int i = 0, n = c.id_keys.len(); i < n; i++) {
    if (ids[i].is_null()) continue;
    List statement = _generate_cache_initializer(i, c, prefix);
    statements.push(_rewrite_header_cache_refs(c, statement, prefix, NULL));
  }
  declarations.push(
    _make_header_cache_init(guard, initializer, statements.list_free()));
  ids.free();
  List prelude = declarations.list_free(), Array output = %[];
  int inserted = 0;
  foreach (List node, header) {
    int replaced = 0;
    node = _rewrite_header_cache_refs(c, node, prefix, &replaced);
    int captured = node.car() == <sourceinit>;
    List function = node;
    if (captured) function = node.cadr();
    match (function)
      case %(function ?type ?bind (block *statements)):
        if (replaced) {
          if (!inserted) {
            foreach (Var item, prelude) output.push(item);
            inserted = 1;
          }
          function = _patch_header_cache_function(
            type, bind, statements, guard, initializer_name);
          node = captured ? %(sourceinit $function) : function;
        }
    output.push(node);
  }
  return output.list_free();
}

/* Materialize source cache slots before ordinary file-static assignments.
   While generating String.initialize or List.initialize, a cache graph that
   requires that same canonicalizer runs late, after the initializer body;
   dependent file-static assignments move late with it. */
static List _setup_source_cache_init(
  Compiler c, List source, Array ids, Array initializers) {
  source = _rewrite_file_scope_statics(c, source, initializers);
  Array keys = c.id_keys, Symbol deferred_kind = 0;
  if (c.init_fn == "String_initialize") deferred_kind = <string>;
  else if (c.init_fn == "List_initialize") deferred_kind = <cons>;
  if (!ids) {
    _queue_static_initializers(c, initializers, deferred_kind);
    return source;
  }
  for (int i = 0, n = keys.len(); i < n; i++) {
    if (ids[i].is_null()) continue;
    List stmt = _generate_cache_initializer(i, c, NULL), int deferred = 0;
    if (deferred_kind) {
      Array dependencies = _cache_ids_in(c, %(cache $i));
      for (int dependency = 0; dependency < keys.len(); dependency++) {
        if (dependencies[dependency].is_null()) continue;
        Symbol kind = keys[dependency].car();
        if (kind == deferred_kind) {
          deferred = 1;
          break;
        }
      }
      dependencies.free();
    }
    if (deferred) c.add_late_init(stmt);
    else c.add_early_init(stmt);
  }
  _queue_static_initializers(c, initializers, deferred_kind);
  List (list_ids, string_ids, var_ids) = _split_ids(keys, ids);
  ids.free();
  Array built = %[];
  List declaration = _generate_cache_declare(list_ids, "List", c, NULL);
  if (declaration) built.push(declaration);
  declaration = _generate_cache_declare(string_ids, "String", c, NULL);
  if (declaration) built.push(declaration);
  declaration = _generate_cache_declare(var_ids, "Var", c, NULL);
  if (declaration) built.push(declaration);
  List declarations = built.list_free();
  return declarations.append(source);
}

/** Materializes cached literals and deferred file-static initialization.
    `header` and `source` must be partitioned lowered AST regions from this
    compiler. Every `(cache id)` must index `compiler.id_keys`, and file-static
    dependency state from the full parse must be complete. `prefix`,
    `guard_name`, and `initializer_name` name the header's private slots,
    guard, and initializer. Returns `(header source)` and appends source work
    to the compiler's early, middle, and late initialization phases; the
    operation is not idempotent. Header cache storage remains private to each
    C translation unit that includes it.
*/
List Compiler.setup_cache_init(
  Compiler compiler, List header, List source, String prefix,
  String guard_name, String initializer_name) {
  Array initializers = %[];
  header = _rewrite_file_scope_statics(compiler, header, initializers);
  Array header_ids = _cache_ids_in(compiler, header);
  /* A deferred header initializer is now in the source's initializer,
     so its slots belong to the source region. */
  Array scan = %[];
  scan.push(source);
  foreach (Var initializer, initializers) scan.push(initializer);
  Array source_ids = _cache_ids_in(compiler, scan.list_free());
  if (header_ids)
    header = _setup_header_cache(
      compiler, header, header_ids, prefix, guard_name, initializer_name);
  source = _setup_source_cache_init(
    compiler, source, source_ids, initializers);
  initializers.free();
  return %($header $source);
}
