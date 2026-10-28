/*  emission.x -- meta group emission

    Copyright (c) 2026 Gary William Flake.
*/

// emitting the group

/* Emits the group through the ordinary backend as `(hfile htext cfile
   ctext)` named by `stem`, with exported names ending in `suffix`, or
   returns NULL with `failure` set when it does not lower. The emission
   borrows the unit's bindings and types and leaves the unit as it found
   it: generated names, literal caches, helpers, initializers, and semantic
   rows are its own. */
module List _emit(
  Compiler c, String stamp, String stem, String suffix, String &failure) =>
  _emit_prepared(c, stamp, stem, suffix, NULL, NULL, failure);

module List _emit_prepared(
  Compiler c, String stamp, String stem, String suffix,
  List declarations, Func prepare, String &failure) {
  Array units = prepare ? NULL : _units(c);
  String provider = c.filename;
  /* The backend reads more of the unit's compiler than a child from
     `Compiler.new_shared` inherits, such as its tokenizer, runtime header
     and literal policy, init names, origin, and meta bindings, so the
     emission runs on the unit's own compiler and restores it after. */
  struct Compiler saved = *c;
  struct GenNames names = *c.names;
  SymTxn transaction = c.begin_semantic_transaction();
  _isolate(c, saved, names, stem);
  List code = NULL;
  try {
    if (prepare) {
      c.meta_group = [];
      c.unit_nodes = declarations;
      c.group_meta_function(prepare(c));
      units = _units(c);
    }
    if (c.meta_build) _name_provider_bindings(c, provider, units, saved.deps);
    List lowered = _lower(c, units, stamp, suffix);
    /* A project group holds the unit's public functions, so it also
       holds the protocol adapters they call and their registration. */
    if (c.meta_build) lowered = c.generate_protocol_adapters(lowered);
    List ast = c.transform(lowered);
    code = c.generate_code_text(ast, stem);
  }
  catch %(?kind *detail): {
    List entries = c.diagnostics.entries();
    failure = entries ? Compiler.meta_diagnostic_line(entries.car())
                      : cons(kind, detail).repr();
    code = NULL;
  }
  *c = saved;
  *c.names = names;
  transaction.rollback();
  return code;
}

/* A helper owns replacement bodies separately from the linked runtime.
   Included definitions take their provider's spelling; this file's public
   definitions take its own. An import merges its package's definitions into
   this file's collection, so the package's provider names them afterward.
   Evaluator names remain source spellings. */
static void _name_provider_bindings(
  Compiler c, String provider, Array units, Map dependencies) {
  int index = c.meta_build - 1;
  c.name_meta_provider_bindings(provider, index);
  foreach ((String path, int table) in meta_build_tables)
    if (meta_build_providers && path != provider)
      c.name_loaded_provider(path, table, meta_build_providers[path]);
    else if (path != provider && path in dependencies)
      c.name_meta_provider_bindings(path, table);
  Var identity, String name;
  foreach (List item in units)
    if (_function_identity(item, identity, name) &&
        (c.public_native_function(item, name) ||
         (c.load_source && name == "main"))) {
      List binding = item.caddr().cadr();
      c.set_fact(
        %(emitted $binding), %"_x2c_gensym_meta_group_$(index)_$name");
    }
}

/** Formats a meta diagnostic as `FILE:LINE:COLUMN: CODE: MESSAGE`,
    followed by its notes on the same line.
*/
String Compiler.meta_diagnostic_line(List entry) {
  String line = entry.repr();
  if (entry ~= %((code ?code) * (message ?(String message))
        (location ((file ?file) (line ?row) (column ?column) *))
        (notes ?(List notes)))) {
    line = %"$file:$row:$column: $code: $message";
    foreach (Var note in notes)
      if (note is <string>) line = %"$line; $note";
  }
  return line;
}

/* Gives the emission its own copies of the state it adds to, taken from
   the unit's `saved` compiler and `names`, and fresh state where it starts
   from nothing, so restoring those undoes the emission. */
static void _isolate(
  Compiler c, struct Compiler &saved, struct GenNames &names, String stem) {
  alias c {
    _.names.adapters = names.adapters.copy();
    _.names.file_scope_owners = names.file_scope_owners.copy();
    _.id_keys = saved.id_keys.copy();
    _.key_ids = saved.key_ids.copy();
    _.pending.reset();
    _.origins = saved.origins.copy();
    _.init_tokens = {};
    _.static_init_deps = {};
    _.fn_defs = saved.fn_defs.copy();
    _.protocol_helpers = saved.protocol_helpers.copy();
    _.meta_regions = saved.meta_regions.copy();
    _.deps = {};
    _.needs_exception = 0;
    _.macro_stack = NULL;
    _.macro_holes = NULL;
    _.meta_body = 0;
    _.permanent_literals = !c.meta_build;
    _.return_type = NULL;
    _.lambda_scopes = NULL;
    _.source_facts = 0;
    _.recovery_depth = saved.recovery_depth + 1;
    _.filename = %"$stem.x";
    _.diagnostics = Diagnostics.new(NULL, 1);
  }
}

/* The group's units as the backend takes them: every template call becomes
   a call of `x2c_template_call`, which is declared after the leading
   directives; a meta build's native calls go through their modules; and
   the entry follows. */
static List _lower(Compiler c, Array units, String stamp, String suffix) {
  List binding = c.sym.introduce("x2c_template_call");
  Type type = $!Type{ List (Var, List) };
  List callee = %(expr $type (ident $binding));
  for (int i = 0; i < (int) units.len(); i++)
    units[i] = _template_calls(c, units[i], callee);
  if (c.meta_build) _native_lookups(c, units);
  int after = _after_directives(units);
  units.insert(
    after, c.rebuild_statement($!{ List $binding(Var, List); }).cadr());
  if (c.meta_build) {
    List start = c.sym.introduce("x2c_meta_helper_start");
    units.insert(
      after, c.rebuild_statement($!{ void $start(String); }).cadr());
    _native_entries(c, units, start);
  }
  Map initials = _initial_copies(c, units);
  foreach (
    List unit in
    _entry(c, stamp, initials, _public_functions(c, units), suffix))
    units.push(unit);
  return units.list_free();
}

/* A meta build calls a native module's function through the address
   `x2c_meta_native_symbol` finds in the module. */
static void _native_lookups(Compiler c, Array units) {
  Type lookup_type = $!Type{ void *(String, String) };
  List lookup_binding = c.sym.introduce("x2c_meta_native_symbol");
  List lookup = %(expr $lookup_type (ident $lookup_binding));
  units.push(
    c.rebuild_statement($!{ void *$lookup_binding(String, String); }).cadr());
  for (int i = 0; i < (int) units.len(); i++)
    units[i] = _native_targets(c, units[i], lookup);
}

static int _after_directives(Array units) {
  int after = 0;
  while (after < (int) units.len() &&
         Ast.without_origin(units[after]).car() == <preproc>)
    after++;
  return after;
}

// rewriting calls

/* `node` with each template call replaced by a call of `x2c_template_call`,
   named by `callee`, on its template and its arguments as Vars. */
static List _template_calls(Compiler c, List node, List callee) {
  if (node ~= %(expr ?type (tpl-call ?stored (args *arguments)))) {
    List values = %(nil);
    foreach (List argument in arguments.reverse())
      values = %(expr ("List") (cons $(c.convert_expression(
        _template_calls(c, argument, callee), %("Var"))) $values));
    List template = stored is <list>
      ? c.convert_expression(c.cache_literal_list(stored), %("Var"))
      : %(expr ("Var") $(c.cache_literal_var(stored.str())));
    return %(expr $type (call $callee (args $template $values)));
  }
  List child;
  $ast.rewrite_children(node, child, _template_calls(c, child, callee));
}

/* `node` with each use of a native module's function made through the
   address `lookup` finds in that module. A native module's C target lives
   in the module, not in the helper. */
static List _native_targets(Compiler c, List node, List lookup) {
  match (node) {
    case %(expr ?(Type result) $($called(
        %(!set ?callee
          (expr ? (ident (binding ? ?name)))),
        %(*arguments)))): {
      if (name is not <string>) break;
      String spelling = name;
      List call = _native_call(c, callee, spelling, arguments, lookup);
      if (call) return c.convert_expression(call, result);
    }
    case %(expr ?(Type type) (ident (binding ? ?name))): {
      if (name is not <string>) break;
      String spelling = name;
      List symbol = _native_symbol(c, type, spelling, lookup);
      if (symbol) return symbol;
    }
  }
  List child;
  $ast.rewrite_children(node, child, _native_targets(c, child, lookup));
}

/* A call of the native function `callee`, or NULL when no native module
   supplies it. A Func argument the module takes as a Var is passed boxed.
*/
static List _native_call(
  Compiler c, List callee, String name, List arguments, List lookup) {
  Type native = NULL;
  if (!(name in c.native_meta) || !c.native_meta_module(name, native))
    return NULL;
  Array values = [];
  /* Compiler and native Func signatures retain List function headers. */
  List declared_header = c.func_signature(callee.cadr()).car();
  List native_header = native.car();
  List declared = declared_header.cadr();
  List parameters = native_header.cadr();
  foreach (List argument in arguments) {
    argument = _native_targets(c, argument, lookup);
    if (_boxes_func(c, declared.car(), parameters.car()))
      argument = c.convert_expression(
        c.convert_expression(argument, %("Func")), %("Var"));
    values.push(argument);
    declared = declared.cdr();
    parameters = parameters.cdr();
  }
  List target = _native_targets(c, callee, lookup);
  return c.resolve_expression(
    %(expr () (call $target (args @(values.list_free())))), NULL);
}

/* Whether the compiler declares a parameter `Func` that the native module
   declares `Var`. */
static int _boxes_func(Compiler c, List declared, List parameter) =>
  c.sym.normalize_declared_type(declared) ==
    c.sym.normalize_declared_type(%("Func")) &&
  c.sym.normalize_declared_type(parameter) ==
    c.sym.normalize_declared_type(%("Var"));

/* The native function `name` of `type` read through its module's address,
   or NULL when no native module supplies it. The read keeps the function
   type of the module that supplied the compiler's binding. */
static List _native_symbol(Compiler c, Type type, String name, List lookup) {
  if (!type.is_function() || !(name in c.native_meta)) return NULL;
  String module = c.native_meta_module(name, type);
  if (!module) return NULL;
  c.add_translation_dependency(module);
  Type pointer = type.reference();
  List target = %(expr (* void) (call $lookup
    (args $($!String{ $module })
          $($!String{ $name }))));
  return %(expr $pointer (cast $pointer $target));
}

// the group's entry

/* A project group's mutable meta values initialize only in its reset.
   An anonymous aggregate needs a same-declaration copy because C cannot
   spell its type in the later assignment. Ordinary native modules keep
   their existing initializers and braced copies. */
static Map _initial_copies(Compiler c, Array units) {
  Map copies = {};
  foreach (List entry in c.meta_group)
    match (entry)
      case %(static (!set ?declaration (declare ?spec
                      (bindings (op = (!set ?bound (bind ?binding ?mods))
                                     ?initializer))))): {
        Type type =
          %(declare $spec (bindings $bound)).type_from_ast().declared();
        if (<const> in type) continue;
        if (type.is_array()) {
          List zero = _braced(initializer)
            ? c.zero_initializer(initializer) : initializer;
          if (c.meta_build)
            for (int i = 0; i < (int) units.len(); i++)
              if (units[i] == declaration)
                units[i] = %(declare $spec (bindings
                  (op = $bound $zero)));
          continue;
        }
        int copied = _braced(initializer) &&
                     (!c.meta_build || type.tag().car() is <list>);
        if (!c.meta_build && !copied) continue;
        /* Static meta entries retain their declaration's binding List. */
        List identity = binding;
        List copy = copied
          ? c.sym.introduce(
            %"_x2c_gensym_meta_initial_$(identity.last())") : NULL;
        for (int i = 0; i < (int) units.len(); i++)
          if (units[i] == declaration) {
            List original = c.meta_build ? bound : %(op = $bound $initializer);
            List bindings = copied
              ? %($original (op = (bind $copy $mods) $initializer))
              : $(original);
            units[i] = %(declare $spec (bindings @bindings));
          }
        if (copied) copies[binding] = %(expr $type (ident $copy));
      }
  return copies;
}

/* The group's entry in the shape `x2c build --kind meta-module` writes:
   the stamp, `x2c_module_reset`, which reinitializes each mutable `meta
   static` value, and `x2c_module_targets`, a Map from the name of each
   group function and of the reset entry to a `Func` that calls it. The
   exported names end in `suffix`, so several groups link into one
   program. */
static List _entry(
  Compiler c, String stamp, Map initials, List functions, String suffix) {
  List resets = _resets(c, initials);
  List reset = c.initializer_function(
    %(void), c.sym.introduce(%"x2c_module_reset$suffix"), resets);
  List table = _targets(c, _named(c, reset), functions);
  List stamp_binding = c.sym.introduce(%"x2c_module_stamp$suffix");
  String literal = %"\"$stamp\"";
  return %(
    (declare (const char)
      (bindings (op = (bind $stamp_binding ((dim)))
                     (expr (* char) (literal (* char) $literal)))))
    $reset
    $(c.initializer_function(
      %("Map"), c.sym.introduce(%"x2c_module_targets$suffix"),
      %((return ("Map") $table)))));
}

/* Public native calls enter their own provider before the body runs. The
   protocol does the same for direct evaluator calls, including private
   functions. Unused provider objects do not start their tables. */
static void _native_entries(Compiler c, Array units, List start) {
  Var identity, String name;
  for (int i = 0; i < (int) units.len(); i++) {
    List item = units[i];
    if (!_function_identity(item, identity, name) ||
        !c.public_native_function(item, name)) continue;
    if (item ~= %(function ?type ?declarator (block *body))) {
      List argument = $!String{ $name };
      List enter = c.rebuild_statement($!{ $start($argument); }).cadr();
      units[i] = %(function $type $declarator (block $enter @body));
    }
  }
}

/* Native provider ownership includes functions whose signatures cannot
   cross the evaluator boundary. Their names stay separate from Funcs. */
static List _public_functions(Compiler c, Array units) {
  Array functions = [];
  Var identity, String name;
  foreach (List item in units)
    if (_function_identity(item, identity, name) &&
        c.public_native_function(item, name))
      functions.push(name);
  return functions.list_free();
}

/* An assignment of each mutable `meta static` value's initializer, or of
   the unchanging copy `initials` holds for a braced one. */
static List _resets(Compiler c, Map initials) {
  Array resets = [];
  foreach (List entry in c.meta_group)
    match (entry)
      case %(static (declare ?spec
                      (bindings (op = (!set ?bound (bind ?binding *))
                                     ?initializer)))): {
        Type type =
          %(declare $spec (bindings $bound)).type_from_ast().declared();
        if (<const> in type) continue;
        Var initial;
        if (initials.try_get(binding, initial)) initializer = initial;
        List target = %(expr $type (ident $binding));
        if (type.is_array()) {
          if (!_braced(initializer))
            initializer = %(expr () (composite (commas $initializer)));
          Type native = %("__typeof__" (parens $target));
          initializer = %(expr $type (cast $native
            $(c.convert_initializer(initializer, type, target))));
          resets.push(
            c.rebuild_statement(
              $!{ memcpy($target, $initializer, sizeof($target)); }).cadr());
        }
        else resets.push(
          c.rebuild_statement($!{ $target = $initializer; }).cadr());
      }
  return resets.list_free();
}

static int _braced(Var node) {
  if (node is not <list>) return 0;
  if (((List) node).car() == <composite>) return 1;
  foreach (Var part in (List) node) if (_braced(part)) return 1;
  return 0;
}

/* The reset entry and each group function as `(name binding type)`. */
static List _named(Compiler c, List reset) {
  List named = %(("x2c_module_reset" $(reset.caddr().cadr())
                  ((func ((void))) void)));
  foreach (List entry in c.meta_group)
    if (entry ~= %(function ?fn ?(String name) ?(Type type) *))
      named = named.append(%(($name $(fn.caddr().cadr()) $type)));
  return named;
}

/* The target table uses ordinary Func adapters, including native object
   parameters. Signatures without an adapter stay native-only. */
static List _targets(Compiler c, List named, List functions) {
  Array entries = [];
  if (c.meta_build)
    entries.push(
      %(map-entry $($!Symbol{ $(<functions>) })
        $(c.cache_literal_list(functions))));
  foreach (List row in named) {
    (String name, List binding, Type type) = row;
    if (c.load_source) type = c.loaded_call_type(type);
    List function = NULL;
    try function = c.convert_expression(
      %(expr $type (ident $binding)), %("Func"));
    catch %(malformed *): continue;
    entries.push(%(map-entry $($!String{ $name }) $function));
  }
  Macro shape = $map_value;
  return c.rebuild_expression(%("Map"), shape(entries.list_free()));
}
