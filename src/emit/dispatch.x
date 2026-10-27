/*  dispatch.x -- ordered traversal and C token assembly */

// writing tokens

/* Emission writes each C token to `e.out` in order, so no token List is
   built: a form writes its text and emits its children where they stand. */
module void _put(Emitter &e, Var token) { e.out.push(token); }

/* Writes `tokens`, a token List that may nest, in order. */
module void _put_all(Emitter &e, List tokens) {
  foreach (Var token in tokens)
    if (token is <list>) _put_all(e, token);
    else e.out.push(token);
}

/* Writes `parts` in order: each String or number as a token, and each node
   emitted in place; a Symbol heads a node of its own. */
module void _write(Emitter &e, List parts) {
  foreach (Var part in parts) _node(e, part);
}

/* Emits `item` as `_emit` emits the one-element sequence holding it. */
module void _node(Emitter &e, Var item) {
  if (item is <list>) _emit(e, item);
  else if (item is <symbol>) _emit(e, $(item));
  else e.out.push(item);
}

/* The tokens `_emit` writes for `ast`, apart from `e.out`, for a form that
   places them out of order or inspects them. */
module Array _captured(Emitter &e, Var ast) {
  Array saved = e.out;
  e.out = [];
  _node(e, ast);
  Array tokens = e.out;
  e.out = saved;
  return tokens;
}

module List _tokens(Emitter &e, Var ast) => _captured(e, ast).list_free();

/* The items of the sequence `ast` as `_commas` separates them: each item
   before a Symbol on its own, then each token of the node that Symbol
   heads. */
module List _grouped(Emitter &e, List ast) {
  Array items = [];
  while (ast && ast.car() is not <symbol>) {
    items.push(_tokens(e, ast.car()));
    ast = ast.cdr();
  }
  foreach (Var token in _tokens(e, ast)) items.push(token);
  return items.list_free();
}

/* Writes the sequence `ast` with commas between its items. */
static void _comma_items(Emitter &e, List ast) {
  int first = 1;
  while (ast && ast.car() is not <symbol>) {
    if (!first) _put(e, ", ");
    _node(e, ast.car());
    ast = ast.cdr();
    first = 0;
  }
  if (!ast) return;
  foreach (Var token in _tokens(e, ast)) {
    if (!first) _put(e, ", ");
    _put(e, token);
    first = 0;
  }
}

static void _keyword_group(
  Emitter &e, String keyword, Var inner, Var body) {
  _put(e, keyword);
  _put(e, "(");
  _node(e, inner);
  _put(e, ")");
  _node(e, body);
}

/* Between `?` and `:` C accepts a complete expression, so only the
   condition and the false arm can regroup. */
static void _conditional(Emitter &e, Var condition, Var yes, Var no) {
  _operand(e, condition, EMIT_CONDITIONAL + 1);
  _put(e, "?");
  _node(e, yes);
  _put(e, ":");
  _operand(e, no, EMIT_CONDITIONAL);
}

static void _cast(Emitter &e, Type type, Var expression) {
  _put(e, "(");
  _put_all(e, _semantic_type(e, type));
  _put(e, ")");
  _operand(e, expression, EMIT_UNARY);
}

static void _index(Emitter &e, Var array, Var index) {
  _operand(e, array, EMIT_POSTFIX);
  _put(e, "[");
  _node(e, index);
  _put(e, "]");
}

static void _cache(Emitter &e, Var id) {
  if (e.cache_bindings) _ident(e, e.cache_bindings[id]);
  else _put(e, %"_$id");
}

/** Emits a bound, typed, transform-normalized AST sequence as flat C tokens.
    Source mapping adds `src-at`/ID pairs consumed by the formatter.
    The compiler must own the AST's binding facts and origins, and continue the
    translation session's shared generated-name state. This operation does not
    bind, transform, or choose header and source placement; generation supplies
    any added scaffolding in the same normalized grammar. `cache_bindings`
    maps semantic cache ids to generated slots; NULL keeps raw ids for
    inspection. It preserves the top-level AST sequence and advances
    generated-name counters as it allocates temporaries. The returned
    `Array` holds `String`s owned by pools active during emission; promote
    them before releasing those pools if the tokens must survive.
*/
Array Compiler.emit(Compiler c, List ast, Map cache_bindings) {
  Emitter e = {
    .c = c, .origin = 0, .native_macros = [], .out = [],
    .cache_bindings = cache_bindings};
  _emit(e, ast);
  Array before = [], after = [];
  if (e.static_support)
    before.push("#include \"exception.h\"\n#include <string.h>");
  foreach (List entry in e.native_macros.list_free()) {
    (String name, String definition) = entry;
    before.push(definition);
    after.push(%"#undef $name");
  }
  return before.concat(e.out).concat(after);
}

/* Emission visits sibling nodes from left to right because generated names
   and origins change during the walk. Generic sequences walk their items in
   order; a specialized form writes its text and emits its children in the
   order C reads them. This orders tokens, not C operand
   evaluation; only producer-marked forms such as statement-expression
   blocks introduce runtime sequencing. Parser, transform, and generation
   produce every recognized AST shape, so the fallback handles only already
   C-shaped nodes. */
module void _emit(Emitter &e, List ast) {
  if (!ast) return;
  Var head = ast.car();
  if (head is not <symbol>) {
    _sequence(e, ast);
    return;
  }
  if (head != <typedef> &&
      (head.symbol().is_storage_class() ||
       head.symbol().is_type_qualifier() ||
       head.symbol().is_inline())) {
    _prefix(e, ast);
    return;
  }
  match (ast) {
    case %(unqual *type): {
      _put(e, "__typeof__((0, (");
      _put_all(e, _semantic_type(e, type));
      _put(e, "){0}))");
    }
    case %(at ?origin ?inner): _at(e, origin, inner);
    case %(cons ?item ?tail):
      _write(e, %("cons(" $item ", " $tail ")"));
    case %(append ?head ?tail):
      _write(e, %("List_append(" $head ", " $tail ")"));
    case %(c-assert ?test ?message):
      _write(e, %("_Static_assert(" $test "," $message ");"));
    case %(initcode ?input ?body): {
      _put_all(e, _initializer_macro(e, input, body));
      _put(e, ";");
    }
    case %(localinit ?decl (block *body)):
      _put_all(e, _local_static(e, decl, body));
    case %(sourceinit ?fn): _put_all(e, _source_initializer(e, fn));
    case %(initval *): _put_all(e, _initializer_value(e, ast));
    case %(indexinit ?index ?value): _put_all(e, _index_init(e, index, value));
    case %(dotinit ?field ?value): _put_all(e, _dot_init(e, field, value));
    case %(cast ?type ?expr): _cast(e, type, expr);
    case %(cache ?id): _cache(e, id);
    case %(expr ? ?content): _node(e, content);
    case %(postfix ?op ?argument): _postfix(e, op, argument);
    case %(generic ?control *rows): _generic(e, control, rows);
    case %(va-arg ?expr ?decl): _write(e, %("va_arg(" $expr ", " $decl ")"));
    case %(offsetof ?type ?member): {
      _put(e, "offsetof(");
      _put_all(e, _semantic_type(e, type));
      _put(e, ", ");
      _emit(e, member);
      _put(e, ")");
    }
    case %(call ?fn ?args): _call(e, fn, args);
    case %(index ?array ?index): _index(e, array, index);
    case %(op ?op ?argument): _unary(e, op, argument);
    case %(op ?op ?left ?right): _binary(e, op, left, right);
    case %(op ? ?test ?yes ?no): _conditional(e, test, yes, no);
    case %(break): _put(e, "break;");
    case %(continue): _put(e, "continue;");
    case %(if ?test ?yes): _keyword_group(e, "if", test, yes);
    case %(if ?test ?yes ?no): {
      _keyword_group(e, "if", test, yes);
      _put(e, "else");
      _node(e, no);
    }
    case %(while ?test ?body): _keyword_group(e, "while", test, body);
    case %(do ?body ?test):
      _write(e, %("do" $body "while" "(" $test ")" ";"));
    case %(for ?initial ?test ?step ?body):
      _write(e, %("for" "(" $initial ";" $test ";" $step ")" $body));
    case %(switch ?expr ?body): _keyword_group(e, "switch", expr, body);
    case %(return): _put(e, "return;");
    case %(return (!set ?expr (expr ? ?))): _return(e, expr);
    case %(goto ?label): _write(e, %("goto" $label ";"));
    case %(raise ?cause (args *args)): _put_all(e, _raise(e, ast, cause, args));
    case %((!or fnmod func) ?params): _parameters(e, params);
    case %(label ?name): _label(e, name);
    case %(ident ?binding): _ident(e, binding);
    case %(declare ?type ?bindings): {
      _declare(e, type, bindings);
      _put(e, ";");
    }
    case %(decl ?type ?bindings): _declare(e, type, bindings);
    case %(bind ?ident ?mods): _bind(e, ident, mods);
    case %(param ?type ?mods): _param(e, type, mods);
    case %(function ?type ?bindings ?body):
      _function(e, type, bindings, body);
    case %(falias (!set ?declaration (declare ? (bindings (bind ?target ?))))
                  ?native):
      _put_all(e, _foreign_alias(e, declaration, target, native));
    default: _leaf(e, ast);
  }
}

/* A run of nodes and verbatim C text: each node is emitted in place and
   each String is written as it is, so a lowered carrier can hold C text
   around the nodes it lowers. A Symbol ends the run and heads a node. */
static void _sequence(Emitter &e, List ast) {
  for (; ast && ast.car() is not <symbol>; ast = ast.cdr()) _node(e, ast.car());
  _emit(e, ast);
}

static void _prefix(Emitter &e, List ast) {
  while (ast && ast.car() is <symbol>) {
    Symbol item = ast.car();
    if (item == <typedef> ||
        (!item.is_storage_class() && !item.is_type_qualifier() &&
         !item.is_inline()))
      break;
    if (item == <threaded>) _put(e, "_Thread_local");
    else _put(e, ast.car());
    ast = ast.cdr();
  }
  _emit(e, ast);
}

static void _leaf(Emitter &e, List ast) {
  Var head = ast.car();
  switch (head.symbol()) {
    case <adopt>: case <macrodef>: case <protocol>: return;
    case <literal>:    _literal(e, ast); return;
    case <preproc>:    _put_all(e, _preproc(e, ast)); return;
    case <enum>:       _put_all(e, _enum(e, ast)); return;
    case <struct>:     _put_all(e, _aggregate(e, ast)); return;
    case <typedef>:    _typedef(e, ast); return;
    case <union>:      _put_all(e, _aggregate(e, ast)); return;
    case <args>:       _args(e, ast); return;
    case <bindings>: case <params>: case <commas>:
      _comma_items(e, ast.cdr());
      return;
    case <fields>: case <group>: _emit(e, ast.cdr()); return;
    case <block>:      _block(e, ast); return;
    case <parens>:     _surround(e, "(", ast.cdr(), ")"); return;
    case <sizeof>:     _put(e, "sizeof"); _emit(e, ast.cdr()); return;
    case <case>:       _surround(e, "case", ast.cdr(), ":"); return;
    case <composite>:  _surround(e, "{", ast.cdr(), "}"); return;
    case <default>:    _put(e, "default:"); return;
    case <empty>:      _put(e, ";"); return;
    case <stmnt>:      _emit(e, ast.cdr()); _put(e, ";"); return;
    case <binding>:    _binding(e, ast); return;
    case <comment>: case <space>: _put_all(e, ast.cdr()); return;
    case <nil>:        _put(e, "NULL"); return;
  }
  _put(e, head);
  _emit(e, ast.cdr());
}

static void _surround(Emitter &e, String open, List inner, String close) {
  _put(e, open);
  _emit(e, inner);
  _put(e, close);
}

static void _at(Emitter &e, int origin, List inner) {
  int old_origin = e.origin;
  e.origin = origin;
  if (e.c.source_map) {
    _put(e, <src-at>);
    _put(e, origin);
  }
  _emit(e, inner);
  e.origin = old_origin;
  if (e.c.source_map) {
    _put(e, <src-at>);
    _put(e, old_origin);
  }
}

// statements

static void _return(Emitter &e, Var expression) {
  _put(e, "return");
  _node(e, expression);
  _put(e, ";");
}

static void _label(Emitter &e, Var name) {
  _node(e, name);
  _put(e, ":");
}

static List _raise(Emitter &e, Ast ast, Var cause, List arguments) {
  List code = _tokens(e, cause);
  List arg_tokens = _commas(_grouped(e, arguments));
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
  List runtime = e.c.runtime_inc ? NULL : %("," ".runtime = 1");
  return %("{"
    "static const X2CErrorSite " $site_name " = {"
      ".file = " $file_literal ","
      ".function = " $function_literal ","
      ".line = " $line @runtime
    "};"
    "x2c_error_raise_n(&" $site_name "," @code ","
      "$(arguments.len() / 2)" @tail ");"
    @terminal
  "}");
}

static String _c_string_literal(String value) {
  if (!value) value = "<unknown>";
  return %"\"$(value.escape())\"";
}

// Normalize #include directives to reference generated headers.
static List _preproc(Emitter &e, List ast) {
  int angle = 0;
  String target = Compiler.preproc_include_target(ast.cadr(), angle);
  if (!target || !Path.is_x2c_source(target)) return ast.cdr();
  String stem = target[:target.rfind(".")];
  String out = %"#include \"$stem.h\"";
  return $(out);
}

// Wrap declarators in parentheses when pointer precedence requires it.
module List _parens(List decl) => %("(" @decl ")");

module List _commas(List items) {
  if (!items.cdr()) return items;
  Array result = [];
  int first = 1;
  foreach (Var item in items) {
    if (!first) result.push(", ");
    result.push(item);
    first = 0;
  }
  return result.list_free();
}
