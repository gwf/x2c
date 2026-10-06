/*  emit.x -- C tokens from normalized x2c ASTs

    This module owns emission: it turns a bound, typed, transform-normalized
    AST into the token `List`s that formatting prints as C. One stack-local
    Emitter holds the current function's name, static objects, and native
    aliases, so emission is reentrant and a failed translation cannot
    contaminate later units. `transform.x` has already placed each cleanup
    region's statements on the exits that leave it.
*/

#pragma once
#include "compiler.x"
#include <stdlib.h>
#include <stdio.h>
#include "string.x"
#include "var.x"
#include "ast.x"
#include "format.x"
#include "cleanup.x"

/*  emit.x -- generated C scaffolding */

// initializer macros

static macro Expression $emit.initializer.expanded(
  Expr $name, Expr $formal, Expr $replacement) =>
  %"#define ${$name}(${$formal}) ${$replacement}";

static macro Expression $emit.initializer.forwarding(
  Expr $name, Expr $formal, Expr $expanded) =>
  %"#define ${$name}(${$formal}) ${$expanded}(${$formal})";

// native aliases

static macro Expression $emit.alias.definition(Expr $target, Expr $native) =>
  %"#define ${$target} ${$native}";

static macro Expression $emit.alias.checked(
  Expr $native, Expr $pointer, Expr $message, Expr $definition) =>
  %(
    "#ifndef X2CCPP"
    "_Static_assert("
    "_Generic(&" @{$native} ", " @{$pointer} ": 1, default: 0), "
    "\"${$message}\");"
    "#endif"
    ${$definition}
  );

// static objects

static macro Expression $emit.object.inferred_alias(Expr $formal, Expr $alias) =>
  %("typedef __typeof__(" ${$formal} ")" ${$alias} ";");

static macro Expression $emit.object.fixed_alias(Expr $declaration, Expr $alias) =>
  %(
    "typedef" @{$declaration} ";"
    "_Static_assert(__builtin_constant_p(sizeof(" ${$alias} ")),"
      "\"static object size must be constant\");"
  );

static macro Expression $emit.object.acquire(Expr $r, Expr $threaded, Expr $copy) =>
  %(
    @{$r.prefix}
    ${$r.storage} "X2CStatic" ${$r.guard} "= {0};"
    ${$r.alias} "*" ${$r.pointer} ";"
    "if (x2c_static_acquire(&" ${$r.guard} ", sizeof(" ${$r.alias} "),"
        "_Alignof(" ${$r.alias} "),"
        ${$threaded} ")) {"
      ${$r.slot} "=" ${$r.guard} ".payload;"
      "X2CCleanup" ${$r.cleanup} "= { .fn = x2c_static_abort,"
                               ".env = &" ${$r.guard} "};"
      "x2c_cleanup_push(&" ${$r.cleanup} ");"
      @{$r.initial_copy}
      @{$copy}
      "x2c_static_commit(&" ${$r.guard} ");"
      "x2c_cleanup_leave(&" ${$r.cleanup} ");"
    "}"
    "(void)(" ${$r.pointer} "=" ${$r.guard} ".payload);"
  );

static macro Expression $emit.object.copy(
  Expr $alias, Expr $guard, Expr $source, Expr $object,
  Expr $data, Expr $index) =>
  %(
    "if (_Generic((" ${$alias} "*)0, volatile" ${$alias} "*: 1, default: 0)) {"
      "const volatile unsigned char *" ${$data} "="
        "(const volatile unsigned char *)" @{$source} ";"
      "for (size_t" ${$index} "= 0;" ${$index} "< sizeof(" ${$object} ");"
           ${$index} "++)"
        "((unsigned char *)" ${$guard} ".payload)[" ${$index} "] ="
          ${$data} "[" ${$index} "];"
    "} else memcpy(" ${$guard} ".payload, (const void *)" @{$source} ","
                   "sizeof(" ${$object} "));"
  );

// match statements

static macro Expression $emit.match.values(Expr $count) =>
  %"Var _x2c_match_values[${$count}];";

static macro Expression $emit.match.buffer(Expr $count) =>
  "MatchCaptureBuffer _x2c_match_capture = { "
      + %".values = _x2c_match_values, .capacity = ${$count} };";

static macro Expression $emit.match.empty_buffer() =>
  %("MatchCaptureBuffer _x2c_match_capture = { 0 };");

static macro Expression $emit.match.dispatch(
  Expr $subject, Expr $captures, Expr $selector, Expr $arms) =>
  %("
  {
    List _x2c_match_expr = " ${$subject} ";
    " @{$captures} "
    switch (" @{$selector} ") {
      " @{$arms} "
    }
  }
");

static macro Expression $emit.match.macro_arm(
  Expr $site, Expr $condition, Expr $declarations, Expr $body,
  Expr $implicit_break) =>
  %("static MacroCaseSite" ${$site} ";"
    "if (" @{$condition} ") {"
      @{$declarations} @{$body} @{$implicit_break} "}");

static macro Expression $emit.match.flat_arm(
  Expr $condition, Expr $declarations, Expr $body, Expr $closing) =>
  %("{ List _x2c_match_cursor;" "if (" @{$condition} ") {"
      @{$declarations} @{$body} ${$closing});

static macro Expression $emit.match.capture_arm(
  Expr $site, Expr $entry, Expr $pattern, Expr $declarations,
  Expr $body, Expr $implicit_break) =>
  %(
    @{$site}
    "if (" @{$entry}
      "_x2c_match_expr, List_var(" @{$pattern} "),"
      "&_x2c_match_capture)) {"
    @{$declarations} @{$body} @{$implicit_break} "}"
  );

static macro Expression $emit.match.head_condition(Expr $bits) =>
  "_x2c_match_expr && "
  + %"_x2c_match_expr->car.u64 == ${$bits}ULL && "
  + "(_x2c_match_cursor = _x2c_match_expr->cdr, 1)";

static macro Expression $emit.match.cursor_present() =>
  "&& _x2c_match_cursor ";

static macro Expression $emit.match.cursor_tag(Expr $tag) =>
  "&& Var_is(_x2c_match_cursor->car, " + %"${$tag}) ";

static macro Expression $emit.match.capture_value(Expr $index) =>
  %"&& (_x2c_match_values[${$index}] = _x2c_match_cursor->car, "
  + "_x2c_match_cursor = _x2c_match_cursor->cdr, 1)";

static macro Expression $emit.match.cursor_empty() =>
  "&& !_x2c_match_cursor";

static macro Expression $emit.match.value_at(Expr $values, Expr $index) =>
  %"${$values}[${$index}]";

static macro Expression $emit.match.list_binder(Expr $name, Expr $value) =>
  %"List ${$name} = Var_list(${$value});";

static macro Expression $emit.match.value_binder(Expr $name, Expr $value) =>
  %"Var ${$name} = ${$value};";

// diagnostics

static macro Stmt $report.emit.static_switch(Expr $c) {
  {
    String note = "place the declaration before the switch "
                + "or within one case block";
    $c.report_error(
      <emit>, "switch cannot bypass dynamic static initialization",
      NULL, %($note));
  }
}

// form templates

static macro Expression $emit.cons(Expr $e, Expr $item, Expr $tail) =>
  %("cons(" @{$e._emit(%(${$item}))} ", " @{$e._emit(%(${$tail}))} ")");

static macro Expression $emit.append(Expr $e, Expr $head_list, Expr $tail) =>
  %("List_append(" @{$e._emit(%(${$head_list}))} ", "
    @{$e._emit(%(${$tail}))} ")");

static macro Expression $emit.c_assert(
  Expr $e, Expr $condition, Expr $message) =>
  %("_Static_assert(" @{$e._emit(%(${$condition}))} ","
    @{$e._emit(%(${$message}))} ");");

static macro Expression $emit.initcode(Expr $e, Expr $input, Expr $body) =>
  %(@{$e._initializer_macro($input, $body)} ";");

static macro Expression $emit.cast(Expr $e, Expr $type, Expr $expression) =>
  %("(" @{$e._semantic_type($type)} ")"
    @{$e._operand($expression, EMIT_UNARY)});

static macro Expression $emit.cache(Expr $e, Expr $id) =>
  $e.cache_bindings ? $e._emit_ident($e.cache_bindings[$id])
                   : %("_${$id}");

static macro Expression $emit.vararg(
  Expr $e, Expr $expression, Expr $declaration) =>
  %("va_arg(" @{$e._emit(%(${$expression}))} ", "
    @{$e._emit(%(${$declaration}))} ")");

static macro Expression $emit.offset(Expr $e, Expr $type, Expr $member) =>
  %("offsetof(" @{$e._semantic_type($type)} ", " @{$e._emit($member)}
    ")");

static macro Expression $emit.index(Expr $e, Expr $array, Expr $index) =>
  %(@{$e._operand($array, EMIT_POSTFIX)} "[" @{$e._emit(%(${$index}))}
    "]");

/* Between `?` and `:` C accepts a complete expression, so only the
   condition and the false arm can regroup. */
static macro Expression $emit.conditional(
  Expr $e, Expr $condition, Expr $ontrue, Expr $onfalse) =>
  %(@{$e._operand($condition, EMIT_CONDITIONAL + 1)} "?"
    @{$e._emit(%(${$ontrue}))} ":"
    @{$e._operand($onfalse, EMIT_CONDITIONAL)});

static macro Expression $emit.if(Expr $e, Expr $condition, Expr $ontrue) =>
  %("if" "(" @{$e._emit(%(${$condition}))} ")" @{$e._emit(%(${$ontrue}))});

static macro Expression $emit.if_else(
  Expr $e, Expr $condition, Expr $ontrue, Expr $onfalse) =>
  %("if" "(" @{$e._emit(%(${$condition}))} ")" @{$e._emit(%(${$ontrue}))}
    "else" @{$e._emit(%(${$onfalse}))});

static macro Expression $emit.while(Expr $e, Expr $condition, Expr $body) =>
  %("while" "(" @{$e._emit(%(${$condition}))} ")"
    @{$e._emit(%(${$body}))});

static macro Expression $emit.do(Expr $e, Expr $body, Expr $condition) =>
  %("do" @{$e._emit(%(${$body}))} "while"
    "(" @{$e._emit(%(${$condition}))} ")" ";");

static macro Expression $emit.for(Expr $e, Expr $ast) => ({
  Var (initial, condition, increment, body) = $ast.cdr();
  %("for" "(" @{$e._emit(%($initial))} ";"
    @{$e._emit(%($condition))} ";" @{$e._emit(%($increment))} ")"
    @{$e._emit(%($body))});
});

static macro Expression $emit.switch(Expr $e, Expr $expression, Expr $body) =>
  %("switch" "(" @{$e._emit(%(${$expression}))} ")"
    @{$e._emit(%(${$body}))});

static macro Expression $emit.goto(Expr $e, Expr $label) =>
  %("goto" @{$e._emit(%(${$label}))} ";");

// emission

/* `native_macros` holds the `#define` rows initializer choices need, and
   `static_support` records that a runtime static was emitted, so the unit
   includes its runtime headers. */
static typedef struct Emitter {
  delegate Compiler c;
  int origin, String fn_name, List native_aliases;
  Array native_macros;
  Map static_objects, cache_bindings;
  int static_support;
} Emitter;

/** Emits a bound, typed, transform-normalized AST sequence as flat C tokens.
    Source mapping adds `src-at`/ID pairs consumed by the formatter.
    The compiler must own the AST's binding facts and origins, and continue the
    translation session's shared generated-name state. This operation does not
    bind, transform, or choose header and source placement; generation supplies
    any added scaffolding in the same normalized grammar. `cache_bindings`
    maps semantic cache ids to generated slots; NULL keeps raw ids for
    inspection. It preserves the top-level AST sequence and advances
    generated-name counters as it allocates temporaries. Returned canonical
    `List`s and `String`s are owned by pools
    active during emission; promote them before releasing those pools if the
    tokens must survive.
*/
List Compiler.emit(Compiler c, List ast, Map cache_bindings) {
  Emitter e = {
    .c = c, .origin = 0, .native_macros = [],
    .cache_bindings = cache_bindings};
  // flatten_all leaves no list element behind, so one pass is the fixed
  // point and a second call would only re-cons the whole unit to prove it.
  List code = e._emit(ast).flatten_all();
  Array before = [], after = [];
  if (e.static_support)
    before.push("#include \"exception.h\"\n#include <string.h>");
  foreach (List entry, e.native_macros.list_free()) {
    (String name, String definition) = entry;
    before.push(definition);
    after.push(%"#undef $name");
  }
  return before.list_free().append(code).append(after.list_free());
}

/* Emission visits sibling nodes from left to right because generated names
   and origins change during the walk. Generic sequences walk their items in
   order; a specialized form builds its tokens in one literal, whose parts
   x2c evaluates left to right. This orders tokens, not C operand
   evaluation; only producer-marked forms such as statement-expression
   blocks introduce runtime sequencing. Parser, transform, and generation
   produce every recognized AST shape, so the fallback handles only already
   C-shaped nodes. */
static List Emitter._emit(Emitter &e, List ast) {
  if (!ast) return ast;
  Var head = ast.car();
  if (head is <list>) return e._emit_sequence(ast);
  if (head is not <symbol>) return %( $head @{e._emit(ast.cdr())} );
  if (head != <typedef> &&
      (head.symbol().is_storage_class() ||
       head.symbol().is_type_qualifier() ||
       head.symbol().is_inline())) {
    return e._emit_prefix(ast);
  }
  match (ast) {
    case %(at ?origin ?inner): return e._emit_at(origin, inner);
    case %(cons ?item ?tail): return $emit.cons(e, item, tail);
    case %(append ?head ?tail): return $emit.append(e, head, tail);
    case %(c-assert ?test ?message): return $emit.c_assert(e, test, message);
    case %(initcode ?input ?body): return $emit.initcode(e, input, body);
    case %(localinit ?decl (block *body)): return e._local_static(decl, body);
    case %(sourceinit ?fn): return e._source_initializer(fn);
    case %(initval *): return e._initializer_value(ast);
    case %(indexinit ?index ?value): return e._emit_index_init(index, value);
    case %(dotinit ?field ?value): return e._emit_dot_init(field, value);
    case %(cast ?type ?expr): return $emit.cast(e, type, expr);
    case %(cache ?id): return $emit.cache(e, id);
    case %(expr ? ?content): return e._emit(%($content));
    case %(postfix ?op ?argument): return e._emit_postfix(op, argument);
    case %(generic ?control *rows): return e._emit_generic(control, rows);
    case %(va-arg ?expr ?decl): return $emit.vararg(e, expr, decl);
    case %(offsetof ?type ?member): return $emit.offset(e, type, member);
    case %(call ?fn ?args): return e._emit_call(fn, args);
    case %(index ?array ?index): return $emit.index(e, array, index);
    case %(op ?op ?argument): return e._emit_unary(op, argument);
    case %(op ?op ?left ?right): return e._emit_binary(op, left, right);
    case %(op ? ?test ?yes ?no): return $emit.conditional(e, test, yes, no);
    case %(break): return %("break;");
    case %(continue): return %("continue;");
    case %(if ?test ?yes): return $emit.if(e, test, yes);
    case %(if ?test ?yes ?no): return $emit.if_else(e, test, yes, no);
    case %(while ?test ?body): return $emit.while(e, test, body);
    case %(do ?body ?test): return $emit.do(e, body, test);
    case %(for ? ? ? ?): return $emit.for(e, ast);
    case %(switch ?expr ?body): return $emit.switch(e, expr, body);
    case %(return): return %("return;");
    case %(return (!set ?expr (expr ? ?))): return e._emit_return(expr);
    case %(goto ?label): return $emit.goto(e, label);
    case %(raise ?cause (args *args)): return e._raise(ast, cause, args);
    case %((!or fnmod func) ?params): return e._emit_parameters(params);
    case %(label ?name): return e._emit_label(name);
    case %(ident ?binding): return e._emit_ident(binding);
  }
  return e._emit_leaf(ast);
}

static List Emitter._emit_sequence(Emitter &e, List ast) {
  Array emitted = $auto([]);
  while (ast && ast.car() is <list>) {
    emitted.push(e._emit(ast.car()));
    ast = ast.cdr();
  }
  List result = e._emit(ast);
  for (int i = (int) emitted.len() - 1; i >= 0; i--)
    result = cons(emitted[i], result);
  return result;
}

static List Emitter._emit_prefix(Emitter &e, List ast) {
  Array prefix = [];
  while (ast && ast.car() is <symbol>) {
    Symbol item = ast.car();
    if (item == <typedef> ||
        (!item.is_storage_class() && !item.is_type_qualifier() &&
         !item.is_inline()))
      break;
    if (item == <threaded>) prefix.push("_Thread_local");
    else prefix.push(ast.car());
    ast = ast.cdr();
  }
  return prefix.list_free().append(e._emit(ast));
}

static List Emitter._emit_leaf(Emitter &e, List ast) {
  Var head = ast.car();
  switch (head.symbol()) {
    case <adopt>: case <macrodef>: case <protocol>: return NULL;
    case <literal>:    return e._literal(ast);
    case <preproc>:    return e._preproc(ast);
    case <bind>:       return e._bind(ast);
    case <declare>:    return e._declare_stmt(ast);
    case <decl>:       return e._decl_stmt(ast);
    case <enum>:       return e._enum(ast);
    case <falias>:     return e._foreign_alias(ast);
    case <function>:   return e._function(ast);
    case <param>:      return e._param(ast);
    case <struct>:     return e._aggregate(ast);
    case <typedef>:    return e._typedef(ast);
    case <union>:      return e._aggregate(ast);
    case <args>:       return e._args(ast);
    case <bindings>: case <params>: return _commas(e._emit(ast.cdr()));
    case <fields>:     return e._emit(ast.cdr());
    case <block>:      return e._block(ast);
    case <group>:      return e._emit(ast.cdr());
    case <parens>:     return %("(" @{e._emit(ast.cdr())} ")");
    case <sizeof>: return %("sizeof" @{e._emit(ast.cdr())});
    case <case>: return %("case" ${e._emit(ast.cdr())} ":");
    case <composite>: return %("{" @{e._emit(ast.cdr())} "}");
    case <default>:    return %("default:");
    case <empty>:      return %(";");
    case <stmnt>:      return %( @{e._emit(ast.cdr())} ";");
    case <matchcases>: return e._match_cases(ast);
    case <binding>:    return e._binding(ast);
    case <commas>: return _commas(e._emit(ast.cdr()));
    case <comment>:    return ast.cdr();
    case <nil>:        return %("NULL");
    case <space>:      return ast.cdr();
  }
  return %($head @{e._emit(ast.cdr())});
}

// source positions and list forms

static List Emitter._emit_at(Emitter &e, int origin, List inner) {
  int old_origin = e.origin;
  e.origin = origin;
  List result = e._emit(inner);
  e.origin = old_origin;
  if (e.c.source_map)
    return %(src-at $origin @result src-at $old_origin);
  return result;
}

/* initializer choices

   A native macro selects an initializer's conversion when C sees the
   argument types, and `__builtin_choose_expr` selects among a value's
   typed alternatives. */

/* Native macro arguments expand once before C sees the selected conversion.
   Generated bodies have no source-map directives; the original argument keeps
   its ordinary mapping at the invocation and its original storage scope. */
static List Emitter._initializer_macro(Emitter &e, List input, List body) {
  Buffer parameters = Buffer.new(0);
  foreach (List argument, input.cdr()) {
    if (parameters.len()) parameters.write_char(',');
    parameters.write(argument.car().str());
  }
  String formal = parameters.str_free();
  String hash = filename_hash(e.c.filename);
  String name = e.c.fresh_name(%"initializer_choice_$hash");
  String replacement;
  $let(e.c.source_map, 0) {
    List tokens = e._emit(body).flatten_all();
    String formatted = e.c.code_pretty_string(tokens, NULL);
    replacement = formatted.rstrip("\n").replace("\n", "\\\n");
  }
  String expanded = %"${name}_expanded";
  String definition =
    $emit.initializer.expanded(expanded, formal, replacement);
  e.native_macros.push(%($expanded $definition));
  String forwarding = $emit.initializer.forwarding(name, formal, expanded);
  e.native_macros.push(%($name $forwarding));
  Array arguments = [];
  foreach (List argument, input.cdr()) {
    List emitted = e._emit(argument.cadr());
    arguments.push(%("(" @emitted ")"));
  }
  return %($name "(" @{_commas(arguments.list_free())} ")");
}

static List Emitter._initializer_value(Emitter &e, List ast) {
  List source = NULL;
  List functions = Ast.initializer_functions(ast, source);
  if (functions)
    return e._emit(%(call (expr () (initval @functions)) (args $source)));
  List input = NULL;
  List cases = Ast.initializer_cases(ast, input);
  if (input)
    return e._initializer_macro(input, %(initval @cases));
  List result = NULL;
  foreach (List choice, cases.reverse()) {
    (List condition, List path, Type type, List value) = choice;
    if (value.match(%(expr ? (composite *))))
      value = type ? %(expr $type (cast $type $value))
                   : %(expr (int) (literal (int) "0"));
    List emitted = e._emit(%($value));
    if (!result || !condition) result = emitted;
    else {
      List test = e._emit(%($condition));
      result = %("__builtin_choose_expr(" @test ","
                  @emitted "," @result ")");
    }
  }
  return result;
}

static List Emitter._emit_index_init(Emitter &e, Var index, List value) {
  String assign = value.car() == <dotinit> ||
                  value.car() == <indexinit> ? "" : " =";
  return %("[" @{e._emit(%($index))} "]" $assign @{e._emit(%($value))});
}

static List Emitter._emit_dot_init(Emitter &e, Var field, List value) {
  String assign = value.car() == <dotinit> ||
                  value.car() == <indexinit> ? "" : "=";
  return %("." @{e._emit(%($field))} $assign @{e._emit(%($value))});
}

// local statics

static List Emitter._local_static(
  Emitter &e, List declaration, List body) {
  while (declaration.car() == <at>) {
    e.origin = declaration.cadr();
    declaration = declaration.caddr();
  }
  if (_static_case_entry(body)) {
    e.c.origin = e.origin;
    $report.emit.static_switch(e);
  }
  List (base, bindings) = declaration.cdr();
  Type declared_base = base;
  String base_name = e.fresh_name("static_type");
  List base_decl = e._semantic_name(declared_base.declared(), base_name);
  Array output = [];
  output.push(%("typedef" @base_decl ";"));
  String storage = declared_base.is_threaded() ? "static _Thread_local"
                                              : "static";
  foreach (List binding, bindings.cdr())
    e._static_binding(binding, declared_base, base_name, storage, output);
  // The region shares its source block, including a statement expression's
  // final value; another C block here would turn that value into void.
  output.push(e._emit(body));
  return output.list_free();
}

static int _static_case_entry(List node) {
  match (node) {
    case %((!or switch function expr declare typedef) *): return 0;
    case %((!or case default) *): return 1;
  }
  foreach (Var child, node)
    if (child is <list> && _static_case_entry(child)) return 1;
  return 0;
}

static typedef struct StaticRuntime {
  Emitter *e;
  Array output;
  Type declared_base, type;
  List name, initial, prefix, initial_copy, source;
  String storage, alias, pointer, guard, cleanup, temporary;
  String slot, object, formal;
  int inferred;
} StaticRuntime;

static void Emitter._static_binding(
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
  Type type = mods.append(%($base_name));
  String spelling = e.emitted_binding_name(name);
  List record = NULL;
  match (initial) case %(staticinit ?cleanup ?value): {
    record = cleanup;
    initial = value;
  }
  if (!initial ||
      !e.c.static_value_is_runtime(initial, e.static_objects)) {
    List native = e._semantic_name(type, spelling);
    List value = initial ? %("=" @{e._emit(initial)}) : NULL;
    output.push(%($storage @native @value ";"));
    return;
  }
  e.static_support = 1;
  StaticRuntime runtime = {
    .e = &e, .output = output, .declared_base = declared_base,
    .type = type, .name = name, .initial = initial, .storage = storage,
    .inferred = type.car() == <dim> || type.match(%((dim) *))};
  runtime.alias = e.fresh_name("static_object_type");
  runtime.pointer = e.fresh_name("static_object");
  runtime.guard = e.fresh_name("static_guard");
  runtime.cleanup = e.emitted_binding_name(record);
  runtime.temporary = e.fresh_name("static_initial");
  runtime.prepare();
  runtime.emit();
}

static void StaticRuntime.prepare(StaticRuntime &r) {
  r.slot = r.pointer;
  r.object = r.temporary;
  if (r.inferred) {
    r.slot = (*r.e).fresh_name("static_incomplete");
    r.formal = (*r.e).fresh_name("static_input");
    List probe_decl = (*r.e)._semantic_name(r.type.reference(), r.slot);
    r.output.push(%(@probe_decl ";"));
    r.e.static_objects[r.name] = r.slot;
    r.prefix = $emit.object.inferred_alias(r.formal, r.alias);
    r.source = %("&" ${r.formal});
    r.object = r.alias;
    return;
  }
  List alias_decl = (*r.e)._semantic_name(r.type, r.alias);
  r.e.static_objects[r.name] = r.pointer;
  List value = (*r.e)._emit(r.initial);
  r.prefix = $emit.object.fixed_alias(alias_decl, r.alias);
  r.initial_copy = %(${r.alias} ${r.temporary} "=" @value ";");
  r.source = %("&" ${r.temporary});
}

static void StaticRuntime.emit(StaticRuntime &r) {
  String threaded_flag = r.declared_base.is_threaded() ? "1" : "0";
  List copy = (*r.e)._static_copy(r.alias, r.guard, r.source, r.object);
  List acquisition = $emit.object.acquire(r, threaded_flag, copy);
  if (r.inferred) {
    List operand = %(expr ${r.type} (cast ${r.type} ${r.initial}));
    acquisition = (*r.e)._initializer_macro(
      %(input (${r.formal} $operand)), acquisition);
  }
  r.output.push(acquisition);
  r.e.static_objects[r.name] = r.pointer;
}

/* The native alias retains typedef and array qualifiers. Only a volatile
   object needs bytewise volatile reads; storage has no declared type yet. */
static List Emitter._static_copy(
  Emitter &e, String alias, String guard, List source, String object) {
  String data = e.fresh_name("static_bytes");
  String index = e.fresh_name("static_byte");
  return $emit.object.copy(alias, guard, source, object, data, index);
}

// source initializers

static List Emitter._source_initializer(Emitter &e, List function) {
  List (type, binding, body) = function.cdr();
  Array inputs = [], declarations = [];
  body = e._capture_source(body, inputs, declarations);
  List emitted = %(@{declarations.list_free()}
    (function $type $binding $body));
  return e._initializer_macro(%(input @{inputs.list_free()}), emitted);
}

static List Emitter._capture_source(
  Emitter &e, List node, Array inputs, Array declarations) {
  match (node) {
    case %((!set ?kind (!or initval initcode))
           (!set ?input (input *)) *body): {
      List captured = e._capture_source(input, inputs, declarations);
      return %($kind $captured @body);
    }
    case %(expr ?type (!set ?content (composite *))): {
      List captured = e._capture_source(content, inputs, declarations);
      return %(expr $type $captured);
    }
    case %(expr ?type ?content): {
      int opaque = 0;
      match (content)
        case %(call (expr ?callable ?) ?): opaque = !callable;
      if (opaque || !_source_type_definition(content)) {
        String formal = e.fresh_name("static_input");
        inputs.push(%($formal $node));
        return %(expr $type $formal);
      }
      List captured = e._capture_source(content, inputs, declarations);
      return %(expr $type $captured);
    }
    case %(!or ((!or struct union) ? (fields *))
               ((!or struct union) (fields *))
               (enum ? (!is type list))):
      return e._capture_definition(node, inputs, declarations);
    case %(call ?callee ?arguments): {
      List captured = e._capture_source(arguments, inputs, declarations);
      return %(call $callee $captured);
    }
  }
  return e._capture_children(node, inputs, declarations);
}

static List Emitter._capture_definition(
  Emitter &e, List node, Array inputs, Array declarations) {
  (Type definition, Type reference) = e.initializer_native_types(node);
  if (node.car() == <enum>) {
    reference = %(enum ${node.cadr()});
    match (node)
      case %(enum (gensym ? ?) ?body): {
        String name = e.fresh_name("static_enum");
        definition = %(enum $name $body);
        reference = %(enum $name);
      }
  }
  definition = e._capture_children(definition, inputs, declarations);
  declarations.push(%(declare $definition (bindings (bind () ()))));
  return reference;
}

/* Expand source operands before moving native tag declarations ahead of the
   helper. An opaque call stays one operand, including its native quoting or
   token-pasting rules; x2c does not interpret declarations hidden inside
   it. */
static List Emitter._capture_children(
  Emitter &e, List node, Array inputs, Array declarations) {
  Array children = [];
  foreach (Var child, node) {
    if (child is <list>)
      children.push(e._capture_source(child, inputs, declarations));
    else children.push(child);
  }
  return children.list_free();
}

static int _source_type_definition(List value) {
  Array pending = $auto([]);
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
    foreach (Var child, node)
      if (child is <list>) pending.push(child);
  }
  return 0;
}

// operator grouping

/* Canonical AST nesting already states how operators group, but C text
   regroups by precedence, so emission is the one place that restores the
   nesting with parentheses. Every producer therefore builds operator nodes by
   structure alone and none of them tracks grouping.

   Larger levels bind more tightly, matching the C grammar: member access with
   postfix, then unary and cast, the binary levels above the conditional,
   the conditional, and assignment. Level 0 means the emitter has no
   grouping rule for the operator, which leaves its text exactly as the
   other cases build it. */
static enum {
  EMIT_ASSIGNMENT  = 2,
  EMIT_CONDITIONAL = 3,
  EMIT_UNARY       = 14,
  EMIT_POSTFIX     = 15,
  EMIT_PRIMARY     = 16
};

static int _operator_precedence(Symbol operator) {
  if (operator == <.> || operator == <"->">) return EMIT_POSTFIX;
  if (operator.is_assignment_op()) return EMIT_ASSIGNMENT;
  int level = operator.binary_precedence();
  return level ? EMIT_CONDITIONAL + level : 0;
}

/* The precedence of the C expression a node emits. Names, literals, calls,
   compound literals, statement expressions, and `parens` all emit text that
   already binds as tightly as a primary expression, so the default needs no
   grouping and adds no parentheses that C does not require. */
static int _emitted_precedence(Var node) {
  match (node) {
    case %(at ? ?inner):         return _emitted_precedence(inner);
    case %(expr ? ?content):     return _emitted_precedence(content);
    case %(op ?operator ? ?): {
      int level = _operator_precedence(operator);
      return level ? level : EMIT_PRIMARY;
    }
    case %(op ? ?):              return EMIT_UNARY;
    case %(op ? ? ? ?):          return EMIT_CONDITIONAL;
    case %((!or cast sizeof) *): return EMIT_UNARY;
    case %(postfix ? ?):         return EMIT_POSTFIX;
    case %(commas *):            return 1;
  }
  return EMIT_PRIMARY;
}

// The least tightly binding operand each side of a binary form accepts.
static int _left_operand_level(Symbol operator) {
  int level = _operator_precedence(operator);
  if (!level) return 0;
  return operator.is_assignment_op() ? level + 1 : level;
}

static int _right_operand_level(Symbol operator) {
  int level = _operator_precedence(operator);
  // A member name is not an expression, so it never takes parentheses.
  if (!level || operator == <.> || operator == <"->">) return 0;
  return operator.is_assignment_op() ? level : level + 1;
}

/* A node already stored as a List enters its own dispatch directly. Wrapping
   it in a one-element sequence would emit the same tokens through two more
   frames per operand, which the pinned chain stack budgets cannot spend. */
static List Emitter._operand(Emitter &e, Var node, int level) {
  List code = node is <list> && !node.is_nil()
            ? e._emit(node) : e._emit(%($node));
  if (_emitted_precedence(node) < level) return _parens(code);
  return code;
}

/* A left-leaning chain nests one (expr (op ...)) level per source term;
   walk the spine and build the token stream iteratively, folding from the
   right so each emitted piece is copied once. A separate function keeps the
   spine arrays out of _emit's frame on every other recursion path. The walk
   stops where the nested operator needs parentheses, leaving that operand to
   the ordinary recursion. */
static List Emitter._op_spine(Emitter &e, Var operator, Var left, Var right) {
  Array operators = $auto([]);
  Array rights = $auto([]);
  Var op_item = operator, left_item = left, right_item = right;
  int level = 0;
  for (;;) {
    operators.push(op_item);
    rights.push(right_item);
    level = _left_operand_level(op_item);
    int deeper = 0;
    if (_emitted_precedence(left_item) >= level)
      match (left_item)
        case %(expr ? (op ?next_operator ?next_left ?next_right)): {
          op_item = next_operator;
          left_item = next_left;
          right_item = next_right;
          deeper = 1;
        }
    if (!deeper) break;
  }
  List result = e._operand(left_item, level);
  Array pieces = $auto([]);
  for (int i = (int) operators.len() - 1; i >= 0; i--) {
    Symbol binary = operators[i];
    pieces.push(operators[i]);
    pieces.push(e._operand(rights[i], _right_operand_level(binary)));
  }
  List tail = NULL;
  for (int i = (int) pieces.len() - 1; i >= 0; i--) {
    Var piece = pieces[i];
    if (piece is <list>) tail = piece.list().append(tail);
    else tail = cons(piece, tail);
  }
  return result.append(tail);
}

// expressions

static List Emitter._emit_postfix(Emitter &e, Symbol operator, Var argument) {
  List c_arg = e._operand(argument, EMIT_POSTFIX);
  return %(@c_arg $operator);
}

static List Emitter._emit_generic(Emitter &e, Var control, List associations) {
  List c_control = e._emit(%($control));
  Array rows = [];
  foreach (List association, associations) match (association) {
    case %(association default ?value):
      rows.push(%("default" ":" @{e._emit(%($value))}));
    case %(association ?type ?value):
      rows.push(%(@{e._semantic_type(type)} ":" @{e._emit(%($value))}));
  }
  List c_rows = _commas(rows.list_free());
  return %("_Generic(" @c_control ", " @c_rows ")");
}

static List Emitter._emit_unary(Emitter &e, Symbol operator, Var argument) {
  List c_arg = e._operand(argument, EMIT_UNARY);
  return %($operator @c_arg);
}

static List Emitter._emit_binary(
  Emitter &e, Symbol operator, Var left, Var right) {
  if (left is <list> && left.list().match(%(expr ? (op *))))
    return e._op_spine(operator, left, right);
  Symbol binary = operator;
  return %(@{e._operand(left, _left_operand_level(binary))} $operator
           @{e._operand(right, _right_operand_level(binary))});
}

static List Emitter._emit_ident(Emitter &e, Var binding) {
  /* A template's free name in a declared type, such as an array size,
     keeps the spelling it lands with. */
  match (binding)
    case %((!or binding-name binding-global) ?(String spelling)):
      return %($spelling);
  Var pointer;
  if (e.static_objects && e.static_objects.try_get(binding, pointer))
    return %("(*" $pointer ")");
  return e._emit(%($binding));
}

// calls

static List Emitter._emit_call(Emitter &e, Var function, Var arguments) {
  List site_call = e._match_site_call(function, arguments);
  if (site_call) return site_call;
  return %(@{e._operand(function, EMIT_POSTFIX)} "("
           @{e._emit(%($arguments))} ")");
}

/* A source-literal pattern is the same value on every call, so the call gets
   its own process-lifetime plan site and prepares once. A computed pattern
   keeps the ordinary entry, which prepares one plan per call. Only a direct
   global function binding identifies a runtime operation. Returns NULL
   when the call is not one of those operations or its pattern is computed. */
static List Emitter._match_site_call(Emitter &e, Var function, Var arguments) {
  List binding = NULL;
  while (!binding && function is <list>) match (function) {
    case %(expr ? (parens ?inner)): function = inner;
    case %(expr ? (ident ?target)): binding = target;
    default: return NULL;
  }
  String name = binding_identity_spelling(binding);
  String entry = _match_site_entry(name);
  if (!entry) return NULL;
  Type type = NULL;
  List global = e.c.sym.resolve_global(%($name), type);
  if (!global || global != binding || !type.is_function())
    return NULL;
  List args = arguments;
  match (args)
    case %(args ? ?pattern *): {
      if (pattern is not <list> ||
          !e.match_pattern_is_static(pattern))
        return NULL;
      String site = e.fresh_name("match_site");
      List c_args = e._emit(%($arguments));
      return %("({ static MatchCaptureSite " $site ";"
               $entry "(&" $site "," @c_args "); })");
    }
  return NULL;
}

/* Each `List_` matcher has an `x2c_match_site_` entry of the same name. */
static String _match_site_entry(String name) =>
  name && name in %("List_match" "List_try_match" "List_search"
                    "List_try_search" "List_match_replace"
                    "List_try_match_replace" "List_search_replace")
    ? "x2c_match_site_" + name[5:] : NULL;

// statements

static List Emitter._emit_return(Emitter &e, Var expression) {
  List value = e._emit(%($expression));
  return %("return" @value ";");
}

static List Emitter._emit_parameters(Emitter &e, Var parameters) {
  List c_params = e._emit(%($parameters));
  return %("(" @c_params ")");
}

static List Emitter._emit_label(Emitter &e, Var name) {
  List c_name = e._emit(%($name));
  return %(@c_name ":");
}

static List Emitter._raise(Emitter &e, Ast ast, Var cause, List arguments) {
  List code = e._emit(cause);
  List arg_tokens = _commas(e._emit(arguments));
  String site_name = e.fresh_name("error_site");
  List location = e.origin_location(e.origin);
  String file = location
    ? location.assoc(<file>) : e.c.filename;
  int line = location ? location.assoc(<line>) : 0;
  String function = e.fn_name
    ? e.fn_name : "<unknown>";
  String file_literal = _c_string_literal(file);
  String function_literal = _c_string_literal(function);
  List tail = arguments ? %("," @arg_tokens) : NULL;
  List terminal = ast.never_returns()
                ? %("__builtin_unreachable();") : NULL;
  return %("{"
    "static const X2CErrorSite " $site_name " = {"
      ".file = " $file_literal ","
      ".function = " $function_literal ","
      ".line = " $line
    "};"
    "x2c_error_raise_n(&" $site_name "," @code ","
      "${arguments.len() / 2}" @tail ");"
    @terminal
  "}");
}

static String _c_string_literal(String value) {
  if (!value) value = "<unknown>";
  return %"\"${value.escape().replace("$$", "$")}\"";
}

// literals and directives

static List Emitter._literal(Emitter &e, List ast) {
  (List type, String text, Var value) = ast.cdr();
  if (type === %("Var") && text == "void") return %("((void) 0, Void)");
  if (type === %("String")) {
    String qq = "\"";
    text = qq + text.escape().replace("$$", "$") + qq;
    return %("String_new" "(" $text ")");
  }
  if (type === %("Symbol")) {
    Symbol symbol = value;
    text = %"${(long) symbol}";
  }
  if (type === %("Atom")) return _atom_intern(text);
  // C has no `0o` prefix; its octal spelling is a bare leading zero.
  if (text[0] == '0' && (text[1] == 'o' || text[1] == 'O'))
    text = "0" + String.new(text + 2);
  return %( $text );
}

static List _atom_intern(String spelling) {
  String qq = "\"", text = %"$qq${spelling.escape().replace("$$", "$")}$qq";
  Atom atom = Atom.intern(spelling);
  if (atom is <symbol>) return %( "Symbol_var(Symbol_new($text))" );
  return %( "Atom_intern(String_new($text))" );
}

// Normalize #include directives to reference generated headers.
static List Emitter._preproc(Emitter &e, List ast) {
  int angle = 0;
  String target = preproc_include_target(ast.cadr(), angle);
  if (!target || !is_source_file(target)) return ast.cdr();
  String stem = target[:target.rfind(".")];
  String out = %"#include \"$stem.h\"";
  return %( $out );
}

// declarations

static List Emitter._declare_stmt(Emitter &e, List ast) =>
  %( @{e._declare(ast)} ";");

static List Emitter._decl_stmt(Emitter &e, List ast) {
  match (ast)
    case %(decl *declaration): ast = %(declare @declaration);
  return e._declare(ast);
}

static List Emitter._declare(Emitter &e, List ast) {
  List (type, bindings) = ast.cdr();
  type = e._emit(%( $type ));
  bindings = %( $bindings );
  return type.append(e._emit(bindings));
}

static List Emitter._bind(Emitter &e, Ast ast) {
  List (ident, mods) = ast.cdr();
  ident = e._emit(ident);
  if (!mods) return ident;
  return e._declarator(ident, mods);
}

static List Emitter._param(Emitter &e, List ast) {
  List (type, mods) = ast.cdr();
  List code = e._emit(type);
  mods = %( $mods );
  return code.append(e._emit(mods));
}

static List Emitter._args(Emitter &e, List ast) {
  Array result = [];
  int first = 1;
  foreach (List argument, ast.cdr()) {
    List emitted = e._emit(argument);
    if (argument.match(%(expr ? (commas *)))) emitted = _parens(emitted);
    if (!first) result.push(", ");
    result.push(emitted);
    first = 0;
  }
  return result.list_free();
}

static List Emitter._function(Emitter &e, List ast) {
  List (type, bindings, body) = ast.cdr();
  String old_fn = e.fn_name;
  List function_binding = bindings.cadr();
  e.fn_name = binding_identity_spelling(function_binding);
  Var defer_owner;
  if (e.semantic_binding_facts().try_get(
    %(defer-ownr $function_binding), defer_owner))
    e.fn_name = defer_owner;
  type = e._emit(%( $type ));
  bindings = %( $bindings );
  body = %( $body );
  List decl, body_code;
  $let(e.static_objects, {}) {
    decl = e._emit(bindings);
    body_code = e._emit(body);
  }
  e.fn_name = old_fn;
  return %(@type @decl @body_code);
}

// Emit a checked native-function alias without a wrapper object.
static List Emitter._foreign_alias(Emitter &e, List ast) {
  List (declaration, native_binding) = ast.cdr();
  List bindings = declaration.caddr(), target = bindings.cadr().cadr();
  Type function_type = declaration.type_from_ast().declared();
  Type pointer_type = function_type.reference();
  List pointer = e._semantic_type(pointer_type);
  List native = e._emit(native_binding);
  String target_name = e.emitted_binding_name(target);
  String native_name = e.emitted_binding_name(native_binding);
  String message = %"native alias $target_name does not match $native_name";
  String define = $emit.alias.definition(target_name, native_name);
  return $emit.alias.checked(native, pointer, message, define);
}

static List Emitter._typedef(Emitter &e, List ast) {
  List code = %("typedef" @{e._emit(ast.cdr())} ";");
  foreach (List declarator, ast.caddr().cdr()) {
    List binding = declarator.cadr();
    Var type;
    if (e.semantic_binding_facts().try_get(%(ntype $binding), type))
      e.native_aliases = cons(%($type $binding), e.native_aliases);
  }
  return code;
}

static List Emitter._block(Emitter &e, List ast) {
  $let(e.native_aliases, e.native_aliases)
    return %("{" @{e._emit(ast.cdr())} "}");
}

static List Emitter._binding(Emitter &e, List ast) =>
  %(${e.emitted_binding_name(ast)});

// declarators

/* Fold one layer at a time; typedef prefixes surround the final result. */
static List Emitter._declarator(Emitter &e, List decl, List mods) {
  int typedefs = 0;
  while (mods) {
    Var first = mods.car();
    if (first is <list>) {
      decl = e._list_declarator(decl, first);
      mods = mods.cdr();
      continue;
    }
    Symbol sym = first;
    switch (sym) {
      case <dim>: decl = e._array_declarator(decl, NULL); break;
      case <&>: case <opt-ref>: decl = cons(<*>, decl); break;
      case <*>: decl = cons(first, decl); break;
      case <typedef>: typedefs++; break;
      case <bitfield>: decl = e._bitfield_declarator(mods); continue;
      default: decl = _native_declarator(decl, mods, sym); break;
    }
    mods = mods.cdr();
  }
  while (typedefs--) decl = cons(<typedef>, decl);
  return decl;
}

static List Emitter._list_declarator(Emitter &e, List decl, Type mod) {
  if (mod.car() == <fnmod>) return e._function_declarator(decl, mod.cadr());
  if (mod.car() is <string>) return %(@decl @mod);
  if (mod.is_array()) return e._array_declarator(decl, mod.cadr());
  return %(@decl ":" @{e._emit(mod.cadr())});
}

static List Emitter._bitfield_declarator(Emitter &e, List &mods) {
  List tokens = e._emit(mods.cdr());
  mods = NULL;
  return tokens;
}

static List _native_declarator(List decl, List &mods, Symbol sym) {
  if (sym.is_type_qualifier()) return cons(sym, decl);
  List tokens = %(@mods @decl);
  mods = NULL;
  return tokens;
}

static List Emitter._array_declarator(Emitter &e, List decl, List dimension) {
  if (decl.type().is_pointer()) decl = _parens(decl);
  List size = e._emit(dimension);
  return size ? %(@decl "[" @size "]") : %(@decl "[]");
}

// Wrap declarators in parentheses when pointer precedence requires it.
static List _parens(List decl) => %("(" @decl ")");
static List Emitter._function_declarator(
  Emitter &e, List decl, List parameters) {
  if (decl.type().is_pointer()) decl = _parens(decl);
  return %(@decl "(" @{e._emit(parameters)} ")");
}

static List Emitter._semantic_type(Emitter &e, Type type) {
  List declaration = type.declaration_ast(NULL);
  return e._declare(declaration);
}

static List Emitter._semantic_name(Emitter &e, Type type, String name) {
  List (base, mods) = type.declaration_parts();
  List declarator = e._declarator(%($name), mods);
  return %(${e._emit(base)} @declarator);
}

static List _commas(List items) {
  if (!items.cdr()) return items;
  Array result = [];
  int first = 1;
  foreach (Var item, items) {
    if (!first) result.push(", ");
    result.push(item);
    first = 0;
  }
  return result.list_free();
}

// tagged types

static List Emitter._enum(Emitter &e, List ast) {
  List name = ast.type().tag(), body = ast.type().body().car();
  if (_is_gensym_tag(name) && !ast.type().is_enum_tag()) name = NULL;
  if (name) name = e._emit(name);
  body = e._emit(body);
  body = _commas(body);
  if (name) {
    if (body) return %( ${ast.car()} @name "{" @body "}");
    return %( ${ast.car()} @name );
  }
  return %( ${ast.car()} "{" @body "}");
}

static List Emitter._aggregate(Emitter &e, List ast) {
  if (ast.type().is_aggregate_tag()) {
    Var alias = e.native_aliases.assoc(ast);
    if (alias is <list>) return e._emit(alias);
  }
  List tag = ast.type().tag();
  if (_is_gensym_tag(tag) && !ast.type().is_aggregate_tag()) tag = NULL;
  if (tag) tag = e._emit(tag);
  if (ast.type().is_aggregate_tag()) return %( ${ast.car()} @tag );
  List body = ast.type().body();
  body = e._emit(body);
  body = body.flatten_all();
  if (tag && body) return %( ${ast.car()} @tag "{" @body "}");
  if (tag) return %( ${ast.car()} @tag );
  return %( ${ast.car()} "{" @body "}");
}

/* The tag slot of an anonymous aggregate holds the compiler-internal
   gensym key that stands in for the tag the source never wrote. It names
   nothing outside this unit, and two units that reach the same counter
   state mint the same key, so it is never emitted. The tagless definition
   is what the source wrote, and tagless typedefs are compatible across
   translation units (C11 6.2.7). */
static int _is_gensym_tag(List tag) {
  if (!tag) return 0;
  Var head = tag.car();
  if (head is not <list>) return 0;
  return head.list().car() == <gensym>;
}

/* match statements

   Each case lowers to a conditional, in source order, inside a switch on
   the subject's head symbol. A label stays in front of the conditional
   groups around its arm, so the switch still reaches later arms when the
   preprocessor removes that arm. */

static List Emitter._match_cases(Emitter &e, List ast) {
  List (expr, cases) = ast.cdr();
  expr = e._emit(expr);
  int max_binders = 0;
  foreach (List rec, cases) {
    int count = rec.car() == <preproc> ? 0 : rec.car().list().len();
    if (count > max_binders) max_binders = count;
  }
  // An arm reads only the values it bound, so the buffer names the two
  // fields it needs and Match fills in presence and order.
  List capture_declarations;
  if (max_binders) {
    String values_decl = $emit.match.values(max_binders);
    String capture_decl = $emit.match.buffer(max_binders);
    capture_declarations = %($values_decl $capture_decl);
  }
  else
    capture_declarations = $emit.match.empty_buffer();
  int dispatched;
  List arms = e._match_if(cases, dispatched);
  // The subject's head symbol selects the first arm that can still match;
  // with no case labels every subject reaches the sole default arm.
  List selector = dispatched
    ? %("Var_symbol(car(_x2c_match_expr))") : %("0");
  return $emit.match.dispatch(expr, capture_declarations, selector, arms);
}

static List Emitter._match_if(Emitter &e, List ast, int &dispatched) {
  Array values = [], heads = [], int labelling = 1, opening = 0;
  List arms = NULL;
  foreach (List rec, ast) {
    if (rec.car() == <preproc>) {
      if (!arms) opening = values.len();
      arms = preproc_track_arms(arms, rec.cadr());
      values.push(e._emit(rec));
      continue;
    }
    List (binders, pattern_ast, body_ast) = rec;
    Var value = e.match_pattern_value(pattern_ast);
    List label = _match_arm_label(match_value_head(value), heads, labelling);
    if (label) values.insert(arms ? opening++ : values.len(), label);
    values.push(e._match_arm(binders, pattern_ast, body_ast, value));
  }
  if (labelling) values.push(%("default: break;"));
  dispatched = heads.len() != 0;
  heads.free();
  return values.list_free();
}

/* Label one arm so the switch can reach it directly. An arm whose pattern
   begins with a literal symbol only matches a subject beginning with that
   same symbol, so the arms in front of it may be jumped over; the second and
   later arms sharing a head take no label and are reached by falling through
   from the first. The first arm with no literal head can match anything, so
   it takes `default:` and ends the labelling. A failed arm still falls into
   everything after it, so arm order is unchanged. */
static List _match_arm_label(Symbol head, Array heads, int &labelling) {
  if (!labelling) return NULL;
  if (!head) {
    labelling = 0;
    return %("default: ;");
  }
  if (head in heads) return NULL;
  heads.push(head);
  long code = head;
  return %("case $code: ;");
}

static List Emitter._match_arm(
  Emitter &e, List binders, List pattern_ast, List body_ast, Var value) {
  List implicit_break = %("break;");
  match (body_ast)
    case %(guarded ?body): {
      body_ast = body;
      implicit_break = NULL;
    }
  List flat_tags = NULL;
  Symbol flat_head = match_value_flat_head(value, binders, flat_tags);
  List pattern = e._emit(pattern_ast);
  List body = e._emit(body_ast);
  List macro_case = e._macro_case(pattern_ast);
  if (pattern === %(*)) return %($body @implicit_break);
  if (macro_case) {
    List declarations = _make_local_binders(binders, "_x2c_match_values");
    String site = macro_case[1];
    return $emit.match.macro_arm(
      site, macro_case, declarations, body, implicit_break);
  }
  if (flat_head) {
    List condition = _flat_match_condition(flat_head, flat_tags);
    List declarations = _make_local_binders(binders, "_x2c_match_values");
    String closing = implicit_break ? "break; } }" : "} }";
    return $emit.match.flat_arm(condition, declarations, body, closing);
  }
  return e._match_capture_arm(binders, pattern, body, implicit_break, value);
}

/* A macro-valued case recognizes the subject through the runtime, which
   publishes captures into the arm's buffer. */
static List Emitter._macro_case(Emitter &e, List pattern_ast) {
  match (pattern_ast)
    case %(expr ? (call (expr ? (ident (binding ? "Macro_case_pattern")))
                        (args ?template ?names))):
      return %("Macro_case_capture_at(&" ${e.fresh_name("macro_site")}
        ", _x2c_match_expr," @{e._emit(template)} "," @{e._emit(names)} ","
        "&_x2c_match_capture)");
  return NULL;
}

/* The pattern contains one Symbol and unique single-element captures.
   Keep the head check even under head dispatch: a failed arm falls through.
   A typed capture tests its tag the way the `is` operator does.
*/
static List _flat_match_condition(Symbol head, List tags) {
  Var literal = head;
  unsigned long long bits = literal.u64;
  Array condition = [];
  condition.push($emit.match.head_condition(bits));
  int index = 0;
  foreach (Var tag, tags) {
    condition.push($emit.match.cursor_present());
    if (tag is <symbol>)
      condition.push($emit.match.cursor_tag((unsigned long) tag.symbol()));
    condition.push($emit.match.capture_value(index));
    index++;
  }
  condition.push($emit.match.cursor_empty());
  return condition.list_free();
}

static List Emitter._match_capture_arm(
  Emitter &e, List binders, List pattern, List body,
  List implicit_break, Var value) {
  int static_pattern = match_value_is_static(value);
  String site_name = static_pattern ? e.fresh_name("match_site") : NULL;
  List site_declaration = static_pattern
    ? %("static MatchCaptureSite $site_name;") : NULL;
  List entry = static_pattern
    ? %("x2c_match_site_try_capture(&" $site_name ",")
    : %("x2c_match_try_capture(");
  List declarations = _make_local_binders(binders, "_x2c_match_values");
  return $emit.match.capture_arm(
    site_declaration, entry, pattern, declarations, body, implicit_break);
}

/* Declare the named binders of a match case in source order. The wildcard
   binders `*` and `?` get no declaration. */
static List _make_local_binders(List binders, String values_name) {
  Array values = [], int index = 0;
  foreach (Var binder, binders) {
    if (binder != <?> && binder != <*>) {
      String bvar = String.new(binder.str() + 1);
      String rhs = $emit.match.value_at(values_name, index);
      values.push(
        binder.is_list_binder()
          ? $emit.match.list_binder(bvar, rhs)
          : $emit.match.value_binder(bvar, rhs));
    }
    index++;
  }
  return values.list_free();
}
