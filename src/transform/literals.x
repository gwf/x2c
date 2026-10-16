/*  literals.x -- AST transformation literals */

module List _ordered_raise(
  Compiler c, List cause, List arguments) {
  Array values = [cause], orders = $auto([_part_order(c, cause)]);
  foreach (List argument, arguments) {
    values.push(argument);
    orders.push(_part_order(c, argument));
  }
  List declarations = _ordered_parts(c, values, orders);
  List parts = values.list_free();
  List raised = %(raise ${parts.car()} (args @{parts.cdr()}));
  return declarations ? %(block @declarations $raised) : raised;
}

// collection literals

/* A collection literal lowers through the literal rule for its head. The
   constructor call that rule returns receives the literal's parts as its
   `Var` arguments, or as C values with no x2c type, which pass as `Var`;
   they keep their source order. */
module Ast _collection_literal(Compiler c, Ast ast, Symbol tag) {
  int map = tag == <map> || tag == <vmap>;
  Type type = map ? %("Map") : %("Array");
  Symbol head = map ? <map> : <array>;
  List lowered = _shipped_lowering(
    c, <literal>, head, %(expr $type ($head @{ast.cdr()})), <expression>,
    type, %"${type.repr()} literal");
  match (lowered) case %(expr ? (call ?callee (args *arguments))): {
    Array values = $auto([]), orders = $auto([]);
    foreach (List argument, arguments) {
      Type passed = argument.cadr();
      values.push(argument);
      orders.push(!passed || passed == %("Var") ? _part_order(c, argument) : 0);
    }
    List declarations = _ordered_parts(c, values, orders);
    if (declarations) {
      List call = %(call $callee (args @{values.list()}));
      return _step(c, _ordered(declarations, type, call));
    }
  }
  return lowered.caddr();
}

static List _to_list(Compiler c, List expr) =>
  c.convert_expression(expr, %("List"));

static List _spliced(Compiler c, List expr) {
  if (c.sym.is_var_type(expr.cadr()))
    return %(expr ("List") (call "Var_list_payload" (args $expr)));
  return _to_list(c, expr);
}

/* literal order

   A literal evaluates its parts once each, left to right, though C leaves
   the order of its constructor's arguments unspecified. Once two or more
   parts read state, each part that reads state, through the last one that
   may change state, moves into a temporary. A part's order is 0 when it is
   constant, 1 when it only reads state, and 2 when it may change state. A
   builtin boxer or scalar formatter reads what its argument reads. Custom
   converters and dynamic nested literal construction may change state. */
static int _part_order(Compiler c, Var part) {
  if (part is not <list>) return 0;
  List node = part;
  match (node) {
    case %(!or (cache ?) (literal *) (nil)): return 0;
    case %(expr () (ident ?)): return 2;
    case $source_identifier_content(%(?)): return 1;
    case %(cons ?head ?tail):
      return _part_order(c, head) || _part_order(c, tail) ? 2 : 0;
    case %(expr ? (call ? (args ?argument))):
      return c.is_builtin_converter_call(node)
        ? _part_order(c, argument) : 2;
    case %(!or (expr ? ?inner) (cast ? ?inner) ${$grouped(?inner)}):
      return _part_order(c, inner);
    case $source_operator_content(%((!or . (!quote ->)) ?inner ?)): {
      int order = _part_order(c, inner);
      return order > 1 ? order : 1;
    }
  }
  return 2;
}

/* The number of leading parts that move, or zero. */
static int _ordered_count(Array orders) {
  int reads = 0, count = 0;
  for (int i = 0; i < orders.len(); i++) {
    int order = orders[i];
    if (order) reads++;
    if (order > 1) count = i + 1;
  }
  return reads < 2 ? 0 : count;
}

/* Moves the parts that need it into temporaries and returns their
   declarations, or NULL when the parts stay in place. */
static List _ordered_parts(Compiler c, Array values, Array orders) {
  int count = _ordered_count(orders);
  if (!count) return NULL;
  Array declarations = [];
  for (int i = 0; i < count; i++)
    if ((int) orders[i])
      values[i] = _sequenced(
        c, _passed_as(values[i], %("Var")), "literal_part", declarations);
  return declarations.list_free();
}

static List _ordered(List declarations, Type type, List content) =>
  declarations ? _statement_expression(declarations, %(expr $type $content))
               : content;

/* A List chain's parts are its cons heads and spliced Lists in source
   order, then its final tail. Convert before classifying each part, so an
   implicit custom converter participates in the same ordering as a call. */
module List _ordered_list(Compiler c, List chain) {
  Array kinds = $auto([]), values = $auto([]), orders = $auto([]);
  List node = chain;
  int spliced = 0;
  for (List cell = _list_cell(node); cell; cell = _list_cell(node)) {
    (Symbol kind, List part, List rest) = cell;
    if (kind != <cons>) spliced = 1;
    List value = kind == <cons> ? _to_var(c, part)
      : _passed_as(_spliced(c, part), %("List"));
    value = _step(c, value);
    kinds.push(kind);
    values.push(value);
    orders.push(_part_order(c, value));
    node = rest;
  }
  int counted = !spliced && node.match(%(nil));
  node = _step(c, _passed_as(_to_list(c, node), %("List")));
  kinds.push(<nil>);
  values.push(node);
  orders.push(_part_order(c, node));
  List declarations = _ordered_parts(c, values, orders);
  List rebuilt = values.take_last();
  if (counted && values.len() > 128)
    return _ordered(declarations, %("List"), _list_n(c, values));
  for (int i = (int) values.len() - 1; i >= 0; i--)
    rebuilt = %(expr ("List") (${kinds[i]} ${values[i]} $rebuilt));
  return _ordered(declarations, %("List"), rebuilt.caddr());
}

/* A chain of more than 128 cons cells is one `List.list_n` call, which keeps
   nested cons calls below host-C bracket-depth limits. */
static List _list_n(Compiler c, Array values) {
  String count = %"${values.len()}U";
  Type signature = NULL;
  List binding = c.sym.reference(%("List_list_n"), signature);
  return %(call (expr $signature (ident $binding))
    (args (expr (unsigned) (literal (unsigned) $count)) @{values.list()}));
}

static List _list_cell(List node) {
  match (node) {
    case %((!or cons append) ? ?): return node;
    case %(expr ? (!set ?cell ((!or cons append) ? ?))): return cell;
  }
  return NULL;
}

// interpolated strings

/* An interpolated String lowers through the literal rule for `segments`,
   each insertion converted to `String` as the parser converts its own:
   constructed syntax that arrives typed is not resolved again. The parts of
   the List chain the rule joins move ahead of the whole join when they
   move. A constructed String of one constant text is already the whole
   string: it reuses the parsed literal's cache slot. Raise details are
   excluded: their cache slots would fill inside _file_init_ constructors,
   where re-entrant string-pool bootstrap can hand back NULL Strings. */
module Ast _interpolation(Compiler c, Ast ast) {
  match (ast)
    case $source_string_content(
        %((segexp (expr ("String") (literal ("String") ?text))))):
      if (!c.runtime_literals)
        return c.cache(%(string (expr ("String") (literal ("String") $text))));
  Array rows = [];
  foreach (List row, ast.cdr()) match (row) {
    case %((!set ?tag (!or segvar segexp)) ?value):
      rows.push(%($tag ${c.convert_segment_to_string(value)}));
    default: rows.push(row);
  }
  List source = source_string_content(rows.list_free());
  List lowered = _shipped_lowering(
    c, <literal>, <segments>, %(expr ("String") $source), <expression>,
    %("String"), "interpolated String");
  match (lowered)
    case %(expr ?type (call ?callee (args ?separator
        (expr ? (parens (block *declarations (stmnt ?parts))))))):
      return _ordered(
        declarations, type, %(call $callee (args $separator $parts)));
  return lowered.caddr();
}

/* evaluation order

   C leaves the order of call arguments unspecified. A value that x2c
   evaluates in source order moves into a temporary, declared ahead of the
   expression that uses it inside a statement expression. */
static List _sequenced(
  Compiler c, List value, String stem, Array declarations) {
  Type type = value.cadr();
  List temporary = c.sym.introduce(c.fresh_name(stem));
  declarations.push(
    c.rebuild_statement($!{ $type $temporary = $value; }).cadr());
  return $!($type){ $temporary };
}

/* A C macro such as raylib's WHITE expands to an expression x2c has no
   type for, and a temporary still has to declare one: the type the value is
   about to be passed as. */
static List _passed_as(List value, Type type) {
  match (value) case %(expr () ?body): return %(expr $type $body);
  return value;
}

static List _statement_expression(List declarations, List expression) =>
  %(parens (block @declarations (stmnt $expression)));

/** Calls the typed callable `callee` with `arguments`, each converted to
    its parameter and evaluated once, in source order, as a statement
    expression. */
List Compiler.call_in_order(Compiler c, List callee, List arguments) {
  Type signature = callee.cadr();
  List parameters = signature.car().list().cadr();
  Array converted = [];
  for (List actual = arguments, expected = parameters;
       actual && expected;
       actual = actual.cdr(), expected = expected.cdr()) {
    List value = c.convert_expression(actual.car(), expected.car());
    converted.push(_passed_as(value, expected.car()));
  }
  Array declarations = [], arguments_out = [];
  foreach (List value, converted)
    arguments_out.push(_sequenced(c, value, "protocol_arg", declarations));
  converted.free();
  Macro called = $called;
  List call = c.rebuild_expression(
    signature.cdr(), called(callee, arguments_out.list_free()));
  return _statement_expression(declarations.list_free(), call);
}
