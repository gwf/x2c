/*  expressions.x -- C expressions, calls and literal values */

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
module List _operand(Emitter &e, Var node, int level) {
  List code = node is <list> && !node.is_nil()
            ? _emit(e, node) : _emit(e, $(node));
  if (_emitted_precedence(node) < level) return _parens(code);
  return code;
}

/* A left-leaning chain nests one (expr (op ...)) level per source term;
   walk the spine and build the token stream iteratively, folding from the
   right so each emitted piece is copied once. A separate function keeps the
   spine arrays out of _emit's frame on every other recursion path. The walk
   stops where the nested operator needs parentheses, leaving that operand to
   the ordinary recursion. */
static List _op_spine(Emitter &e, Var operator, Var left, Var right) {
  Array operators = auto [];
  Array rights = auto [];
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
  List result = _operand(e, left_item, level);
  Array pieces = auto [];
  for (int i = (int) operators.len() - 1; i >= 0; i--) {
    Symbol binary = operators[i];
    pieces.push(operators[i]);
    pieces.push(_operand(e, rights[i], _right_operand_level(binary)));
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

module List _postfix(Emitter &e, Symbol operator, Var argument) {
  List c_arg = _operand(e, argument, EMIT_POSTFIX);
  return $(@c_arg, operator);
}

module List _generic(Emitter &e, Var control, List associations) {
  List c_control = _emit(e, $(control));
  Array rows = [];
  foreach (List association in associations) match (association) {
    case %(association default ?value):
      rows.push(%("default" ":" @(_emit(e, $(value)))));
    case %(association ?type ?value):
      rows.push(%(@(_semantic_type(e, type)) ":" @(_emit(e, $(value)))));
  }
  List c_rows = _commas(rows.list_free());
  return %("_Generic(" @c_control ", " @c_rows ")");
}

module List _unary(Emitter &e, Symbol operator, Var argument) {
  List c_arg = _operand(e, argument, EMIT_UNARY);
  return $(operator, @c_arg);
}

module List _binary(
  Emitter &e, Symbol operator, Var left, Var right) {
  match (left)
    case %(expr ? (op *)): return _op_spine(e, operator, left, right);
  Symbol binary = operator;
  return $(
    @(_operand(e, left, _left_operand_level(binary))), operator,
    @(_operand(e, right, _right_operand_level(binary))));
}

module List _ident(Emitter &e, Var binding) {
  /* A template's free name in a declared type, such as an array size,
     keeps the spelling it lands with. */
  match (binding)
    case %((!or binding-name binding-global) ?(String spelling)):
      return $(spelling);
  Var pointer;
  if (e.static_objects && e.static_objects.try_get(binding, pointer))
    return %("(*" $pointer ")");
  return _emit(e, $(binding));
}

// calls

module List _call(Emitter &e, Var function, Var arguments) {
  List site_call = _match_site_call(e, function, arguments);
  if (site_call) return site_call;
  return %(@(_operand(e, function, EMIT_POSTFIX)) "("
           @(_emit(e, $(arguments))) ")");
}

/* A source-literal pattern is the same value on every call, so the call gets
   its own process-lifetime plan site and prepares once. A computed pattern
   keeps the ordinary entry, which prepares one plan per call. Only a direct
   global function binding identifies a runtime operation. Returns NULL
   when the call is not one of those operations or its pattern is computed. */
static List _match_site_call(Emitter &e, Var function, Var arguments) {
  List binding = NULL;
  while (!binding && function is <list>) match (function) {
    case %(expr ? (parens ?inner)): function = inner;
    case %(expr ? (ident ?target)): binding = target;
    default: return NULL;
  }
  String name = Ast.binding_spelling(binding);
  String entry = _match_site_entry(name);
  if (!entry) return NULL;
  Type type = NULL;
  List global = e.c.sym.resolve_global($(name), type);
  if (!global || global != binding || !type.is_function())
    return NULL;
  List args = arguments;
  match (args)
    case %(args ? ?pattern *): {
      if (pattern is not <list> ||
          !e.match_pattern_is_static(pattern))
        return NULL;
      String site = e.fresh_name("match_site");
      List c_args = _emit(e, $(arguments));
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

// literals

module List _literal(Emitter &e, List ast) {
  (List type, String text, Var value) = ast.cdr();
  if (type === %("Var") && text == "void") return %("((void) 0, Void)");
  if (type === %("String")) {
    text = %"\"$(text.escape())\"";
    return %("String_new" "(" $text ")");
  }
  if (type === %("Symbol")) {
    Symbol symbol = value;
    text = %"$((long) symbol)";
  }
  if (type === %("Atom")) return _atom_intern(text);
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
  return $(text);
}

static List _atom_intern(String spelling) {
  String text = %"\"$(spelling.escape())\"";
  Atom atom = Atom.intern(spelling);
  if (atom is <symbol>) return %( "Symbol_var(Symbol_new($text))" );
  return %( "Atom_intern(String_new($text))" );
}

module List _args(Emitter &e, List ast) {
  Array result = [];
  int first = 1;
  foreach (List argument in ast.cdr()) {
    List emitted = _emit(e, argument);
    match (argument) case %(expr ? (commas *)): emitted = _parens(emitted);
    if (!first) result.push(", ");
    result.push(emitted);
    first = 0;
  }
  return result.list_free();
}
