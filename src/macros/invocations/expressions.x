/*  expressions.x -- macro invocation expressions */

static keyword loop $private.loop;

/* expression invocations

   In an expression, a `$` name without arguments is a Macro value, and a
   `$` call of a function is an explicit meta call. An Expression macro or
   decorator becomes a `macro-invoke` node that binding expands. */

/** Parses and resolves a direct or keyword-alias expression macro.
    Returns NULL without consuming an identifier that is not an applicable
    alias; a direct `$` invocation must resolve to a visible expression form.
*/
List Compiler.try_parse_macro_expression(Compiler c) {
  Token invocation = c.token;
  if (c.peek(0) == <$>) {
    List value = _named_macro_value(c, invocation);
    if (value) return value;
  }
  if ((c.peek(0) == <$> || c.peek(0) == <@>) &&
      !_peek_invocation(c, <expression>))
    return _parse_meta_call(c, invocation);
  List definition = _take_invocation(c, <expression>);
  if (!definition) return NULL;
  return c.resolve_expression(
    _expression_invocation(c, definition, invocation), invocation);
}

/* Returns the Macro value of a `$name` without arguments; otherwise restores
   the cursor to `$`. */
static List _named_macro_value(Compiler c, Token invocation) {
  Atom name = _name(c);
  if (c.peek(0) != <(>) {
    List value = _macro_value(c, name);
    if (value) return value;
  }
  c.token = invocation;
  return NULL;
}

static List _parse_meta_call(Compiler c, Token invocation) {
  c.next();
  /* A meta function is called by its compile-time binding, even from a
     template, whose other free names bind where the expansion lands. */
  List callee = NULL;
  with (c.macro_holes = NULL) { callee = c.parse_variable(); }
  Type signature = callee.cadr();
  if (!signature.is_function()) {
    c.token = invocation;
    Atom name = _name(c);
    (void) _lookup(c, name, invocation);
  }
  /* Inside a `meta` body the whole body runs at compile time, so a `$`
     call there is an ordinary call, except in a pattern, whose binders
     come from its value. */
  Symbol head = c.meta_body && !c.macro_holes && !c.in_pattern
    ? <call> : <meta-call>;
  Array arguments =
    _meta_arguments(c, signature.car().list().cadr(), head);
  Type result = c.macro_holes ? %(<macro-expr>) : signature.cdr();
  List call = %(expr $result ($head $callee
    (args @(arguments.list_free()))));
  return c.resolve_expression(call, invocation);
}

/* Each argument converts to its parameter's type, except in a template.
   A compile-time call passes its argument's own value to a `Var`
   parameter. */
static Array _meta_arguments(Compiler c, List parameters, Symbol head) {
  Array arguments = [];
  c.expect(<(>);
  if (c.peek(0) != <)>) loop {
    Type parameter = parameters ? parameters.car() : NULL;
    Type rest = Type.rest_container(parameter);
    List argument = rest && !c.peek_macro_hole()
      ? c.parse_call_splice() : NULL;
    if (!argument && rest == %("Map") && !c.peek_macro_hole())
      argument = c.parse_call_entry();
    if (!argument) argument = _meta_argument(c);
    if (parameters && !rest && !c.macro_holes &&
        !(head == <meta-call> && c.sym.is_var_type(parameter)))
      argument = c.convert_expression(argument, parameter);
    if (!rest) parameters = parameters.cdr();
    arguments.push(argument);
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return arguments;
}

/* A hole passed alone passes the value it captures, and a sequence hole
   passes its captured items as one List. */
static List _meta_argument(Compiler c) {
  List hole = c.peek_macro_hole();
  Symbol next = hole ? c.after_hole().type : 0;
  int direct = next == <,> || next == <)>;
  if (direct && hole.assoc(<sequence>).int()) {
    c.expect(<$>);
    c.next();
    return %(expr ("List") (meta-cap ($(_hole_key(hole, "value")))));
  }
  Symbol kind = hole ? hole.assoc(<kind>) : 0;
  List argument = direct
    ? %(expr (<macro-expr>) $(_parse_hole(c, kind ? kind : <argument>)))
    : c.parse_assignment();
  if (hole && (argument ~= %(expr ? (macro-bind ?)))) {
    Atom projection = Macro.binder(hole.assoc(<binder>), "value", 0);
    argument = %(expr ("List") (meta-cap $projection));
  }
  return argument;
}

static List _expression_invocation(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  if (kind == <decorator> && definition.assoc(<target>) == <expr>)
    return _expression_decorator(c, definition, invocation);
  if (c.meta_body && (kind == <unit> || kind == <block-item>))
    return _template_call(c, definition);
  List arguments = _invocation_arguments(c, definition, invocation);
  if (kind != <expression>) _not_expression(c, definition, invocation);
  List node = _invocation_node(c, definition, arguments, invocation);
  return %(expr (<macro-expr>) $node);
}

/* In a `meta` body, invoking a Unit or Stmt macro is a template call,
   whose syntax the meta function builds when it runs. */
static List _template_call(Compiler c, List definition) {
  Array arguments = [];
  c.expect(<(>);
  foreach (List hole in definition.assoc(<parameters>).list()) {
    if (arguments.len()) c.expect(<,>);
    arguments.push(c.parse_assignment());
  }
  c.expect(<)>);
  Var stored = definition.assoc(<local>).int()
    ? definition : definition.assoc(<name>);
  return %(expr ("List") (tpl-call $stored
    (args @(arguments.list_free()))));
}

static void _not_expression(Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  String spelling = definition.assoc(<name>).str();
  $fail.macros_result_expr(
    c, invocation, kind, spelling, _definition_note(definition));
}

static List _expression_decorator(
  Compiler c, List definition, Token invocation) {
  List arguments = _invocation_arguments(c, definition, invocation);
  if (c.peek(0) == <;> || c.peek(0) == <eof>) {
    String spelling = definition.assoc(<name>).str();
    $fail.macros_decorator_expr(
      c, invocation, spelling, _definition_note(definition));
  }
  List target = c.parse_macro_expression_target();
  List input = %(
    target $arguments
    $(_capture_row_project(c, definition.assoc(<targetp>), $(target), 0))
  );
  List node = _invocation_node(c, definition, input, invocation);
  return %(expr (<macro-expr>) $node);
}
