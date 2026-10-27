/*  initialization.x -- initializer choices and static storage */

static typedef struct StaticRuntime {
  Emitter *e;
  Array output;
  Type declared_base, type;
  List name, initial, prefix, initial_copy, source;
  String storage, alias, pointer, guard, cleanup, temporary;
  String slot, object, formal;
  int inferred;
} StaticRuntime;

// initializer macros

static macro Expression $emit.initializer.expanded(
  Expr $name, Expr $formal, Expr $replacement) =>
  %"#define $($name)($($formal)) $($replacement)";

static macro Expression $emit.initializer.forwarding(
  Expr $name, Expr $formal, Expr $expanded) =>
  %"#define $($name)($($formal)) $($expanded)($($formal))";

// static objects

static macro Expression $emit.object.inferred_alias(
  Expr $formal, Expr $alias) =>
  %("typedef __typeof__(" $($formal) ")" $($alias) ";");

static macro Expression $emit.object.fixed_alias(
  Expr $declaration, Expr $alias) =>
  %(
    "typedef" @($declaration) ";"
    "_Static_assert(__builtin_constant_p(sizeof(" $($alias) ")),"
      "\"static object size must be constant\");"
  );

static macro Expression $emit.object.acquire(
  Expr $r, Expr $threaded, Expr $copy) =>
  %(
    @($r.prefix)
    $($r.storage) "X2CStatic" $($r.guard) "= {0};"
    $($r.alias) "*" $($r.pointer) ";"
    "if (x2c_static_acquire(&" $($r.guard) ", sizeof(" $($r.alias) "),"
        "_Alignof(" $($r.alias) "),"
        $($threaded) ")) {"
      $($r.slot) "=" $($r.guard) ".payload;"
      "X2CCleanup" $($r.cleanup) "= { .fn = x2c_static_abort,"
                               ".env = &" $($r.guard) "};"
      "x2c_cleanup_push(&" $($r.cleanup) ");"
      @($r.initial_copy)
      @($copy)
      "x2c_static_commit(&" $($r.guard) ");"
      "x2c_cleanup_leave(&" $($r.cleanup) ");"
    "}"
    "(void)(" $($r.pointer) "=" $($r.guard) ".payload);"
  );

static macro Expression $emit.object.copy(
  Expr $alias, Expr $guard, Expr $source, Expr $object,
  Expr $data, Expr $index) =>
  %(
    "if (_Generic((" $($alias) "*)0, volatile" $($alias) "*: 1, default: 0)) {"
      "const volatile unsigned char *" $($data) "="
        "(const volatile unsigned char *)" @($source) ";"
      "for (size_t" $($index) "= 0;" $($index) "< sizeof(" $($object) ");"
           $($index) "++)"
        "((unsigned char *)" $($guard) ".payload)[" $($index) "] ="
          $($data) "[" $($index) "];"
    "} else memcpy(" $($guard) ".payload, (const void *)" @($source) ","
                   "sizeof(" $($object) "));"
  );

// diagnostics

static macro Stmt $fail.emit_static_switch(Expr $c, Expr $site) {
  {
    String note = "place the declaration before the switch "
      "or within one case block";
    $c.report_error(
      <emit>, "switch cannot bypass dynamic static initialization",
      $site, $(note));
  }
}

/* initializer choices

   A native macro selects an initializer's conversion when C sees the
   argument types, and `__builtin_choose_expr` selects among a value's
   typed alternatives. */

module List _initializer_value(Emitter &e, List ast) {
  List source = NULL;
  List functions = Ast.initializer_functions(ast, source);
  if (functions)
    return _tokens(e, %(call (expr () (initval @functions)) (args $source)));
  List input = NULL;
  List cases = Ast.initializer_cases(ast, input);
  if (input)
    return _initializer_macro(e, input, %(initval @cases));
  List result = NULL;
  foreach (List choice in cases.reverse()) {
    (List condition, List path, Type type, List value) = choice;
    if (value ~= %(expr ? (composite *)))
      value = type ? %(expr $type (cast $type $value))
                   : %(expr (int) (literal (int) "0"));
    List emitted = _tokens(e, value);
    if (!result || !condition) result = emitted;
    else {
      List test = _tokens(e, condition);
      result = %("__builtin_choose_expr(" @test ","
                  @emitted "," @result ")");
    }
  }
  return result;
}

module List _index_init(Emitter &e, Var index, List value) {
  String assign = value.car() == <dotinit> ||
                  value.car() == <indexinit> ? "" : " =";
  return %("[" @(_tokens(e, index)) "]" $assign @(_tokens(e, value)));
}

module List _dot_init(Emitter &e, Var field, List value) {
  String assign = value.car() == <dotinit> ||
                  value.car() == <indexinit> ? "" : "=";
  return %("." @(_tokens(e, field)) $assign @(_tokens(e, value)));
}

// local statics

module List _local_static(
  Emitter &e, List declaration, List body) {
  while (declaration.car() == <at>) {
    e.origin = declaration.cadr();
    declaration = declaration.caddr();
  }
  if (_static_case_entry(body)) {
    e.c.origin = e.origin;
    $fail.emit_static_switch(e, NULL);
  }
  List (base, bindings) = declaration.cdr();
  Type declared_base = base;
  String base_name = e.fresh_name("static_type");
  List base_decl = _semantic_name(e, declared_base.declared(), base_name);
  Array output = [];
  output.push(%("typedef" @base_decl ";"));
  String storage = declared_base.is_threaded() ? "static _Thread_local"
                                              : "static";
  foreach (List binding in bindings.cdr())
    _static_binding(e, binding, declared_base, base_name, storage, output);
  /* The region shares its source block, including a statement expression's
     final value; another C block here would turn that value into void. */
  output.push(_tokens(e, body));
  return output.list_free();
}

static int _static_case_entry(List node) {
  match (node) {
    case %((!or switch function expr declare typedef) *): return 0;
    case %((!or case default) *): return 1;
  }
  foreach (Var child in node)
    if (child is <list> && _static_case_entry(child)) return 1;
  return 0;
}

static void _static_binding(
  Emitter &e, List binding, Type declared_base,
  String base_name, String storage, Array output) {
  List name, mods, initial = NULL;
  match (binding) {
    case %(op = (bind ?captured ?modifiers) ?value): {
      name = captured; mods = modifiers; initial = value;
    }
    case %(bind ?captured ?modifiers): {
      name = captured; mods = modifiers;
    }
  }
  Type type = mods.append($(base_name));
  String spelling = e.emitted_binding_name(name);
  List record = NULL;
  match (initial) case %(staticinit ?cleanup ?value): {
    record = cleanup;
    initial = value;
  }
  if (!initial ||
      !e.c.static_value_is_runtime(initial, e.static_objects)) {
    List native = _semantic_name(e, type, spelling);
    List value = initial ? %("=" @(_tokens(e, initial))) : NULL;
    output.push(%($storage @native @value ";"));
    return;
  }
  e.static_support = 1;
  StaticRuntime runtime = {
    .e = &e, .output = output, .declared_base = declared_base,
    .type = type, .name = name, .initial = initial, .storage = storage,
    .inferred = type.car() == <dim> || (type ~= %((dim) *))};
  runtime.alias = e.fresh_name("static_object_type");
  runtime.pointer = e.fresh_name("static_object");
  runtime.guard = e.fresh_name("static_guard");
  runtime.cleanup = e.emitted_binding_name(record);
  runtime.temporary = e.fresh_name("static_initial");
  _prepare(runtime);
  _static(runtime);
}

static void _prepare(StaticRuntime &r) {
  r.slot = r.pointer;
  r.object = r.temporary;
  if (r.inferred) {
    r.slot = (*r.e).fresh_name("static_incomplete");
    r.formal = (*r.e).fresh_name("static_input");
    List probe_decl = _semantic_name((*r.e), r.type.reference(), r.slot);
    r.output.push(%(@probe_decl ";"));
    r.e.static_objects[r.name] = r.slot;
    r.prefix = $emit.object.inferred_alias(r.formal, r.alias);
    r.source = $("&", r.formal);
    r.object = r.alias;
    return;
  }
  List alias_decl = _semantic_name((*r.e), r.type, r.alias);
  r.e.static_objects[r.name] = r.pointer;
  List value = _tokens((*r.e), r.initial);
  r.prefix = $emit.object.fixed_alias(alias_decl, r.alias);
  r.initial_copy = %($(r.alias) $(r.temporary) "=" @value ";");
  r.source = $("&", r.temporary);
}

static void _static(StaticRuntime &r) {
  String threaded_flag = r.declared_base.is_threaded() ? "1" : "0";
  List copy = _static_copy((*r.e), r.alias, r.guard, r.source, r.object);
  List acquisition = $emit.object.acquire(r, threaded_flag, copy);
  if (r.inferred) {
    List operand = %(expr $(r.type) (cast $(r.type) $(r.initial)));
    acquisition = _initializer_macro(
      (*r.e), %(input ($(r.formal) $operand)), acquisition);
  }
  r.output.push(acquisition);
  r.e.static_objects[r.name] = r.pointer;
}

/* The native alias retains typedef and array qualifiers. Only a volatile
   object needs bytewise volatile reads; storage has no declared type yet. */
static List _static_copy(
  Emitter &e, String alias, String guard, List source, String object) {
  String data = e.fresh_name("static_bytes");
  String index = e.fresh_name("static_byte");
  return $emit.object.copy(alias, guard, source, object, data, index);
}

// source initializers

module List _source_initializer(Emitter &e, List function) {
  List (type, binding, body) = function.cdr();
  Array inputs = [], declarations = [];
  body = _capture_source(e, body, inputs, declarations);
  List emitted = %(@(declarations.list_free())
    (function $type $binding $body));
  return _initializer_macro(e, %(input @(inputs.list_free())), emitted);
}



/* Native macro arguments expand once before C sees the selected conversion.
   Generated bodies have no source-map directives; the original argument keeps
   its ordinary mapping at the invocation and its original storage scope. */
module List _initializer_macro(Emitter &e, List input, List body) {
  Buffer parameters = Buffer.new(0);
  foreach (List argument in input.cdr()) {
    if (parameters.len()) parameters.write_char(',');
    parameters.write(argument.car().str());
  }
  String formal = parameters.str_free();
  String hash = Path.identifier_hash(e.c.filename);
  String name = e.c.fresh_name(%"initializer_choice_$hash");
  String replacement;
  with (e.c.source_map = 0) {
    Array tokens = _captured(e, body);
    String formatted = e.c.code_pretty_string(tokens, NULL);
    replacement = formatted.rstrip("\n").replace("\n", "\\\n");
  }
  String expanded = %"$(name)_expanded";
  String definition =
    $emit.initializer.expanded(expanded, formal, replacement);
  e.native_macros.push($(expanded, definition));
  String forwarding = $emit.initializer.forwarding(name, formal, expanded);
  e.native_macros.push($(name, forwarding));
  Array arguments = [];
  foreach (List argument in input.cdr()) {
    List emitted = _tokens(e, argument.cadr());
    arguments.push(%("(" @emitted ")"));
  }
  return %($name "(" @(_commas(arguments.list_free())) ")");
}

static List _capture_source(
  Emitter &e, List node, Array inputs, Array declarations) {
  match (node) {
    case %((!or ?kind initval initcode)
           (!set ?input (input *)) *body): {
      List captured = _capture_source(e, input, inputs, declarations);
      return $(kind, captured, @body);
    }
    case %(expr ?type (!set ?content (composite *))): {
      List captured = _capture_source(e, content, inputs, declarations);
      return %(expr $type $captured);
    }
    case %(expr ?type ?content): {
      int opaque = (content ~= %(call (expr ?callable ?) ?)) && !callable;
      if (opaque || !_source_type_definition(content)) {
        String formal = e.fresh_name("static_input");
        inputs.push($(formal, node));
        return %(expr $type $formal);
      }
      List captured = _capture_source(e, content, inputs, declarations);
      return %(expr $type $captured);
    }
    case %(!or ((!or struct union) ? (fields *))
               ((!or struct union) (fields *))
               (enum ? (!is type list))):
      return _capture_definition(e, node, inputs, declarations);
    case %(call ?callee ?arguments): {
      List captured = _capture_source(e, arguments, inputs, declarations);
      return %(call $callee $captured);
    }
  }
  return _capture_children(e, node, inputs, declarations);
}

static List _capture_definition(
  Emitter &e, List node, Array inputs, Array declarations) {
  (Type definition, Type reference) = e.initializer_native_types(node);
  match (node) {
    case %(enum (gensym ? ?) ?body): {
      String name = e.fresh_name("static_enum");
      definition = %(enum $name $body);
      reference = %(enum $name);
    }
    case %(enum ?tag ?): reference = %(enum $tag);
  }
  definition = _capture_children(e, definition, inputs, declarations);
  declarations.push(%(declare $definition (bindings (bind () ()))));
  return reference;
}

/* Expand source operands before moving native tag declarations ahead of the
   helper. An opaque call stays one operand, including its native quoting or
   token-pasting rules; x2c does not interpret declarations hidden inside
   it. */
static List _capture_children(
  Emitter &e, List node, Array inputs, Array declarations) {
  Array children = [];
  foreach (Var child in node) {
    if (child is <list>)
      children.push(_capture_source(e, child, inputs, declarations));
    else children.push(child);
  }
  return children.list_free();
}

/* A hand worklist rather than `$ast.walk`: an `expr` contributes only its
   content, since an anonymous aggregate type in its type slot is not a
   source definition, and the walk macro cannot skip one child. */
static int _source_type_definition(List value) {
  Array pending = auto [];
  pending.push(value);
  while (pending.len()) {
    List node = pending.take_last();
    match (node) {
      case %(expr ? ?content): {
        pending.push(content);
        continue;
      }
      case %((!or struct union) ? (fields *)): return 1;
      case %((!or struct union) (fields *)): return 1;
      case %(enum ? (!is type list)): return 1;
    }
    foreach (Var child in node)
      if (child is <list>) pending.push(child);
  }
  return 0;
}
