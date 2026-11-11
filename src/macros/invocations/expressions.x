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

/** Expands `receiver.name(...)` as the Expression macro `$T.name` of the
    receiver's named type `T`, with the receiver as its first explicit
    argument. The receiver's postfix expression begins at `start`, and
    `dot` is its `.`. Returns NULL, consuming nothing, when no such macro
    applies; the call is then an ordinary method call.

    Raises: `<method-dec>` when `start` begins an expression statement, a
    target follows the arguments, and `$T.name` is a decorator or, in a
    template other than `$T.name`'s own, may be one where the template
    expands. The statement continues with `parse_method_decorator`.
*/
List Compiler.try_parse_method_macro(
  Compiler c, List receiver, Token start, Token dot) {
  String name = Token.skip_trivia(dot + 1).text;
  Var own = _own_definition(c);
  List definition = _method_macro(c, receiver, name, own);
  int decorator = definition && definition.assoc(<kind>) == <decorator>;
  if (definition && !decorator) {
    c.method_receiver = _capture_source(c, receiver, start, dot);
    return c.resolve_expression(
      _expression_invocation(c, definition, start), start);
  }
  int deferred = c.macro_holes && !_names_member(own, name);
  if ((decorator || deferred) && start == c.meta_statement &&
      _target_follows(c)) {
    c.method_receiver = _capture_source(c, receiver, start, dot);
    c.method_decorator = definition;
    raise %(method-dec);
  }
  return NULL;
}

/** Parses the method-form decorator application whose arguments begin at
    the cursor, after `try_parse_method_macro` raised `<method-dec>` for
    the expression statement that begins at `start`. In a template whose
    receiver has no type yet, the result is `(method-decorator CALL
    TARGET)`, which `bind_method_decorator` applies where it expands.
*/
List Compiler.parse_method_decorator(
  Compiler c, Token start, Symbol position) {
  List definition = c.method_decorator, receiver = c.method_receiver;
  c.method_decorator = NULL;
  if (definition) return _decorate(c, definition, start, position, 0);
  c.method_receiver = NULL;
  String name = _previous_source_token(c, c.token).text;
  List call = c.parse_call(%(expr () (op . $receiver ($name))));
  return %(method-decorator $call $(c.parse_governed(position)));
}

/** Marks a template's call `receiver.name(...)` written in the template of
    a macro `$T.name` as `(expr () (method-call DEFINITION CALL))`, so that
    where the template expands the call is `$T.name`'s method, not the
    macro. Returns `call` unchanged otherwise.
*/
List Compiler.mark_method_call(Compiler c, List call, Var member) {
  Var own = _own_definition(c);
  return _names_member(own, member)
    ? %(expr () (method-call $own $call)) : call;
}

/** Expands a template's method-form call `receiver.name(supplied)` as the
    Expression macro `$T.name` once the receiver has its type where the
    template expands. Returns NULL when no such macro applies, or when the
    call was written in the template of the macro `own` that it names.
*/
List Compiler.bind_method_macro(
  Compiler c, List receiver, String name, List supplied, Var own) {
  List definition = _method_macro(c, receiver, name, own);
  if (!definition || definition.assoc(<kind>) != <expression>) return NULL;
  List input = _method_arguments(c, definition, receiver, supplied);
  return c.bind_syntax(
    %(macro-invoke $definition $input m-invoke), <expression>,
    c.return_type);
}

/** Applies a template's `(method-decorator CALL TARGET)` as the decorator
    `$T.name` of the call's receiver, at `position`.
*/
List Compiler.bind_method_decorator(
  Compiler c, List call, List target, Symbol position) {
  match (call)
    case $called(%(expr ? (op . ?receiver (?(String name)))), *supplied): {
      receiver = c.resolve_expression(receiver, c.token);
      List definition = _method_macro(c, receiver, name, NULL);
      if (!definition || definition.assoc(<kind>) != <decorator>)
        $fail.macros_macro_unbound(
          c, c.token, _method_spelling(receiver, name));
      List input = %(target
        $(_method_arguments(c, definition, receiver, supplied))
        $(_capture_row_project(c, definition.assoc(<targetp>), $(target), 0)));
      return c.bind_syntax(
        %(macro-invoke $definition $input m-invoke), position, c.return_type);
    }
  __builtin_unreachable();
}

/* The Expression macro or decorator `$T.name` for the receiver's named type
   `T`, which a package type finds by its source name, as `$Ui.row` for
   `x2cui__Ui`. In the template of `own`, `$T.name`'s own call is the
   method, so a macro can wrap the method it shadows. */
static List _method_macro(
  Compiler c, List receiver, String name, Var own) {
  Type type = receiver.cadr();
  Var owner = type ? type.car() : NULL;
  if (owner is not <string>) return NULL;
  String source = c.package_source_name(owner);
  Var stored;
  if (!_try_macro(c, c.macros, Atom.intern(%"$owner.$name"), stored) &&
      (source == owner ||
       !_try_macro(c, c.macros, Atom.intern(%"$source.$name"), stored)))
    return NULL;
  List definition = stored;
  if (definition.assoc(<name>).equal(own)) return NULL;
  Symbol kind = definition.assoc(<kind>);
  return kind == <expression> || kind == <decorator> ? definition : NULL;
}

/* The name of the macro whose template is being parsed: an Atom, a
   computed `(macro-name PART ...)`, or NULL. */
static Var _own_definition(Compiler c) =>
  c.macro_holes ? c.macro_holes.getdefault(%(definition), NULL) : NULL;

/* Whether the macro `own`, as `Ui.row` or `$W.$m`, ends in the member
   `member`, a spelling or a Name hole's member projection. */
static int _names_member(Var own, Var member) {
  match (own) case %(macro-name * ?last): return last.equal(member);
  if (!own.is_atom() || member is not <string>) return 0;
  Atom name = own;
  return name.str().endswith("." + member);
}

// The decorator name a method form spells, as `Ui.row`.
static String _method_spelling(List receiver, String name) {
  Var owner = receiver.cadr() ? receiver.cadr().car() : NULL;
  return owner is <string> ? %"$owner.$name" : name;
}

/* The capture rows of a method form whose arguments a template parsed as
   a call's: the receiver, then each argument in order, a sequence hole
   taking the rest. A forwarded `key: value` row fills an Entry hole. */
static List _method_arguments(
  Compiler c, List definition, List receiver, List supplied) {
  List rest = cons(receiver, _call_values(supplied));
  Array values = [];
  for (List holes = definition.assoc(<parameters>); holes;
       holes = holes.cdr()) {
    List hole = holes.car();
    if (hole.assoc(<sequence>).int()) {
      // A sequence before the final Entry rows stops at the first row.
      Array taken = [];
      while (rest && !(holes.cdr() && rest.car() ~= %(map-entry ? ?))) {
        taken.push(rest.car());
        rest = rest.cdr();
      }
      values.push(taken.list_free());
      continue;
    }
    if (!rest) $fail.macros_macro_missing_args(c, c.token);
    values.push(rest.car());
    rest = rest.cdr();
  }
  if (rest) $fail.macros_macro_extra_args(c, c.token);
  return _template_arguments(c, definition, values.list_free(), c.token, 0);
}

/* A call's arguments as values: no arguments for `()`, the items of a
   spliced sequence, and a `key: value` argument as its row. */
static List _call_values(List supplied) {
  Array values = [];
  foreach (Var argument in supplied) match (argument) {
    case %(expr (void) ()): {}
    case %(seq *items): foreach (Var item in items) values.push(item);
    case %(expr ? (!set ?row (map-entry ? ?))): values.push(row);
    default: values.push(argument);
  }
  return values.list_free();
}

/* Whether a decorator's target follows the arguments that begin at the
   cursor: a brace, `$`, or a word other than the operators `is` and `in`.
   No other word can follow the closing parenthesis of a call inside an
   expression. */
static int _target_follows(Compiler c) {
  Token next = c.token.after_group();
  return next.type == <"{"> || next.type == <$> ||
    (next.text.is_identifier() && next.text != "is" && next.text != "in");
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
   passes its captured items as one List; spliced as `@name`, its items
   are separate arguments, as a rest parameter takes them. */
static List _meta_argument(Compiler c) {
  List hole = c.peek_macro_hole();
  Symbol next = hole ? c.after_hole().type : 0;
  int direct = next == <,> || next == <)>;
  if (direct && hole.assoc(<sequence>).int()) {
    int splice = c.test(<@>);
    if (!splice) c.expect(<$>);
    c.next();
    List items =
      %(expr ("List") (meta-cap ($(_hole_key(hole, "value")))));
    return splice ? %(expr ("List") (splice $items)) : items;
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
  if (kind == <decorator> && definition.assoc(<target>) in %<expr macro>)
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
      c, invocation, kind, spelling,
      Diagnostics.macro_definition_note(definition));
}

static List _expression_decorator(
  Compiler c, List definition, Token invocation) {
  if (_producer_decorator(definition))
    return _decorate(c, definition, invocation, <expression>, 1);
  List arguments = _invocation_arguments(c, definition, invocation);
  if (c.peek(0) == <;> || c.peek(0) == <eof>) {
    String spelling = definition.assoc(<name>).str();
    $fail.macros_decorator_expr(
      c, invocation, spelling, Diagnostics.macro_definition_note(definition));
  }
  List target = c.parse_macro_expression_target();
  List input = %(
    target $arguments
    $(_capture_row_project(c, definition.assoc(<targetp>), $(target), 0))
  );
  List node = _invocation_node(c, definition, input, invocation);
  return %(expr (<macro-expr>) $node);
}
