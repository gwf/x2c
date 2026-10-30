/*  expressions.x -- C expressions, calls and literal values */

/* Writes each of `tests` with the C operator `op` between them, each
   grouped as that operator's right operand needs. */
module void _joined(Emitter &e, List tests, Symbol op) {
  int first = 1;
  foreach (Var test in tests) {
    if (!first) _put(e, op);
    first = 0;
    _operand(e, test, _right_operand_level(op));
  }
}

// expressions

module void _postfix(Emitter &e, Symbol operator, Var argument) {
  _operand(e, argument, EMIT_POSTFIX);
  _put(e, operator);
}

module void _generic(Emitter &e, Var control, List associations) {
  _put(e, "_Generic(");
  _node(e, control);
  _put(e, ", ");
  int first = 1;
  foreach (List association in associations) {
    if (!first) _put(e, ", ");
    first = 0;
    match (association) {
      case %(association default ?value): {
        _put(e, "default");
        _put(e, ":");
        _node(e, value);
      }
      case %(association ?type ?value): {
        _put_all(e, _semantic_type(e, type));
        _put(e, ":");
        _node(e, value);
      }
    }
  }
  _put(e, ")");
}

module void _unary(Emitter &e, Symbol operator, Var argument) {
  _put(e, operator);
  _operand(e, argument, EMIT_UNARY);
}

module void _binary(
  Emitter &e, Symbol operator, Var left, Var right) {
  if (left ~= %(expr ? (op *))) {
    _op_spine(e, operator, left, right);
    return;
  }
  _operand(e, left, _left_operand_level(operator));
  _put(e, operator);
  _operand(e, right, _right_operand_level(operator));
}

/* A left-leaning chain nests one (expr (op ...)) level per source term;
   walk the spine iteratively, so a long chain spends no recursion on its
   left operands. The walk stops where the nested operator needs
   parentheses, leaving that operand to the ordinary recursion. */
static void _op_spine(Emitter &e, Symbol operator, Var left, Var right) {
  Array operators = auto [];
  Array rights = auto [];
  Var op_item = operator, left_item = left, right_item = right;
  int level = 0;
  for (;;) {
    operators.push(op_item);
    rights.push(right_item);
    level = _left_operand_level(op_item);
    int deeper = 0;
    if (_emitted_precedence(left_item) >= level &&
        left_item ~= %(expr ? (op ?next_operator ?next_left ?next_right))) {
      op_item = next_operator;
      left_item = next_left;
      right_item = next_right;
      deeper = 1;
    }
    if (!deeper) break;
  }
  _operand(e, left_item, level);
  for (int i = (int) operators.len() - 1; i >= 0; i--) {
    Symbol binary = operators[i];
    _put(e, binary);
    _operand(e, rights[i], _right_operand_level(binary));
  }
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

module void _ident(Emitter &e, Var binding) {
  /* A template's free name in a declared type, such as an array size,
     keeps the spelling it lands with. */
  if (binding ~= %((!or binding-name binding-global) ?(String spelling))) {
    _put(e, spelling);
    return;
  }
  Var pointer;
  if (e.static_objects && e.static_objects.try_get(binding, pointer)) {
    _put(e, "(*");
    _put(e, pointer);
    _put(e, ")");
    return;
  }
  _node(e, binding);
}

// calls

module void _call(Emitter &e, Var function, Var arguments) {
  if (_match_site_call(e, function, arguments)) return;
  _operand(e, function, EMIT_POSTFIX);
  _put(e, "(");
  _node(e, arguments);
  _put(e, ")");
}

/* Emits `node`, in parentheses when it binds less tightly than `level`. A
   node already stored as a List enters its own dispatch directly. Wrapping
   it in a one-element sequence would emit the same tokens through two more
   frames per operand, which the pinned chain stack budgets cannot spend. */
module void _operand(Emitter &e, Var node, int level) {
  int grouped = _emitted_precedence(node) < level;
  if (grouped) _put(e, "(");
  if (node is <list> && !node.is_nil()) _emit(e, node);
  else _emit(e, $(node));
  if (grouped) _put(e, ")");
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
    case %(m-all *):             return _operator_precedence(<"&&">);
    case %(m-any *):             return _operator_precedence(<"||">);
    case %(m-bits *):            return _operator_precedence(<"==">);
  }
  return EMIT_PRIMARY;
}

static int _operator_precedence(Symbol operator) {
  if (operator == <.> || operator == <"->">) return EMIT_POSTFIX;
  if (operator.is_assignment_op()) return EMIT_ASSIGNMENT;
  int level = operator.binary_precedence();
  return level ? EMIT_CONDITIONAL + level : 0;
}

/* A source-literal pattern gets its own process-lifetime plan site, which
   retains a borrowable pattern's plan. Computed patterns use the ordinary
   entry's active plan cache: admitted canonical patterns reuse plans; other
   patterns need transient plans. Only a direct global function binding
   identifies a runtime operation. Writes the call and returns 1, or returns
   0 for other calls or computed patterns. */
static int _match_site_call(Emitter &e, Var function, Var arguments) {
  List binding = NULL;
  while (!binding && function is <list>) match (function) {
    case %(expr ? (parens ?inner)): function = inner;
    case %(expr ? (ident ?target)): binding = target;
    default: return 0;
  }
  String name = Ast.binding_spelling(binding);
  String entry = _match_site_entry(name);
  if (!entry) return 0;
  Type type = NULL;
  List global = e.c.sym.resolve_global($(name), type);
  if (!global || global != binding || !type.is_function())
    return 0;
  List args = arguments;
  if (args ~= %(args ? ?pattern *) && pattern is <list> &&
      e.match_pattern_is_static(pattern)) {
    String site = e.fresh_name("match_site");
    _put_all(
      e, %("({ static MatchCaptureSite " $site ";" $entry "(&" $site ","));
    _node(e, arguments);
    _put(e, "); })");
    return 1;
  }
  return 0;
}

/* Each `List_` matcher has an `x2c_match_site_` entry of the same name. */
static String _match_site_entry(String name) =>
  name && name in %("List_match" "List_try_match" "List_search"
                    "List_try_search" "List_match_replace"
                    "List_try_match_replace" "List_search_replace")
    ? "x2c_match_site_" + name[5:] : NULL;

// literals

module void _literal(Emitter &e, List ast) {
  (List type, String text, Var value) = ast.cdr();
  if (type === %("Var") && text == "void") {
    _put(e, "((void) 0, Void)");
    return;
  }
  if (type === %("String")) {
    _put(e, "String_new");
    _put(e, "(");
    _put(e, %"\"$(text.escape())\"");
    _put(e, ")");
    return;
  }
  if (type === %("Symbol")) {
    Symbol symbol = value;
    text = %"$((long) symbol)";
  }
  if (type === %("Atom")) {
    _put(e, _atom_intern(text));
    return;
  }
  Type numeric = type;
  if (text[0] == '-') {
    unsigned long long magnitude;
    if (numeric.integer_literal_magnitude(String.new(text + 1), magnitude)) {
      unsigned long long limit = 0;
      String suffix = "";
      switch (numeric.scalar_tag()) {
        case <i32>: limit = INT_MAX; break;
        case <long>: limit = LONG_MAX; suffix = "L"; break;
        case <llong>: limit = LLONG_MAX; suffix = "LL"; break;
      }
      // A signed decimal spelling keeps C from negating an unsigned type.
      if (limit && magnitude == limit + 1)
        text = %"(-$limit$suffix - 1$suffix)";
      else if (limit) text = %"-$magnitude$suffix";
    }
  }
  // C has no `0o` prefix; its octal spelling is a bare leading zero.
  int digits = text[0] == '-' || text[0] == '+';
  if (text[digits] == '0' &&
      (text[digits + 1] == 'o' || text[digits + 1] == 'O'))
    text = text[:digits] + "0" + String.new(text + digits + 2);
  _put(e, text);
}

static String _atom_intern(String spelling) {
  String text = %"\"$(spelling.escape())\"";
  Atom atom = Atom.intern(spelling);
  if (atom is <symbol>) return %"Symbol_var(Symbol_new($text))";
  return %"Atom_intern(String_new($text))";
}

module void _args(Emitter &e, List ast) {
  int first = 1;
  foreach (List argument in ast.cdr()) {
    if (!first) _put(e, ", ");
    first = 0;
    int grouped = argument ~= %(expr ? (commas *));
    if (grouped) _put(e, "(");
    _emit(e, argument);
    if (grouped) _put(e, ")");
  }
}
