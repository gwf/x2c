/*  dispatch.x -- ordered traversal and C token assembly */

// form templates

static macro Expression $emit.cons(Expr $e, Expr $item, Expr $tail) =>
  %("cons(" @{_emit($e, %(${$item}))} ", " @{_emit($e, %(${$tail}))} ")");

static macro Expression $emit.append(Expr $e, Expr $head_list, Expr $tail) =>
  %("List_append(" @{_emit($e, %(${$head_list}))} ", "
    @{_emit($e, %(${$tail}))} ")");

static macro Expression $emit.c_assert(
  Expr $e, Expr $condition, Expr $message) =>
  %("_Static_assert(" @{_emit($e, %(${$condition}))} ","
    @{_emit($e, %(${$message}))} ");");

static macro Expression $emit.initcode(Expr $e, Expr $input, Expr $body) =>
  %(@{_initializer_macro($e, $input, $body)} ";");

static macro Expression $emit.cast(Expr $e, Expr $type, Expr $expression) =>
  %("(" @{_semantic_type($e, $type)} ")"
    @{_operand($e, $expression, EMIT_UNARY)});

static macro Expression $emit.cache(Expr $e, Expr $id) =>
  $e.cache_bindings ? _ident($e, $e.cache_bindings[$id])
                   : %("_${$id}");

static macro Expression $emit.vararg(
  Expr $e, Expr $expression, Expr $declaration) =>
  %("va_arg(" @{_emit($e, %(${$expression}))} ", "
    @{_emit($e, %(${$declaration}))} ")");

static macro Expression $emit.offset(Expr $e, Expr $type, Expr $member) =>
  %("offsetof(" @{_semantic_type($e, $type)} ", " @{_emit($e, $member)}
    ")");

static macro Expression $emit.index(Expr $e, Expr $array, Expr $index) =>
  %(@{_operand($e, $array, EMIT_POSTFIX)} "[" @{_emit($e, %(${$index}))}
    "]");

/* Between `?` and `:` C accepts a complete expression, so only the
   condition and the false arm can regroup. */
static macro Expression $emit.conditional(
  Expr $e, Expr $condition, Expr $ontrue, Expr $onfalse) =>
  %(@{_operand($e, $condition, EMIT_CONDITIONAL + 1)} "?"
    @{_emit($e, %(${$ontrue}))} ":"
    @{_operand($e, $onfalse, EMIT_CONDITIONAL)});

static macro Expression $emit.if(Expr $e, Expr $condition, Expr $ontrue) =>
  %("if" "(" @{_emit($e, %(${$condition}))} ")" @{_emit($e, %(${$ontrue}))});

static macro Expression $emit.if_else(
  Expr $e, Expr $condition, Expr $ontrue, Expr $onfalse) =>
  %("if" "(" @{_emit($e, %(${$condition}))} ")" @{_emit($e, %(${$ontrue}))}
    "else" @{_emit($e, %(${$onfalse}))});

static macro Expression $emit.while(Expr $e, Expr $condition, Expr $body) =>
  %("while" "(" @{_emit($e, %(${$condition}))} ")"
    @{_emit($e, %(${$body}))});

static macro Expression $emit.do(Expr $e, Expr $body, Expr $condition) =>
  %("do" @{_emit($e, %(${$body}))} "while"
    "(" @{_emit($e, %(${$condition}))} ")" ";");

static macro Expression $emit.for(Expr $e, Expr $ast) => ({
  Var (initial, condition, increment, body) = $ast.cdr();
  %("for" "(" @{_emit($e, %($initial))} ";"
    @{_emit($e, %($condition))} ";" @{_emit($e, %($increment))} ")"
    @{_emit($e, %($body))});
});

static macro Expression $emit.switch(Expr $e, Expr $expression, Expr $body) =>
  %("switch" "(" @{_emit($e, %(${$expression}))} ")"
    @{_emit($e, %(${$body}))});

static macro Expression $emit.goto(Expr $e, Expr $label) =>
  %("goto" @{_emit($e, %(${$label}))} ";");

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
  List code = _emit(e, ast).flatten_all();
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
module List _emit(Emitter &e, List ast) {
  if (!ast) return ast;
  Var head = ast.car();
  if (head is not <symbol>) return _sequence(e, ast);
  if (head != <typedef> &&
      (head.symbol().is_storage_class() ||
       head.symbol().is_type_qualifier() ||
       head.symbol().is_inline())) {
    return _prefix(e, ast);
  }
  match (ast) {
    case %(at ?origin ?inner): return _at(e, origin, inner);
    case %(cons ?item ?tail): return $emit.cons(e, item, tail);
    case %(append ?head ?tail): return $emit.append(e, head, tail);
    case %(c-assert ?test ?message): return $emit.c_assert(e, test, message);
    case %(initcode ?input ?body): return $emit.initcode(e, input, body);
    case %(localinit ?decl (block *body)): return _local_static(e, decl, body);
    case %(sourceinit ?fn): return _source_initializer(e, fn);
    case %(initval *): return _initializer_value(e, ast);
    case %(indexinit ?index ?value): return _index_init(e, index, value);
    case %(dotinit ?field ?value): return _dot_init(e, field, value);
    case %(cast ?type ?expr): return $emit.cast(e, type, expr);
    case %(cache ?id): return $emit.cache(e, id);
    case %(expr ? ?content): return _emit(e, %($content));
    case %(postfix ?op ?argument): return _postfix(e, op, argument);
    case %(generic ?control *rows): return _generic(e, control, rows);
    case %(va-arg ?expr ?decl): return $emit.vararg(e, expr, decl);
    case %(offsetof ?type ?member): return $emit.offset(e, type, member);
    case %(call ?fn ?args): return _call(e, fn, args);
    case %(index ?array ?index): return $emit.index(e, array, index);
    case %(op ?op ?argument): return _unary(e, op, argument);
    case %(op ?op ?left ?right): return _binary(e, op, left, right);
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
    case %(return (!set ?expr (expr ? ?))): return _return(e, expr);
    case %(goto ?label): return $emit.goto(e, label);
    case %(raise ?cause (args *args)): return _raise(e, ast, cause, args);
    case %((!or fnmod func) ?params): return _parameters(e, params);
    case %(label ?name): return _label(e, name);
    case %(ident ?binding): return _ident(e, binding);
    case %(falias (!set ?declaration (declare ? (bindings (bind ?target ?))))
                  ?native):
      return _foreign_alias(e, declaration, target, native);
  }
  return _leaf(e, ast);
}

/* A run of nodes and verbatim C text: each node is emitted in place and
   each String is written as it is, so a lowered carrier can hold C text
   around the nodes it lowers. A Symbol ends the run and heads a node. */
static List _sequence(Emitter &e, List ast) {
  Array emitted = $auto([]);
  while (ast && ast.car() is not <symbol>) {
    Var item = ast.car();
    emitted.push(item is <list> ? _emit(e, item) : item);
    ast = ast.cdr();
  }
  List result = _emit(e, ast);
  for (int i = (int) emitted.len() - 1; i >= 0; i--)
    result = cons(emitted[i], result);
  return result;
}

static List _prefix(Emitter &e, List ast) {
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
  return prefix.list_free().append(_emit(e, ast));
}

static List _leaf(Emitter &e, List ast) {
  Var head = ast.car();
  switch (head.symbol()) {
    case <adopt>: case <macrodef>: case <protocol>: return NULL;
    case <literal>:    return _literal(e, ast);
    case <preproc>:    return _preproc(e, ast);
    case <bind>:       return _bind(e, ast);
    case <declare>:    return _declare_stmt(e, ast);
    case <decl>:       return _decl_stmt(e, ast);
    case <enum>:       return _enum(e, ast);
    case <function>:   return _function(e, ast);
    case <param>:      return _param(e, ast);
    case <struct>:     return _aggregate(e, ast);
    case <typedef>:    return _typedef(e, ast);
    case <union>:      return _aggregate(e, ast);
    case <args>:       return _args(e, ast);
    case <bindings>: case <params>: return _commas(_emit(e, ast.cdr()));
    case <fields>:     return _emit(e, ast.cdr());
    case <block>:      return _block(e, ast);
    case <group>:      return _emit(e, ast.cdr());
    case <parens>:     return %("(" @{_emit(e, ast.cdr())} ")");
    case <sizeof>: return %("sizeof" @{_emit(e, ast.cdr())});
    case <case>: return %("case" ${_emit(e, ast.cdr())} ":");
    case <composite>: return %("{" @{_emit(e, ast.cdr())} "}");
    case <default>:    return %("default:");
    case <empty>:      return %(";");
    case <stmnt>:      return %( @{_emit(e, ast.cdr())} ";");
    case <binding>:    return _binding(e, ast);
    case <commas>: return _commas(_emit(e, ast.cdr()));
    case <comment>:    return ast.cdr();
    case <nil>:        return %("NULL");
    case <space>:      return ast.cdr();
  }
  return %($head @{_emit(e, ast.cdr())});
}

static List _at(Emitter &e, int origin, List inner) {
  int old_origin = e.origin;
  e.origin = origin;
  List result = _emit(e, inner);
  e.origin = old_origin;
  if (e.c.source_map)
    return %(src-at $origin @result src-at $old_origin);
  return result;
}

// statements

static List _return(Emitter &e, Var expression) {
  List value = _emit(e, %($expression));
  return %("return" @value ";");
}

static List _label(Emitter &e, Var name) {
  List c_name = _emit(e, %($name));
  return %(@c_name ":");
}

static List _raise(Emitter &e, Ast ast, Var cause, List arguments) {
  List code = _emit(e, cause);
  List arg_tokens = _commas(_emit(e, arguments));
  String site_name = e.fresh_name("error_site");
  List location = e.origin_location(e.origin);
  String file = location
    ? location.assoc(<file>) : e.c.filename;
  int line = location ? location.assoc(<line>) : 0;
  String file_literal = _c_string_literal(file);
  String function_literal = _c_string_literal(e.fn_name);
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
  return %"\"${value.escape()}\"";
}

// Normalize #include directives to reference generated headers.
static List _preproc(Emitter &e, List ast) {
  int angle = 0;
  String target = Compiler.preproc_include_target(ast.cadr(), angle);
  if (!target || !Path.is_x2c_source(target)) return ast.cdr();
  String stem = target[:target.rfind(".")];
  String out = %"#include \"$stem.h\"";
  return %( $out );
}

// Wrap declarators in parentheses when pointer precedence requires it.
module List _parens(List decl) => %("(" @decl ")");

module List _commas(List items) {
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
