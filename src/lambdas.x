/*  lambdas.x -- lambda parsing and capture resolution

    Copyright (c) 2026 Gary William Flake.

    A source lambda and a lambda that a macro or transform constructs bind
    through the same capture operations, which record each captured binding
    and its value or reference mode in semantic binding facts. The rows
    leave here resolved and in first-use order; `callables.x` lowers them.
*/
#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#pragma private
$(import "../src/grammar.xmacro")
#include "parse.x"
#include "type.x"
#include "expressions.x"

/* lambda literals

   `%!(params) using &name, ... => body` parses its parameters in a scope
   of their own, closes it while `using` names outer bindings, and reopens
   it for the body. A template leaves its type, captures, and body open
   for expansion. */

/** Parses a `%!(...) => ...` literal and returns its typed lambda expression.
    Parameter bindings are in a new `Sym` scope, block bodies use `Var` as the
    active return type, and capture rows come from `semantic_binding_facts`.
    Capturing lambdas have type `Func`; noncapturing lambdas retain a native
    function type.
*/
List Compiler.parse_lambda_literal(Compiler c) {
  c.expect(<"%!">);
  c.expect(<(>);
  c.sym.push_new_scope();
  List entries = c.peek(0) == <)> ? NULL : c._parse_params();
  c.expect(<)>);
  SymScope params = c.sym.pop_scope();
  Array references = [], prescribed = [];
  c._parse_using(references, prescribed);
  c.expect(<"=">);
  c.expect(<">">);
  $let(c.lambda_scopes, c.lambda_scopes) {
    c.begin_lambda_captures(references.list_free(), NULL);
    c.sym.push_scope(params);
    List body = c._parse_lambda_body();
    List ftype = %((func ${c.lambda_param_types(entries)}) "Var");
    List captures = c.end_lambda_captures();
    c.check_lambda_captures(body);
    if (c.macro_holes) captures = prescribed.list_free();
    c.sym.pop_scope();
    if (c.macro_holes) return c._lambda_template(body, captures, entries);
    Type type = captures ? %("Func") : ftype;
    return c.rebuild_expression(type, _lambda_node(body, captures, entries));
  }
}

static List Compiler._parse_params(Compiler c) =>
  c._params_look_typed() ? c._parse_typed_params() : c._parse_bare_params();

/* Typed parameters begin with a type: a type keyword, a typedef name, or
   a template's `$` hole. */
static int Compiler._params_look_typed(Compiler c) {
  Symbol head = c.peek(0);
  if (head == <$> && c.macro_holes) return 1;
  if (head.is_builtin_type() || head.is_type_qualifier() ||
      head == <struct> || head == <union> || head == <enum> || head == <void>)
    return 1;
  if (head != <ident>) return 0;
  String folded = c.package_alias_spelling();
  if (!folded) folded = c.package_member_spelling(c.token.text);
  String name = folded ? folded : c.token.text;
  return c.sym.get(%($name)).type().is_typedef();
}

static List Compiler._parse_typed_params(Compiler c) {
  List params = c.parse_parameter_list();
  foreach (List param, params)
    match (param)
      case %(param ? (bind ?binding ?)):
        c.semantic_binding_facts()[%(lambda-param $binding)] = 1;
  return params;
}

static List Compiler._parse_bare_params(Compiler c) {
  Array names = [];
  do names.push(c._parse_bare_param());
  while (c.test(<,>));
  return names.list_free();
}

/* A bare parameter is an automatic Var. */
static List Compiler._parse_bare_param(Compiler c) {
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "expected identifier in parameter list", c.token, NULL);
  String name = c.token.text;
  List binding = c.sym.define(%($name), %("Var"));
  Map facts = c.semantic_binding_facts();
  facts[%(parameter $binding)] = 1;
  facts[%(lambda-param $binding)] = 1;
  facts[%(automatic $binding)] = 1;
  facts[%(type $binding)] = %("Var");
  c.next();
  return binding;
}

/* `using` shares source bindings by reference. A template instead lists
   reference rows, or one captures hole, for expansion to complete. */
static void Compiler._parse_using(
  Compiler c, Array references, Array prescribed) {
  if (c.peek(0) != <ident> || c.token.text != "using") return;
  c.next();
  List hole = c.try_parse_macro_slot(<captures>);
  if (hole) prescribed.push(hole);
  else do {
    c.expect(<&>);
    if (c.macro_holes) prescribed.push(c._template_capture());
    else references.push(c._shared_binding());
  } while (c.test(<,>));
}

/* A template's `&$name` leaves the binding to expansion, while `&name`
   resolves it now. */
static List Compiler._template_capture(Compiler c) {
  List name = NULL, value = NULL;
  Type reference = %(& <macro-expr>);
  if (c.peek(0) == <$>) {
    name = c.try_parse_macro_slot(<name>);
    value = %(expr (<macro-expr>) (ident $name));
  }
  else {
    Token origin = c.token;
    name = c.parse_basic_identifier();
    value = c.resolve_expression(%(expr () (ident $name)), origin);
    name = c.sym.lookup(name, NULL);
    reference = cons(<&>, value.cadr());
  }
  return %(capture $name $reference (expr $reference (op & $value)));
}

static List Compiler._shared_binding(Compiler c) {
  Token origin = c.token;
  String spelling = c.token.text;
  c.expect(<ident>);
  Type type = NULL;
  List binding = c.sym.lookup(%($spelling), type);
  if (!type)
    c.report_error(
      <type>, %"identifier '$spelling' has no semantic type", origin, NULL);
  return binding;
}

static List Compiler._parse_lambda_body(Compiler c) {
  if (!c.test(<"{">)) return c.parse_assignment();
  $let(c.return_type, %("Var")) return c.parse_callable_body();
}

/** The parameter types of a lambda's function signature, keeping typed
    declarators; a bare parameter is a `Var`. */
List Compiler.lambda_param_types(Compiler c, List entries) {
  if (!entries) return %((void));
  Array types = [];
  foreach (List entry, entries)
    match (entry) {
      case %(binding ? ?): types.push(%("Var"));
      case %(param ? ?): {
        Type type = entry.type_from_ast().declared();
        if (type.car() == <&> || type.car() == <opt-ref>)
          type = cons(
            type.car(), c.sym.normalize_declared_type(type.cdr()));
        types.push(type);
      }
    }
  return types.list_free();
}

/* The body hole may supply either an expression or a block. */
static List Compiler._lambda_template(
  Compiler c, List body, List captures, List entries) {
  match (body)
    case %(expr (<macro-expr>) (!set ?hole (macro-bind ?))): body = hole;
  return c.rebuild_expression(
    %(<macro-expr>), _lambda_node(body, captures, entries));
}

static List _lambda_node(List body, List captures, List params) {
  Macro captured = $lambda_captured, lambda = $lambda_expression;
  return captures ? captured(body, captures, params) : lambda(body, params);
}

/* constructed lambdas

   A lambda that a macro or transform builds binds through the capture
   operations of source lambdas. Its supplied rows name their targets and
   fix their capture mode. */

/** Binds a constructed lambda through the lexical capture operations used by
    source literals. Parameter declarations keep their existing declarators;
    supplied canonical capture rows retain their value or reference mode.
*/
List Compiler.bind_lambda_expression(
  Compiler c, Type type, List parameters, List supplied, List body) {
  Array prescribed = [], aliases = [];
  foreach (List row, supplied) c._prescribe(row, prescribed, aliases);
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  foreach (List alias, aliases) {
    (List binding, Type annotation) = alias;
    c.sym.bind_identity(NULL, binding, annotation.declaration_ast(binding));
  }
  $let(c.lambda_scopes, c.lambda_scopes) {
    c.begin_lambda_captures(NULL, prescribed.list_free());
    c.sym.push_new_scope();
    defer c.sym.pop_scope();
    Array entries = [];
    foreach (List entry, parameters.cdr())
      c._add_param(entries, c._declare_param(entry));
    body = c._bind_body(body);
    List captures = c.end_lambda_captures();
    c.check_lambda_captures(body);
    List params = entries.list_free();
    if (captures)
      return c.rebuild_expression(
        %("Func"), _lambda_node(body, captures, params));
    return c._plain_lambda(type, supplied, params, body);
  }
}

/* A row's target is a spelling or a binding. An open captured type
   becomes a reference to the target's type, and a target without a
   binding identity gets a fresh binding that the lambda binds as an
   alias. */
static void Compiler._prescribe(
  Compiler c, List row, Array prescribed, Array aliases) {
  match (row)
    case %(capture ?target ?captured_type ?expression): {
      Type source = NULL, target_type = captured_type;
      List binding = target is <string>
                   ? c.sym.lookup(%($target), source) : target;
      if (<macro-expr> in target_type)
        target_type = source.car() == <&> ? source : cons(<&>, source);
      if (!binding_identity_spelling(binding)) {
        binding = c.sym.introduce(_alias_spelling(target, binding));
        aliases.push(%($binding $target_type));
      }
      prescribed.push(%(capture $binding $target_type $expression));
    }
}

static String _alias_spelling(Var target, List binding) {
  String spelling = target is <string> ? target : NULL;
  match (binding) {
    case %(?(String name)): spelling = name;
    case %("x2c.ident" ?(String name)): spelling = name;
  }
  return spelling;
}

/* A `param` keeps its base and declarator; a bare binding declares a Var. */
static List Compiler._declare_param(Compiler c, List entry) {
  match (entry) {
    case %(param ?base ?binding):
      return c.bind_syntax(
        %(declare $base (bindings $binding)), AST_BLOCK, %("Var"));
    case %(binding ? ?):
      return c.bind_syntax(
        %(declare ("Var") (bindings (bind $entry ()))), AST_BLOCK, %("Var"));
  }
  return NULL;
}

static void Compiler._add_param(Compiler c, Array entries, List declaration) {
  match (declaration)
    case %(declare ?base (bindings (!set ?declarator (bind ?binding ?)))): {
      Map facts = c.semantic_binding_facts();
      facts[%(parameter $binding)] = 1;
      facts[%(lambda-param $binding)] = 1;
      if (declaration.type_from_ast().car() == <&>)
        facts[%(reference-param $binding)] = 1;
      entries.push(%(param $base $declarator));
    }
}

static List Compiler._bind_body(Compiler c, List body) {
  match (body) case $source_block_content(%(*)):
    return c.bind_callable_body(body, %("Var"));
  return c.resolve_expression(body, c.token);
}

/* An open type is a Func when rows were supplied, and otherwise the
   native function type of the parameters. A meta body keeps a Func lambda
   for meta lowering to adapt; the transform lifts it for native code. */
static List Compiler._plain_lambda(
  Compiler c, Type type, List supplied, List params, List body) {
  List node = _lambda_node(body, NULL, params);
  if (type === %(<macro-expr>))
    type = supplied ? %("Func")
         : %((func ${c.lambda_param_types(params)}) "Var");
  if (type !== %("Func") || c.meta_body)
    return c.rebuild_expression(type, node);
  Type signature = %((func ${c.lambda_param_types(params)}) "Var");
  return c.lift_func_expression(c.rebuild_expression(signature, node));
}

/* lambda captures

   Each open lambda has a frame `(lambda-scope SCOPE DEPTH REFERENCES
   SUPPLIED)` in `lambda_scopes`, innermost first. Capture rows and their
   order live in semantic binding facts, so macro transactions restore
   them. */

/** Opens lexical capture resolution while a lambda body is parsed or bound.
    `references` names explicitly shared surrounding bindings; `supplied`
    contains canonical capture rows supplied by constructed syntax. Evolving
    rows live in semantic binding facts so macro transactions restore them.
*/
void Compiler.begin_lambda_captures(
  Compiler c, List references, List supplied) {
  List scope = c.sym.introduce(c.fresh_name("lambda_scope"));
  int depth = c.sym.scope_count();
  c.lambda_scopes = cons(
    %(lambda-scope $scope $depth $references $supplied), c.lambda_scopes);
}

/** Finishes the active lambda's captures in first-use order. */
List Compiler.end_lambda_captures(Compiler c) {
  List scope = c.lambda_scopes.car().cadr();
  c.lambda_scopes = c.lambda_scopes.cdr();
  List rows = c.semantic_binding_facts().getdefault(
    %(lambda-order $scope), %());
  return rows.reverse();
}

/** Reports whether the active lambda still needs to capture a binding. */
int Compiler.lambda_capture_required(Compiler c, List binding) {
  match (c.lambda_scopes)
    case %((lambda-scope ? ?depth ? ?supplied) *):
      return _prescribed_row(supplied, binding, binding) ||
             c._declared_outside(binding, depth);
  return 0;
}

/** Resolves an automatic identifier through each enclosing lambda's captures.
    Fresh captured bindings keep sibling snapshots independent of shared-cell
    rewriting. Reference captures preserve qualifiers; snapshots of reference
    parameters copy their current referents.
*/
List Compiler.capture_lambda_identifier(Compiler c, List binding, Type type) {
  List original = binding;
  foreach (List frame, c.lambda_scopes.reverse())
    match (c._frame_capture(frame, binding, original, type))
      case %(capture ?captured ?captured_type ?): {
        binding = captured;
        type = captured_type;
      }
  return %(expr $type (ident $binding));
}

/* One binding's capture through one lambda frame: the frame's fields, the
   binding and type that the frame sees, and the identifier's source
   binding. `facts` is read before a supplied value resolves. */
typedef struct Capture {
  Compiler c;
  Map facts;
  List frame, key, prescribed, binding, original;
  Type type;
  Var scope, depth, references;
} Capture;

/* The row that captures `binding` in `frame`, or NULL when the binding is
   the frame's own or static. */
static List Compiler._frame_capture(
  Compiler c, List frame, List binding, List original, Type type) {
  match (frame)
    case %(lambda-scope ?scope ?depth ?references ?supplied): {
      List prescribed = _prescribed_row(supplied, binding, original);
      if (!prescribed && !c._declared_outside(binding, depth)) return NULL;
      if (type.is_static()) return NULL;
      Map facts = c.semantic_binding_facts();
      List key = %(lambda-capture $scope $binding);
      Var stored;
      if (facts.try_get(key, stored)) return stored;
      Capture k = {
        .c = c, .facts = facts, .frame = frame, .key = key,
        .prescribed = prescribed, .binding = binding, .original = original,
        .type = type, .scope = scope, .depth = depth,
        .references = references};
      return k.add();
    }
  return NULL;
}

/* The last supplied row whose target is the binding or the identifier's
   source binding. */
static List _prescribed_row(Var supplied, List binding, List original) {
  List prescribed = NULL;
  foreach (List row, supplied.list())
    match (row)
      case %(capture ?target ? ?)
        if (target == binding || target == original):
          prescribed = row;
  return prescribed;
}

/* A captured copy is outside every lambda deeper than the one that made
   it; another automatic binding is outside when a scope below `depth`
   declares it. */
static int Compiler._declared_outside(Compiler c, List binding, int depth) {
  Var captured_depth;
  Map facts = c.semantic_binding_facts();
  if (facts.try_get(%(lambda-depth $binding), captured_depth))
    return captured_depth.integer() < depth;
  return %(automatic $binding) in facts &&
         c.sym.binding_is_local_before(binding, depth);
}

/* A supplied row fixes the captured type and value. Otherwise a binding
   listed after `using` captures by reference, and a snapshot of a
   reference parameter copies its referent. */
static List Capture.add(Capture *k) {
  Type type = k.type, captured_type = type.car() == <&> ? type.cdr() : type;
  List binding = k.binding, expression = %(expr $type (ident $binding));
  int reference = k.original in k.references.list();
  if (k.prescribed) {
    match (k.prescribed)
      case %(capture ? ?target_type ?value): {
        captured_type = target_type;
        expression = k.c._resolve_outside(k.frame, value);
        reference = captured_type.car() == <&>;
      }
  }
  else if (reference) {
    captured_type = cons(<&>, captured_type);
    if (type.car() != <&>)
      expression = %(expr $captured_type (op & $expression));
  }
  else if (type.car() == <&>)
    expression = %(expr $captured_type (op * $expression));
  if (reference && %(lambda-snapshot $binding) in k.facts)
    k.c.report_error(
      <type>, "reference capture requires an enclosing reference capture",
      k.c.token, %("binding: ${binding_identity_spelling(k.original)}"));
  return k.record(captured_type, expression, reference);
}

/* A supplied value resolves outside its lambda and the lambdas inside it. */
static List Compiler._resolve_outside(Compiler c, List frame, Var value) {
  List outside = c.lambda_scopes;
  while (outside.car() != frame) outside = outside.cdr();
  $let(c.lambda_scopes, outside.cdr())
    return c.resolve_expression(value, c.token);
}

/* The captured copy is a fresh automatic binding: a reference parameter or
   a snapshot. Rows join the lambda's order newest first. */
static List Capture.record(
  Capture *k, Type captured_type, List expression, int reference) {
  Map facts = k.facts;
  List captured = k.c.sym.introduce(binding_identity_spelling(k.binding));
  List row = %(capture $captured $captured_type $expression);
  facts[k.key] = row;
  facts[%(automatic $captured)] = 1;
  facts[%(type $captured)] = captured_type;
  facts[%(lambda-depth $captured)] = k.depth;
  if (reference) facts[%(reference-param $captured)] = 1;
  else facts[%(lambda-snapshot $captured)] = 1;
  List order = %(lambda-order ${k.scope});
  facts[order] = cons(row, facts.getdefault(order, %()));
  return row;
}

// capture checks

/** Rejects writes and reference access to read-only snapshot bindings.
    The body has already resolved identifiers and call arguments. Templates
    defer this check until expansion; nested lambdas check their own bodies.
*/
void Compiler.check_lambda_captures(Compiler c, List ast) {
  if (c.macro_holes) return;
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  Array pending = $auto([]);
  pending.push(ast);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) {
      case lambda(?body, *params): continue;
      case captured(?body, *captures, *params): continue;
      case $source_operator_content(%(& ?target)):
        c._require_capture_lvalue(target);
      case $source_operator_content(%(?operator ?target *)):
        if (operator is <symbol> && ast_changes_left_operand(operator))
          c._require_capture_lvalue(target);
      case $source_postfix_content(%(? ?target)):
        c._require_capture_lvalue(target);
      case %(dstrasgn (targets *targets) ?):
        foreach (List target, targets) c._require_capture_lvalue(target);
      case $source_call_content($called,
          %(expr ?callee_type ?), %(*arguments)):
        c._require_reference_arguments(callee_type, arguments);
    }
    foreach (Var child, node) pending.push(child);
  }
}

static void Compiler._require_capture_lvalue(Compiler c, List target) {
  List binding = Ast.lvalue_binding(target);
  if (binding &&
      %(lambda-snapshot $binding) in c.semantic_binding_facts())
    c.report_error(
      <type>, "captured value requires 'using &name' for reference access",
      c.token, %("binding: ${binding_identity_spelling(binding)}"));
}

/* An argument bound to a reference parameter is reference access. */
static void Compiler._require_reference_arguments(
  Compiler c, Type callee_type, List arguments) {
  List parameters = NULL;
  if (!Type.function_parts(callee_type, parameters, NULL)) return;
  for (; parameters && arguments;
       parameters = parameters.cdr(), arguments = arguments.cdr()) {
    Type parameter = parameters.car();
    if (parameter.car() == <&> || parameter.car() == <opt-ref>)
      c._require_capture_lvalue(arguments.car());
  }
}
