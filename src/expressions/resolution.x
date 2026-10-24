/*  resolution.x -- canonical expression resolution */


/* A C string literal cast to `String` is promoted as an assignment
   promotes it; C would reinterpret the literal's bytes as a header. */
module List _cast_expression(
  Compiler c, List decl, Type type, List operand) {
  if (c.sym.is_string_type(type) && _is_raw_string_literal(operand))
    return c.convert_expression(operand, type);
  return %(expr $type ${source_cast_content(%($decl $operand))});
}

/* A statement expression has the value and type of its final expression
   statement, and is void otherwise. A defer directly inside would wrap that
   statement in a cleanup region, and C would lose the value. A template
   binds its statement expression where it expands. */
module List _statement_expression(
  Compiler c, List block, Token origin) {
  List items = Ast.without_origin(block).cdr();
  if (_defers_directly(items))
    $fail.expressions_statement_defer(c, origin);
  Type type = c.macro_holes ? %(<macro-expr>) : _final_value_type(items);
  return %(expr $type (parens $block));
}

static int _defers_directly(List items) {
  foreach (List item in items)
    match (Ast.without_origin(item)) {
      case %(defer ?): return 1;
      case %(seq *rows): if (_defers_directly(rows)) return 1;
    }
  return 0;
}

/* Reference reads retain their resolved type through the last expression. */
static Type _final_value_type(List items) {
  List last = items ? Ast.without_origin(items.last()) : NULL;
  match (last)
    case %(stmnt (expr ?(Type type) ?)): return type;
  return %(void);
}

/* expression resolution

   Parsed source and constructed syntax enter the same resolver, which
   dispatches on a node's content. */

/** Resolves and type-annotates one expression AST in current compiler state.
    Existing `expr` type annotations are resolved semantic types.
    Already-resolved trees without unresolved descendants and non-expression
    inputs are returned unchanged; abstract declarations use the declaration
    binder. `origin` anchors diagnostics and generated operations that must
    retain source position.
*/
List Compiler.resolve_expression(Compiler c, List input, Token origin) {
  if (c.macro_application) {
    Var staged;
    int retained;
    Var carrier = input;
    match (input) case %(expr (<macro-expr>) ?inside): carrier = inside;
    if (c.take_code_value(carrier, staged, retained))
      return retained ? staged : c.resolve_expression(staged, origin);
  }
  match (input) {
    case %(decl *):
      return c.bind_syntax(input, <block>, c.return_type);
    /* A quotation or macro value application that hand-built syntax holds
       expands where it is resolved, like one the binder meets directly. */
    case %((!or "x2c.template" "x2c.quoted" macro-invoke) *):
      return c.bind_syntax(input, <expression>, c.return_type);
    case %(expr ?type ?(List content)): {
      if (type && !c.needs_resolution(input)) return input;
      return _resolve_content(c, input, type, content, origin);
    }
  }
  return input;
}

/** True when syntax still needs ordinary binding or macro substitution. */
int Compiler.needs_resolution(Compiler c, Var value) {
  List syntax;
  $ast.walk(value, syntax)
    match (syntax) {
      case %(expr (!or () (<macro-expr>)) ?): return 1;
      case %(expr ? (parens (block *))): continue;
      case $lambda_captured(?body, *captures, *params): {
        foreach (List row in captures)
          match (row) case %(capture ?binding ? ?):
            if (!(%(lambda-depth $binding) in c.semantic_binding_facts()))
              return 1;
        continue;
      }
      case $lambda_expression(?body, *params): return 1;
      case %(at m-origin ?):
        if (c.source_map && !c.macro_holes) return 1;
      case %((!or macro-bind macro-invoke macro-slot meta-call macro-value
                  "x2c.quoted") *):
        return 1;
      case $source_identifier_content(%(?name)):
        if (name is <list>) {
          List binding = name;
          if (_identifier_needs_resolution(c, binding)) return 1;
        }
        else return 1;
      // A Type hole can supply declarators with the base they bind to.
      case %(decl ?(List base) *):
        if (base.type().parts().cadr()) return 1;
    }
  return 0;
}

// True when a receiver's type must wait for macro substitution.
module int _deferred_receiver(List expr) {
  match (expr) case %(expr (<macro-expr>) ?): return 1;
  return 0;
}

static List _resolve_content(
  Compiler c, List input, Type input_type, List content, Token origin) {
  Resolve r = {.c = c, .input = input, .type = input_type, .origin = origin};
  return _content(r, content);
}

static List _content(Resolve &r, List content) {
  match (r.input) {
    case $lambda_captured(?body, *rows, *params):
      return _lambda(r, body, rows, params);
    case $lambda_expression(?body, *params):
      return _lambda(r, body, NULL, params);
  }
  if (content && (content.car() == <at> || content.car() == <src>))
    return _source(r, content);
  if (content && content.car() == <expr>)
    match (content) case %(!set ?inner (expr ? ?)):
      return r.c.resolve_expression(inner, r.origin);
  match (r.input) {
    case $indexed(?base, ?index):
      return _resolve_indexed(r.c, base, index, r.origin);
  }
  match (content) {
    case %(call ?(String callee) (args *args)):
      return _native(r, callee, args);
  }
  match (r.input) case $called(?callee, *args): return _call(r, callee, args);
  match (content) {
    case $source_identifier_content(%(?value)):
      return _resolve_identifier(r.c, value, r.type, r.origin);
    case %(!set ?binding (binding ? ?)): return _binding(r, binding);
    case $source_literal_content(%(*)): return r.input;
    case %(tpl-call *): return r.input;
    case %(macro-value ?form): return r.c.capture_macro_value(form);
    case %(meta-call ? (args *)): return _meta_call(r);
    case %(meta-cap *): return r.input;
    case %(macro-invoke *): return _invocation(r, content);
    case %("x2c.quoted" *):
      return r.c.bind_syntax(content, <expression>, r.c.return_type);
    case %(macro-slot ? ? *): return _macro_slot(r, content);
    case $source_string_content(%(*items)): return _segments(r, items);
    case %(cons ?head ?tail): return _cons(r, head, tail);
    case %(append ?head ?tail): return _append(r, head, tail);
    case $source_slice_content(%(? ? ? ?)): return _slice(r, content);
    case %(getindex ?base ?index): return _getindex(r, base, index);
    case %(dstrasgn (targets *rows) ?value):
      return _destructure(r, rows, value);
    case $source_content_pattern($sizeof_grouped, %(?value)):
      return _sizeof(r, $sizeof_grouped, value);
    case $source_content_pattern($sizeof_expression, %(?value)):
      return _sizeof(r, $sizeof_expression, value);
    case $source_generic_content(%(?control *rows)):
      return _generic(r, control, rows);
    case $source_va_arg_content(%(?expr ?decl)): return _va_arg(r, expr, decl);
    case $source_commas_content(%(*items)): return _commas(r, items);
    case %(splice ?value): return _splice(r, value);
    case %((!or offsetof nil cache macro-bind) *): return r.input;
    case $source_content_pattern($grouped, %(?inner)):
      return _parens(r, inner);
    case %(initval *): return _initval(r, content);
    case $source_composite_content(%(*items)): return _composite(r, items);
    case $source_cast_content(%((!set ?decl (decl *)) ?value)):
      return _cast(r, decl, value);
    case %(type-tag ?target): return r.c.var_tag_expression(target, r.origin);
    case $source_content_pattern($has_type, %(?value ?target)):
      return _is_type(r, value, target);
    case $source_content_pattern($has_symbol, %(?value ?tag)):
      return _is_symbol(r, value, tag);
    case $source_operator_content(%(*parts)): return _operator(r, parts);
    case $source_postfix_content(%(?op ?value)): return _postfix(r, op, value);
    case %(tadapt ?target ?value): return _tadapt(r, target, value);
  }
  if (content && content.car() == <array>) return _array_value(r);
  if (content && content.car() == <map>) return _map_value(r);
  return r.input;
}

static List _operator(Resolve &r, List parts) {
  match (parts) {
    case %((!or (!set ?op .) (!set ?op (!quote ->)))
           ?receiver (!set ?field (*))):
      return _member(r, op, receiver, field);
    case %(?op ?value): return _unary(r, op, value);
    case %(?op ?test ?yes ?no): return _conditional(r, op, test, yes, no);
    case %(?op ?left ?right): return _binary(r, op, left, right);
  }
  return r.input;
}

static List _binding(Resolve &r, List binding) {
  if (!Ast.try_binding(binding, NULL, NULL)) return r.input;
  return _resolve_identifier(r.c, binding, r.type, r.origin);
}

static List _lambda(
  Resolve &r, List body, List captures, List params) {
  if (r.c.macro_holes) return r.input;
  return r.c.bind_lambda_expression(
    r.type, %(params @params), captures, body);
}

static List _source(Resolve &r, List content) {
  match (content) case %(at m-origin ?inner): {
    if (!r.c.source_map || r.c.macro_holes) return r.input;
    return %(expr ${r.type} (at ${r.c.origin} $inner));
  }
  return r.input;
}

static List _meta_call(Resolve &r) {
  if ((r.c.meta_body && !r.c.in_pattern) || r.c.macro_holes)
    return r.input;
  if (r.origin == r.c.meta_statement && r.c.peek(0) == <;>) return r.input;
  return r.c.evaluate_meta_expression(r.input, r.origin);
}

/* An invocation expands where it is resolved, as the binder expands one,
   except in a template, whose expansion expands it. */
static List _invocation(Resolve &r, List content) {
  if (r.c.macro_holes) return r.input;
  return r.c.bind_syntax(content, <expression>, r.c.return_type);
}

static List _macro_slot(Resolve &r, List content) {
  if (r.c.macro_holes) return r.input;
  Var value = r.c.evaluate_macro_slot(content);
  match (value)
    case %(!set ?expression (expr ? ?)):
      return r.c.resolve_expression(expression, r.origin);
  return r.c.resolve_expression(
    r.c.lift_macro_lisp_expression(value, r.origin), r.origin);
}

// conversions and predicates

static List _is_type(Resolve &r, List operand, Type target) {
  List lhs = r.c.resolve_expression(operand, r.origin);
  Type lhs_type = lhs.cadr();
  if (_deferred_receiver(lhs) || _deferred_type_test(target)) {
    Macro has_type = $has_type;
    return r.c.rebuild_expression(%(<macro-expr>), has_type(lhs, target));
  }
  if (!r.c.sym.is_var_type(lhs_type))
    $fail.expressions_is_var(r.c, r.origin, lhs_type);
  Macro called = $called;
  if (target === %(void) || target === %("Void")) {
    List callee = _resolve_identifier(r.c, "Var_is_void", NULL, r.origin);
    return r.c.rebuild_expression(%(int), called(callee, %($lhs)));
  }
  Symbol vartag = _require_var_tag(r.c, target, r.origin);
  List direct = _constant_row_test(r.c, lhs, vartag, r.origin);
  if (direct) return direct;
  String tagsym = %"${(unsigned long) vartag}";
  List callee = _resolve_identifier(r.c, "Var_is", NULL, r.origin);
  return r.c.rebuild_expression(
    %(int), called(callee, %($lhs (expr ("Symbol") $tagsym))));
}

static List _is_symbol(Resolve &r, List operand, List selector) {
  List lhs = r.c.resolve_expression(operand, r.origin);
  selector = r.c.resolve_expression(selector, r.origin);
  Type lhs_type = lhs.cadr(), selector_type = selector.cadr();
  if (_deferred_receiver(lhs) || _deferred_receiver(selector)) {
    Macro has_symbol = $has_symbol;
    return r.c.rebuild_expression(
      %(<macro-expr>), has_symbol(lhs, selector));
  }
  if (!r.c.sym.is_var_type(lhs_type))
    $fail.expressions_is_var(r.c, r.origin, lhs_type);
  if (!r.c.sym.is_named_value_type(selector_type, "Symbol"))
    $fail.expressions_is_selector(r.c, r.origin, selector_type);
  match (selector)
    case %(expr ("Symbol") ${$source_literal_content(
        %(("Symbol") ? ?tag_value))}): {
      if (tag_value is <symbol>) {
        Symbol tag = tag_value;
        List direct = _constant_row_test(r.c, lhs, tag, r.origin);
        if (direct) return direct;
      }
    }
  List callee = _resolve_identifier(r.c, "Var_is", NULL, r.origin);
  Macro called = $called;
  return r.c.rebuild_expression(%(int), called(callee, %($lhs $selector)));
}

/* A statically known tag whose encoding row the decoder discriminates on
   `top` and `bottom` alone tests as two compares. `Var.is_row` takes the
   row as constants so the C compiler folds them and the operand is
   evaluated once. Tags with a validity clause, an immediate width, or a
   user registration have no row and keep the deciding decode. */
static List _constant_row_test(
  Compiler c, List lhs, Symbol tag, Token origin) {
  unsigned long top, mask, bottom;
  if (!Type.var_tag_row(tag, top, mask, bottom)) return NULL;
  List callee = _resolve_identifier(c, "Var_is_row", NULL, origin);
  List arguments = %($lhs
    (expr (unsigned) (literal (unsigned) "$top"))
    (expr (unsigned long) (literal (unsigned long) "$mask"))
    (expr (unsigned long) (literal (unsigned long) "$bottom")));
  Macro called = $called;
  return c.rebuild_expression(%(int), called(callee, arguments));
}

/* Returns the exact Var tag for a type test, rejecting types without one.
   Enums retain no identity after boxing and cannot be tested this way.
*/
static Symbol _require_var_tag(Compiler c, Type target, Token origin) {
  Type resolved = NULL;
  Symbol vartag = c.sym.var_tag_for_type(target, resolved);
  if (resolved && resolved.is_enum())
    $fail.expressions_is_enum(c, origin, target);
  if (!vartag)
    $fail.expressions_is_tag(c, origin, target);
  return vartag;
}

/** Builds an exact tag expression, deferring macro type slots until
    binding. */
List Compiler.var_tag_expression(Compiler c, Type target, Token origin) {
  if (_deferred_type_test(target))
    return %(expr (<macro-expr>) (type-tag $target));
  Symbol tag = _require_var_tag(c, target, origin);
  return %(expr ("Symbol") (literal ("Symbol") ${tag.str()} $tag));
}

static int _deferred_type_test(Type target) {
  foreach (Var specifier in target)
    match (specifier)
      case %((!or macro-bind macro-slot) *): return 1;
  return 0;
}

static List _cast(Resolve &r, List declaration, List operand) {
  operand = r.c.resolve_expression(operand, r.origin);
  declaration = r.c.bind_syntax(declaration, <block>, r.c.return_type);
  List typed = %(declare @{declaration.cdr()});
  Type type = operand.cadr() === %(<macro-expr>) ||
              _casts_to_template_typedef(r.c, declaration)
            ? %(<macro-expr>) : typed.type_from_ast();
  return _cast_expression(r.c, declaration, type, operand);
}

static List _tadapt(Resolve &r, List target, List source) {
  target = r.c.resolve_expression(target, r.origin);
  source = r.c.resolve_expression(source, r.origin);
  match (target)
    case %(expr (!set ?syntax (typedef ?target_type)) ?): {
      Type type = r.c.sym.resolve_key(syntax);
      if (!type || !type.is_pointer() ||
          !type.dereference().is_function())
        $fail.expressions_adapter_pointer(r.c, r.origin, type);
      return %(expr ($target_type) (tadapt ${r.c.origin} $source));
    }
  $fail.expressions_adapter_typedef(r.c, r.origin);
}

// collection literals

static List _segments(Resolve &r, List items) {
  Array resolved = [];
  Type type = %("String");
  foreach (List item in items) match (item) {
    case %((!or ?tag segvar segexp) ?value): {
      List expression = r.c.resolve_expression(value, r.origin);
      if (_deferred_receiver(expression)) {
        type = %(<macro-expr>);
        resolved.push(%($tag $expression));
        continue;
      }
      resolved.push(%($tag ${r.c.convert_segment_to_string(expression)}));
      continue;
    }
    default: resolved.push(item);
  }
  return %(expr $type ${source_string_content(resolved.list_free())});
}

static List _cons(Resolve &r, List head, List tail) {
  head = r.c.resolve_expression(head, r.origin);
  tail = r.c.resolve_expression(tail, r.origin);
  Type type = r.type ? r.type : %("List");
  if (_deferred_receiver(head) || _deferred_receiver(tail))
    return %(expr $type (cons $head $tail));
  head = r.c.convert_expression(head, %("Var"));
  List cached = r.c.cache_cons_cell(head, tail);
  if (cached) return cached;
  return %(expr $type (cons $head $tail));
}

static List _append(Resolve &r, List head, List tail) {
  head = r.c.resolve_expression(head, r.origin);
  tail = r.c.resolve_expression(tail, r.origin);
  head = r.c.sym.is_var_type(head.cadr())
       ? %(expr ("List") (call "Var_list_payload" (args $head)))
       : r.c.convert_expression(head, %("List"));
  return %(expr ${r.type ? r.type : %("List")}
           (append $head $tail));
}

static List _splice(Resolve &r, List expression) =>
  %(expr ${r.type} (splice ${r.c.resolve_expression(expression, r.origin)}));

static List _array_value(Resolve &r) {
  Macro array_value = $array_value;
  match (r.input) case $array_value(*elements): {
    Array resolved = [];
    foreach (Var element in elements)
      foreach (List row in r.c.evaluate_macro_rows(element))
        resolved.push(r.c.resolve_expression(row, r.origin));
    return r.c.rebuild_expression(
      r.type, array_value(resolved.list_free()));
  }
  return r.input;
}

static List _map_value(Resolve &r) {
  Macro map_value = $map_value;
  match (r.input) case $map_value(*entries): {
    Array resolved = [];
    foreach (Var entry in entries)
      foreach (Var row in r.c.evaluate_macro_rows(entry))
        resolved.push(r.c.resolve_map_entry(row, r.origin));
    return r.c.rebuild_expression(
      r.type, map_value(resolved.list_free()));
  }
  return r.input;
}

/** Resolves the key and value of one `(map-entry key value)` AST row.
    Any other shape is reported at `origin` as a parse error.
*/
List Compiler.resolve_map_entry(Compiler c, List input, Token origin) {
  match (input)
    case %(map-entry ?key ?value):
      return %(map-entry
        ${c.resolve_expression(key, origin)}
        ${c.resolve_expression(value, origin)});
  $fail.expressions_map_entry(c, origin);
}

static List _initval(Resolve &r, List content) {
  List header = NULL;
  List cases = Ast.initializer_cases(content, header);
  Array resolved = [];
  if (header) {
    Array inputs = [];
    foreach (List argument in header.cdr()) {
      List value = r.c.resolve_expression(argument.cadr(), r.origin);
      inputs.push(%(${argument.car()} $value));
    }
    resolved.push(%(input @{inputs.list_free()}));
  }
  foreach (List choice in cases) {
    (List condition, List path, Type destination, List value) = choice;
    if (condition) condition = r.c.resolve_expression(condition, r.origin);
    value = r.c.resolve_expression(value, r.origin);
    resolved.push(%($condition $path $destination $value));
  }
  return %(expr ${r.type} (initval @{resolved.list_free()}));
}

static List _composite(Resolve &r, List elements) {
  Array values = [];
  foreach (Var element in elements)
    foreach (List row in r.c.evaluate_macro_rows(element))
      values.push(_resolve_initializer(r.c, row, r.origin));
  return %(expr ${r.type} ${source_composite_content(
    values.list_free())});
}

static List _resolve_initializer(
  Compiler c, List node, Token origin) {
  match (node) {
    case %(dotinit ?field ?value):
      return %(dotinit $field ${_resolve_initializer(c, value, origin)});
    case %(indexinit ?index ?value):
      return %(indexinit ${c.resolve_expression(index, origin)}
               ${_resolve_initializer(c, value, origin)});
  }
  return c.resolve_expression(node, origin);
}

// groups and built-in forms

static List _parens(Resolve &r, List inner) {
  if (Ast.without_origin(inner).car() == <block>)
    return _statement_expression(
      r.c, r.c.bind_syntax(inner, <statement>, r.c.return_type), r.origin);
  inner = r.c.resolve_expression(inner, r.origin);
  Type type = inner.cadr();
  return %(expr $type (parens $inner));
}

static List _commas(Resolve &r, List expressions) {
  Array resolved = [];
  foreach (List expression in expressions)
    resolved.push(r.c.resolve_expression(expression, r.origin));
  List values = resolved.list_free();
  Type type = r.type;
  if (values) type = values.last().cadr();
  return %(expr $type ${source_commas_content(values)});
}

static List _destructure(Resolve &r, List targets, List source) {
  Array resolved = [];
  foreach (List target in targets)
    resolved.push(r.c.resolve_expression(target, r.origin));
  source = r.c.resolve_expression(source, r.origin);
  return %(expr ${source.cadr()}
           (dstrasgn (targets @{resolved.list_free()}) $source));
}

static List _generic(Resolve &r, List control, List associations) {
  control = r.c.resolve_expression(control, r.origin);
  Array resolved = [];
  foreach (List association in associations) match (association)
    case %(association ?selector ?value):
      resolved.push(
        %(association $selector ${r.c.resolve_expression(value, r.origin)}));
  Type type = control.cadr() === %(<macro-expr>) ? %(<macro-expr>) : NULL;
  return %(expr $type ${source_generic_content(
    %($control @{resolved.list_free()}))});
}

/* A `sizeof` keeps its grouped or bare form around the resolved operand;
   an operand that is not syntax stays as written. */
/* A template leaves `sizeof` of a typedef name untyped until it expands;
   binding the operand there makes it the `size_t` it always is. */
static List _sizeof(Resolve &r, Macro form, Var argument) {
  if (argument is not <list>) return r.input;
  List operand = argument;
  Type type = r.input.cadr();
  if (type === %(<macro-expr>)) type = %("size_t");
  return r.c.rebuild_expression(
    type, form(r.c.resolve_expression(operand, r.origin)));
}

static List _va_arg(Resolve &r, List argument, List declaration) {
  return %(expr ${r.type}
           ${source_va_arg_content(
             %(${r.c.resolve_expression(argument, r.origin)}
               ${r.c.resolve_expression(declaration, r.origin)}))});
}
