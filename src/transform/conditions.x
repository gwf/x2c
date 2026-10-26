/*  conditions.x -- pattern conditions and their successful continuations */

/* Only positive conjunction and grouping export captures. Other operators
   consume each pattern test as an ordinary int expression. */
module int _pattern_condition(List expression) {
  match (expression) {
    case %(expr ? (matches ? ? ? ?)): return 1;
    case %(expr ? (parens ?inner)): return _pattern_condition(inner);
    case %(expr ? (op && ?left ?right)):
      return _pattern_condition(left) || _pattern_condition(right);
  }
  return 0;
}

/* Places the continuation inside the typed-capture scope when present. */
static List _condition_body(List declarations, List body) {
  match (declarations)
    case %(block *before (block *native)):
      return %(block @before (block @native $body));
  return declarations.append($(body));
}

/* A successful pattern enters its own lexical scope. There is no switch
   or loop around the user's continuation, so its control transfers keep
   their original targets. */
module List _condition_then(List condition, List body) {
  match (condition) {
    case %(expr ? (matches ?subject ?pattern ?declarations ?)):
      return %(match-if $subject
        ($pattern $(_condition_body(declarations, body))));
    case %(expr ? (parens ?inner)):
      return _condition_then(inner, body);
    case %(expr ? (op && ?left ?right)):
      return _condition_then(left, _condition_then(right, body));
  }
  return %(if $condition $body);
}

static List _condition_flag(Compiler c, List &value) {
  List binding = c.sym.introduce(c.fresh_name("condition"));
  value = %(expr (int) (ident $binding));
  return %(declare (int) (bindings
    (op = (bind $binding ()) (expr (int) (literal (int) "0")))));
}

static List _condition_success(List value) =>
  %(stmnt (expr (int) (op = $value (expr (int) (literal (int) "1")))));

/* One false arm remains outside the positive scopes, even when several
   tests can fail. */
module List _condition_else(Compiler c, List condition, List yes, List no) {
  List value = NULL;
  List declaration = _condition_flag(c, value);
  List success = %(block $(_condition_success(value)) $yes);
  return %(block $declaration $(_condition_then(condition, success))
    (if (expr (int) (op ! $value)) $no));
}

/* A predicate used as a value retains short circuit and local captures. */
module List _condition_value(Compiler c, List condition) {
  List value = NULL;
  List declaration = _condition_flag(c, value);
  return %(expr (int) (parens (block $declaration
    $(_condition_then(condition, _condition_success(value)))
    (stmnt $value))));
}
