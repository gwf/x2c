/*  adapter.x -- the admitted x2c subset as C* builder calls.

    The parser already established types, bindings, and legal positions, so
    the adapter reads the typed AST and renders one `make_*` call per node.
    It never treats an unrecognized form as having no effect: the first form
    outside the admitted subset stops the file and is reported with its
    source location.

    The rendered text is x2c: statement segments go through `Cstar.feed`,
    while structure uses the package's pinned raw builder API directly, in
    the same order `cstarc` itself emits.
*/

#include "frontend.x"

typedef struct Adapter *Adapter;

#pragma private

#include <stdlib.h>

struct Adapter {
  Compiler compiler;
  Array lines;
  Map annotations;
  Map earlier;
  String failure;
  String file;
  int line, column, arrays;
};

static Map _binary_operators = %{
  <"*">: BINOP_MULTIPLY, <"/">: BINOP_DIVIDE, <"%">: BINOP_MODULO,
  <"+">: BINOP_ADD, <"-">: BINOP_SUBTRACT, <"<<">: BINOP_LEFT_SHIFT,
  <">>">: BINOP_RIGHT_SHIFT, <"&">: BINOP_BITWISE_AND,
  <"^">: BINOP_BITWISE_XOR, <"|">: BINOP_BITWISE_OR, <"<">: BINOP_LESS,
  <">">: BINOP_GREATER, <"<=">: BINOP_LESS_EQUAL,
  <">=">: BINOP_GREATER_EQUAL, <"==">: BINOP_EQUAL,
  <"!=">: BINOP_NOT_EQUAL, <"&&">: BINOP_LOGICAL_AND,
  <"||">: BINOP_LOGICAL_OR
};

static Map _unary_operators = %{
  <"-">: UNOP_MINUS, <"+">: UNOP_PLUS, <"~">: UNOP_BITWISE_NOT,
  <"!">: UNOP_LOGICAL_NOT
};

static Map _scalar_types = %{
  ${%(void)}: "make_void_type()", ${%(int)}: "make_int_type()",
  ${%(char)}: "make_char_type()",
  ${%(unsigned)}: "make_unsigned_int_type()",
  ${%(unsigned int)}: "make_unsigned_int_type()",
  ${%(unsigned char)}: "make_unsigned_char_type()"
};

/** Records the first unsupported construct and returns NULL so every caller
    stops rendering. */
static String _reject(Adapter adapter, String what) {
  if (!adapter.failure)
    adapter.failure = %"unsupported: ${what} at " +
                      %"${adapter.file}:${adapter.line}";
  return NULL;
}

static void _emit(Adapter adapter, String text) {
  if (!adapter.failure) adapter.lines.push(text);
}

/** Submits one segment at the statement position currently being rendered. */
static void _feed(Adapter adapter, String segment) {
  if (!segment) return;
  _emit(adapter, %"  cstar.feed(${segment}, ${adapter.line}, " +
                  %"${adapter.column});");
}

/** Moves the rendered position to the source of one `(at ID NODE)` wrapper. */
static List _locate(Adapter adapter, List node) {
  match (node)
    case %(at ?occurrence ?inner): {
      List where = adapter.compiler.origin_location(occurrence.integer());
      if (where) {
        adapter.line = where.assoc(<line>).integer();
        adapter.column = where.assoc(<column>).integer();
      }
      return inner.list();
    }
  return node;
}

// types

static String _ctype(Adapter adapter, Var declared);

static String _pointers(Adapter adapter, String base, List declarator) {
  foreach (Var star, declarator) {
    if (star !== <"*">)
      return _reject(adapter, %"declarator ${declarator.repr()}");
    base = %"make_pointer_type(${base})";
  }
  return base;
}

static const SymbolSet _storage = %<<static extern inline register auto>>;

/** Renders one type. A single-word type reaches the adapter as the bare
    symbol wherever the parser had nothing to qualify, as in a function
    type's result, so both spellings name the same type here. */
static String _ctype(Adapter adapter, Var declared) {
  List type = declared is <list> ? declared.list() : %($declared);
  while (type && type.car() is <symbol> && _storage.contains(type.car()))
    type = type.cdr();
  if (type && type.car() === <"*">)
    return _pointers(adapter, _ctype(adapter, type.cdr()), %(*));
  Var named;
  if (_scalar_types.try_get(type, &named)) return named.str();
  return _reject(adapter, %"type ${type.repr()}");
}

/** Combines a declaration's base type with one declarator's pointers. */
static String _declared(Adapter adapter, Var type, List declarator) {
  String base = _ctype(adapter, type);
  return base ? _pointers(adapter, base, declarator) : NULL;
}

// expressions

static String _expression(Adapter adapter, Var value);

static String _arguments(Adapter adapter, List args) {
  Array rendered = %[];
  foreach (Var argument, args) {
    String text = _expression(adapter, argument);
    if (!text) return NULL;
    rendered.push(text);
  }
  return rendered.len()
    ? %"(expression []) { ${rendered.join(%", ")} }"
    : %"(expression *) NULL";
}

static String _call(Adapter adapter, List callee, List args, String result) {
  match (callee) {
    case %(expr ((func ?parameters) ?returns)
           (ident (binding ? ?spelling))): {
      String name = spelling.str();
      if (!adapter.earlier.contains(name))
        return _reject(adapter,
          %"call to ${name}, which no earlier verified function defines");
      Array types = %[];
      foreach (Var parameter, parameters.list()) {
        String text = _ctype(adapter, parameter);
        if (!text) return NULL;
        types.push(text);
      }
      String returned = _ctype(adapter, returns);
      String rendered = _arguments(adapter, args);
      if (!returned || !rendered) return NULL;
      String signature = %"make_function_type(${returned}, (ctype []) " +
                         %"{ ${types.join(%", ")} }, ${types.len()})";
      return %"make_call_expr(make_var_expr(\"${name}\", ${signature}), " +
             %"${rendered}, ${args.len()}, ${result})";
    }
  }
  return _reject(adapter, %"indirect call");
}

static String _expression(Adapter adapter, Var value) {
  if (value is not <list>) return _reject(adapter, %"expression");
  List node = value;
  match (node) {
    case %(expr ?type ?inner): {
      String rendered = _ctype(adapter, type);
      if (!rendered) return NULL;
      List body = inner.list();
      match (body) {
        case %(literal ?kind ?spelling):
          return _scalar_types.contains(kind)
            ? %"make_const_expr(${spelling.str()}, ${rendered})"
            : _reject(adapter, %"literal of type ${kind.repr()}");
        case %(ident (binding ? ?spelling)):
          return %"make_var_expr(\"${spelling.str()}\", ${rendered})";
        case %(index ?array ?position): {
          String base = _expression(adapter, array);
          String offset = _expression(adapter, position);
          return base && offset
            ? %"make_index_expr(${base}, ${offset}, ${rendered})" : NULL;
        }
        case %(cast (decl ?target (bindings (bind () ?declarator)))
               ?operand): {
          String into = _declared(adapter, target, declarator.list());
          String source = _expression(adapter, operand);
          return into && source
            ? %"make_cast_expr(${source}, ${into})" : NULL;
        }
        case %(call ?callee (args *args)):
          return _call(adapter, callee.list(), args, rendered);
        case %(op ?operator ?left ?right): {
          Var selected;
          if (!_binary_operators.try_get(operator, &selected))
            return _reject(adapter, %"operator ${operator.repr()}");
          String first = _expression(adapter, left);
          String second = _expression(adapter, right);
          return first && second
            ? %"make_binary_expr(${selected.str()}, ${first}, " +
              %"${second}, ${rendered})" : NULL;
        }
        case %(op ?operator ?operand): {
          String only = _expression(adapter, operand);
          if (!only) return NULL;
          if (operator === <"*">)
            return %"make_deref_expr(${only}, ${rendered})";
          if (operator === <"&">)
            return %"make_addrof_expr(${only}, ${rendered})";
          Var selected;
          if (!_unary_operators.try_get(operator, &selected))
            return _reject(adapter, %"operator ${operator.repr()}");
          return %"make_unary_expr(${selected.str()}, ${only}, ${rendered})";
        }
      }
      return _reject(adapter, %"expression ${body.car().repr()}");
    }
  }
  return _reject(adapter, %"expression ${node.car().repr()}");
}

// annotations

/** Returns the record a `cstar_marker(id)` statement stands for, or NULL
    when the statement is not a marker. */
static List _annotation(Adapter adapter, List node) {
  match (node)
    case %(stmnt (expr ?
           (call (expr ? (ident (binding ? "cstar_marker")))
                 (args (expr ? (literal ? ?spelling)))))): {
      Var record;
      int id = atoi(spelling.str());
      return adapter.annotations.try_get(Var.new(<i32>, id), &record)
        ? record.list() : NULL;
    }
  return NULL;
}

static String _quoted(List texts) {
  Array parts = %[];
  foreach (Var text, texts) parts.push(%"\"${text.str()}\"");
  return parts.join(%", ");
}

static void _feed_annotation(Adapter adapter, List record) {
  match (record) {
    case %(assert ? ?text ? ? ?):
      _feed(adapter,
        %"make_cst_assert(cstar.program_assertion(\"${text.str()}\"), 0)");
    case %(invariant ? ?text ? ? ?):
      _feed(adapter,
        %"make_cst_invariant(cstar.program_assertion(\"${text.str()}\"), 0)");
    case %(invariant_sl ? ?text ? ? ?):
      _feed(adapter,
        %"make_cst_invariant(cstar.assertion(\"${text.str()}\"), 1)");
    case %(proof ? ?step ?args ? ? ?): {
      adapter.arrays = 1;
      _emit(adapter, %"  cstar.${step.str()}(${_quoted(args.list())});");
    }
    case %(helper ? ?name ?args ? ? ?): {
      String arguments = _quoted(args.list());
      _emit(adapter, arguments.len()
        ? %"  ${name.str()}(cstar, ${arguments});"
        : %"  ${name.str()}(cstar);");
    }
  }
}

// statements

static void _statement(Adapter adapter, Var value);

/** Feeds `i++`, `++i`, `i--`, or `--i` written as a whole statement. The
    parser produces these two nodes for those four spellings only. The same
    operator inside an expression stays unsupported, because its place in
    the evaluation order is not part of the admitted subset. */
static void _increment(Adapter adapter, Var operator, Var operand,
                       String position) {
  String rendered = _expression(adapter, operand);
  String step = operator === <"++"> ? %"INCREMENT" : %"DECREMENT";
  if (rendered)
    _feed(adapter, %"make_inc_dec(${rendered}, INCDEC_${step}_${position})");
}

static void _braced(Adapter adapter, Var value) {
  List node = _locate(adapter, value.list());
  if (node && node.car() === <block>) {
    _statement(adapter, node);
    return;
  }
  _feed(adapter, %"make_block_begin()");
  _statement(adapter, node);
  _feed(adapter, %"make_block_end()");
}

static void _declaration(Adapter adapter, Var type, List bindings) {
  foreach (Var declared, bindings) {
    match (declared.list()) {
      case %(op = (bind (binding ? ?spelling) ?declarator) ?initializer): {
        String rendered = _declared(adapter, type, declarator.list());
        String value = _expression(adapter, initializer);
        if (rendered && value)
          _feed(adapter, %"make_var_def_init(\"${spelling.str()}\", " +
                         %"${rendered}, ${value})");
        continue;
      }
      case %(bind (binding ? ?spelling) ?declarator): {
        String rendered = _declared(adapter, type, declarator.list());
        if (rendered)
          _feed(adapter,
            %"make_var_def(\"${spelling.str()}\", ${rendered})");
        continue;
      }
    }
    _reject(adapter, %"declarator ${declared.repr()}");
  }
}

static void _statement(Adapter adapter, Var value) {
  if (adapter.failure) return;
  List node = _locate(adapter, value.list());
  if (!node) return;
  List record = _annotation(adapter, node);
  if (record) {
    _feed_annotation(adapter, record);
    return;
  }
  match (node) {
    case %(empty): return;
    case %(block *items): {
      _feed(adapter, %"make_block_begin()");
      foreach (Var item, items) _statement(adapter, item);
      _feed(adapter, %"make_block_end()");
      return;
    }
    case %(declare ?type (bindings *bindings)): {
      _declaration(adapter, type, bindings);
      return;
    }
    case %(return): {
      _feed(adapter, %"make_return()");
      return;
    }
    case %(return ? ?result): {
      String rendered = _expression(adapter, result);
      if (rendered) _feed(adapter, %"make_return_expr(${rendered})");
      return;
    }
    case %(if ?condition ?consequent ?alternative): {
      String rendered = _expression(adapter, condition);
      if (!rendered) return;
      _feed(adapter, %"make_if_condition(${rendered})");
      _braced(adapter, consequent);
      _feed(adapter, %"make_else()");
      _braced(adapter, alternative);
      return;
    }
    case %(if ?condition ?consequent): {
      String rendered = _expression(adapter, condition);
      if (!rendered) return;
      _feed(adapter, %"make_if_condition(${rendered})");
      _braced(adapter, consequent);
      return;
    }
    case %(while ?condition ?body): {
      String rendered = _expression(adapter, condition);
      if (!rendered) return;
      _feed(adapter, %"make_while_condition(${rendered})");
      _braced(adapter, body);
      return;
    }
    case %(stmnt (expr ? (postfix ?operator ?operand))): {
      _increment(adapter, operator, operand, %"POST");
      return;
    }
    case %(stmnt (expr ? (op (!set ?operator (!or ++ --)) ?operand))): {
      _increment(adapter, operator, operand, %"PRE");
      return;
    }
    case %(stmnt (expr ? (op = ?target ?source))): {
      String left = _expression(adapter, target);
      String right = _expression(adapter, source);
      if (left && right)
        _feed(adapter,
          %"make_assign(${left}, ${right}, ASSIGNOP_ASSIGN)");
      return;
    }
    case %(stmnt ?expression): {
      String rendered = _expression(adapter, expression);
      if (rendered) _feed(adapter, %"make_compute(${rendered})");
      return;
    }
  }
  _reject(adapter, %"statement ${node.car().repr()}");
}

// functions

static void _signature(Adapter adapter, String name, Var returns,
                       List parameters) {
  Array types = %[], names = %[];
  foreach (Var declared, parameters) {
    match (declared.list()) {
      case %(param ?type (bind (binding ? ?spelling) ?declarator)): {
        String rendered = _declared(adapter, type, declarator.list());
        if (!rendered) return;
        types.push(rendered);
        names.push(%"\"${spelling.str()}\"");
        continue;
      }
      case %(param (void) (bind () ())): continue;
    }
    _reject(adapter, %"parameter ${declared.repr()}");
    return;
  }
  String result = _ctype(adapter, returns);
  if (!result) return;
  String type_list = types.len()
    ? %"(ctype []) { ${types.join(%", ")} }" : %"(ctype *) NULL";
  String name_list = names.len()
    ? %"(const char *[]) { ${names.join(%", ")} }" : %"(const char **) NULL";
  _feed(adapter, %"make_function_start(\"${name}\", ${result}, " +
                 %"${type_list}, ${name_list}, ${types.len()})");
}

/** Renders one verified function: ghost parameters, contract, signature,
    and the captured body, whose markers place the annotations. */
void Adapter.function(Adapter adapter, List record, List definition) {
  match (record)
    case %(function ?name ?pre ?post ?ghosts ?file ?line ?column ?captured ?):
    {
      String spelling = name.str();
      adapter.file = file.str();
      adapter.line = line.integer();
      adapter.column = column.integer();
      _emit(adapter, %"static void _verify_${spelling}(Cstar cstar) {");
      String spelled = ghosts.str();
      if (spelled.len()) {
        List ghost_terms = spelled.split(%",");
        Array parsed = %[];
        foreach (Var ghost, ghost_terms)
          parsed.push(%"cstar.term(\"${ghost.str().strip(NULL)}\")");
        _emit(adapter,
          %"  term ghosts[${parsed.len()}] = { ${parsed.join(%", ")} };");
        _feed(adapter,
          %"make_cst_param((type *) NULL, 0, ghosts, ${parsed.len()})");
      }
      _feed(adapter,
        %"make_cst_require(cstar.assertion(\"${pre.str()}\"))");
      _feed(adapter,
        %"make_cst_ensure(cstar.assertion(\"${post.str()}\"))");
      match (definition)
        case %(function ?returns
               (bind ? ((fnmod (params *parameters)))) ?):
          _signature(adapter, spelling, returns, parameters);
      List body = captured.list();
      if (body && body.car() === <block>) body = body.cdr();
      _feed(adapter, %"make_block_begin()");
      foreach (Var item, body) _statement(adapter, item);
      _feed(adapter, %"make_block_end()");
      _feed(adapter, %"make_function_end()");
      _emit(adapter, %"  cstar.complete();");
      _emit(adapter, %"}\n");
      adapter.earlier[spelling] = spelling;
    }
}

/** Opens an adapter over one unit's annotation records. */
Adapter Adapter.new(Compiler compiler, Map annotations) {
  Adapter adapter = Scope.calloc(1, sizeof(struct Adapter));
  adapter.compiler = compiler;
  adapter.lines = %[];
  adapter.annotations = annotations;
  adapter.earlier = %{};
  return adapter;
}

/** Returns the first unsupported construct, or NULL when every rendered
    function stayed inside the admitted subset. */
String Adapter.failure(Adapter adapter) => adapter.failure;

/** Reports whether any rendered function used one of the session's own
    proof steps, all of which are array steps today. */
int Adapter.uses_arrays(Adapter adapter) => adapter.arrays;

/** Returns the rendered function bodies. */
String Adapter.text(Adapter adapter) => adapter.lines.join(%"\n");
