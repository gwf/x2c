/*  targets.x -- macro invocation targets */

/* decorators

   A decorator application parses the decorator's arguments and then its
   target. Parsing the target can publish symbols before the replacement is
   known, so one semantic transaction stages the target and the expansion
   and a rejection rolls both back. */

/* One decorator application. A Block decorator standing before a
   file-scope function decorates that function's body, so one spelling
   covers a statement and a whole function; `function` holds the function
   then. */
static typedef struct Decoration {
  Compiler c, List definition, function, generator, Token invocation, start;
  Symbol position, Symbol kind, int open;
} Decoration;

/* invocations at syntax positions

   A claimed invocation at file, block, statement, field, enumerator, or
   map-entry position parses its arguments; a decorator also parses the
   target that follows it. */

/** Parses a direct or keyword-alias macro at the requested syntax position.
    Returns NULL without consuming a macro hole or an invocation that
    `macro_starts_target_at` does not claim; template parsing returns a
    deferred `(seq (macro-invoke ...))`, and ordinary parsing returns the bound
    expansion.
*/
List Compiler.try_parse_macro_target_at(Compiler c, Symbol position) =>
  _target_at(c, position, 0);

// macro invocation targets

/* An `open` statement omits its final `;`, as an anonymous Stmt arrow's
   statement does. */
module List _target_at(Compiler c, Symbol position, int open) {
  if (c.macro_holes && c.peek_macro_hole()) return NULL;
  Token invocation = c.token;
  List definition = _take_invocation(c, position);
  if (!definition) return NULL;
  if (definition.assoc(<kind>) == <decorator>)
    return _decorate(c, definition, invocation, position, open);
  _check_position(c, definition, invocation, position);
  return _invoke_definition(c, definition, invocation, position, open);
}

/* A macro's result must fit where it is invoked; a Declaration result also
   fits at file scope. */
module void _check_position(
  Compiler c, List definition, Token invocation, Symbol position) {
  Symbol kind = definition.assoc(<kind>);
  const MacroPos *place = _position(position);
  if (kind == place.kind || (kind == <decl-unit> && position == <unit>))
    return;
  $fail.macros_result_position(
    c, invocation, Diagnostics.macro_spelling(definition, invocation),
    _kind_spelling(kind), place.description);
}

/* Invocation parsing and expansion share one semantic transaction. Empty
   generated syntax and raised diagnostics therefore cannot leave provisional
   bindings, enumerators, statics, or generated-name state behind. */
static List _invoke_definition(
  Compiler c, List definition, Token invocation, Symbol position, int open) {
  int deferred = !!c.macro_holes;
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  List input = _invocation_arguments(c, definition, invocation);
  if (_position(position).semicolon && !open) c.expect(<;>);
  List node = _invocation_node(c, definition, input, invocation);
  List result = deferred ? %(seq $node) :
    c.bind_syntax(node, position, c.return_type);
  if (result != %(seq) || transaction.local_macros_changed())
    transaction.commit();
  return result;
}

module List _decorate(
  Compiler c, List definition, Token invocation, Symbol position, int open) {
  Decoration d = {
    .c = c, .definition = definition, .invocation = invocation,
    .position = position, .kind = definition.assoc(<target>), .open = open};
  if (_producer_decorator(definition)) return _decorate_producer(d);
  int deferred = !!c.macro_holes;
  _check_decoration_position(d);
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  int block_scope = !c.macro_holes && d.kind == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  List node = _decoration_node(d, _arguments(d, block_scope));
  if (deferred) {
    transaction.commit();
    if (_on_body(d))
      if (d.function ~= %(function ?rtype ?declarator ?))
        return %(seq (function $rtype $declarator (block $node)));
    return %(seq $node);
  }
  List result = _bind_decoration(d, node);
  with (c.token = invocation) {
    transaction.commit();
  }
  return result;
}

/* Expr and Macro producers can return another decorator. Its signature
   reads the next target; only the terminal result is placed in the program. */
static List _decorate_producer(Decoration &d) {
  Compiler c = d.c;
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  List arguments = _arguments(d, 0);
  loop {
    List node = _decoration_node(d, arguments);
    if (c.macro_holes && !_returns_decorator(d.definition)) {
      transaction.commit();
      return d.position == <expression> ? %(expr (<macro-expr>) $node)
                                       : %(seq $node);
    }
    List value = c.expand_macro_invocation_node(
      d.definition, node.caddr(), d.invocation, <decorator>);
    if (value ~= %(macrodef *)) {
      /* A named definition is published, or handed to an enclosing Macro
         target as a value; an anonymous Decorator consumes its target. */
      if (!Compiler.anonymous_macro_name(value.assoc(<name>).str())) {
        if (d.position == <expression>)
          value = c.capture_macro_value(value);
        List result = c.bind_syntax(value, d.position, c.return_type);
        transaction.commit();
        return result;
      }
      if (value.assoc(<kind>) == <decorator>) {
        if (value.assoc(<parameters>).list())
          $fail.macros_decorator_parameters(c, d.invocation);
        d.definition = value;
        d.kind = value.assoc(<target>);
        arguments = %(args);
        if (c.peek(0) == <eof> || c.peek(0) == <;>)
          $fail.macros_decorator_target(
            c, d.invocation, Diagnostics.macro_spelling(value, d.invocation),
            Diagnostics.macro_definition_note(value));
        if (d.kind in %<expr macro>) continue;
        _check_decoration_position(d);
        List continued = _decoration_node(d, arguments);
        List result = c.macro_holes ? %(seq $continued)
          : _bind_decoration(d, continued);
        transaction.commit();
        return result;
      }
      if (d.position == <expression>)
        value = c.capture_macro_value(value);
      List result = c.bind_syntax(value, d.position, c.return_type);
      transaction.commit();
      return result;
    }
    if (d.kind == <macro>) {
      List result = _bind_macro_result(
        c, d.generator, value, d.invocation, d.position);
      transaction.commit();
      return result;
    }
    if (d.kind == <expr> && d.position != <expression> &&
        _previous_source_token(c, c.token).type != <;> && !d.open)
      c.expect(<;>);
    if (d.kind == <expr> && d.position in %<block statement>)
      value = %(stmnt $value);
    List result = c.macro_holes ? value
      : c.bind_syntax(value, d.position, c.return_type);
    transaction.commit();
    return result;
  }
}

module int _producer_decorator(List definition) =>
  definition.assoc(<kind>) == <decorator> &&
  (definition.assoc(<target>) == <macro> || _returns_decorator(definition));

static int _returns_decorator(List definition) {
  match (_producer_body(definition)) {
    case %(expr ? (macro-value ?macro)):
      return macro.list().assoc(<kind>) == <decorator>;
    case %(expr ? (meta-call (expr ?type ?) ?)):
      return type.list().cdr() == %("Macro");
    default: return 0;
  }
}

module List _literal_decorator(List definition) {
  match (_producer_body(definition)) {
    case %(expr ? (macro-value ?macro)):
      return macro.list().assoc(<kind>) == <decorator> ? macro : NULL;
    default: return NULL;
  }
}

static List _producer_body(List definition) {
  List body = definition.assoc(<template>);
  loop match (body) {
    case %(expr ? (parens ?inner)): body = inner;
    default: return body;
  }
}

static void _misplaced(Decoration &d) {
  $fail.macros_decorator_position(
    d.c, d.invocation, Diagnostics.macro_spelling(d.definition, d.invocation),
    _kind_spelling(d.kind));
}

static void _check_decoration_position(Decoration &d) {
  if (!_on_body(d) &&
      _result_kind(d.definition) != _position(d.position).kind)
    _misplaced(d);
}

static List _arguments(Decoration &d, int block_scope) {
  Compiler c = d.c;
  List definition = d.definition;
  List arguments = _invocation_arguments(c, definition, d.invocation);
  if (block_scope) _bind_name_arguments(c, definition, arguments);
  if (c.peek(0) == <;>)
    $fail.macros_decorator_semicolon(
      c, d.invocation, Diagnostics.macro_definition_note(definition));
  if (c.peek(0) == <eof>)
    $fail.macros_decorator_target(
      c, d.invocation, Diagnostics.macro_spelling(definition, d.invocation),
      Diagnostics.macro_definition_note(definition));
  return arguments;
}

/* A Block decorator's Name arguments are referenced in the block's scope,
   which opens before the arguments are read. */
static void _bind_name_arguments(Compiler c, List definition, List arguments) {
  List parameters = definition.assoc(<parameters>);
  List captures = arguments.cdr();
  while (parameters) {
    List parameter = parameters.car();
    if (parameter.assoc(<kind>) == <name>) {
      Var names = captures.car().list().assoc(<value>);
      List values = parameter.assoc(<sequence>).int()
                  ? names : $(names);
      foreach (Var value in values) {
        String name = value is <list>
          ? Ast.binding_spelling(value) : value;
        c.sym.reference($(name), NULL);
      }
    }
    parameters = parameters.cdr();
    captures = captures.cdr();
  }
}

static List _decoration_node(Decoration &d, List arguments) {
  Compiler c = d.c;
  d.start = c.token;
  List target = _target(d);
  if (d.kind == <macro>) d.generator = target;
  if (d.position == <statement>) target = c.anchor_origin(target, d.start);
  List target_capture = _capture(d, target);
  List input = %(
    target $arguments
    $target_capture
  );
  return _invocation_node(c, d.definition, input, d.invocation);
}

/* Inside a template the node names its definition as the expansion will
   find it: a definition that is itself template syntax by value, a local
   macro by its local name, and any other macro by name. */
module List _invocation_node(
  Compiler c, List definition, List input, Token invocation) {
  Var stored = definition;
  Var site = invocation;
  if (c.macro_holes) {
    stored = _stored_reference(c, definition);
    site = <m-invoke>;
  }
  return %(macro-invoke $stored $input $site);
}

/* A template names a visible local macro, so its expansion applies the
   definition published where it lands, with that expansion's names. */
static Var _stored_reference(Compiler c, List definition) {
  Atom name = definition.assoc(<name>);
  if (definition.assoc(<local>).int() &&
      c.sym.lookup_macro(name) == definition)
    return %(local-macro $name);
  if (definition.assoc(<template>))
    return definition.assoc(<local>).int()
      ? definition : %(!quote $definition);
  return name;
}

static List _target(Decoration &d) {
  Compiler c = d.c;
  if (d.kind == <expr>) return c.parse_macro_expression_target();
  if (d.kind == <macro>) return _macro_argument(c);
  if (_on_body(d)) {
    d.function = c.parse_function_definition();
    if (d.function ~= %(function ? ? ?body)) return body;
    return NULL;
  }
  if (d.kind == <function>) return c.parse_function_target();
  if (d.kind == <named-type>) return c.parse_named_type();
  if (d.open) return _arrow_statement(c, 1);
  return _positional_target(c, d.position);
}

static List _positional_target(Compiler c, Symbol position) {
  switch (position) {
    case <unit>:
      with (c.capture_unit = 1) { return c.parse_top_level(); }
    case <block>: case <statement>:
      return c.parse_governed(position);
    case <field>:      return c.parse_field(c.aggregate_type);
    case <enumerator>: return c.parse_enumerator(c.aggregate_type);
    case <map-entry>:  return c.parse_map_entry();
    default: __builtin_unreachable();
  }
}

/* The target's capture row. A public Unit target of one item also carries
   that item as the construction the template requires. */
static List _capture(Decoration &d, List target) {
  Compiler c = d.c;
  List targets = target.car() == <seq> ? target.cdr() : $(target);
  Array captured_targets = [];
  foreach (List item in targets)
    captured_targets.push(_capture_source(c, item, d.start, c.token));
  List captured = captured_targets.list_free();
  List target_capture =
    _capture_row_project(c, d.definition.assoc(<targetp>), captured, 0);
  if (d.kind == <unit> && !_private_target(c, target) &&
      captured && !captured.cdr())
    target_capture = target_capture.append(%((construct $(captured.car()))));
  return target_capture;
}

/* Visibility comes from a static declaration,
   seen through a lone `seq` and a foreign alias. */
static int _private_target(Compiler c, List target) {
  int private_target = c.source_private > 0;
  List visibility_target = Ast.lone_item(target);
  if (visibility_target ~= %(falias ?declaration ?))
    visibility_target = declaration;
  if (visibility_target ~= %((!or function declare typedef) ?type *))
    private_target |= type.type().is_static();
  return private_target;
}

static List _bind_decoration(Decoration &d, List node) {
  Compiler c = d.c;
  if (!_on_body(d)) return c.bind_syntax(node, d.position, c.return_type);
  return _bind_body(c, node, d.function);
}

static int _on_body(Decoration &d) =>
  d.kind == <block> && d.position == <unit>;

/* The body was bound with the function's own result type; bind the
   produced items with it too, so a `return` that needs a conversion still
   gets one. */
static List _bind_body(Compiler c, List node, List decorated) {
  Type declared = _declared_result(decorated);
  List result = NULL;
  with (c.return_type = declared) {
    result = c.bind_syntax(node, <block>, c.return_type);
  }
  List items = result.car() == <seq> ? result.cdr() : $(result);
  if (decorated ~= %(function ?rtype ?declarator ?))
    result = %(seq (function $rtype $declarator (block @items)));
  return result;
}

static Type _declared_result(List decorated) {
  Type declared = NULL;
  if (decorated ~= %(function ?rtype ?declarator ?)) {
    List declaration = %(declare $rtype (bindings $declarator));
    if (declaration.type_from_ast() ~= %((func *) *result_type))
      declared = result_type.type().declared();
  }
  return declared;
}
