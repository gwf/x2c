/*  conditions.x -- conditional groups and the `#if` evaluator

    A condition holds, fails, or is undecided. An `#if` expression is
    evaluated over `long` after `defined` and the visible macros are
    replaced; any other identifier left in it is undecided rather than 0,
    because a header x2c does not read may define it. */

/* One evaluation of an expanded `#if` expression. */
static typedef struct CppEval {
  CppToken *items;
  size_t count, at;
  Cpp cpp;
  int failed;
} CppEval;

/* A value of an `#if` expression, which is undecided unless `known`. */
static typedef struct CppValue {
  long value;
  int known;
} CppValue;

// directives

/** Applies the directive `token` of the file `path` to `cpp` and returns
    its conditional kind: `<open>`, `<branch>`, `<close>`, or 0 for another
    directive. A conditional opens, changes, or closes a group. Outside
    hidden arms, `#define` and `#undef` change the macro table and an
    `#include` of a file x2c reads applies the macros that file exports.
    Other directives stay for the C compiler.
*/
Symbol Compiler.cpp_directive(Compiler c, Cpp cpp, Token token, String path) {
  String text = token.text;
  Symbol kind = Compiler.preproc_conditional_kind(text);
  if (kind == <open>) _open(c, cpp, token);
  else if (kind == <branch>) _branch(c, cpp, token);
  else if (kind == <close>) _close(cpp);
  else if (!cpp.hidden()) _command(c, cpp, token, path);
  return kind;
}

// conditional groups

static void _open(Compiler c, Cpp cpp, Token token) {
  CppGroup group = {.id = ++cpp.serial};
  if (cpp.hidden()) {
    group.inert = 1;
    group.state = <hidden>;
  }
  else _enter_arm(cpp, &group, _condition(c, cpp, token));
  cpp.groups.push(&group);
}

/* An `#elif` or `#else` starts from the table before the group. */
static void _branch(Compiler c, Cpp cpp, Token token) {
  size_t depth = cpp.groups.len();
  if (!depth) return;
  CppGroup *group = &((CppGroup *) cpp.groups.bytes)[depth - 1];
  group.arm++;
  if (group.inert) return;
  if (group.state == <maybe>) cpp.macros = group.before.copy();
  if (group.taken) group.state = <hidden>;
  else _enter_arm(cpp, group, _condition(c, cpp, token));
}

/* An arm after an undecided one is undecided even when its own condition
   holds. */
static void _enter_arm(Cpp cpp, CppGroup *group, int holds) {
  if (!holds) group.state = <hidden>;
  else if (holds > 0 && !group.doubtful) {
    group.state = <taken>;
    group.taken = 1;
  }
  else {
    group.state = <maybe>;
    group.doubtful = 1;
    if (!group.before) group.before = cpp.macros.copy();
  }
}

/* After an undecided group, every macro one of its arms changed is
   conditionally defined; the enclosing group counts the changes too. */
static void _close(Cpp cpp) {
  CppGroup group;
  if (!cpp.groups.try_pop(&group)) return;
  if (group.state == <maybe>) cpp.macros = group.before;
  if (!group.touched) return;
  foreach (String name in group.touched.keys()) {
    if (group.doubtful) cpp.macros[name] = <cond>;
    _touch(cpp, name);
  }
}

// conditions

/* 1 when the conditional directive `token` holds, 0 when it fails, and
   -1 when x2c cannot decide it. */
static int _condition(Compiler c, Cpp cpp, Token token) {
  Token word = Token.skip_trivia(
    Compiler.scan_directive(Compiler.preproc_directive(token.text)));
  Token rest = Token.skip_trivia(word + 1);
  switch (word.text) {
    case "if": case "elif": return _evaluate(c, cpp, token, rest);
    case "ifdef": case "elifdef": return _defined(cpp, rest);
    case "ifndef": case "elifndef": return _negate(_defined(cpp, rest));
    case "else": return 1;
  }
  return -1;
}

/* Whether the name at `token` is defined. */
static int _defined(Cpp cpp, Token token) {
  if (!token.is_word()) return -1;
  Var value = cpp.macros[token.text];
  if (value is <list>) return 1;
  if (value == <undef> || (value is void && _never_defined(token.text)))
    return 0;
  return -1;
}

static int _negate(int holds) => holds < 0 ? holds : !holds;

/* x2c output is compiled as C by a GNU-style compiler, so `__cplusplus` and
   `_MSC_VER` are never defined, and a compiler built for a host other than
   Windows never targets it. */
static int _never_defined(String name) {
  if (name == "__cplusplus" || name == "_MSC_VER") return 1;
#if defined(_WIN32) || defined(__CYGWIN__)
  return 0;
#else
  return name == "_WIN32" || name == "_WIN64" || name == "__CYGWIN__";
#endif
}

// expressions

/* Evaluates the `#if` expression from `first`: `defined` is replaced
   first, then the visible macros, and the rest is evaluated. */
static int _evaluate(Compiler c, Cpp cpp, Token site, Token first) {
  Block items = auto Block.new(sizeof(CppToken));
  for (Token token = first; token.type != <eof>;
       token = Token.skip_trivia(token + 1))
    token = _operand(cpp, items, token);
  Block expanded = _expand_items(c, cpp, items, site);
  CppEval e = {
    .items = expanded.bytes, .count = expanded.len(), .cpp = cpp};
  CppValue result = _ternary(e);
  if (e.failed || e.at != e.count || !result.known) return -1;
  return result.value != 0;
}

/* Adds the token at `token`, or the value of the `defined` operator that
   begins there, to `items`. Returns the operand's last token. */
static Token _operand(Cpp cpp, Block items, Token token) {
  CppToken item = {.token = *token};
  if (token.text != "defined") {
    items.push(&item);
    return token;
  }
  Token name = Token.skip_trivia(token + 1), last = name;
  if (name.type == <(>) {
    name = Token.skip_trivia(name + 1);
    last = name.type == <eof> ? name : Token.skip_trivia(name + 1);
  }
  int holds = _defined(cpp, name);
  item.token.type = holds < 0 ? <unknown> : <lit-int>;
  item.token.text = holds > 0 ? "1" : "0";
  items.push(&item);
  return last.type == <eof> ? last - 1 : last;
}

static CppValue _ternary(CppEval &e) {
  CppValue test = _binary(e, 1);
  if (!_take(e, "?")) return test;
  CppValue yes = _ternary(e);
  if (!_take(e, ":")) e.failed = 1;
  CppValue no = _ternary(e);
  if (test.known) return test.value ? yes : no;
  if (yes.known && no.known && yes.value == no.value) return yes;
  return (CppValue) {0};
}

/* Binary operators from `||` at level 1 to the multiplicative ones at 10,
   each level left-associative. */
static CppValue _binary(CppEval &e, int level) {
  if (level > 10) return _unary(e);
  CppValue left = _binary(e, level + 1);
  while (e.at < e.count && _level(_text(e)) == level) {
    String op = _text(e);
    e.at++;
    left = _apply(op, left, _binary(e, level + 1));
  }
  return left;
}

static int _level(String op) {
  switch (op) {
    case "||": return 1;
    case "&&": return 2;
    case "|": return 3;
    case "^": return 4;
    case "&": return 5;
    case "==": case "!=": return 6;
    case "<": case ">": case "<=": case ">=": return 7;
    case "<<": case ">>": return 8;
    case "+": case "-": return 9;
    case "*": case "/": case "%": return 10;
  }
  return 0;
}

/* `&&` and `||` decide from one known side as C's short circuit does. */
static CppValue _apply(String op, CppValue left, CppValue right) {
  if (op == "&&") return _logical(left, right, 0);
  if (op == "||") return _logical(left, right, 1);
  if (!left.known || !right.known) return (CppValue) {0};
  long a = left.value, b = right.value;
  switch (op) {
    case "|": return _known(a | b);
    case "^": return _known(a ^ b);
    case "&": return _known(a & b);
    case "==": return _known(a == b);
    case "!=": return _known(a != b);
    case "<": return _known(a < b);
    case ">": return _known(a > b);
    case "<=": return _known(a <= b);
    case ">=": return _known(a >= b);
    case "<<": return _known(a << (b & 63));
    case ">>": return _known(a >> (b & 63));
    case "+": return _known(a + b);
    case "-": return _known(a - b);
    case "*": return _known(a * b);
    case "/": return b ? _known(a / b) : (CppValue) {0};
    case "%": return b ? _known(a % b) : (CppValue) {0};
  }
  return (CppValue) {0};
}

/* `decisive` is the value of one side that decides the result. */
static CppValue _logical(CppValue left, CppValue right, int decisive) {
  if ((left.known && !left.value == !decisive) ||
      (right.known && !right.value == !decisive))
    return _known(decisive);
  if (left.known && right.known) return _known(!decisive);
  return (CppValue) {0};
}

static CppValue _unary(CppEval &e) {
  if (e.at >= e.count) {
    e.failed = 1;
    return (CppValue) {0};
  }
  String op = _text(e);
  if (op != "!" && op != "-" && op != "+" && op != "~") return _primary(e);
  e.at++;
  CppValue operand = _unary(e);
  if (!operand.known) return operand;
  switch (op) {
    case "!": return _known(!operand.value);
    case "-": return _known(-operand.value);
    case "~": return _known(~operand.value);
  }
  return operand;
}

/* A name still unexpanded is 0 in C. x2c knows that only for a name it
   sees defined or undefined, or one never defined. */
static CppValue _primary(CppEval &e) {
  Token token = &e.items[e.at++].token;
  switch (token.type) {
    case <(>: {
      CppValue inner = _ternary(e);
      if (!_take(e, ")")) e.failed = 1;
      return inner;
    }
    case <lit-int>: return _number(e, token.text);
    case <lit-char>: return _character(token.text);
    case <unknown>: return (CppValue) {0};
  }
  if (!token.is_word()) e.failed = 1;
  else {
    Var value = e.cpp.macros[token.text];
    if (value is <list> || value == <undef> ||
        (value is void && _never_defined(token.text)))
      return _known(0);
  }
  return (CppValue) {0};
}

static CppValue _number(CppEval &e, String text) {
  char *end = NULL;
  long value = (long) strtoull(text, &end, 0);
  while (*end && strchr("uUlL", *end)) end++;
  if (*end) e.failed = 1;
  return _known(value);
}

static CppValue _character(String text) {
  String inner = text[1:-1].unescape();
  return _known(inner.len() ? (unsigned char) inner[0] : 0);
}

static CppValue _known(long value) => (CppValue) {.value = value, .known = 1};

static String _text(CppEval &e) => e.items[e.at].token.text;

static int _take(CppEval &e, String text) {
  if (e.at >= e.count || _text(e) != text) return 0;
  e.at++;
  return 1;
}
