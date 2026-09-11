/*  expressions.x -- x2c expression parsing

    Parses postfix operators and calls, unary operators and casts,
    binary operators with precedence/associativity, conditionals, assignment,
    primary/grouped forms, and comma folding. Precedence and associativity
    follow C; dotted method sugar and string-like addition use resolved type
    information from the compiler and type modules.
  */
#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#include "type.x"

#pragma private
#include "parse.x"
#include "literals.x"
#include "protocol.x"
#include "lambda.x"

static List _iter_destination(void) => %(expr (* struct "Iter")
    (op & (expr (struct "Iter")
      (cast (decl (struct "Iter") (bindings (bind () ())))
        (expr () (composite
          (commas (expr (int) (literal (int) "0")))))))));

static int _iter_parameters_variadic(List parameters) {
  foreach (Var parameter, parameters) if (parameter == <...>) return 1;
  return 0;
}

static int _exact_iter_type(Var value) {
  Type type = value is <list> ? value.list() : %($value);
  return List.equal(type.canonicalize(), %("Iter"));
}

/** Completes an eligible resolved `Iter` call chain for immediate consumption.
    It accepts only a typed identifier call of the form
    `(expr R (call (expr ((func P) T) (ident B)) (args A)))`, where `R` and
    the last formal in `P` canonicalize to `Iter`. `Iter` arguments are
    completed recursively; a call missing only that last formal receives the
    hidden destination. Variadic calls and `Iter_unzip` are returned unchanged.
*/
List Compiler.complete_iter_chain(Compiler compiler, List expression) {
  match (expression) {
    case %(expr ?result (call (!set ?callee
           (expr ((func (!set ?parameters (*))) ?)
              (ident ?binding))) (args *arguments))): {
      String name = binding_identity_spelling(binding);
      if (!_exact_iter_type(result) || name == "Iter_unzip" ||
          _iter_parameters_variadic(parameters))
        return expression;

      Array completed = %[];
      List formal = parameters, actual = arguments;
      int supplied = arguments.len(), expected = formal.len();
      if (!formal ||
          (supplied != expected && supplied + 1 != expected) ||
          !_exact_iter_type(formal.last()))
        return expression;
      int changed = 0;
      while (actual) {
        List argument = actual.car(), rewritten = argument;
        if (_exact_iter_type(formal.car()))
          rewritten = compiler.complete_iter_chain(argument);
        if (rewritten != argument) changed = 1;
        completed.push(rewritten);
        actual = actual.cdr();
        formal = formal.cdr();
      }

      List values = completed.list_free();
      if (supplied + 1 == expected) {
        values = values.append(%(${_iter_destination()}));
        changed = 1;
      }
      if (!changed) return expression;
      return %(expr ("Iter") (call $callee (args @values)));
    }
  }
  return expression;
}

#include "macros.x"

// True when a receiver's type must wait for macro substitution.
static int _deferred_receiver(List expr) {
  match (expr) case %(expr (<macro-expr>) ?): return 1;
  return 0;
}

/* Called after the optional start index and first `:` of
   `expr[start:end:step]`. */
static List _parse_slice(Compiler c, List expr, List start) {
  List type = expr.cadr(), stop = NULL, step = NULL;
  if (c.test(<:>)) {
    if (c.peek(0) != <]>) step = c.parse_expression();
  }
  else if (c.peek(0) != <]>) {
    stop = c.parse_expression();
    if (c.test(<:>) && c.peek(0) != <]>) step = c.parse_expression();
  }
  if (step && step.match(%(expr ? (literal ? "0"))))
    c.report_error(<parse>, "slice step cannot be zero", c.token, %());
  c.expect(<]>);
  return %(expr $type (slice $expr $start $stop $step));
}

static List Compiler._postfix_index_expression(
  Compiler compiler, List expr, List index) {
  Type type = expr.cadr();
  if (type.is_pointer() || type.is_array()) {
    type = type.dereference();
    return %(expr $type (index $expr $index));
  }
  if (!type.is_typedef_name()) return NULL;
  String owner = type.car().str(), Type receiver = type;
  if (Sym.is_array_type(compiler.sym, type)) {
    owner = "Array";
    receiver = %("Array");
  }
  else if (Sym.is_map_type(compiler.sym, type)) {
    owner = "Map";
    receiver = %("Map");
  }
  String fnname = %"${owner}_getindex";
  List fntype = compiler.sym.get(%($fnname));
  match (fntype) {
    case %((func (!set ?params ($receiver ?))) ?rtype): {
      Type key = params.list().cadr(), supplied = index.cadr();
      if (key.is_integral() &&
          compiler.sym.is_named_value_type(supplied, "Symbol"))
        compiler.report_error(
          <type>, "Symbol cannot be used as an integer bracket index",
          compiler.token, NULL);
      return %(expr ($rtype) (getindex $expr $index));
    }
  }
  Type native = compiler.sym.resolve_key(type);
  if (native.is_array())
    return %(expr ${native.dereference()} (index $expr $index));
  return NULL;
}

static List _parse_postfix_index(Compiler c, List expr) {
  c.expect(<[>);
  if (c.test(<:>)) return _parse_slice(c, expr, NULL);
  List index = c.parse_expression();
  if (c.test(<:>)) return _parse_slice(c, expr, index);
  c.expect(<]>);
  return c.resolve_expression(%(expr () (index $expr $index)), c.token);
}

static List _parse_postfix_apply(Compiler c, List expr) {
  Token origin = c.token;
  c.expect(
    <(>);
  Array arguments = %[];
  if (c.peek(0) == <)>) arguments.push(%(expr (void) ()));
  while (c.peek(0) != <)>) {
    List argument = c.try_parse_macro_slot(<argument>);
    arguments.push(argument ? argument : c.parse_assignment());
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  List result = c.resolve_expression(
    %(expr () (call $expr (args @{arguments.list_free()}))), origin);
  return result;
}

static Type _receiver_relative_signature(
  Compiler compiler, List binding, Type signature, Type receiver) {
  String spelling = binding_identity_spelling(binding);
  if (!spelling) return signature;
  Type relative = compiler.sym.get_exact(%(self $spelling));
  if (!relative) return signature;
  Type base = receiver.canonicalize().base_type();
  if (!base || base.len() != 1) return signature;
  return relative.search_replace(<self>, base.car());
}

/* Find a method that an imported package adds to an external receiver. The
   package names are sorted so an ambiguous call reports deterministically. */
static List _imported_method(Compiler compiler, String method, Type receiver) {
  List packages = compiler.imported_providers(method);
  if (!packages) return NULL;
  if (packages.cdr()) return cons(<ambiguous>, packages);

  String spelling = %"${packages.car()}__$method";
  Type signature = compiler.sym.get_exact(%($spelling));
  List binding = compiler.sym.reference(%($spelling), NULL);
  signature = _receiver_relative_signature(
    compiler, binding, signature, receiver);
  return %(method $binding $signature);
}

/** Resolves one field or method selection without consuming parser tokens.
    `field` is a single-name `List` and `access` is `.` or
    `->`. The result is a
    `(field access type)`, `(method binding signature)`, or `(ambiguous ...)`
    row, or NULL when no member is visible. Method lookup is enabled only by
    `call_context` and records the selected binding in `compiler.sym`.
*/
List Compiler.resolve_postfix_member(
  Compiler c, Type receiver_type, List field, Symbol access,
  int call_context) {
  // The receiver type is a lookup key here. A const or volatile receiver
  // names the same aggregate, fields, and methods.
  Type type = receiver_type.canonicalize();
  int hops = 0;
  if (access == <"->">) {
    Type object_type = c.sym.resolve_key(type);
    object_type = object_type.dereference();
    Type field_type = c.sym.lookup_field(object_type, field);
    return field_type ? %(field -> $field_type) : NULL;
  }
  while (type) {
    int is_method_type = type.is_typedef_name() || type.is_builtin();
    if (call_context && is_method_type) {
      Type ctype = type;
      String method = %"${ctype.base_type().car()}_${field.car()}";
      Type signature = c.sym.get(%($method));
      int rejected =
        c.protocol_rejects_direct_member(ctype, field.car().str());
      if (signature && rejected) signature = NULL;
      List binding = NULL;
      if (signature) binding = c.sym.reference(%($method), NULL);
      else {
        List imported = rejected
          ? NULL : _imported_method(c, method, receiver_type);
        if (imported) return imported;
        List resolved =
          c.resolve_protocol_method(ctype, field.car().str());
        if (resolved) {
          (List method_binding, Type method_signature) = resolved;
          return %(method $method_binding $method_signature);
        }
      }
      if (signature) {
        signature = _receiver_relative_signature(
          c, binding, signature, receiver_type);
        return %(method $binding $signature);
      }
    }
    if (type.is_pointer()) {
      Type object_type = type.dereference();
      Type field_type = c.sym.lookup_field(object_type, field);
      if (field_type) return %(field -> $field_type);
      type = NULL;
    }
    else if (type.is_aggregate()) {
      Type field_type = c.sym.lookup_field(type, field);
      if (field_type) return %(field . $field_type);
      type = NULL;
    }
    else type = c.sym.next_typedef(type, &hops);
  }
  return NULL;
}

static String _delegate_type_name(Type type) {
  Type base = type.base_type();
  Var (head, name) = base;
  return base.is_aggregate_tag() ? name.str() : head.str();
}

static String _delegate_path_string(Type receiver, List path, String member) {
  Array parts = %[];
  parts.push(_delegate_type_name(receiver));
  foreach (List step, path.cdr()) parts.push(step.caddr());
  if (member) parts.push(member);
  return %".".join(parts.list_free());
}

static void _report_imported_method_ambiguity(
  Compiler compiler, Type receiver, String member, List packages,
  String delegate_path, Token origin) {
  List notes = delegate_path
             ? %("delegate path: $delegate_path") : NULL;
  foreach (String package, packages)
    notes = cons(%"package: '$package'", notes);
  String type = _delegate_type_name(receiver);
  compiler.report_error(
    <type>,
    %"method '$type.$member' is provided by multiple imported packages",
    origin, notes.reverse());
}

static List _delegate_step(Compiler compiler, Type receiver, String name) {
  List field = compiler.resolve_postfix_member(receiver, %($name), <.>, 0);
  (Symbol access, Type field_type) = field.cdr();
  return %(step $access $name $field_type);
}

static void _find_delegate_methods(
  Compiler compiler, Type receiver, String member, List reverse_path,
  List seen, Array candidates, List *first_cycle, Type outer, Token origin) {
  Type aggregate = compiler.sym.delegate_aggregate(receiver);
  if (!aggregate) return;
  if (seen.contains(aggregate)) {
    if (!*first_cycle) *first_cycle = cons(<path>, reverse_path.reverse());
    return;
  }
  seen = cons(aggregate, seen);
  List order = compiler.sym.field_order(aggregate);
  foreach (List row, order ? order.cdr() : NULL) {
    String name = row.car();
    if (!name) continue;
    if (!compiler.sym.get(%(@aggregate delegate $name))) continue;
    List step = _delegate_step(compiler, receiver, name);
    Type field_type = step.cddr().cadr();
    List next_path = cons(step, reverse_path);
    List resolution = compiler.resolve_postfix_member(
      field_type, %($member), <.>, 1);
    if (resolution && resolution.car() == <method>) {
      (Var method_tag, List binding, Type signature) = resolution;
      (void) method_tag;
      List path = cons(<path>, next_path.reverse());
      candidates.push(%( delegate $binding $signature $path ));
    }
    else if (resolution && resolution.car() == <ambiguous>) {
      String path = _delegate_path_string(
        outer, cons(<path>, next_path.reverse()), NULL);
      _report_imported_method_ambiguity(
        compiler, field_type, member, resolution.cdr(), path, origin);
    }
    else if (!resolution)
      _find_delegate_methods(
        compiler, field_type, member, next_path, seen,
        candidates, first_cycle, outer, origin);
  }
}

static List _resolve_delegate_method(
  Compiler compiler, Type receiver, String member, Token origin) {
  Array found = %[], List first_cycle = NULL;
  _find_delegate_methods(
    compiler, receiver, member, NULL, NULL,
    found, &first_cycle, receiver, origin);
  List candidates = found.list_free();
  if (candidates && candidates.cdr()) {
    List notes = NULL;
    foreach (List candidate, candidates) {
      List path = candidate.cddr().cadr();
      String spelling = binding_identity_spelling(candidate.cadr());
      String description = _delegate_path_string(receiver, path, member);
      notes = cons(%"delegate path: $description -> $spelling", notes);
    }
    String type = _delegate_type_name(receiver);
    compiler.report_error(
      <type>, %"method '$type.$member' has multiple delegate paths",
      origin, notes.reverse());
  }
  if (candidates) return candidates.car();
  if (first_cycle) {
    String type = _delegate_type_name(receiver);
    String path = _delegate_path_string(receiver, first_cycle, NULL);
    compiler.report_error(
      <type>, %"delegation cycle resolving $type.$member", origin,
      %("delegate path: $path"));
  }
  return NULL;
}

static List _materialize_delegate_receiver(List receiver, List path) {
  foreach (List step, path.cdr()) {
    (Symbol access, String name, Type type) = step.cdr();
    receiver = %(
      expr $type
        (op $access $receiver ($name))
    );
  }
  return receiver;
}

static List _parse_field_name(Compiler compiler, Symbol op_sym, List lhs_opt) {
  List slot = compiler.try_parse_macro_slot(<name>);
  if (slot) return %($slot);
  String field_name = compiler.token.text;
  if (!field_name || !field_name.is_identifier()) {
    List notes = %("token:" ${compiler.token.text});
    if (lhs_opt) notes = cons(%("lhs expr:" ${lhs_opt.str()}), notes);
    String msg = %"expected identifier after '$op_sym'";
    compiler.report_error(<parse>, msg, compiler.token, notes);
  }
  List field = %( $field_name );
  compiler.next();
  return field;
}

static List _parse_postfix_dot(Compiler compiler, List expr) {
  Token origin = compiler.token;
  compiler.expect(<.>);
  List field = _parse_field_name(compiler, <.>, expr);
  List result = %(expr () (op . $expr $field));
  if (compiler.peek(0) != <(>)
    return compiler.resolve_expression(result, origin);
  // Allocate a method identity before parsing its arguments.
  (void) compiler.resolve_postfix_member(expr.cadr(), field, <.>, 1);
  return result;
}

static List _parse_postfix_arrow(Compiler compiler, List expr) {
  Token origin = compiler.token;
  compiler.expect(<"->">);
  List field = _parse_field_name(compiler, <"->">, expr);
  return compiler.resolve_expression(%(expr () (op -> $expr $field)), origin);
}

static List _parse_postfix_decinc(Compiler compiler, List expr) {
  Token origin = compiler.token;
  Symbol op = compiler.peek(0);
  compiler.next();
  return compiler.resolve_expression(%(expr () (postfix $op $expr)), origin);
}

static List _parse_postfix_tail(Compiler compiler, List expr) {
  loop {
    switch (compiler.peek(0)) {
      case <[>:      expr = _parse_postfix_index(compiler, expr);   break;
      case <(>:      expr = _parse_postfix_apply(compiler, expr);   break;
      case <"->">:   expr = _parse_postfix_arrow(compiler, expr);   break;
      case <.>:      expr = _parse_postfix_dot(compiler, expr);     break;
      case <++>:
      case <-->:     expr = _parse_postfix_decinc(compiler, expr);  break;
      default:       return expr;
    }
  }
}

static List _parse_postfix(Compiler compiler) =>
  _parse_postfix_tail(compiler, compiler.parse_primary());

// unary operators and builtins
static List _parse_offsetof(Compiler compiler) {
  compiler.expect(<offsetof>);
  compiler.expect(
    <(>);
  List type = compiler.parse_simple_declaration();
  compiler.expect(<,>);
  List field = compiler.parse_basic_identifier();
  compiler.expect(<)>);
  return %(expr (unsigned) (offsetof $type $field));
}

static List _parse_sizeof(Compiler c) {
  c.expect(<sizeof>);
  int parens = c.test(
    <(>);
  Token head = c.token;
  List arg = NULL;
  if (c.test_declaration()) {
    arg = c.parse_simple_declaration();
    arg = cons(<decl>, cdr(arg));
  }
  else {
    c.token = head;
    arg = _parse_unary_op(c);
  }
  if (parens) {
    c.expect(<)>);
    arg = %(parens $arg);
  }
  return %(expr (unsigned) (sizeof $arg));
}

static List _parse_parens(Compiler compiler) {
  compiler.expect(<(>);
  List expr = compiler.parse_expression();
  compiler.expect(<)>);
  List type = expr.cadr();
  return %(expr $type (parens $expr));
}

// Designator chains retain the canonical field/index initializer forms.
static int _test_dot_init(Compiler compiler) {
  Token token = compiler.token;
  return token.type == <.> &&
    compiler.skip_trivia_from(token + 1).type == <ident>;
}

static List _parse_designated_init(Compiler compiler) {
  Symbol tag;
  List key;
  if (compiler.test(<.>)) {
    tag = <dotinit>;
    key = compiler.parse_basic_identifier();
  }
  else {
    compiler.expect(<[>);
    tag = <indexinit>;
    key = compiler.parse_assignment();
    compiler.expect(<]>);
  }
  List value;
  if (compiler.peek(0) == <.> || compiler.peek(0) == <[>)
    value = _parse_designated_init(compiler);
  else {
    compiler.expect(<=>);
    value = compiler.parse_assignment();
  }
  return %($tag $key $value);
}

static List _parse_va_arg(Compiler compiler) {
  compiler.next();
  compiler.expect(<(>);
  List expr = compiler.parse_assignment();
  compiler.expect(<,>);
  List decl = compiler.parse_simple_declaration(), type = decl.type_from_ast();
  decl = %( decl @{ cdr(decl) } );
  compiler.expect(<)>);
  expr = %( va-arg $expr $decl );
  return %( expr $type $expr );
}

static List _parse_unary_op(Compiler c) {
  Symbol op = c.peek(0);
  Token origin = c.token;
  if (op == <sizeof>) return _parse_sizeof(c);
  if (op == <offsetof>) return _parse_offsetof(c);
  if (op != <++> && op != <--> && op != <~> && op != <*> &&
      op != <&> && op != <-> && op != <+> && op != <!>)
    return _parse_postfix(c);
  c.next();
  List operand = op == <++> || op == <--> || op == <~>
               ? _parse_unary_op(c) : _parse_cast(c);
  return c.resolve_expression(%(expr () (op $op $operand)), origin);
}

static int _cast_operand_follows(Compiler compiler, int index) {
  switch (compiler.peek(index)) {
    case <ident>:
    case <$>:
    case <"$(">:
    case <"(">:
    case <"{">:
    case <"%(">:
    case <"%<<">:
    case <"%[">:
    case <"%{">:
    case <"%\"">:
    case <"%!">:
    case <lit-char>:
    case <lit-int>:
    case <lit-float>:
    case <lit-char*>:
    case <lit-atom>:
    case <lit-symbol>:
    case <void>:
    case <sizeof>:
    case <offsetof>:
    case <++>:
    case <-->:
    case <!>:
    case <~>:
    case <*>:
    case <&>:
    case <->:
    case <+>:
      return 1;
  }
  return 0;
}

static int _macro_hole_starts_cast_type(Compiler compiler) {
  if (!compiler.macro_holes || compiler.peek(0) != <$> ||
      compiler.peek(2) != <)>) return 0;
  List hole = compiler.peek_macro_hole();
  if (!hole) return 0;
  Symbol kind = hole.assoc(<kind>);
  if (kind && kind != <type>) return 0;
  return _cast_operand_follows(compiler, 3);
}

static int _parenthesized_cast_operand_follows(Compiler compiler) {
  Token token = compiler.token;
  if (token.type != <"(">) return 0;
  int depth = 0;
  loop {
    switch (token.type) {
      case <eof>: return 0;
      case <"(">: case <"$(">: depth++; break;
      case <")">:
        depth--;
        if (!depth) {
          token = compiler.skip_trivia_from(token + 1);
          Token head = compiler.token;
          compiler.token = token;
          int follows = _cast_operand_follows(compiler, 0);
          compiler.token = head;
          return follows;
        }
        break;
    }
    token = compiler.skip_trivia_from(token + 1);
  }
}

static List _parse_cast(Compiler c) {
  Token head = c.token;
  if (_parenthesized_cast_operand_follows(c) && c.test(<(>)) {
    if (c.test_declaration() || _macro_hole_starts_cast_type(c)) {
      List decl = c.parse_simple_declaration(), type = decl.type_from_ast();
      decl = %(decl @{cdr(decl)});
      c.expect(<)>);
      List expr = _parse_cast(c);
      if (expr.cadr() === %(<macro-expr>)) type = %(<macro-expr>);
      return %(expr $type (cast $decl $expr));
    }
  }
  c.token = head;
  return _parse_unary_op(c);
}

/** Parses one macro target through the cast-expression grammar.
    Parsing starts at `compiler.token` and leaves it at the first token after
    the target.
*/
List Compiler.parse_macro_expression_target(Compiler compiler) =>
  _parse_cast(compiler);

/* Larger levels bind more tightly. The recursive parser descends to level 10
   before consuming operators while each level folds left; `is` shares the
   relational level but is recognized from its identifier spelling. */
static inline int _precedence(Symbol op) {
  switch (op) {
    case <||>:                 return 1;   // logical OR
    case <&&>:                 return 2;   // logical AND
    case <|>:                  return 3;   // bitwise OR
    case <^>:                  return 4;   // bitwise XOR
    case <&>:                  return 5;   // bitwise AND
    case <==>:   case <!=>:
    case <===>:  case <!==>:   return 6;   // equality
    case <"<">:  case <">">:   case <in>:
    case <"<=">: case <">=">:  return 7;   // relational
    case <"<<">: case <">>">:  return 8;   // shift
    case <+>:    case <->:     return 9;   // additive
    case <*>:    case </>:
    case <%>:    case <@>:     return 10;  // multiplicative
    default:                   return 0;   // not a binary operator
  }
}

static inline int _is_type_operator(Compiler compiler) =>
  compiler.peek(0) == <ident> &&
         compiler.token.text == "is";

static int _is_type_selector_start(Compiler c) {
  if (c.peek(0) == <ident> && c.token.text == "Void") return 1;
  Token head = c.token;
  if (c.test(<(>)) {
    int declaration = c.test_declaration();
    c.token = head;
    return declaration;
  }
  if (c.test_declaration()) return 1;
  if (c.peek(0) != <ident>) return 0;
  String spelling = c.token.text;
  return !c.sym.get(%($spelling));
}

static Type _parse_is_type(Compiler c, Token origin) {
  int parenthesized = c.test(
    <(>), Type type = c.parse_type_name();
  if (parenthesized) {
    if (c.peek(0) == <[>)
      c.report_error(
        <type>, "array type cannot be used after operator 'is'",
        origin, %("array types have no supported Var tag"));
    if (c.peek(0) == <(>)
      c.report_error(
        <type>, "function type cannot be used after operator 'is'",
        origin, %("function types have no supported Var tag"));
    c.expect(<)>);
  }
  else if (type.is_pointer())
    c.report_error(
      <parse>, "pointer type after 'is' must be parenthesized",
      origin, %("write value is (T *)"));
  return type;
}

static inline int _type_is_string(List type) => type === %("String");

static int _expression_requires_resolution(Compiler compiler, Var value) {
  // The scan is an any-search; a worklist keeps deep operator chains from
  // costing one C frame per nesting level.
  Array pending = %[];
  defer pending.free();
  pending.push(value);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list>) continue;
    List syntax = current;
    match (syntax) {
      case %(expr (? *) (parens (block *))): continue;
      case %(lambda ? (captures *captures) ?): {
        foreach (List row, captures)
          match (row) case %(capture ?binding ? ?):
            if (!compiler.semantic_binding_facts().contains(
                  %(lambda-depth $binding))) return 1;
        continue;
      }
      case %(lambda ? ?): return 1;
      case %(expr (!or () (<macro-expr>)) ?): return 1;
      case %(at m-origin ?):
        if (compiler.source_map && !compiler.macro_holes) return 1;
      case %((!or macro-bind macro-invoke macro-slot) *): return 1;
      case %(ident ?(List binding)): {
        String spelling = binding_identity_spelling(binding);
        int retained_parameter = compiler.semantic_binding_facts().contains(
          %(lambda-param $binding));
        int retained_capture = compiler.semantic_binding_facts().contains(
          %(lambda-depth $binding));
        if (compiler.lambda_capture_required(binding)) return 1;
        if (retained_parameter &&
            ((void *) compiler.local_macro_captures != NULL ||
             compiler.semantic_binding_facts().contains(
               %(local-macro-capture $binding))))
          return 1;
        if (!spelling ||
            (compiler.sym.lookup(%($spelling), NULL) != binding &&
             !retained_parameter && !retained_capture))
          return 1;
      }
      case %(ident ?): return 1;
    }
    foreach (Var child, syntax)
      if (child is <list>) pending.push(child);
  }
  return 0;
}

static inline int _type_is_char_pointer_like(List type) {
  if (!type) return 0;
  return !!type.match(%((!or (dim *) (!quote *)) char));
}

static inline int _expr_is_string_like(List expr) {
  if (!expr) return 0;
  List type = expr.cadr();
  return _type_is_string(type) || _type_is_char_pointer_like(type);
}

static int _expr_is_raw_string_literal(List expr) {
  match (expr) {
    case %(expr ? (parens ?inner)):
      return _expr_is_raw_string_literal(inner);
    case %(expr ? (literal ?type ?)):
      return _type_is_char_pointer_like(type);
  }
  return 0;
}

/* A participant that converts its operator's other operand: a struct or
   union, or a handle typedef pointing at one. Scalar pointers keep native C
   behavior, since `text + 1` must stay pointer arithmetic. */
static int _converts_operands(Compiler compiler, Type type) {
  Type resolved = compiler.sym.resolve_key(type);
  if (resolved && resolved.is_pointer())
    resolved = compiler.sym.resolve_key(resolved.dereference());
  return resolved && resolved.is_aggregate();
}

/* A binary operator whose one operand is a converting participant converts
   the other operand to that type through its declared converter, so
   `x * 2.0` and `2.0 - x` resolve like `x * two`. The converted operand
   replaces the original through `lhs` and `rhs`. */
static List _resolve_protocol_operator(
  Compiler compiler, Symbol op, List *lhs, List *rhs, Symbol *derived) {
  if (derived) *derived = 0;
  (Var lhs_tag, Type lhs_type) = *lhs;
  (void) lhs_tag;
  Type participant = lhs_type, rhs_type = NULL;
  Var rhs_tag;
  if (*rhs) {
    (rhs_tag, rhs_type) = *rhs;
    (void) rhs_tag;
  }
  Symbol member = 0;
  if (!*rhs) {
    if (op != <->) return NULL;
    member = <neg>;
  }
  else if (op == <in>) {
    participant = rhs_type;
    member = <contains>;
  }
  else {
    if (!participant) return NULL;
    member = compiler.operator_member(op);
    Symbol source = compiler.derived_member(op);
    if (!member) member = source;
    if (derived) *derived = source;
    if (!member) return NULL;
    if (participant !== rhs_type) {
      if (compiler.sym.is_var_type(participant) ||
          compiler.sym.is_var_type(rhs_type))
        return NULL;
      int lhs_member = !!compiler.resolve_protocol_member(participant, member)
        && _converts_operands(compiler, participant);
      int rhs_member = !!compiler.resolve_protocol_member(rhs_type, member)
        && _converts_operands(compiler, rhs_type);
      List converted = NULL;
      if (lhs_member && !rhs_member)
        converted = _converter_call(compiler, *rhs, rhs_type, participant);
      if (converted) *rhs = converted;
      else if (rhs_member && !lhs_member) {
        converted = _converter_call(compiler, *lhs, lhs_type, rhs_type);
        if (!converted) return NULL;
        participant = rhs_type;
        *lhs = converted;
      }
      else return NULL;
    }
  }
  return participant && member
       ? compiler.resolve_protocol_member(participant, member)
       : NULL;
}

/* A call result is an unnamed temporary the consuming operator or call may
   discard when its callee is known to return a fresh value: a protocol
   operator member, a converter from a number, or a wrapper of either. The
   callee binding is shared by every call to that function, so the record
   survives the re-resolution that rebuilds call nodes. */
static void _note_fresh_callee(Compiler compiler, List binding) {
  long identity = (long) binding;
  compiler.protocol_helpers[%"fresh-callee $identity"] = 1;
}

static List _expression_node(List expression) {
  if (!expression) return NULL;
  List body = expression.cdr().cdr();
  if (!body || !(body.car() is <list>)) return NULL;
  List node = body.car();
  return node;
}

static List _call_binding(List node) {
  if (!node || node.car() != <call> || !(node.cadr() is <list>)) return NULL;
  List callee = node.cadr(), inner = _expression_node(callee);
  if (!inner || inner.car() != <ident> || !(inner.cadr() is <list>))
    return NULL;
  List binding = inner.cadr();
  return binding;
}

static int _is_operator_temporary(Compiler compiler, List expression) {
  List node = _expression_node(expression);
  if (!node) return 0;
  if (node.car() == <parens>)
    return _is_operator_temporary(compiler, node.cadr());
  List binding = _call_binding(node);
  if (!binding) return 0;
  long identity = (long) binding;
  return compiler.protocol_helpers.contains(%"fresh-callee $identity");
}

static List Compiler._protocol_operator_expression(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  Symbol derived = 0;
  List resolved =
    _resolve_protocol_operator(compiler, op, &lhs, &rhs, &derived);
  if (!resolved) return NULL;
  (List binding, Type signature) = resolved;
  Type result = signature.cdr(), List arguments = NULL;
  int which = 0;
  if (!rhs) arguments = %(args $lhs);
  else if (op == <in>) {
    List parameters = signature.car().list().cadr();
    lhs = compiler.convert_expression(lhs, parameters.cadr());
    arguments = %(args $rhs $lhs);
  }
  else arguments = %(args $lhs $rhs);
  if (op != <in>) {
    if (_is_operator_temporary(compiler, lhs)) which |= 1;
    if (rhs && _is_operator_temporary(compiler, rhs)) which |= 2;
  }
  if (!derived && compiler.resolve_protocol_member(result, "discard"))
    _note_fresh_callee(compiler, binding);
  if (which) {
    Symbol member = rhs ? compiler.operator_member(op) : <neg>;
    if (!member) member = compiler.derived_member(op);
    Type participant = lhs.cadr();
    List helper = compiler.protocol_discard_helper(
      participant, member.str(), which);
    if (helper) (binding, signature) = helper;
  }
  List call = %(expr $result
    (call (expr $signature (ident $binding)) $arguments));
  if (!derived) return call;
  if (derived == <equal>) return %(expr (int) (op ! $call));
  List zero = %(expr (int) (literal (int) "0"));
  return %(expr (int) (op $op $call $zero));
}

static List _binary_op_type_addsub(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type ltype) = lhs;
  (Var rhs_tag, Type rtype) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  if (op == <+> && _expr_is_string_like(lhs) && _expr_is_string_like(rhs))
    return %("String");
  Type lscalar = compiler.sym.resolve_numeric_type(ltype);
  Type rscalar = compiler.sym.resolve_numeric_type(rtype);
  if (lscalar) {
    if (rscalar) return lscalar.widest(rscalar);
    else if (op == <+> && rtype.is_pointer()) return rtype;
  }
  else if (ltype.is_pointer()) {
    if (rscalar)                  return ltype;
    else if (rtype.is_pointer())  return %(int);
  }
  return NULL;
}

static List _binary_op_type_fallback(List lhs, List rhs) {
  (Var lhs_tag, Type ltype) = lhs;
  (Var rhs_tag, Type rtype) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  if (!ltype) return rtype;
  if (!rtype) return ltype;
  if (ltype === %("Var") || rtype === %("Var")) return %("Var");
  if (ltype.is_pointer()) return ltype;
  if (rtype.is_pointer()) return rtype;
  return NULL;
}

static List Compiler._binary_op_type(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type ltype) = lhs;
  (Var rhs_tag, Type rtype) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  if (op == <in>) return NULL;
  if (compiler.sym.is_var_type(ltype) ||
      compiler.sym.is_var_type(rtype)) {
    switch (op) {
      case <||>:   case <&&>:
      case <==>:   case <!=>:  case <===>:  case <!==>:
      case <"<">:  case <">">: case <"<=">: case <">=">:
        return %(int);
      default: return %("Var");
    }
  }
  switch (op) {
    case <||>:   case <&&>:
    case <==>:   case <!=>:  case <===>:  case <!==>:
    case <"<">:  case <">">: case <"<=">: case <">=">:
      return %(int);
    case <"<<">: case <">>">: {
      Type lscalar = compiler.sym.resolve_numeric_type(ltype);
      return lscalar ? lscalar.promote() : NULL;
    }
    case </>:    case <%>:
    case <"|">:  case <&>:   case <*>:
    case <^>: {
      Type lscalar = compiler.sym.resolve_numeric_type(ltype);
      Type rscalar = compiler.sym.resolve_numeric_type(rtype);
      return lscalar.widest(rscalar);
    }
    case <+>:    case <->:
      return _binary_op_type_addsub(compiler, op, lhs, rhs);
    default: return _binary_op_type_fallback(lhs, rhs);
  }
}

/* Parsed identifiers arrive as spellings, while constructed syntax may carry
   producer-issued binding identities. Semantic binding facts validate those
   identities before resolution. A visible local replaces a stale local
   identity; global shadow handling instead gives the visible declaration an
   emitted alias so the original identity keeps its meaning. */
static List _resolve_identifier(
  Compiler c, Var value, Type type, Token origin) {
  int deferred = type === %(<macro-expr>);
  if (deferred) type = NULL;
  int read_reference = !type;
  List binding = NULL, int require_type = value is <string>;
  if (value is <string>) binding = c.sym.reference(%(${value.str()}), &type);
  else if (value is <list>) {
    List name = value;
    int identity = 0;
    String spelling = NULL;
    if (binding_identity_try_parts(name, &identity, &spelling)) {
      Var issued;
      if (!c.semantic_binding_facts().try_get(
        %(known $identity), &issued) ||
          issued is not <string> || !issued.string().equal(spelling))
        c.report_error(
          <type>, "identifier has an unknown binding identity",
          origin, %("binding: ${name.repr()}"));
      binding = name;
    }
    else match (name) {
      case %("x2c.ident" ?(String spelling)): {
        require_type = 1;
        binding = c.sym.reference(%($spelling), &type);
      }
      case %((!is ? type string)):
        binding = c.sym.reference(name, &type);
    }
  }
  int macro_binder = value.is_binder() ||
    (value is <list> && !value.is_nil() &&
     value.list().car() == <macro-bind>);
  if (!binding && macro_binder) return %(expr (<macro-expr>) (ident $value));
  Map binding_facts = c.semantic_binding_facts();
  String spelling = binding_identity_spelling(binding);
  if ((void *) c.local_macro_captures != NULL && binding &&
      c.sym.binding_is_local_before(
        binding, c.local_macro_capture_scopes) &&
      !c.local_macro_captures.contains(binding)) {
    Var order = c.local_macro_captures[<order>];
    c.local_macro_captures[<order>] = cons(
      binding, order is <list> ? order.list() : NULL);
    c.local_macro_captures[binding] = 1;
  }
  if (spelling) {
    List visible_type = NULL;
    List visible = c.sym.lookup(%($spelling), &visible_type);
    if (visible && visible != binding) {
      if (binding_facts.contains(%(local-macro-capture $binding))) {
        if (!binding_facts.contains(%(emitted $visible)))
          binding_facts[%(emitted $visible)] =
            c.fresh_name("binding_shadow");
      }
      else if (c.sym.binding_is_local(binding) &&
               !binding_facts.contains(%(lambda-depth $binding)))
        binding = visible;
      else if (visible_type &&
               (!type || c.sym.resolve_global(%($spelling), NULL)) &&
               !binding_facts.contains(%(emitted $visible)))
        binding_facts[%(emitted $visible)] =
          c.fresh_name("binding_shadow");
    }
  }
  if (!type) {
    Var stored;
    if (binding_facts.try_get(%(type $binding), &stored) && stored is <list>)
      type = stored;
    if (!type && spelling) type = c.sym.get(%($spelling));
  }
  if (!type && require_type)
    c.report_error(
      <type>, %"identifier ${value.repr()} has no semantic type",
      origin, NULL);
  List result = %(expr $type (ident $binding));
  if (c.lambda_scopes && !c.macro_holes) {
    result = c.capture_lambda_identifier(binding, type);
    match (result)
      case %(expr ?captured_type (ident ?captured)): {
        if (type.car() != <&> && captured_type.list().car() == <&>)
          read_reference = 1;
        type = captured_type;
        binding = captured;
      }
  }
  if (read_reference &&
      binding_facts.contains(%(reference-param $binding))) {
    Type value_type = cdr(type);
    return %(expr $value_type
             (parens (expr $value_type (op * $result))));
  }
  return result;
}

static int _expression_is_addressable(Compiler c, List expression) {
  match (expression) {
    case %(expr ? (ident ?binding)):
      return !c.semantic_binding_facts().contains(%(lambda-snapshot $binding));
    case %(expr ? (!or (index ? ?)
                       (op (!quote *) ?) (op (!quote ->) ? ?))): return 1;
    case %(expr ? (!or (parens ?base) (op . ?base ?))):
      return _expression_is_addressable(c, base);
  }
  return 0;
}

static List _method_bind(
  Compiler compiler, List receiver, Type type, Type declared, Token origin) {
  if (!declared || !type) return receiver;
  Type target = declared.canonicalize();
  if (car(target) != <*> || cdr(target) != type.canonicalize())
    return receiver;
  if (!_expression_is_addressable(compiler, receiver))
    compiler.report_error(
      <type>, "method pointer receiver requires an addressable value",
      origin, %("bind the value to an object before calling the method"));
  List address = %(expr ${type.reference()} (op & (parens $receiver)));
  return compiler.convert_expression(address, declared);
}

static List _resolve_call_arguments(
  Compiler compiler, List receiver, List supplied, Token origin) {
  Array arguments = %[];
  if (receiver) arguments.push(receiver);
  if (!receiver && !supplied) supplied = %((expr (void) ()));
  if (receiver && supplied === %((expr (void) ()))) supplied = NULL;
  foreach (Var argument, supplied) {
    int slot = argument is <list> && !argument.is_nil() &&
               argument.list().car() == <macro-slot>;
    Var value = compiler.evaluate_macro_slot(argument);
    if (value is <list> && !value.is_nil() &&
        value.list().car() == <seq>)
      foreach (List item, value.list().cdr())
        arguments.push(compiler.resolve_expression(item, origin));
    else if (slot)
      arguments.push(
        compiler.resolve_expression(
          compiler.lift_macro_lisp_expression(value, origin), origin)
      );
    else if (value is <list>)
      arguments.push(compiler.resolve_expression(value, origin));
    else arguments.push(value);
  }
  return arguments.list_free();
}

/* A call whose receiver or argument is an unnamed operator temporary goes
   through a helper that discards that temporary once the call returns. */
static List _discarding_callee(
  Compiler compiler, List callee, Type callee_type, List arguments) {
  if (!callee_type || !(callee_type.car() is <list>) ||
      callee_type.car().list().car() != <func>)
    return callee;
  List body = callee.cdr().cdr();
  if (!body || !(body.car() is <list>)) return callee;
  List ident = body.car();
  if (ident.car() != <ident> || !(ident.cadr() is <list>)) return callee;
  List binding = ident.cadr();
  long identity = (long) binding;
  if (compiler.protocol_helpers.contains(%"discard-helper $identity"))
    return callee;
  int which = 0, index = 0;
  foreach (Var argument, arguments) {
    if (argument is <list> && _is_operator_temporary(compiler, argument))
      which |= 1 << index;
    index++;
  }
  if (!which) return callee;
  String stem = binding_identity_spelling(binding);
  if (!stem) return callee;
  List helper = compiler.discard_helper(binding, callee_type, stem, which);
  if (!helper) return callee;
  List (helper_binding, signature) = helper;
  return %(expr $signature (ident $helper_binding));
}

static List _finish_call(
  Compiler compiler, Type result_type, List callee, Type callee_type,
  List receiver, List supplied, Token origin) {
  if (result_type === %(<macro-expr>)) result_type = NULL;
  Type applied = callee_type.apply();
  if (!applied && callee_type)
    applied = compiler.sym.resolve_key(callee_type).apply();
  List arguments = _resolve_call_arguments(
    compiler, receiver, supplied, origin);
  if (_deferred_receiver(callee) ||
      (receiver && _deferred_receiver(receiver)))
    result_type = %(<macro-expr>);
  foreach (Var argument, arguments)
    if (argument is <list> && !argument.is_nil()) {
      List syntax = argument;
      if (_deferred_receiver(syntax) ||
          syntax.car() == <macro-bind> || syntax.car() == <macro-slot>)
        result_type = %(<macro-expr>);
    }
  if (!result_type) result_type = applied;
  callee = _discarding_callee(compiler, callee, callee_type, arguments);
  return %(expr $result_type
           (call $callee (args @arguments)));
}

/* A dynamic Func call stores a nonempty call's callee once, then prepares
   arguments from left to right. Each argument queries the runtime signature:
   an addressable expression can supply a checked reference carrier, while a
   representable value is boxed. Func_apply validates arity and dispatches;
   the selected adapter, `x2c_func_reference_argument`, and
   `x2c_func_value_argument` check carrier, type, and conversion. */
static List _resolve_func_call(
  Compiler compiler, List callee, List supplied, Token origin) {
  List arguments = _resolve_call_arguments(compiler, NULL, supplied, origin);
  match (arguments)
    case %((expr (void) ())): arguments = NULL;
  List storage = NULL;
  Array locals = %[], values = %[];
  List invoked = callee;
  String count_text = %"${arguments.len()}";
  List count = %(
    expr (unsigned) (literal (unsigned) $count_text)
  );
  if (arguments) {
    String callee_name = compiler.fresh_name("func_call");
    List callee_binding = compiler.sym.define(%($callee_name), %("Func"));
    locals.push(
      %(
      declare ("Func")
        (bindings (op = (bind $callee_binding ()) $callee))
    ));
    invoked = %(expr ("Func") (ident $callee_binding));
    List query_type = NULL, value_type = NULL, reference_type = NULL;
    List unrepresentable_type = NULL;
    List query = compiler.sym.resolve_global(
      %("x2c_func_reference_type"), &query_type);
    List value_constructor = compiler.sym.resolve_global(
      %("FuncArg_value"), &value_type);
    List reference_constructor = compiler.sym.resolve_global(
      %("FuncArg_reference"), &reference_type);
    List unrepresentable = compiler.sym.resolve_global(
      %("x2c_func_unrepresentable_argument"), &unrepresentable_type);
    List null_binding = compiler.sym.reference(%("NULL"), NULL);
    int index = 0;
    foreach (List argument, arguments) {
      Type source_type = argument.cadr();
      List source_type_literal = compiler.cache_literal_list(
        compiler.sym.normalize_declared_type(source_type));
      List index_expr = %(
        expr (unsigned) (literal (unsigned) "$index")
      );
      List reference_name = compiler.sym.define(
        %(${compiler.fresh_name("func_reference_type")}), %("List"));
      List queried = %(
        expr ("List")
          (call (expr $query_type (ident $query))
                (args $invoked $count $index_expr))
      );
      locals.push(
        %(
        declare ("List")
          (bindings (op = (bind $reference_name ()) $queried))
      ));
      String argument_name = compiler.fresh_name("func_argument");
      List binding = compiler.sym.define(%($argument_name), %("FuncArg"));
      locals.push(
        %(
        declare ("FuncArg") (bindings (bind $binding ()))
      ));

      List address = %(expr () (ident $null_binding));
      if (_expression_is_addressable(compiler, argument)) {
        Type pointer = source_type.reference();
        address = %(expr $pointer (op & (parens $argument)));
      }
      List reference_value = %(
        expr ("FuncArg")
          (call (expr $reference_type (ident $reference_constructor))
                (args $address $source_type_literal))
      );
      List value_value = NULL;
      if (compiler.sym.var_tag_for_type(source_type, NULL)) {
        List boxed = compiler.convert_expression(argument, %("Var"));
        value_value = %(
          expr ("FuncArg")
            (call (expr $value_type (ident $value_constructor))
                  (args $boxed))
        );
      }
      else value_value = %(
        expr ("FuncArg")
          (call
            (expr $unrepresentable_type (ident $unrepresentable))
            (args $invoked $index_expr $source_type_literal))
      );
      List target = %(expr ("FuncArg") (ident $binding));
      locals.push(
        %(
        if (expr ("List") (ident $reference_name))
          (stmnt (expr ("FuncArg") (op = $target $reference_value)))
          (stmnt (expr ("FuncArg") (op = $target $value_value)))
      ));
      values.push(%(expr ("FuncArg") (ident $binding)));
      index++;
    }
    List array_type = %(
      decl ("FuncArg") (bindings (bind () ((dim))))
    );
    storage = %(
      expr ((dim) "FuncArg")
        (cast $array_type
          (expr ((dim) "FuncArg")
            (composite (commas @{values.list_free()}))))
    );
  }
  else {
    List null_binding = compiler.sym.reference(%("NULL"), NULL);
    storage = %(expr () (ident $null_binding));
  }
  List apply_type = NULL;
  List apply = compiler.sym.resolve_global(%("Func_apply"), &apply_type);
  List call = %(
    expr ("Var")
      (call (expr $apply_type (ident $apply))
            (args $invoked $count $storage))
  );
  if (!arguments) return call;
  return %(
    expr ("Var")
      (parens (block @{locals.list_free()} (stmnt $call)))
  );
}

static List _resolve_call(
  Compiler c, Type result_type, List function, List supplied,
  Token origin) {
  match (function) {
    case %(expr ? (op . ?receiver (!set ?field (?name)))): {
      receiver = c.resolve_expression(receiver, origin);
      Type type = receiver.cadr();
      String method = name.str();
      List resolution = c.resolve_postfix_member(type, field, <.>, 1);
      if (!resolution)
        resolution = _resolve_delegate_method(c, type, method, origin);
      if (!resolution && _deferred_receiver(receiver)) {
        List callee = %(
          expr (<macro-expr>) (op . $receiver $field)
        );
        return _finish_call(
          c, result_type, callee, NULL, NULL, supplied, origin);
      }
      if (!resolution)
        c.report_error(
          <type>, %"type ${type.repr()} has no method $name",
          origin, NULL);
      match (resolution) {
        case %(ambiguous *packages):
          _report_imported_method_ambiguity(
            c, type, method, packages, NULL, origin);
        case %(method ?binding (!set ?signature
          ((func (!set ?parameters (?declared *))) *returns))): {
          receiver = _method_bind(c, receiver, type, declared, origin);
          Type signature_type = signature;
          List callee = %(
            expr ((func $parameters) $returns) (ident $binding));
          return _finish_call(
            c, signature_type.apply(), callee,
            signature_type, receiver, supplied, origin);
        }
        case %(delegate ?binding (!set ?signature
               ((func (!set ?parameters (?declared *))) *returns))
               ?path): {
          receiver = _materialize_delegate_receiver(receiver, path);
          Type type = receiver.cadr();
          receiver = _method_bind(c, receiver, type, declared, origin);
          Type signature_type = signature;
          List callee = %(
            expr ((func $parameters) $returns) (ident $binding));
          return _finish_call(
            c, signature_type.apply(), callee,
            signature_type, receiver, supplied, origin);
        }
        case %(field ?access ?field_type): {
          List callee = %(expr $field_type (op $access $receiver $field));
          return _finish_call(
            c, result_type, callee, field_type, NULL, supplied, origin);
        }
      }
    }
  }
  List resolved = c.resolve_expression(function, origin);
  Type type = resolved.cadr();
  Type func_type = c.sym.resolve_key(%("Func"));
  if (type && List.equal(c.sym.resolve_key(type), func_type))
    return _resolve_func_call(c, resolved, supplied, origin);
  return _finish_call(
    c, result_type, resolved, type, NULL, supplied, origin);
}

/** Returns the exact Var tag for a type test, rejecting types without one.
    Enums retain no identity after boxing and cannot be tested this way.
*/
Symbol Compiler.require_var_tag(
  Compiler compiler, Type target, Token origin) {
  Type resolved = NULL;
  Symbol vartag = compiler.sym.var_tag_for_type(target, &resolved);
  if (resolved && resolved.is_enum()) {
    String note =
      "enum values box as the shared i32 family and retain no enum identity";
    compiler.report_error(
      <type>, %"enum type ${target.repr()} cannot be tested with 'is'",
      origin, %($note));
  }
  if (!vartag)
    compiler.report_error(
      <type>,
      %"type ${target.repr()} has no supported Var tag for operator 'is'",
      origin, NULL);
  return vartag;
}

static int _deferred_type_test(Type target) {
  foreach (Var specifier, target)
    match (specifier)
      case %((!or macro-bind macro-slot) *): return 1;
  return 0;
}

/** Builds an exact tag expression, deferring macro type slots until binding. */
List Compiler.var_tag_expression(Compiler c, Type target, Token origin) {
  if (_deferred_type_test(target))
    return %(expr (<macro-expr>) (type-tag $target));
  Symbol tag = c.require_var_tag(target, origin);
  return %(expr ("Symbol") (literal ("Symbol") ${tag.str()} $tag));
}

/* Operands have been resolved in the caller's current semantic scope. */
static List Compiler._binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  if (lhs_type === %(<macro-expr>) ||
      rhs_type === %(<macro-expr>))
    return %(expr (<macro-expr>) (op $operator $lhs $rhs));
  if (operator.is_assignment_op()) {
    Type type = lhs_type;
    if (operator == <=>) rhs = c.convert_expression(rhs, type);
    return %(expr $type (op $operator $lhs $rhs));
  }
  if (operator == <==> || operator == <!=>) {
    if (_type_is_string(lhs_type) && _expr_is_raw_string_literal(rhs))
      rhs = c.convert_expression(rhs, lhs_type);
    else if (_type_is_string(rhs_type) &&
             _expr_is_raw_string_literal(lhs))
      lhs = c.convert_expression(lhs, rhs_type);
  }
  int constant_string = 0;
  if (operator == <+> &&
      _expr_is_string_like(lhs) && _expr_is_string_like(rhs)) {
    Var matched;
    List bindings;
    /* Bare `%(ident *)` also matches literal data ending in <ident>. */
    constant_string =
      !lhs.try_search(%(ident (*)), &matched, &bindings) &&
      !rhs.try_search(%(ident (*)), &matched, &bindings);
    lhs = c.convert_expression(lhs, %("String"));
    rhs = c.convert_expression(rhs, %("String"));
  }
  List lowered = c._protocol_operator_expression(operator, lhs, rhs);
  if (lowered) {
    if (!constant_string) return lowered;
    List cached = c.cache(%(string $lowered));
    return %(expr ("String") $cached);
  }
  if (operator == <in>) {
    c.report_error(
      <type>, "operator 'in' requires an implemented contains member",
      origin, %("receiver type: ${rhs_type.repr()}"));
  }
  /* An operand with no x2c type, such as a preprocessor macro's name,
     cannot be converted for a participant that implements the operator;
     the C compiler would reject the emitted text, so say why here. */
  {
    Symbol member = c.operator_member(operator);
    int lhs_known = lhs_type != NULL;
    int rhs_known = rhs_type != NULL;
    int arithmetic = member && operator != <==> && operator != <!=>;
    if (arithmetic && lhs_known != rhs_known) {
      Type participant = lhs_known ? lhs_type : rhs_type;
      List other = lhs_known ? rhs : lhs;
      if (_converts_operands(c, participant) &&
          c.resolve_protocol_member(participant, member.str()) &&
          other.match(%(expr ? (ident ?))))
        c.report_error(
          <type>, "operand has no x2c type beside a protocol participant",
          origin, %("a preprocessor macro has no type here: cast it, or bind its value to a local"));
    }
  }
  /* `@` has no C meaning, so a static operand pair with no matmul member
     is rejected here rather than emitted as invalid C. */
  if (operator == <@> && !c.sym.is_var_type(lhs_type) &&
      !c.sym.is_var_type(rhs_type)) {
    c.report_error(
      <type>, "operator '@' requires an implemented matmul member",
      origin, %("left type: ${lhs_type.repr()} right type: ${rhs_type.repr()}"));
  }
  Type type = c._binary_op_type(operator, lhs, rhs);
  List operation = %(op $operator $lhs $rhs);
  if (c.sym.is_var_type(lhs_type) ||
      c.sym.is_var_type(rhs_type))
    operation = c.anchor_origin(operation, origin);
  return %(expr $type $operation);
}

static List _resolve_initializer(Compiler c, List node, Token origin) {
  match (node) {
    case %(dotinit ?field ?value):
      return %(dotinit $field ${_resolve_initializer(c, value, origin)});
    case %(indexinit ?index ?value):
      return %(indexinit ${c.resolve_expression(index, origin)}
               ${_resolve_initializer(c, value, origin)});
  }
  return c.resolve_expression(node, origin);
}

static List _resolve_content(
  Compiler c, List input, Type input_type, List content, Token origin) {
  match (content) {
    case %(at m-origin ?inner): {
      if (!c.source_map || c.macro_holes) return input;
      return %(expr $input_type (at ${c.origin} $inner));
    }
    case %(!set ?inner (expr ? ?)):
      return c.resolve_expression(inner, origin);
    case %(ident ?value):
      return _resolve_identifier(c, value, input_type, origin);
    case %(!set ?binding (binding ? ?)):
      if (binding_identity_try_parts(binding, NULL, NULL))
        return _resolve_identifier(c, binding, input_type, origin);
    case %(literal *): return input;
    case %(macro-invoke ?definition ?arguments ?invocation): {
      Token site = c.macro_invocation_site(invocation);
      if (!site) return input;
      return c.expand_macro_invocation_node(
        definition, arguments, site, AST_EXPRESSION);
    }
    case %(macro-slot ? ? *): {
      if (c.macro_holes) return input;
      Var value = c.evaluate_macro_slot(content);
      match (value)
        case %(!set ?expression (expr ? ?)):
          return c.resolve_expression(expression, origin);
      return c.resolve_expression(
        c.lift_macro_lisp_expression(value, origin), origin);
    }
    case %(map *entries): {
      Array resolved = %[];
      foreach (Var entry, entries)
        foreach (Var row, c.evaluate_macro_rows(entry))
          resolved.push(c.resolve_map_entry(row, origin));
      return %(expr $input_type (map @{resolved.list_free()}));
    }
    case %(segments *items): {
      Array resolved = %[];
      Type type = %("String");
      foreach (List item, items) match (item) {
        case %((!set ?tag (!or segvar segexp)) ?value): {
          List expression = c.resolve_expression(value, origin);
          if (_deferred_receiver(expression)) {
            type = %(<macro-expr>);
            resolved.push(%($tag $expression));
            continue;
          }
          resolved.push(
            %(
            $tag ${c.convert_segment_to_string(expression)}
          ));
          continue;
        }
        default: resolved.push(item);
      }
      return %(expr $type
               (segments @{resolved.list_free()}));
    }
    case %(cons ?head ?tail): {
      head = c.resolve_expression(head, origin);
      tail = c.resolve_expression(tail, origin);
      if (_deferred_receiver(head) || _deferred_receiver(tail))
        return %(expr ${input_type ? input_type : %("List")}
                 (cons $head $tail));
      head = c.convert_expression(head, %("Var"));
      List cached = c.cache_cons_cell(head, tail);
      if (cached) return cached;
      return %(expr ${input_type ? input_type : %("List")}
               (cons $head $tail));
    }
    case %(append ?head ?tail): {
      head = c.resolve_expression(head, origin);
      tail = c.resolve_expression(tail, origin);
      head = c.sym.is_var_type(head.cadr())
           ? %(expr ("List") (call "Var_list" (args $head)))
           : c.convert_expression(head, %("List"));
      return %(expr ${input_type ? input_type : %("List")}
               (append $head $tail));
    }
    case %(slice ?receiver ?start ?stop ?step): {
      receiver = c.resolve_expression(receiver, origin);
      if (start) start = c.resolve_expression(start, origin);
      if (stop) stop = c.resolve_expression(stop, origin);
      if (step) step = c.resolve_expression(step, origin);
      List operation = %(slice $receiver $start $stop $step);
      if (input_type === %(<macro-expr>))
        operation = c.anchor_origin(operation, origin);
      return %(expr ${receiver.cadr()} $operation);
    }
    case %(getindex ?receiver ?selector):
      return %(expr $input_type
               (getindex ${c.resolve_expression(receiver, origin)}
                         ${c.resolve_expression(selector, origin)}));
    case %(dstrasgn (targets *targets) ?source): {
      Array resolved = %[];
      foreach (List target, targets)
        resolved.push(c.resolve_expression(target, origin));
      source = c.resolve_expression(source, origin);
      return %(expr ${source.cadr()}
               (dstrasgn (targets @{resolved.list_free()}) $source));
    }
    case %(sizeof (parens ?(List argument))):
      return %(expr $input_type
               (sizeof (parens ${c.resolve_expression(argument, origin)})));
    case %(sizeof ?(List argument)):
      return %(expr $input_type
               (sizeof ${c.resolve_expression(argument, origin)}));
    case %(va-arg ?argument ?declaration):
      return %(expr $input_type
               (va-arg ${c.resolve_expression(argument, origin)}
                       ${c.resolve_expression(declaration, origin)}));
    case %(commas *expressions): {
      Array resolved = %[];
      foreach (List expression, expressions)
        resolved.push(c.resolve_expression(expression, origin));
      List values = resolved.list_free();
      Type type = input_type;
      if (values) type = values.last().list().cadr();
      return %(expr $type (commas @values));
    }
    case %(splice ?expression):
      return %(expr $input_type
               (splice ${c.resolve_expression(expression, origin)}));
    case %(array *elements): {
      Array resolved = %[];
      foreach (List element, elements)
        resolved.push(c.resolve_expression(element, origin));
      return %(expr $input_type (array @{resolved.list_free()}));
    }
    case %(lambda ?parameters (captures *captures) ?body): {
      if (c.macro_holes) return input;
      return c.bind_lambda_expression(input_type, parameters, captures, body);
    }
    case %(lambda ?parameters ?body): {
      if (c.macro_holes) return input;
      return c.bind_lambda_expression(input_type, parameters, NULL, body);
    }
    case %((!or offsetof nil cache macro-bind) *): return input;
    case %(parens ?inner): {
      inner = c.resolve_expression(inner, origin);
      Type inner_type = inner.cadr();
      return %(expr $inner_type (parens $inner));
    }
    case %(initval *choices): {
      List header = NULL;
      List cases = Ast.initializer_cases(content, &header);
      Array resolved = %[];
      if (header) {
        Array inputs = %[];
        foreach (List argument, header.cdr()) {
          List value = c.resolve_expression(argument.cadr(), origin);
          inputs.push(%(${argument.car()} $value));
        }
        resolved.push(%(input @{inputs.list_free()}));
      }
      foreach (List choice, cases) {
        (List condition, List path, Type destination, List value) = choice;
        if (condition) condition = c.resolve_expression(condition, origin);
        value = c.resolve_expression(value, origin);
        resolved.push(%($condition $path $destination $value));
      }
      return %(expr $input_type (initval @{resolved.list_free()}));
    }
    case %(composite (commas *elements)): {
      Array values = %[];
      foreach (List element, elements)
        values.push(_resolve_initializer(c, element, origin));
      return %(expr $input_type
               (composite (commas @{values.list_free()})));
    }
    case %(cast (!set ?declaration (decl *)) ?operand): {
      operand = c.resolve_expression(operand, origin);
      declaration = c.bind_syntax(declaration, AST_BLOCK, c.return_type);
      List typed = %(declare @{declaration.list().cdr()});
      Type type = operand.cadr() === %(<macro-expr>)
                ? %(<macro-expr>) : typed.type_from_ast();
      return %(expr $type (cast $declaration $operand));
    }
    case %(type-tag ?target):
      return c.var_tag_expression(target, origin);
    case %(is-type ?operand ?target_syntax): {
      List lhs = c.resolve_expression(operand, origin);
      Type lhs_type = lhs.cadr();
      Type target = target_syntax;
      if (_deferred_receiver(lhs) || _deferred_type_test(target))
        return %(expr (<macro-expr>) (is-type $lhs $target));
      if (!c.sym.is_var_type(lhs_type))
        c.report_error(
          <type>, "operator 'is' requires Var on the left",
          origin, %("operand type: ${lhs_type.repr()}"));
      if (target === %(void) || target === %("Void")) {
        List callee = _resolve_identifier(c, %"Var_is_void", NULL, origin);
        return %(expr (int) (call $callee (args $lhs)));
      }
      Symbol vartag = c.require_var_tag(target, origin);
      String tagsym = %"${(unsigned long) vartag}";
      List callee = _resolve_identifier(c, %"Var_is", NULL, origin);
      return %(expr (int) (call $callee (args
        $lhs (expr ("Symbol") $tagsym))));
    }
    case %(is-symbol ?operand ?selector): {
      List lhs = c.resolve_expression(operand, origin);
      selector = c.resolve_expression(selector, origin);
      (Var lhs_tag, Type lhs_type) = lhs;
      (Var selector_tag, Type selector_type) = selector;
      if (_deferred_receiver(lhs) ||
          _deferred_receiver(selector))
        return %(expr (<macro-expr>) (is-symbol $lhs $selector));
      if (!c.sym.is_var_type(lhs_type))
        c.report_error(
          <type>, "operator 'is' requires Var on the left",
          origin, %("operand type: ${lhs_type.repr()}"));
      if (!c.sym.is_named_value_type(selector_type, "Symbol"))
        c.report_error(
          <type>, "operator 'is' requires a type or Symbol on the right",
          origin, %("operand type: ${selector_type.repr()}"));
      List callee = _resolve_identifier(c, %"Var_is", NULL, origin);
      return %(expr (int) (call $callee (args $lhs $selector)));
    }
    case %(index ?receiver ?selector): {
      receiver = c.resolve_expression(receiver, origin);
      selector = c.resolve_expression(selector, origin);
      if (_deferred_receiver(receiver) ||
          _deferred_receiver(selector))
        return %(expr (<macro-expr>) (index $receiver $selector));
      List resolved = c._postfix_index_expression(receiver, selector);
      if (resolved) return resolved;
      Type receiver_type = receiver.cadr();
      c.report_error(
        <parse>, receiver_type.is_typedef_name()
          ? %"type $receiver_type does not support getindex"
          : %"type $receiver_type does not support indexing",
        origin, %());
    }
    case %(call ?(String callee) (args *supplied)): {
      List arguments = _resolve_call_arguments(c, NULL, supplied, origin);
      return %(expr $input_type
               (call $callee (args @arguments)));
    }
    case %(call ?callee (args *supplied)):
      return _resolve_call(c, input_type, callee, supplied, origin);
    case %(op (!or (!set ?operator .) (!set ?operator (!quote ->)))
              ?receiver (!set ?field (*))): {
      receiver = c.resolve_expression(receiver, origin);
      Type receiver_type = receiver.cadr();
      List resolution = c.resolve_postfix_member(
        receiver_type, field, operator, 0);
      match (resolution)
        case %(field ?access ?field_type):
          return %(expr $field_type (op $access $receiver $field));
      Type type = _deferred_receiver(receiver)
                ? %(<macro-expr>) : NULL;
      return %(expr $type (op $operator $receiver $field));
    }
    case %(op ?operator ?operand): {
      List lhs = c.resolve_expression(operand, origin);
      Type lhs_type = lhs.cadr();
      if (operator == <*> && operand.list().cadr().list().car() == <&> &&
          lhs_type.car() != <&>) return lhs;
      if (lhs_type === %(<macro-expr>))
        return %(expr (<macro-expr>) (op $operator $lhs));
      List lowered = operator == <->
        ? c._protocol_operator_expression(operator, lhs, NULL) : NULL;
      if (lowered) return lowered;
      Type type = lhs_type;
      switch (operator.symbol()) {
        case <!>: type = %(int);                 break;
        case <*>: type = type.dereference(); break;
        case <&>: type = type.reference();   break;
        case <~>: case <+>: case <->: {
          type = c.sym.resolve_numeric_type(type);
          if (type && type.is_integral()) type = type.promote();
          if (!type && lhs_type && operator == <->)
            c.report_error(
              <type>,
              "unary '-' requires a numeric type or implemented neg",
              origin, %("operand type: ${lhs_type.repr()}"));
          if (!type) type = lhs_type;
          break;
        }
      }
      return %(expr $type (op $operator $lhs));
    }
    case %(op ?operator ?condition ?ontrue ?onfalse): {
      condition = c.resolve_expression(condition, origin);
      ontrue = c.resolve_expression(ontrue, origin);
      onfalse = c.resolve_expression(onfalse, origin);
      (Var true_tag, Type true_type) = ontrue;
      (Var false_tag, Type false_type) = onfalse;
      if (condition.cadr() === %(<macro-expr>) ||
          true_type === %(<macro-expr>) ||
          false_type === %(<macro-expr>))
        return %(
          expr (<macro-expr>)
            (op $operator $condition $ontrue $onfalse)
        );
      Type type = true_type, left = c.sym.resolve_numeric_type(type);
      Type right = c.sym.resolve_numeric_type(false_type);
      if (left && right) type = left.widest(right);
      return %(expr $type (op $operator $condition $ontrue $onfalse));
    }
    case %(op ?operator ?left ?right): {
      List lhs = c.resolve_expression(left, origin);
      List rhs = c.resolve_expression(right, origin);
      return c._binary_expression(operator, lhs, rhs, origin);
    }
    case %(postfix ?operator ?operand): {
      operand = c.resolve_expression(operand, origin);
      Type operand_type = operand.cadr();
      if (operand_type === %(<macro-expr>))
        return %(expr (<macro-expr>) (postfix $operator $operand));
      return %(expr $operand_type (postfix $operator $operand));
    }
    case %(tadapt ?target ?source): {
      target = c.resolve_expression(target, origin);
      source = c.resolve_expression(source, origin);
      match (target)
        case %(expr (!set ?syntax (typedef ?target_type)) ?): {
          Type type = c.sym.resolve_key(syntax);
          if (!type || !type.is_pointer() ||
              !type.dereference().is_function())
            c.report_error(
              <macro>,
              "typed callback adapter target must name a function pointer",
              origin,
              type ? %("target type: ${type.repr()}") : NULL);
          return %(expr ($target_type)
                   (tadapt ${c.origin} $source));
        }
      c.report_error(
        <macro>, "typed callback adapter target must be a typedef name",
        origin, NULL);
    }
  }
  return input;
}

/** Resolves the key and value of one `(map-entry key value)` AST row.
    Any other shape is reported at `origin` as a parse error.
*/
List Compiler.resolve_map_entry(Compiler compiler, List input, Token origin) {
  match (input)
    case %(map-entry ?key ?value):
      return %(map-entry
        ${compiler.resolve_expression(key, origin)}
        ${compiler.resolve_expression(value, origin)});
  compiler.report_error(<parse>, "expected one Map entry", origin, NULL);
}

/** Resolves and type-annotates one expression AST in current compiler state.
    Existing `expr` type annotations are resolved semantic types.
    Already-resolved trees without unresolved descendants and non-expression
    inputs are returned unchanged; abstract declarations use the declaration
    binder. `origin` anchors diagnostics and generated operations that must
    retain source position.
*/
List Compiler.resolve_expression(Compiler compiler, List input, Token origin) {
  match (input) {
    case %(decl *):
      return compiler.bind_syntax(input, AST_BLOCK, compiler.return_type);
    case %(expr ?type ?(List content)): {
      if (type && !_expression_requires_resolution(compiler, input))
        return input;
      return _resolve_content(compiler, input, type, content, origin);
    }
  }
  return input;
}

/* Each parser entry consumes exactly its grammar level and leaves
   `compiler.token` at the first token belonging to its caller. Operators are
   resolved as their AST nodes are built, so higher levels receive typed or
   deferred expression nodes. */
static List _parse_binary_level_tail(Compiler c, int level, List lhs) {
  int first = 1;
  while (_precedence(c.peek(0)) == level ||
         (level == 7 && _is_type_operator(c))) {
    if (_is_type_operator(c)) {
      Token origin = c.token;
      c.next();
      int negate = c.peek(0) == <ident> &&
                   c.token.text == "not";
      if (negate) c.next();
      List test;
      if (_is_type_selector_start(c)) {
        Type target = _parse_is_type(c, origin);
        test = c.resolve_expression(
          %(expr () (is-type $lhs $target)), origin);
      }
      else {
        List selector = _parse_cast(c);
        test = c.resolve_expression(
          %(expr () (is-symbol $lhs $selector)), origin);
      }
      lhs = negate
        ? c.resolve_expression(%(expr () (op ! $test)), origin)
        : test;
      continue;
    }
    Symbol op = c.peek(0);
    Token origin = c.token;
    c.next();
    List rhs = _parse_binary_level(c, level + 1);
    if (first) {
      lhs = c.resolve_expression(lhs, origin);
      first = 0;
    }
    rhs = c.resolve_expression(rhs, origin);
    lhs = c._binary_expression(op, lhs, rhs, origin);
  }
  return lhs;
}

static List _parse_binary_level(Compiler compiler, int level) {
  if (level > 10) return _parse_cast(compiler);
  return _parse_binary_level_tail(
    compiler, level, _parse_binary_level(compiler, level + 1));
}

static List _parse_binary_levels_from(Compiler compiler, List lhs) {
  for (int level = 10; level > 0; level--)
    lhs = _parse_binary_level_tail(compiler, level, lhs);
  return lhs;
}

static List _parse_binary_ops(Compiler compiler) =>
  _parse_binary_level(compiler, 1);

static int _destructure_identifier(List expression) => !!expression.match(%(
  !or (expr ? (ident ?))
      (expr ? (parens (expr ? (op * (expr (& *) (ident ?))))))
));

static List _destructure_assignment_targets(Compiler compiler, List lhs) {
  match (lhs)
    case %(expr ? (parens ?target)): {
      if (_destructure_identifier(target)) return %(targets $target);
      match (target)
        case %(expr ? (commas *targets)): {
          foreach (List entry, targets) {
            if (_destructure_identifier(entry)) continue;
            compiler.report_error(
              <parse>, "unsupported destructuring assignment target",
              compiler.token,
              %("destructuring targets must be simple identifiers"));
          }
          return %(targets @targets);
        }
    }
  return NULL;
}

static List _parse_comma_list(Compiler compiler) {
  Array expressions = %[];
  do {
    compiler.expect(<,>);
    expressions.push(compiler.parse_assignment());
  } while (compiler.peek(0) == <,>);
  return expressions.list_free();
}

static List _parse_composite_elements(Compiler compiler) {
  Array elements = %[];
  while (compiler.peek(0) != <"}">) {
    List element = _test_dot_init(compiler) ? _parse_designated_init(compiler)
                 : compiler.peek(0) == <[> ? _parse_designated_init(compiler)
                 : compiler.parse_assignment();
    elements.push(element);
    if (!compiler.test(<,>)) break;
  }
  return elements.list_free();
}

static List _parse_composite(Compiler compiler) {
  compiler.expect(<"{">);
  List elems = _parse_composite_elements(compiler);
  elems = %( commas @elems );
  compiler.expect(<"}">);
  return %(expr () ( composite $elems ));
}

/** Parses and resolves one complex identifier expression.
    Parsing starts at `compiler.token` and leaves it after the identifier.
*/
List Compiler.parse_variable(Compiler c) {
  Token origin = c.token;
  List name = c.parse_complex_identifier();
  Token after = c.token;
  List result = c.resolve_expression(%(expr () (ident $name)), origin);
  if (c.source_facts) match (result)
    case %(expr ?type (ident ?binding)):
      c.record_source_reference(binding, type, origin, after);
  if (c.source_map &&
      (origin.text == "__FILE__" || origin.text == "__LINE__"))
    match (result) case %(expr ?type ?content):
      return %(expr $type ${c.anchor_origin(content, origin)});
  return result;
}

static List _parse_conditional_tail(Compiler compiler, List condition) {
  Token origin = compiler.token;
  if (!compiler.test(<?>)) return condition;
  List ontrue = compiler.parse_expression();
  compiler.expect(<:>);
  return compiler.resolve_expression(
    %(expr () (op ? $condition $ontrue ${compiler.parse_conditional()})),
    origin);
}

/** Parses a binary expression and its optional conditional tail.
    The false arm recurses at conditional precedence, making `?:`
    right-associative, and `compiler.token` stops after the expression.
*/
List Compiler.parse_conditional(Compiler compiler) =>
  _parse_conditional_tail(compiler, _parse_binary_ops(compiler));

static List _parse_assignment_tail(Compiler compiler, List lhs) {
  Symbol op = compiler.peek(0);
  Token origin = compiler.token;
  if (!op.is_assignment_op()) return lhs;
  List targets = op == <=>
               ? _destructure_assignment_targets(compiler, lhs) : NULL;
  compiler.next();
  List rhs = compiler.parse_assignment();
  if (targets) match (rhs)
    case %(expr ?type ?): return %(expr $type (dstrasgn $targets $rhs));
  return compiler.resolve_expression(%(expr () (op $op $lhs $rhs)), origin);
}

/** Parses one right-associative assignment expression.
    A parenthesized identifier list on the left becomes a destructuring
    assignment only for `=`. `compiler.token` stops after the expression.
*/
List Compiler.parse_assignment(Compiler compiler) =>
  _parse_assignment_tail(compiler, compiler.parse_conditional());

/* Preserve each C token's escape boundary and the ordinary raw-string type. */
static List _parse_c_string_literals(Compiler compiler) {
  List first = compiler.parse_atomic_literal();
  if (compiler.peek(0) != <lit-char*>) return first;
  Array spellings = %[];
  spellings.push(first.caddr().caddr());
  while (compiler.peek(0) == <lit-char*>) {
    spellings.push(compiler.token.text);
    compiler.next();
  }
  String text = %" ".join(spellings.list_free());
  return %(expr (* char) (literal (* char) $text));
}

/** Parses one primary expression or expression-valued macro slot.
    Dispatch starts at `compiler.token` to the selected literal, identifier,
    grouping, or macro parser and leaves the token after that primary form.
*/
List Compiler.parse_primary(Compiler compiler) {
  List slot = compiler.try_parse_macro_slot(<expression>);
  if (slot) return slot;
  switch (compiler.peek(0)) {
    case <"$(">: return compiler.parse_macro_lisp_expression();
    case <lit-char*>:  return _parse_c_string_literals(compiler);
    case <$>:          return compiler.try_parse_macro_expression();
    case <ident>: {
      Var candidate;
      if (compiler.semantic_binding_facts().try_get(
        %(with-name ${compiler.token.text}), &candidate)) {
        List binding = compiler.sym.lookup(%(${compiler.token.text}), NULL);
        if (binding && List.equal(binding, candidate)) {
          Var stored;
          if (compiler.semantic_binding_facts().try_get(
            %(with $binding), &stored)) {
            List expression = stored;
            compiler.next();
            match (expression)
              case %(expr ?type ?):
                return %(expr $type (parens $expression));
          }
        }
      }
      List keyword = compiler.try_parse_macro_expression();
      if (keyword) return keyword;
      if (compiler.token.text == "va_arg") return _parse_va_arg(compiler);
      return compiler.parse_variable();
    }
    case <"(">:       return _parse_parens(compiler);
    case <"{">:       return _parse_composite(compiler);
    case <"%(">:      return compiler.parse_list_literal();
    case <"%<<">:     return compiler.parse_symbol_set_literal();
    case <"%[">:      return compiler.parse_array_literal();
    case <"%{">:      return compiler.parse_map_literal();
    case <"%\"">:     return compiler.parse_string_literal();
    case <"%!">:      return compiler.parse_lambda_literal();
  }
  return compiler.parse_atomic_literal();
}

static List _parse_expression_tail(Compiler compiler, List expr) {
  if (compiler.peek(0) == <,>) {
    expr = cons(expr, _parse_comma_list(compiler));
    List last = expr.last(), type = last.cadr();
    return %(expr $type (commas @expr));
  }
  return expr;
}

/** Parses an assignment expression and any following comma expressions.
    A comma expression retains source order and takes the type of its final
    value. `compiler.token` stops at the first token outside the expression.
*/
List Compiler.parse_expression(Compiler compiler) =>
  _parse_expression_tail(compiler, compiler.parse_assignment());

static List _finish_parenthesized_statement_expression(
  Compiler compiler, List expression, int postfix) {
  if (postfix) expression = _parse_postfix_tail(compiler, expression);
  expression = _parse_binary_levels_from(compiler, expression);
  expression = _parse_conditional_tail(compiler, expression);
  expression = _parse_assignment_tail(compiler, expression);
  expression = _parse_expression_tail(compiler, expression);
  compiler.expect(<;>);
  return %(stmnt $expression);
}

/** Parses a statement beginning with `(`.

    The ordinary parameter parser consumes the contents once: one anonymous
    parameter is a cast type, while named parameters are destructuring
    declarations. Everything following an ordinary parenthesized expression
    resumes at the postfix tail it had already reached. This entry consumes
    the terminating `;` and returns `(stmnt expression)` or an origin-anchored
    `(dstrdecl ...)`.
*/
List Compiler.parse_parenthesized_statement(Compiler c) {
  Token origin = c.token;
  c.expect(
    <(>);
  if (c.test_declaration()) {
    List parameters = c.parse_parameter_list();
    c.expect(<)>);
    match (parameters)
      case %((param ?type
                    (!set ?binding (bind () ?)))): {
        List declaration = %(decl $type (bindings $binding));
        List operand = _parse_cast(c);
        List expression = %(expr $type (cast $declaration $operand));
        return _finish_parenthesized_statement_expression(c, expression, 0);
      }
    c.expect(<=>);
    List source = c.parse_assignment();
    c.expect(<;>);
    return c.anchor_origin(
      %(dstrdecl (params @parameters) $source), origin);
  }

  List expression = c.parse_expression();
  c.expect(<)>);
  match (expression)
    case %(expr ?type ?):
      expression = %(expr $type (parens $expression));
  return _finish_parenthesized_statement_expression(c, expression, 1);
}

/* Answer whether an expression is certainly a zero integer literal,
   certainly a nonzero one, or neither.  Parentheses are unwrapped because
   they are the one wrapper that folds away without evaluation, and
   `out_text` receives the spelling when there is one.

   The tokenizer already accepted the spelling and Type.numeric_literal
   already turned its prefix and suffix into the node's own type, so what
   remains here is whether a digit is nonzero.  A float, a name, or an enum
   constant answers <unknown>; the null-pointer guard below stays silent
   when it cannot decide. */
static Symbol _integer_literal_kind(List expr, String *out_text) {
  match (expr) {
    case %(expr ? (parens ?inner)):
      return _integer_literal_kind(inner, out_text);
    case %(expr ? (literal ?ltype ?text)): {
      String spelling = text.str(), Type type = ltype.list();
      if (!spelling || !type.is_integral()) return <unknown>;
      char *s = spelling;
      // A character constant is integral too, but it is not spelled in
      // digits, and '\0' is a null pointer constant.
      if (s[0] < '0' || s[0] > '9') return <unknown>;
      if (out_text) *out_text = spelling;
      char radix = s[0] == '0' ? s[1] : 0;
      int i = radix == 'x' || radix == 'X' || radix == 'b' ||
              radix == 'B' || radix == 'o' || radix == 'O' ? 2 : 0;
      for (; s[i] && s[i] != 'u' && s[i] != 'U' &&
             s[i] != 'l' && s[i] != 'L'; i++)
        if (s[i] != '0') return <nonzero>;
      return <zero>;
    }
  }
  return <unknown>;
}

/* What a pointer may point at for the rule below to call two pointers
   different: a named struct, union, or enum, or a builtin scalar.  void is
   excluded because C converts it, and a function, an array, or a name the
   resolver left untouched is excluded because the compiler does not know
   enough about it to say. */
static int _known_pointee(Type type) {
  if (type === %(void)) return 0;
  return type.is_aggregate_tag() || type.is_enum_tag() || !!type.scalar();
}

/* Report whether two types point at provably different things.  Every
   level of both chains is resolved through the typedef table first, so a
   spelling difference, Ast against List or Pool against struct Pool *, is
   not a difference here. */
static int _unrelated_pointers(Compiler compiler, Type source, Type target) {
  source = compiler.sym.resolve_key(source);
  target = compiler.sym.resolve_key(target);
  if (!source.is_pointer() || !target.is_pointer()) return 0;
  loop {
    source = compiler.sym.resolve_key(source.cdr());
    target = compiler.sym.resolve_key(target.cdr());
    if (source == target) return 0;
    if (!source.is_pointer() || !target.is_pointer())
      return _known_pointee(source) && _known_pointee(target);
  }
}

/* Report whether either name is defined, directly or through further
   typedefs, from the other.  A name and the name it was defined from are
   the same type by construction: an Array is a Block, an Ast is a List.
   C lets them stand for each other in both directions. */
static int _same_typedef_line(Compiler compiler, Type one, Type other) {
  for (int reversed = 0; reversed < 2; reversed++) {
    Type walk = reversed ? other : one, stop = reversed ? one : other;
    int hops = 0;
    while (walk) {
      walk = compiler.sym.next_typedef(walk, &hops);
      if (List.equal(walk, stop)) return 1;
    }
  }
  return 0;
}

/* A proven nonzero operand yields its short spelling; unknown forms yield
   NULL. C11 6.3.2.3p3 requires an integer constant expression with value zero,
   not just the token 0. x2c does not fold constants, so this recognizes
   only syntactically decidable forms. A wrong guess would reject legal C. */
static String _not_null_pointer_constant(Compiler compiler, List expr) {
  match (expr) {
    case %(expr ? (parens ?inner)):
      return _not_null_pointer_constant(compiler, inner);
    // sizeof is an integer constant expression, but never a zero-valued
    // one: no type in C has size zero.
    case %(expr ? (sizeof *)):
      return "sizeof";
    // Unary minus or plus over a nonzero literal is still nonzero.  The
    // pattern has a fixed length, so a binary use of the same operator,
    // which would need folding, does not match it.
    case %(expr ? (op ?oper ?operand)): {
      Symbol op = oper;
      if (op != <-> && op != <+>) return NULL;
      String inner = NULL;
      if (_integer_literal_kind(operand, &inner) != <nonzero>) return NULL;
      return %"$op$inner";
    }
    // A variable is never a permitted operand of an integer constant
    // expression, so an integral one cannot spell a null pointer even when
    // it happens to hold zero at run time.  Enumerations are excluded
    // because an enum constant and a variable of enum type are spelled
    // identically here, and a zero-valued enum constant *is* a null pointer
    // constant.
    case %(expr ?type (ident (binding ? ?name))): {
      Type vartype = compiler.sym.resolve_numeric_type(type.list());
      if (!vartype || vartype.is_enum() || !vartype.is_integral()) return NULL;
      return name.str();
    }
  }
  String spelling = NULL;
  if (_integer_literal_kind(expr, &spelling) != <nonzero>) return NULL;
  return spelling;
}

// Build the T_str / T_<target> converter call for a type pair, or return
// NULL when no such converter is declared.  When name is given it receives
// the name that was looked for, which the caller reports on failure.
//
// Both sides of the comparison are spelled the way the collector recorded
// them, so this matches for a typedef name -- "Symbol" against
// Symbol_str's collected ("Symbol") parameter -- and never for a builtin,
// whose collected parameter is the symbol int rather than the string
// "int".  That asymmetry is why the speculative callers below have to ask
// this function rather than guess from the type.
/* The exact reader for a built-in Var payload is `Var.<target>`: it checks the
   tag and yields NULL for any other kind. `Var.pointer` checks nothing, so
   trying it first let a List-valued Var read as a String. Only a raw native
   pointer with no typed Var reader should still take that path. */
static List _var_exact_reader(Compiler compiler, List expr, Type target) {
  if (!target.match(%(?))) return NULL;
  String reader = %"Var_${target.car().str().lower()}", List readertype = NULL;
  List binding = compiler.sym.resolve_global(%($reader), &readertype);
  if (!binding || !readertype || readertype.car() is not <list>) return NULL;
  List function = readertype.car();
  (Var function_tag, List parameters) = function;
  if (function_tag != <func> || !parameters || parameters.cdr() ||
      !List.equal(parameters.car(), %("Var")) ||
      !List.equal(readertype.cdr(), target))
    return NULL;
  List callee = %(expr $readertype (ident $binding));
  return %(expr $target (call $callee (args $expr)));
}

/* A converter's result exists only for the operator that asked for it.
   Only a conversion from a number is known to be fresh; a converter from a
   handle type may return storage its source still owns. */
static List _converted_temporary(
  Compiler compiler, List call, Type owner, Type target) {
  if (compiler.sym.resolve_numeric_type(owner) &&
      compiler.resolve_protocol_member(target, "discard")) {
    List binding = _call_binding(_expression_node(call));
    if (binding) _note_fresh_callee(compiler, binding);
  }
  return call;
}

static List _converter_owned_call(
  Compiler compiler, List expr, Type owner, Type target, int *declared) {
  String typename = owner.car().str(), targetedname = target.car().str();
  /* A package type is spelled `pkg__Name`; its converter from an external
     owner is `pkg__owner_name`, the package's own spelling of `owner.name`. */
  String prefix = "";
  int split = targetedname.find("__");
  if (split > 0) {
    prefix = targetedname[0:split + 2];
    targetedname = targetedname[split + 2:];
  }
  String convfuncname = targetedname == "String"
                      ? %"$prefix${typename}_str"
                      : %"$prefix${typename}_${targetedname.lower()}";
  List cvrtrtype = NULL;
  List converter_binding = compiler.sym.resolve_global(
    %($convfuncname), &cvrtrtype);
  if (declared) *declared = !!converter_binding || !!cvrtrtype;
  List callee = %(expr $cvrtrtype (ident $converter_binding));
  List argument = expr.cadr() == owner
    ? expr : %(expr $owner $expr);
  if (cvrtrtype && cvrtrtype.car() is <list>) {
    List function = cvrtrtype.car();
    (Var function_tag, List parameters) = function;
    Type result = cvrtrtype.cdr();
    if (function_tag == <func> &&
        parameters && !parameters.cdr() &&
        List.equal(parameters.car(), owner) &&
        List.equal(result, target))
      return _converted_temporary(
        compiler, %(expr $target (call $callee (args $argument))), owner,
        target);
  }
  /* The relaxed form exists so a converter may spell its parameter as a
     typedef of the source type, which the exact comparison above rejects.
     It still takes exactly one argument: matching a longer parameter list
     emitted a call with the arguments missing. */
  if (cvrtrtype.match(%((func (($typename))) ?)))
    return _converted_temporary(
      compiler, %(expr $target (call $callee (args $argument))), owner,
      target);
  return NULL;
}

static List _converter_call(
  Compiler compiler, List expr, Type type, Type target) {
  if (!type.match(%(?)) || !target.match(%(?))) return NULL;
  int hops = 0;
  for (Type owner = type; owner; ) {
    if (owner == target) return NULL;
    if (owner.match(%(?))) {
      int declared = 0;
      List converted = _converter_owned_call(
        compiler, expr, owner, target, &declared);
      if (converted || declared) return converted;
    }
    if (!owner.is_typedef_name() && !owner.is_typedef()) break;
    owner = compiler.sym.next_typedef(owner, &hops);
  }
  return NULL;
}

/* Promote raw string expressions while caching only exact literal leaves.
   Parentheses and conditional arms retain their evaluation structure; a
   dynamic leaf still calls String_new each time it is selected. */
static List _raw_string_to_string(Compiler compiler, List expr) {
  match (expr) {
    case %(expr (!or (* char) ((dim *) char))
        (literal (!or (* char) ((dim *) char)) ?)): {
      List value = %(expr ("String") (call "String_new" (args $expr)));
      return %(expr ("String") ${compiler.cache(%(string $value))});
    }
    case %(expr (!or (* char) ((dim *) char)) (parens ?inner)): {
      List converted = _raw_string_to_string(compiler, inner);
      return %(expr ("String") (parens $converted));
    }
    case %(expr (!or (* char) ((dim *) char))
        (op ? ?condition ?ontrue ?onfalse)): {
      List converted_true = _raw_string_to_string(compiler, ontrue);
      List converted_false = _raw_string_to_string(compiler, onfalse);
      return %(expr ("String")
               (op ? $condition $converted_true $converted_false));
    }
  }

  return %(expr ("String") (call "String_new" (args $expr)));
}

/* C positional initialization skips unnamed bit-fields, not anonymous
   aggregate subobjects. The ordered metadata retains both kinds. */
static List _next_initializer_field(List fields) {
  while (fields) {
    List row = fields.car();
    Type type = row.cadr();
    if (row.car().truth() || !type.is_bitfield()) break;
    fields = fields.cdr();
  }
  return fields;
}

/* Paths are stacks of (owner kind selector type following-fields) frames.
   The same subobject walk owns conversion and deferred native assignment. */
static Type _initializer_type(List path, Type root) {
  if (!path) return root;
  (Type owner, Symbol kind, Var selector, Type type, List rest) =
    path.car().list();
  return type;
}

static List _initializer_field(
  Type owner, List fields, List parent) {
  fields = _next_initializer_field(fields);
  if (!fields) return NULL;
  List row = fields.car();
  return cons(%($owner field ${row.car()} ${row.cadr()} ${fields.cdr()}),
              parent);
}

static List _initializer_first(
  Compiler c, Type type, List parent) {
  Type owner = c.sym.resolve_key(type);
  if (owner.is_array()) {
    List zero = %(expr (int) (literal (int) "0"));
    return cons(%($owner index $zero ${owner.cdr()} ()), parent);
  }
  if (owner.is_aggregate())
    return _initializer_field(owner, c.sym.field_order(owner).cdr(), parent);
  return NULL;
}

// Decode only a literal fact; native expressions are never evaluated here.
static int _initializer_integer(List expression, unsigned long long *value) {
  String text = NULL;
  match (expression) {
    case %(expr ? (literal ? ?spelling)): text = spelling;
    case %(?(String spelling)): text = spelling;
  }
  if (!text || text[0] < '0' || text[0] > '9') return 0;
  char *end, *digits = text;
  int base = 0;
  if (text[0] == '0' && (text[1] == 'b' || text[1] == 'B')) {
    digits += 2;
    base = 2;
  }
  unsigned long long decoded = strtoull(digits, &end, base);
  while (*end == 'u' || *end == 'U' || *end == 'l' || *end == 'L') end++;
  if (*end) return 0;
  *value = decoded;
  return 1;
}

/** Returns native definition/reference types for a compound literal.
    Macro expansion stays in the original cast; named tags let later sizeof
    expressions reuse that exact layout without a new scope. */
List Compiler.initializer_native_types(Compiler c, Type type) {
  Type base = type.base_type(), definition = base, reference = base;
  match (base) {
    case %((!set ?kind (!or struct union)) (gensym ?) ?body): {
      String name = c.fresh_name("initializer_type");
      definition = %($kind $name $body);
      reference = %($kind $name);
    }
    case %((!set ?kind (!or struct union)) (!set ?body (fields *))): {
      String name = c.fresh_name("initializer_type");
      definition = %($kind $name $body);
      reference = %($kind $name);
    }
    case %((!set ?kind (!or struct union)) ?name (fields *)):
      reference = %($kind $name);
  }
  Array definitions = %[], references = %[];
  for (List rest = type; rest != base; rest = rest.cdr()) {
    Var modifier = rest.car(), reused = modifier;
    match (modifier)
      case %(dim ?dimension): {
        List bound = dimension;
        unsigned long long count;
        int captured = 0;
        match (bound)
          case %(expr ? (sizeof (parens
            (struct ?name (fields
              (declare (char) (bindings (bind ? ((dim ?)))))))))): {
            List prior = %(expr (unsigned long)
              (sizeof (parens (struct $name))));
            reused = %(dim $prior);
            captured = 1;
          }
        if (bound && !captured && !_initializer_integer(bound, &count)) {
          String name = c.fresh_name("initializer_bound");
          Type bytes = %((dim $bound) char);
          List field = bytes.declaration_ast(%("bytes"));
          Type declared = %(struct $name (fields $field));
          List size = %(expr (unsigned long) (sizeof (parens $declared)));
          List prior = %(expr (unsigned long)
            (sizeof (parens (struct $name))));
          modifier = %(dim $size);
          reused = %(dim $prior);
        }
      }
    definitions.push(modifier);
    references.push(reused);
  }
  definition = definitions.list_free().append(definition);
  reference = references.list_free().append(reference);
  return %($definition $reference);
}

/* An enum constant captures one native index expansion where the original
   designator occurred. Its ordinary cast shape survives normalization. */
static List _initializer_index(Compiler c, List index, List *reference) {
  match (index)
    case %(expr ? (cast (enum ((op = ?binding ?original)))
                       (!set ?value (expr ? (ident ?binding))))): {
      *reference = value;
      return index;
    }
  unsigned long long at;
  if (_initializer_integer(index, &at)) {
    *reference = index;
    return index;
  }
  Type type = index.cadr();
  List binding = c.sym.introduce(c.fresh_name("initializer_index"));
  c.sym.bind_identity(NULL, binding, type.declaration_ast(binding));
  Type native = %(enum ((op = $binding $index)));
  *reference = %(expr $type (ident $binding));
  return %(expr $type (cast $native ${*reference}));
}

/* Cursor offsets are literal facts even when their native starting index
   is not. Keep one base-plus-offset expression instead of nested increments. */
static void _initializer_position(
  List index, List *base, unsigned long long *offset) {
  *base = NULL;
  if (_initializer_integer(index, offset)) return;
  match (index)
    case %(expr ? (op + (expr ? (parens ?origin)) ?amount)):
      if (_initializer_integer(amount, offset)) {
        *base = origin;
        return;
      }
  *base = index;
  *offset = 0;
}

static List _initializer_drop_bound(
  List condition, List bound, List base, unsigned long long minimum) {
  match (condition) {
    case %(expr ? (op && (expr ? (parens ?left))
                         (expr ? (parens ?right)))):
      return _initializer_and(
        _initializer_drop_bound(left, bound, base, minimum),
        _initializer_drop_bound(right, bound, base, minimum));
    case %(expr ? (op < (expr ? (parens ?index))
                        (expr ? (parens ?length)))): {
      unsigned long long at;
      List origin;
      _initializer_position(index, &origin, &at);
      if (length === bound && origin === base && at <= minimum) return NULL;
    }
  }
  return condition;
}

static List _initializer_and(List first, List second) {
  if (!first) return second;
  if (!second) return first;
  match (second)
    case %(expr ? (op < (expr ? (parens ?index))
                        (expr ? (parens ?bound)))): {
      unsigned long long at;
      List base;
      _initializer_position(index, &base, &at);
      first = _initializer_drop_bound(first, bound, base, at);
    }
  return first ? %(expr (int) (op && (expr (int) (parens $first))
                                    (expr (int) (parens $second)))) : second;
}

/** Selects a native subobject without evaluating it when used by sizeof. */
List Compiler.initializer_slot(Compiler c, List target, List path) {
  foreach (List frame, path.reverse()) {
    (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
    if (kind == <index>)
      target = %(expr $selected (index $target $selector));
    else if (selector.truth())
      target = %(expr $selected (op . $target ($selector)));
  }
  return target;
}

static void _initializer_next(
  Compiler c, List target, List path, List condition, Array states) {
  while (path) {
    List frame = path.car(), parent = path.cdr();
    (Type owner, Symbol kind, Var selector, Type type, List rest) = frame;
    if (kind == <field>) {
      if (owner.car() != <union>) {
        List next = _initializer_field(owner, rest, parent);
        if (next) {
          states.push(%($condition $next 1));
          return;
        }
      }
    }
    else {
      List index = selector, dimension = owner.car().list().cadr();
      unsigned long long at, count;
      List base;
      _initializer_position(index, &base, &at);
      int known_index = !base;
      String next_index = %"${at + 1}ULL";
      List increment = %(expr (unsigned long long)
        (literal (unsigned long long) $next_index));
      index = base ? %(expr (unsigned long long)
        (op + (expr (unsigned long long) (parens $base)) $increment)) : increment;
      List next = cons(%($owner index $index $type ()), parent);
      if (!dimension) {
        states.push(%($condition $next 1));
        return;
      }
      if (known_index && _initializer_integer(dimension, &count)) {
        if (at + 1 < count) {
          states.push(%($condition $next 1));
          return;
        }
      }
      else {
        List array = c.initializer_slot(target, parent);
        List element = %(expr $type (index $array
          (expr (int) (literal (int) "0"))));
        List length = %(expr (unsigned)
          (op / (expr (unsigned) (sizeof (parens $array)))
                (expr (unsigned) (sizeof (parens $element)))));
        List inside = %(expr (int)
          (op < (expr (int) (parens $index))
                (expr (unsigned) (parens $length))));
        states.push(%(${_initializer_and(condition, inside)} $next 1));
        condition = _initializer_and(condition,
          %(expr (int) (op ! (expr (int) (parens $inside)))));
      }
    }
    path = parent;
  }
  // Excess entries are the native initializer's final fallback.
  states.push(%(() () 0));
}

static List _initializer_merge(Array states) {
  Map positions = %{};
  Array merged = %[];
  foreach (List state, states) {
    (List condition, List path, int available) = state;
    List key = %($path $available);
    Var stored;
    if (!positions.try_get(key, &stored)) {
      positions[key] = merged.len();
      merged.push(state);
      continue;
    }
    int at = stored;
    List previous = merged[at], before = previous.car();
    if (!before || !condition) condition = NULL;
    else if (before !== condition)
      condition = %(expr (int)
        (op || (expr (int) (parens $before))
               (expr (int) (parens $condition))));
    merged[at] = %($condition $path $available);
  }
  states.free();
  return merged.list_free();
}

static List _initializer_named(
  Compiler c, Type type, Var name, List parent) {
  Type owner = c.sym.resolve_key(type);
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List row = fields.car();
    List path = _initializer_field(owner, fields, parent);
    if (row.car() == name) return path;
    Type member = row.cadr();
    if (!row.car().truth() && c.sym.resolve_key(member).is_aggregate()) {
      List nested = _initializer_named(c, member, name, path);
      if (nested) return nested;
    }
    fields = fields.cdr();
  }
  return NULL;
}

static List _initializer_designated(
  Compiler c, Type root, List node, List *value, List *normalized) {
  List path = NULL, selectors = NULL;
  Type type = root;
  loop {
    Type owner = c.sym.resolve_key(type);
    match (node) {
      case %(dotinit ?field ?inner): {
        selectors = cons(%(dotinit $field), selectors);
        List selected = _initializer_named(c, type, field.car(), path);
        type = c.sym.lookup_field(type, field);
        path = selected ? selected
          : cons(%($owner field ${field.car()} $type ()), path);
        node = inner;
        continue;
      }
      case %(indexinit ?index ?inner): {
        List reference = NULL;
        List captured = _initializer_index(c, index, &reference);
        selectors = cons(%(indexinit $captured), selectors);
        type = owner.dereference();
        path = cons(%($owner index $reference $type ()), path);
        node = inner;
        continue;
      }
    }
    *value = node;
    foreach (List selector, selectors) node = selector.append(%($node));
    *normalized = node;
    return path;
  }
}

static int _initializer_string_array(Compiler c, Type type, List value) {
  if (!value.match(%(expr (* char) (literal (* char) ?)))) return 0;
  Type array = c.sym.resolve_key(type);
  if (!array.is_array()) return 0;
  Type element = c.sym.resolve_key(array.cdr()).scalar();
  return element === %(char) || element === %(signed char) ||
         element === %(unsigned char);
}

static int _initializer_whole(Compiler c, Type type, List value) {
  if (value.match(%(expr ? (composite *)))) return 1;
  Type source = value.cadr(), resolved = c.sym.resolve_key(type);
  if (List.equal(c.sym.resolve_key(source), resolved)) return 1;
  if (c.sym.is_var_type(type)) return 1;
  if (_initializer_string_array(c, type, value)) return 1;
  return !resolved.is_array() && !resolved.is_aggregate();
}

/* Scalar positional runs have one ordinal, independent of the native array
   boundaries. Count the type tree once instead of retaining cursor histories.
   Children pair ordinary path frames with (type count children) layouts. */
static List _initializer_layout(
  Compiler c, Type type, List target, List string, int *symbolic) {
  Type owner = c.sym.resolve_key(type);
  List one = %(expr (unsigned long long)
    (literal (unsigned long long) "1ULL"));
  if (c.sym.is_var_type(type) ||
      (!owner.is_array() && !owner.is_aggregate()))
    return %($type $one ());
  if (owner.is_array()) {
    List dimension = owner.car().list().cadr();
    if (!dimension) return NULL;
    if (string && _initializer_string_array(c, type, string)) return NULL;
    unsigned long long size;
    if (!_initializer_integer(dimension, &size)) *symbolic = 1;
    List path = _initializer_first(c, type, NULL);
    List element = c.initializer_slot(target, path);
    List child = _initializer_layout(c, owner.cdr(), element,
                                     string, symbolic);
    if (!child) return NULL;
    List bytes = %(expr (unsigned long long) (sizeof (parens $element)));
    List divisor = child.caddr() ? %(expr (unsigned long long)
      (op ? $bytes $bytes $one)) : bytes;
    List count = %(expr (unsigned long long)
      (op / (expr (unsigned long long) (sizeof (parens $target)))
            (expr (unsigned long long) (parens $divisor))));
    List units = child.cadr();
    if (units !== one)
      count = %(expr (unsigned long long)
        (op * (expr (unsigned long long) (parens $count))
              (expr (unsigned long long) (parens $units))));
    return %($type $count ((${path.car()} $child)));
  }
  if (owner.car() == <union>) return NULL;
  Array children = %[];
  List count = NULL;
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List path = _initializer_field(owner, fields, NULL);
    if (!path) break;
    (Type parent, Symbol kind, Var name, Type member, List rest) =
      path.car().list();
    List slot = c.initializer_slot(target, path);
    List child = _initializer_layout(c, member, slot, string, symbolic);
    if (!child) { children.free(); return NULL; }
    List units = child.cadr();
    count = count ? %(expr (unsigned long long)
      (op + (expr (unsigned long long) (parens $count))
            (expr (unsigned long long) (parens $units)))) : units;
    children.push(%(${path.car()} $child));
    fields = rest;
  }
  if (!count) { children.free(); return NULL; }
  return %($type $count ${children.list_free()});
}

static void _initializer_ordinal(
  List layout, List ordinal, List path, List condition, List value,
  Array cases) {
  (Type type, List count, List children) = layout;
  if (!children) {
    cases.push(%($condition $path $type $value));
    return;
  }
  List start = NULL;
  List one = %(expr (unsigned long long)
    (literal (unsigned long long) "1ULL"));
  foreach (List entry, children) {
    (List frame, List child) = entry;
    (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
    List units = child.cadr(), position = ordinal, active = condition;
    if (kind == <index>) {
      List index = ordinal;
      position = %(expr (int) (literal (int) "0"));
      if (units !== one) {
        // Empty native subarrays leave these unselected selectors well-formed.
        List divisor = %(expr (unsigned long long)
          (op ? $units $units $one));
        index = %(expr (unsigned long long)
          (op / (expr (unsigned long long) (parens $ordinal))
                (expr (unsigned long long) (parens $divisor))));
        position = %(expr (unsigned long long)
          (op % (expr (unsigned long long) (parens $ordinal))
                (expr (unsigned long long) (parens $divisor))));
      }
      frame = %($owner index $index $selected ());
    }
    else {
      if (start) {
        position = %(expr (unsigned long long)
          (op - (expr (unsigned long long) (parens $ordinal))
                (expr (unsigned long long) (parens $start))));
        if (units !== one)
          active = _initializer_and(active, %(expr (int)
            (op >= (expr (unsigned long long) (parens $ordinal))
                   (expr (unsigned long long) (parens $start)))));
      }
      List test = units === one
        ? %(expr (int) (op == (expr (unsigned long long) (parens $position))
                             (expr (int) (literal (int) "0"))))
        : %(expr (int)
            (op < (expr (unsigned long long) (parens $position))
                  (expr (unsigned long long) (parens $units))));
      active = _initializer_and(active, test);
      start = start ? %(expr (unsigned long long)
        (op + (expr (unsigned long long) (parens $start))
              (expr (unsigned long long) (parens $units)))) : units;
    }
    _initializer_ordinal(child, position, cons(frame, path), active,
                         value, cases);
  }
}

static List _initializer_scalar_rows(
  Compiler c, Type root, List items, List target) {
  int symbolic = 0;
  List string = NULL;
  foreach (List value, items) {
    match (value) {
      case %(expr ? (!or (composite *) (initval *))): return NULL;
      case %(expr ?type ?): {
        Type source = c.sym.resolve_key(type);
        if (!c.sym.is_var_type(type) &&
            (source.is_array() || source.is_aggregate())) return NULL;
      }
      default: return NULL;
    }
    if (value.match(%(expr (* char) (literal (* char) ?)))) string = value;
  }
  List layout = _initializer_layout(c, root, target, string, &symbolic);
  if (!layout || !symbolic) return NULL;
  int array = c.sym.resolve_key(root).is_array();
  Array rows = %[];
  unsigned long long at = 0;
  foreach (List value, items) {
    String spelling = %"${at++}ULL";
    List ordinal = %(expr (unsigned long long)
      (literal (unsigned long long) $spelling));
    List count = layout.cadr();
    List condition = array ? %(expr (int)
      (op < $ordinal (expr (unsigned long long) (parens $count)))) : NULL;
    Array cases = %[];
    _initializer_ordinal(layout, ordinal, NULL, condition, value, cases);
    cases.push(%(() () () $value));
    rows.push(%($value ${cases.list_free()}));
  }
  return rows.list_free();
}

/** Returns (original cases) rows; each case is
    (native-condition path destination value). Explicit braces start a nested
    walk. Scalar runs map their ordinal through the native dimensions; other
    inputs retain possible cursor continuations. A NULL condition is
    unconditional, and a NULL destination is excess. */
List Compiler.initializer_rows(
  Compiler c, Type root, List items, List target) {
  List scalar = _initializer_scalar_rows(c, root, items, target);
  if (scalar) return scalar;
  Array rows = %[];
  List first_path = _initializer_first(c, root, NULL);
  Type resolved_root = c.sym.resolve_key(root);
  int available = !!first_path || resolved_root.scalar() ||
    resolved_root.is_pointer() || resolved_root.is_enum();
  List states = %((() $first_path $available));
  int first = 1;
  foreach (List original, items) {
    List value = original;
    if (original.car() == <dotinit> || original.car() == <indexinit>) {
      List path = _initializer_designated(c, root, original, &value, &original);
      states = %((() $path 1));
    }
    match (value)
      case %(expr ? (!set ?body (initval *))): {
        List header = NULL;
        List choices = Ast.initializer_cases(body.list(), &header);
        Array following = %[];
        foreach (List choice, choices) {
          (List condition, List path, Type type, List input) = choice;
          _initializer_next(c, target, path, condition, following);
        }
        rows.push(%($original $choices));
        states = _initializer_merge(following);
        first = 0;
        continue;
      }
    Array cases = %[], following = %[];
    foreach (List state, states) {
      (List condition, List path, int available) = state;
      Type type = available ? _initializer_type(path, root) : NULL;
      if (first && _initializer_string_array(c, root, value)) {
        path = NULL;
        type = root;
      }
      while (type && !_initializer_whole(c, type, value)) {
        List next = _initializer_first(c, type, path);
        if (!next) break;
        path = next;
        type = _initializer_type(path, root);
      }
      cases.push(%($condition $path $type $value));
      _initializer_next(c, target, path, condition, following);
    }
    first = 0;
    rows.push(%($original ${cases.list_free()}));
    states = _initializer_merge(following);
  }
  return rows.list_free();
}

static List _initializer_replace(List original, List value) {
  match (original)
    case %((!set ?tag (!or dotinit indexinit)) ?key ?inner):
      return %($tag $key ${_initializer_replace(inner, value)});
  return value;
}

static List _initializer_zero(Type type, List target) {
  Type native = type.is_bitfield() ? type.base_type()
    : target ? %("__typeof__" (parens $target)) : type;
  return %(expr $type (cast $native (expr $type
    (composite (commas (expr (int) (literal (int) "0")))))));
}

/* Only native-dependent alternatives speculate. The semantic transaction
   owns bindings/names; conversion additionally appends literal/adapter data. */
static List _initializer_conversion(
  Compiler c, List value, Type type, List condition, List target,
  int *native_used) {
  if (!condition) return _convert_initializer(c, value, type, target, native_used);
  if (native_used) *native_used = 1;
  match (value)
    case %(expr ?stored (call "__builtin_choose_expr"
                             (args ?when ?yes ?no))):
      if (stored === type && when === condition) return value;
  SymTxn transaction = c.begin_semantic_transaction();
  Map keys = c.key_ids, adapters = c.names.adapters;
  int key_count = c.id_keys.len(), declarations = c.early_decls.len();
  c.key_ids = keys.copy();
  c.names.adapters = adapters.copy();
  Diagnostics diag = c.diagnostics;
  DiagnosticEmitter emit = diag.emit;
  void *owner = diag.owner;
  int entries = diag.entries.len(), count = diag.count;
  int limited = diag.limit_notified, depth = c.recovery_depth;
  int completed = 0, rejected = 0;
  List result = NULL;
  {
    defer {
      c.recovery_depth = depth;
      diag.set_emitter(emit, owner);
      if (rejected) {
        diag.entries.resize(entries);
        diag.count = count;
        diag.limit_notified = limited;
      }
      else if (emit)
        for (int i = entries; i < diag.entries.len(); i++) {
          List entry = diag.entries[i];
          emit(owner, entry);
        }
      if (!completed) {
        c.key_ids = keys;
        c.names.adapters = adapters;
        c.id_keys.resize(key_count);
        c.early_decls.resize(declarations);
      }
      transaction.rollback();
    }
    diag.set_emitter(NULL, NULL);
    c.recovery_depth = depth + 1;
    try {
      result = value.match(%(expr ? (composite ?)))
        ? _convert_composite(c, value, type.canonicalize(), target,
                             condition, native_used)
        : c.convert_expression(value, type);
      transaction.commit();
      completed = 1;
    }
    catch %(malformed (category type)): rejected = 1;
  }
  List zero = _initializer_zero(type, target);
  if (!rejected) {
    if (result.match(%(expr ? (composite *)))) {
      Type native = target ? %("__typeof__" (parens $target)) : type;
      return %(expr $type (cast $native $result));
    }
    return %(expr $type
      (call "__builtin_choose_expr" (args $condition $result $zero)));
  }
  List size = %(expr (int) (op ? $condition
    (expr (int) (literal (int) "-1"))
    (expr (int) (literal (int) "1"))));
  List check = %(expr (unsigned)
    (sizeof ("(" "char[" $size "]" ")")));
  Symbol comma = <,>;
  check = %(expr (void) (cast (void) $check));
  return %(expr $type (parens (expr $type (op $comma $check $zero))));
}

// Keep literal construction/cache facts while capturing native value leaves.
static int _initializer_literal(List value) {
  match (value) {
    case %(expr ? (literal *)): return 1;
    case %(expr ? (!or (parens ?inner) (cast ? ?inner))):
      return _initializer_literal(inner);
  }
  return 0;
}

static List _initializer_capture_leaves(
  Compiler c, List value, Array inputs) {
  match (value) {
    case %((!set ?kind (!or dotinit indexinit)) ?key ?inner):
      return %($kind $key ${_initializer_capture_leaves(c, inner, inputs)});
    case %(expr ?type (composite (commas *items))): {
      Array captured = %[];
      foreach (List item, items)
        captured.push(_initializer_capture_leaves(c, item, inputs));
      return %(expr $type (composite (commas @{captured.list_free()})));
    }
    case %(expr ?type ((!or ident call op cast parens) *)): {
      if (!c.sym.is_var_type(type) && !c.sym.resolve_key(type).scalar())
        return value;
      if (_initializer_literal(value)) return value;
      String formal = c.fresh_name("initializer_value");
      inputs.push(%($formal $value));
      return %(expr $type $formal);
    }
  }
  return value;
}

// Inline native type definitions cannot be copied into conversion arms.
// A selected by-value adapter consumes the original expression just once.
static Type _initializer_value_type(Compiler c, Type type) {
  if (c.sym.is_var_type(type)) return %("Var");
  Type scalar = c.sym.resolve_key(type).scalar();
  return scalar === %(void) ? NULL : scalar;
}

static List _initializer_adapter(
  Compiler c, List source, List converted) {
  Type from = _initializer_value_type(c, source.cadr());
  Type result = _initializer_value_type(c, converted.cadr());
  List formal = %(expr ${source.cadr()} "_x2c_initializer_argument");
  List body = converted.search_replace(%(!quote $source), formal);
  List key = %(iadapt $from $result $body);
  Var stored;
  if (c.names.adapters.try_get(key, &stored)) return stored;
  List parameter = c.sym.introduce(c.fresh_name("initializer_arg"));
  List input = %(expr ${source.cadr()} (ident $parameter));
  body = body.search_replace(%(!quote $formal), input);
  List binding = c.sym.introduce(c.fresh_name("initializer_adapt"));
  List params = %(params ${from.parameter_ast(parameter)});
  List function = %(function (static $result)
    (bind $binding ((fnmod $params)))
    (block (stmnt (return $body))));
  Type callable = %((func ($from)) @result);
  List adapter = %(expr $callable (ident $binding));
  c.names.adapters[key] = adapter;
  c.add_early(function);
  return adapter;
}

static List _initializer_adapters(
  Compiler c, List source, List choices, List placeholder) {
  Type from = _initializer_value_type(c, source.cadr());
  if (!from || !ast_contains_head(source, <fields>)) return NULL;
  Array prepared = %[];
  foreach (List choice, choices) {
    (List condition, List path, Type destination, List value) = choice;
    if (destination && !_initializer_value_type(c, destination)) {
      prepared.free();
      return NULL;
    }
    if (value !== source) {
      match (value) {
        case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
          value = yes;
        default: { prepared.free(); return NULL; }
      }
    }
    if (!_initializer_value_type(c, value.cadr())) {
      prepared.free();
      return NULL;
    }
    prepared.push(%($condition $path $destination $value));
  }
  Array adapted = %[];
  foreach (List choice, prepared.list_free()) {
    (List condition, List path, Type destination, List value) = choice;
    List adapter = _initializer_adapter(c, source, value);
    Type callable = adapter.cadr(), result = callable.apply();
    value = %(expr $result (call $adapter (args $placeholder)));
    adapted.push(%($condition $path $destination $value));
  }
  return adapted.list_free();
}

static List _convert_composite(
  Compiler compiler, List expr, Type target, List native_target,
  List parent_condition, int *native_used) {
  if (!native_target) {
    Type pointer = cons(<*>, target);
    List zero = %(expr (int) (literal (int) "0"));
    native_target = %(expr $target (parens (expr $target
      (op * (expr $pointer (parens (expr $pointer (cast $pointer $zero))))))));
  }
  Array rows = %[], elements = %[];
  List items = expr.caddr().cadr().list().cdr();
  int initialized = 0, discarded = 0;
  foreach (List row, compiler.initializer_rows(target, items, native_target)) {
    List cases = row.cadr();
    int available = 0;
    foreach (List choice, cases)
      if (choice.caddr().truth()) { available = 1; break; }
    if (parent_condition && initialized && !available) {
      discarded = 1;
      continue;
    }
    if (available) initialized = 1;
    rows.push(row);
  }
  // Preserve C's excess warning only when this synthetic alternative applies.
  // The always-true ICE stays on a retained value, so braces remain braces.
  List excess_check = NULL;
  if (discarded) {
    List zero = %(expr (int) (literal (int) "0"));
    List one = %(expr (int) (literal (int) "1"));
    List size = %(expr (int) (op ? $parent_condition $zero $one));
    Type array = %((dim $size) char);
    List probe = %(expr $array (cast $array
      (expr $array (composite (commas $zero)))));
    List count = %(expr (unsigned) (sizeof (parens $probe)));
    excess_check = %(expr (int)
      (op + $one (expr (int) (op * $zero $count))));
  }
  foreach (List row, rows.list_free()) {
    (List original, List cases) = row;
    List row_condition = parent_condition;
    if (excess_check) {
      row_condition = _initializer_and(parent_condition, excess_check);
      excess_check = NULL;
    }
    Type type = NULL;
    List value = NULL;
    int homogeneous = 1, excess = 0, applicable_seen = 0;
    List applicable = NULL, selected_path = NULL;
    foreach (List choice, cases) {
      (List condition, List path, Type destination, List input) = choice;
      value = input;
      if (!destination) { excess = 1; continue; }
      if (!applicable_seen) { applicable = condition; applicable_seen = 1; }
      else if (!applicable || !condition) applicable = NULL;
      else if (applicable !== condition)
        applicable = %(expr (int)
          (op || (expr (int) (parens $applicable))
                 (expr (int) (parens $condition))));
      if (!type) { type = destination; selected_path = path; }
      else if (destination !== type) homogeneous = 0;
    }
    List terminal = original;
    while (terminal.car() == <dotinit> || terminal.car() == <indexinit>)
      terminal = terminal.caddr();
    if (terminal.match(%(expr ? (initval *)))) {
      if (row_condition === parent_condition) elements.push(original);
      else {
        Array checked = %[];
        foreach (List choice, cases) {
          (List condition, List path, Type destination, List input) = choice;
          List slot = compiler.initializer_slot(native_target, path);
          List effective = _initializer_and(row_condition, condition);
          List value = destination ? _initializer_conversion(
            compiler, input, destination, effective, slot, native_used) : input;
          checked.push(%($condition $path $destination $value));
        }
        List header = NULL;
        Ast.initializer_cases(terminal.caddr().list(), &header);
        List choices = checked.list_free();
        if (header) choices = cons(header, choices);
        List value = %(expr () (initval @choices));
        elements.push(_initializer_replace(original, value));
      }
      continue;
    }
    if (homogeneous) {
      List slot = native_target
        ? compiler.initializer_slot(native_target, selected_path) : NULL;
      List condition = _initializer_and(row_condition,
        excess ? applicable : NULL);
      List converted = !type ? value
        : _initializer_conversion(
            compiler, value, type, condition, slot, native_used);
      elements.push(_initializer_replace(original, converted));
    }
    else {
      Array converted = %[], captured = %[];
      List source = value, prepared = value;
      if (value.match(%(expr ? (composite *))))
        prepared = _initializer_capture_leaves(compiler, value, captured);
      int native_identity = !parent_condition;
      foreach (List choice, cases) {
        (List condition, List path, Type destination, List input) = choice;
        input = prepared;
        List slot = native_target
          ? compiler.initializer_slot(native_target, path) : NULL;
        List effective = _initializer_and(row_condition, condition);
        List result = destination
          ? _initializer_conversion(
              compiler, input, destination, effective, slot, native_used)
          : input;
        int identity = result === input;
        match (result)
          case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
            if (yes === input) identity = 1;
        if (!identity) native_identity = 0;
        converted.push(%($condition $path $destination $result));
      }
      if (native_identity) {
        converted.free();
        captured.free();
        elements.push(original);
        continue;
      }
      String formal = compiler.fresh_name("initializer_value");
      List placeholder = %(expr ${source.cadr()} $formal);
      List values = converted.list_free();
      List adapted = _initializer_adapters(compiler, source, values, placeholder);
      if (adapted) values = adapted;
      Array replaced = %[];
      List inputs = captured.list_free();
      int uses_input = !!adapted;
      foreach (List choice, values) {
        (List condition, List path, Type destination, List result) = choice;
        List substituted = !destination && source.match(%(expr ? (composite *)))
          ? result : result.search_replace(%(!quote $source), placeholder);
        if (substituted !== result) uses_input = 1;
        replaced.push(%($condition $path $destination $substituted));
      }
      List choices = replaced.list_free();
      if (uses_input) inputs = cons(%($formal $source), inputs);
      if (inputs) choices = cons(%(input @inputs), choices);
      List result = %(expr () (initval @choices));
      elements.push(_initializer_replace(original, result));
    }
  }
  return %(expr $target (composite (commas @{elements.list_free()})));
}

static List _convert_initializer(
  Compiler c, List value, Type type, List target, int *native_used) {
  if (value.match(%(expr ? (composite ?))))
    return _convert_composite(
      c, value, type.canonicalize(), target, NULL, native_used);
  return c.convert_expression(value, type.declared());
}

/** Converts an initializer using its declared native object for array bounds. */
List Compiler.convert_initializer(
  Compiler c, List value, Type type, List target) =>
  _convert_initializer(c, value, type, target, NULL);

/** Keeps a compound literal's native type definition at its original scope. */
List Compiler.convert_compound_literal(
  Compiler c, List value, Type type, Type native_type) {
  (Type definition, Type reference) = c.initializer_native_types(native_type);
  Type pointer = cons(<*>, reference);
  List zero = %(expr (int) (literal (int) "0"));
  List target = %(expr $type (parens (expr $type
    (op * (expr $pointer (parens (expr $pointer (cast $pointer $zero))))))));
  int native_used = 0;
  List converted = _convert_initializer(c, value, type, target, &native_used);
  if (!native_used) definition = native_type;
  return %(cast $definition $converted);
}

/** Adds operations to convert a resolved expression AST to `target`.
    The result may contain converter, boxing, unboxing, `Func`, reference, or
    composite-literal operations. Returns the original expression when C
    performs the conversion implicitly; an unsupported x2c conversion reports
    a type error through `c`. Synthesized operations may add generated
    bindings or immutable literal entries to compiler state.
*/
List Compiler.convert_expression(Compiler c, List expr, Type target) {
  if (!target) return expr;
  Type type = expr.cadr();
  // Captured Func lambdas wait for reference-cell rewriting.
  if (type.is_function()) {
    List lowered = c.lower_lambda_expr(expr);
    if (lowered != expr) {
      expr = c.adapt_lambda_arg(
        lowered, c.sym.resolve_key(target.type_from_ast()));
      type = expr.cadr();
    }
  }
  Type declared_source = type, declared_target = target;
  if (type) type = type.canonicalize();
  target = target.canonicalize();
  int type_is_var = c.sym.is_var_type(type);
  int target_is_var = c.sym.is_var_type(target);
  Type func_type = c.sym.resolve_key(%("Func"));
  if (List.equal(c.sym.resolve_key(target), func_type)) {
    List lifted = c.lift_func_expression(expr);
    if (lifted != expr) return lifted;
  }
  if (type && List.equal(c.sym.resolve_key(type), func_type) &&
      target.is_pointer() && target.dereference().is_function()) {
    String message =
      "cannot convert Func to a context-free callback";
    List hint = %(
      "call Func directly, or use a noncapturing lambda as the C callback"
    );
    c.report_error(<type>, message, NULL, hint);
  }
  if (expr.match(%(expr ? (composite ?))))
    return _convert_composite(c, expr, target, NULL, NULL, NULL);
  if (!type) {
    if (target_is_var &&
        expr.match(%(expr () (ident (binding ? ?))))) {
      List binding = expr.caddr().cadr();
      if (binding_identity_spelling(binding) == "NULL")
        return %(expr ("Var") (call "Var_null" (args)));
      String message = "cannot convert an unresolved expression to Var";
      c.report_error(
        <type>, message, NULL,
        %("give the expression a declared x2c type before boxing it"));
    }
    return expr;
  }
  /* The conversions below that keep the same canonical type hand the same
     address on without a call, so the target must promise every qualifier
     the source declares. A conversion that reaches a converter function
     copies the value instead and is unaffected.

     A pointer to void also hands the same address on, and it is the one
     type whose base differs by construction, so the same-canonical test
     above cannot see it. Without this it was the one conversion that
     silently discarded const, in both directions: `void *`
     took a `const char *` going in, and `char *` took a `const void *`
     coming back out. */
  int take_reference = car(target) == <&> && type == cdr(target);
  Type qualifier_source = take_reference
                        ? declared_source.reference() : declared_source;
  if ((take_reference || type == target || cdr(type) == cdr(target) ||
       (type.is_pointer() && target.is_pointer() &&
        (declared_target.base_type() === %(void) ||
         declared_source.base_type() === %(void)))) &&
      qualifier_source.discards_qualifiers(declared_target)) {
    String message =
      %"cannot convert ${declared_source.repr()} to ${declared_target.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the target drops a type qualifier the source declares: spell the qualifier in the target, or copy the value"));
  }
  if (type == target || (type_is_var && target_is_var)) return expr;
  if (_integer_literal_kind(expr, NULL) == <zero> &&
      c.sym.resolve_key(target).is_pointer())
    return expr;
  // pointers, references, and address-of/dereference conversions
  // T -> &T : pass address of LHS as ref w/ updated type
  if (type == cdr(target) && car(target) == <&>)
    return %(expr $target (op & (parens $expr)));
  // *T -> &T : pass pointer as ref w/ updated type
  // &T -> *T : pass ref as pointer w/ updated type
  if (cdr(type) == cdr(target))
    if ( (car(type) == <*> && car(target) == <&>) ||
         (car(type) == <&> && car(target) == <*>))
      return %(expr $target $expr);
  // &T -> T : pass deref ref as value
  if (car(type) == <&> && cdr(type) == target)
    return %(expr $target (op * (parens $expr)));
  if (type.match(%((!or (dim *) (!quote *)) char))) {
    List string = _raw_string_to_string(c, expr);
    if (target === %("String")) return string;
    if (target_is_var)
      return %(expr ("Var") (call "String_var" (args $string)));
  }
  // Var -> non-Var
  if (type_is_var && !target_is_var) {
    if (target === %("Symbol"))
      return %(expr $target (call "Var_symbol" (args $expr)));
    Type scalar_target = c.sym.resolve_numeric_type(target);
    if (scalar_target) {
      Symbol tag = scalar_target.scalar_tag();
      if (!tag && scalar_target.is_enum()) tag = <i32>;
      String extractor = scalar_target.var_numeric_extractor();
      if (extractor) {
        String tagsym = %"${(unsigned long) tag}";
        List converted = %(expr ("Var") (call "Var_convert" (args
          $expr (expr ("Symbol") $tagsym))));
        return %(expr $target (call $extractor (args $converted)));
      }
    }
    // A built-in payload has an exact tag-checked reader, and a Var(T)
    // participant declares its own reverse converter. Either takes the
    // crossing ahead of the unchecked pointer payload below.
    List reader = _var_exact_reader(c, expr, target);
    if (reader) return reader;
    List declared = _converter_call(c, expr, type, target);
    if (declared) return declared;
    if (target.is_pointer())
      return %(expr $target (call "Var_pointer" (args $expr)));
    if (target.is_typedef_name()) {
      // A typedef may take the pointer payload only once it is known to
      // name a pointer, and only because no exact reader or declared
      // converter claimed it above: that leaves a raw native pointer with no
      // typed Var reader. A name that resolution leaves
      // untouched has no known representation, since system headers
      // are never collected, so extracting a pointer there is invalid
      // C at best and a silently wrong value at worst.
      Type resolved = c.sym.resolve_key(target);
      if (resolved.is_pointer())
        return %(expr $target (call "Var_pointer" (args $expr)));
      String message = %"cannot convert Var to type ${target.repr()}";
      c.report_error(<type>, message, NULL, NULL);
    }
  }
  // A source-declared T.var converter does the custom boxing. Its unit-local
  // tag row may never authorize direct Var_new emission.
  if (!type_is_var && target_is_var) {
    Type converter_type = type;
    String converter = converter_type.var_converter();
    if (!converter) {
      c.sym.var_tag_for_type(type, &converter_type);
      converter = converter_type.var_converter();
    }
    if (converter) {
      String typename = converter_type.car().str(), List cvrtrtype = NULL;
      List converter_binding = c.sym.resolve_global(
        %($converter), &cvrtrtype);
      if (cvrtrtype === %((func (($typename))) "Var")) {
        List argument = type == converter_type
          ? expr : %(expr $converter_type $expr);
        return %(expr ("Var")
          (call (expr $cvrtrtype (ident $converter_binding))
                (args $argument)));
      }
      String message = %"cannot convert ${type.repr()} to Var without loss";
      c.report_error(<type>, message, NULL, NULL);
    }
  }
  // A -> B where both A and B
  List converted = _converter_call(c, expr, type, target);
  if (converted) return converted;
  // non-Var -> Var
  if (!type_is_var && target_is_var) {
    Type tagged_type = NULL;
    Symbol tag = c.sym.var_tag_for_type(type, &tagged_type);
    if (!tag && tagged_type && tagged_type.is_enum()) tag = <i32>;
    if (tag) {
      String box = NULL;
      switch (tag) {
        case <long>:  box = "Var_box_long"; break;
        case <ulong>:  box = "Var_box_ulong"; break;
        case <llong>: box = "Var_box_long_long"; break;
        case <ullong>: box = "Var_box_ulong_long"; break;
        case <ldouble>: box = "Var_box_long_double"; break;
      }
      if (box) return %(expr ("Var") (call $box (args $expr)));
      String tagsymnumstr = %"${(unsigned long) tag}";
      return %(expr ("Var") (call "Var_new" (args
                  (expr ("Symbol") $tagsymnumstr) $expr)));
    }
    String message = %"cannot convert ${type.repr()} to Var without loss";
    // No token: conversion runs after the parse, where compiler.token is
    // the end-of-file token and would point past the last source line.
    // NULL lets the report resolve the anchor of the statement being
    // transformed instead.
    c.report_error(<type>, message, NULL, NULL);
  }
  if (c.sym.resolve_numeric_type(type) &&
      c.sym.resolve_numeric_type(target))
    return expr; // allow implicit numeric conversions
  // An integer reaching a pointer is the one shape that falls through to C
  // as a constraint violation rather than as a conversion the C compiler
  // completes on its own.  Everything else below is delegated:
  // array and function decay, void *, typedef spelling, varargs, and every
  // type out of a system header the collector never sees.  Only a
  // zero-valued integer constant expression makes a null pointer, so an
  // operand that is provably not one is provably wrong; rejecting it here
  // keeps `match (42)` from emitting `List _x2c_match_expr = 42;`.
  // Resolving the target first means a typedef the resolver cannot see is
  // not a pointer under this rule, so a system type stays silent.
  String integer = _not_null_pointer_constant(c, expr);
  if (integer && c.sym.resolve_key(target).is_pointer()) {
    String message =
      %"cannot convert the integer $integer to pointer type ${target.repr()}";
    List hint =
      %( "only a zero integer constant expression converts to a pointer" );
    c.report_error(<type>, message, NULL, hint);
  }
  // Two unrelated pointers are the other shape C diagnoses without
  // stopping, and x2c writes the C, so that warning is never
  // read.  Everything listed above stays delegated; only a pointer
  // whose target is known on both sides is judged here.
  if (_unrelated_pointers(c, type, target)) {
    String message =
      %"cannot convert ${declared_source.repr()} to ${declared_target.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the pointer types are unrelated: cast the expression to say so on purpose"));
  }
  /* Two names defined from one third name resolve to one C type, which
     leaves the crossing silent even though neither name means the other:
     every typed array is a `typedef Block`, so an ArrayDbl reached an
     ArrayInt and its doubles were read as ints.  Such a pair needs a
     converter, which the lookup above would already have taken, or a cast.
     A `void *` source is the one pointer C itself lets stand for any
     other. */
  if (declared_source.is_bare_typedef_name() &&
      declared_target.is_bare_typedef_name() &&
      !List.equal(declared_source, declared_target) &&
      c.sym.resolve_key(declared_target).is_pointer() &&
      c.sym.resolve_key(declared_source).base_type() !== %(void) &&
      !_same_typedef_line(c, declared_source, declared_target)) {
    String message =
      %"cannot convert ${declared_source.repr()} to ${declared_target.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the names share one C type but not one meaning: declare the converter ${declared_source.car()}_${declared_target.car().str().lower()}, or cast the expression to say so on purpose"));
  }
  // Everything reaching here is delegated to C: a typedef alias, array or
  // function decay, varargs, a system-header type the collector never
  // sees.  The report_error calls above cover every conversion x2c
  // refuses.
  return expr;
}

/** Converts a resolved interpolation segment to `String` when available.
    A missing `String` conversion is expected: the transform boxes that segment
    to `Var` and renders it at runtime.

    A declared numeric converter keeps its formatting; other numeric segments
    use `Var.str`. A segment statically spelled `Var` also uses `Var.str` for
    every
    runtime tag. The ordinary `Var`-to-`String` conversion is
    not equivalent: it
    extracts only a `String` payload and yields empty `String` for every other
    tag.
*/
List Compiler.convert_segment_to_string(Compiler compiler, List expr) {
  Type type = expr.cadr().type().canonicalize();
  if (compiler.sym.is_var_type(type))
    return %(expr ("String") (call "Var_str" (args $expr)));
  if (!compiler.sym.resolve_numeric_type(type))
    return compiler.convert_expression(expr, %("String"));
  List converted = _converter_call(compiler, expr, type, %("String"));
  if (converted) return converted;
  List boxed = compiler.convert_expression(expr, %("Var"));
  return %(expr ("String") (call "Var_str" (args $boxed)));
}
