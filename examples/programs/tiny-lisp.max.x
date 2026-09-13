/*  tiny-lisp.max.x -- a small Lisp built from x2c values

    Copyright (c) 2026 Gary William Flake

    Programs and data share two immutable types: String atoms and proper
    Lists. The reader and evaluator below define the language; x2c supplies
    its values, containers, pattern matching, and memory ownership. None of
    the interpreter uses x2c's Lisp evaluator.
*/

/* Build and run the arithmetic example:

     x2c build examples/programs/tiny-lisp.max.x --output /tmp/tiny-lisp-max
     /tmp/tiny-lisp-max < examples/data/tiny-lisp.slp

   The example defines arithmetic and both conversions in this Lisp:

     (decimal (fact (unary '(4))))                ; (2 4)
     (decimal (mul (unary '(1 2)) (unary '(3))))   ; (3 6)

   There are no numeric primitives. Unary 24 is a list of 24 t's; decimal
   notation is a list of digit atoms. Recursion, conditional evaluation,
   and unbounded list construction supply the computational model, subject
   to the host's available memory and C call stack.
*/

// One lookahead byte belongs to the reader. Keep it as int to preserve EOF;
// initial whitespace lets the same skip operation begin and resume input.
static int lookahead = ' ';

// Reader and evaluation errors share one diagnostic and stop the program.
// The Var result lets a failing expression occupy any evaluator return site.
static Var _fail(void) {
  fputs("error\n", stderr);
  exit(1);
}

static void _next(void) {
  lookahead = getchar();
}

// A semicolon ends an atom and starts a comment, even without a space.
static void _skip(void) {
  for (;;) {
    if (lookahead != EOF && strchr(" \t\r\n", lookahead)) _next();
    else if (lookahead == ';')
      while (lookahead != EOF && lookahead != '\n') _next();
    else
      return;
  }
}

/* The grammar has atoms, parenthesized lists, and the quote abbreviation.
   A dot is an ordinary atom; there are no dotted pairs or string syntax.
   Return with the first byte after the expression still in lookahead.
   EOF is legal between top-level expressions, but not where one is owed. */
static Var _read(void) {
  _skip();
  if (lookahead == EOF || lookahead == ')') return _fail();

  if (lookahead == '\'') {
    _next();
    // The Var argument promotes the C literal to an x2c String atom.
    return cons("quote", cons(_read(), NULL));
  }

  if (lookahead == '(') {
    _next();
    // Append in source order, then freeze as an immutable proper List.
    Array items = $auto(%[]);
    for (_skip(); lookahead != ')'; _skip()) items.push(_read());
    _next();
    return items.list();
  }

  /* Atom spellings are arbitrary-length Strings, including numeric text.
     Interning preserves each complete spelling and shares repeated names.
     str() interns the contents before $auto frees the temporary Buffer. */
  Buffer spelling = $auto(Buffer.new(0));
  do {
    spelling.write_char(lookahead);
    _next();
  } while (lookahead != EOF && !strchr(" \t\r\n()';", lookahead));
  return spelling.str();
}

/* A Map binds atom names to values. Only () is false; every nonempty list
   and every atom is true. An atom must be quoted or bound to be evaluated.

   List literals below describe match patterns, not executable x2c Lisp.
   ?name captures one value, ?(Type name) also checks its type, and *args
   captures the remaining list. Fixed patterns also enforce each form's
   arity; a malformed form eventually reaches the common error path. */
static Var _eval(Var expression, Map environment) {
  if (expression is String) {
    if (expression in environment) return environment[expression];
    return _fail();
  }
  if (expression == %()) return expression;

  match (expression) {
    case %("quote" ?value):
      return value;

    // Evaluate exactly one branch. The other may contain an unbound name,
    // side effects, or a recursive call that must never run.
    case %("if" ?condition ?consequent ?alternative):
      return _eval(
        _eval(condition, environment) != %() ? consequent : alternative,
        environment);

    // A function is its source list, with no captured environment. Parameter
    // names are checked when it is called; quoted lambda lists work too.
    case %("lambda" ?(List parameters) ?body):
      return expression;

    // Definitions affect this call's environment and return the bound name.
    case %("def" ?(String name) ?value): {
      environment[name] = _eval(value, environment);
      return name;
    }

    case %(?operation ?argument)
      if (operation == "car" || operation == "cdr"): {
      Var value = _eval(argument, environment);
      if (value is not List) return _fail();
      List list = value;
      if (operation == "cdr") return list.cdr();
      if (list) return list.car();
      return %();
    }

    // A cons tail must be a List: every list in this language is proper.
    // Separate initializers preserve left-to-right operand evaluation.
    case %("cons" ?head ?tail): {
      Var first = _eval(head, environment), rest = _eval(tail, environment);
      if (rest is not List) return _fail();
      return cons(first, rest);
    }

    // Strings and Lists are canonical immutable values, so their identities
    // compare content. Equality also works on independently built lists.
    case %("eq" ?left ?right): {
      Var first = _eval(left, environment), second = _eval(right, environment);
      if (first == second) return "t";
      return %();
    }

    // The operator is an expression: a name, lambda, or computed function.
    case %(?function *arguments):
      match (_eval(function, environment)) {
        case %("lambda" ?(List parameters) ?body): {
          if (parameters.len() != arguments.len()) return _fail();

          /* Evaluate every actual argument in the caller before installing
             parameters. Copy the environment afterward: an argument's def
             must be visible both to later arguments and to the body. */
          Array values = $auto(%[]);
          foreach (Var argument, arguments)
            values.push(_eval(argument, environment));

          /* Dynamic scope starts from the caller's current bindings. A
             shallow copy isolates local definitions while sharing immutable
             values. Later duplicate parameter names replace earlier ones. */
          Map local = $auto(environment.copy());
          foreach (Var value, values) {
            if (parameters.car() is not String) return _fail();
            local[parameters.car()] = value;
            parameters = parameters.cdr();
          }
          return _eval(body, local);
        }
      }
  }
  return _fail();
}

int main(void) {
  /* The outer scope owns the mutable top-level environment. $auto releases
     temporary Buffers, Arrays, and call Maps at their lexical scope exits.
     Strings and Lists belong to the default interning pool until process
     shutdown, so returned values outlive those temporary containers. There
     is no tracing collector or per-expression pool to invalidate bindings. */
  $scope() {
    Map environment = %{};
    for (_skip(); lookahead != EOF; _skip())
      puts(_eval(_read(), environment).str());
  }
  return 0;
}
