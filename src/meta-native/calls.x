/*  calls.x -- native meta calls

    Copyright (c) 2026 Gary William Flake.
*/

/* explicit meta calls

   A `$f(...)` call of a `meta` function outside a `meta` body runs at
   compile time, and its value becomes syntax at the call. */

/** Executes an explicit meta call and inserts its result at a code
    boundary. */
List Compiler.evaluate_meta_expression(
  Compiler c, List expression, Token site) =>
  _meta_result(
    c, expression, c.evaluate_meta_value(expression, site, 0), site);

/** Executes an explicit meta call written as a whole statement at
    `context`. A code List result binds there, so the call may return a
    statement as well as an expression. */
List Compiler.evaluate_meta_statement(
  Compiler c, List expression, Symbol context, Token site) {
  Var value = c.evaluate_meta_value(expression, site, 0);
  if (_code_result(c, value) && !value.is_nil())
    return c.bind_macro_lisp_statement(value, context);
  return %(stmnt ${_meta_result(c, expression, value, site)});
}

/* The expression a meta call's `value` becomes at its call. */
static List _meta_result(
  Compiler c, List expression, Var value, Token site) {
  if (value is void && c.meta_build) {
    /* A meta body's pattern makes the call when the body runs. */
    if (c.meta_body)
      match (expression) case %(expr ?type (meta-call ?callee ?arguments)):
        return c.resolve_expression(
          %(expr $type (call $callee $arguments)), site);
    List placeholder = %(expr (int) (literal (int) "0"));
    c.meta_group.push(%(later $placeholder));
    return placeholder;
  }
  Type declared = expression.cadr();
  match (expression) case %(expr ? (meta-call (expr ?signature ?) ?)):
    declared = signature.cdr();
  if (declared === %(void))
    return %(expr (void) (cast (void) (expr (int) (literal (int) "0"))));
  if (_code_result(c, value)) return c.lift_macro_lisp_expression(value, site);
  List result = c.meta_value_expression(declared, value, site);
  return result ? result : c.lift_macro_lisp_expression(value, site);
}

/* Whether a meta call's result is code. Inside an expansion every List
   is. Elsewhere code is an expression, an identifier, or a pending
   quotation or macro application; other Lists, and any List a pattern
   inserts, are data. */
static int _code_result(Compiler c, Var value) {
  if (value is not <list>) return 0;
  if (c.macro_stack) return 1;
  if (c.in_pattern) return 0;
  match (value)
    case %((!or expr macro-invoke "x2c.quoted" "x2c.template" "x2c.ident")
           *):
      return 1;
  return Ast.try_binding(value, NULL, NULL);
}

/** Runs the explicit meta call `expression` at `site`. The project meta
    build's own parse leaves a project function's call for the translation:
    an expression takes a placeholder, and a template `slot`, which has
    none, is reported. */
Var Compiler.run_meta_call(
  Compiler c, List expression, Token site, int slot) =>
  _run_meta(c, expression, NULL, NULL, site, slot);

/** Applies the meta function spelled `name` to the evaluated `arguments`
    at `site`, outside any expansion. A call the project meta build leaves
    for the translation returns void. */
Var Compiler.apply_meta_function(
  Compiler c, String name, List arguments, Token site) {
  MetaContext *context = MetaContext.current();
  $let(context.has_bindings, 0)
  $let(context.captures, NULL)
  $let(context.definition_file, c.filename)
  $let(context.expander, c)
  $let(context.evaluator, c)
  $let(context.site, site)
  $let(meta_call_form, meta_call_form)
    return _run_meta(c, NULL, name, arguments, site, 0);
}

/* Runs the meta call `expression`, or else `name` applied to `arguments`,
   and reports its failure at `site`. */
static Var _run_meta(
  Compiler c, List expression, String name, List arguments, Token site,
  int slot) {
  Var value;
  meta_call_form = NULL;
  try value = expression ? _meta_call_value(c, expression, site)
                         : _meta_named_value(c, name, arguments, site);
  catch %(meta-later *): {
    value = void;
    if (slot)
      $fail.meta_native_call_deferred(c, site);
  }
  catch %(malformed (category ?category)):
    raise %(malformed (category $category));
  catch %(call-stack *):
    $fail.meta_native_call_depth(c, site);
  catch %(?code *detail):
    c.report_lisp_failure(site, cons(code, detail), meta_call_form.repr());
  return value;
}

/* The last call a `$` expression made, which a failure renders. A unit's
   Pool holds it, so each `$` expression starts without one. */
static List meta_call_form = NULL;

/* Calls a `meta` function named at a code boundary with its evaluated
   arguments. */
static Var _meta_call_value(Compiler c, List expression, Token site) {
  match (expression)
    case %(expr ? (meta-call
        (expr ?callee ${$source_identifier_content(
          %((!or (binding ? ?name)
                 ((!or binding-name binding-global) ?name))))})
        (args *arguments))): {
      if (name is not <string>) break;
      Array values = _meta_values(c, callee, arguments, site);
      return _meta_named_value(c, name, values.list_free(), site);
    }
  $fail.meta_native_call_target(c, site);
}

/* Applies the session's `name` to `arguments`, recorded as the call a
   failure renders. A compiled function the compiler links is called
   through its Func. */
static Var _meta_named_value(
  Compiler c, String name, List arguments, Token site) {
  Var function = _shipped_callee(c, name);
  if (function is void) function = _meta_function(c, name, site);
  meta_call_form = cons(Atom.intern(name), arguments);
  if (function === _linked_module()[name])
    return _apply_linked(function.pointer(), arguments);
  return c.macro_lisp.apply(function, arguments);
}

/* The compiler's linked copy of `name` when shipped code calls it, or
   void. A shipped rule's translator and a template defined in a linked
   provider resolve their calls to the copies the compiler links, so a
   program definition spelled the same is a separate definition. */
static Var _shipped_callee(Compiler c, String name) {
  if (!c.applying_shipped() && !_shipped_definition()) return void;
  Var function;
  return _linked_module().try_get(name, function) ? function : void;
}

/* Whether the template now expanding was defined in a linked provider. */
static int _shipped_definition(void) {
  String file = MetaContext.current().definition_file;
  if (!file || file.startswith("<")) return 0;
  return !!Compiler.linked_meta_provider_source(Compiler.portable_path(file));
}

static Var _apply_linked(Func function, List arguments) {
  unsigned count = arguments.len(), index = 0;
  FuncArg *argv = xcalloc(count + 1, sizeof(FuncArg));
  defer xfree(argv);
  foreach (Var argument in arguments) argv[index++] = FuncArg.value(argument);
  return function.apply(count, argv);
}

/* Each argument evaluates as the type its parameter declares wants. */
static Array _meta_values(
  Compiler c, Var callee, List arguments, Token site) {
  List params = NULL;
  match (callee) case %((func ?declared) *): params = declared;
  Array values = [];
  foreach (List argument in arguments) {
    Type want = NULL;
    if (params) {
      want = params.car();
      params = params.cdr();
    }
    values.push(c.meta_argument(argument, want, site, _meta_call_value));
  }
  return values;
}

/* The session's binding of `name`, binding an included native function on
   first use. The project meta build's own parse has no helper yet, so a
   call to a project function there is left for the translation. */
static Var _meta_function(Compiler c, String name, Token site) {
  c.ensure_macro_lisp();
  Var function = void;
  if (!c.macro_lisp.try_get(name, function) && _bind_project_meta(c, name))
    c.macro_lisp.try_get(name, function);
  if (!c.macro_lisp.try_get(name, function) && c.bind_native_meta(name))
    c.macro_lisp.try_get(name, function);
  if (function is void && c.meta_build) raise %(meta-later (name $name));
  if (function is void)
    $fail.meta_native_call_binding(c, site, name);
  return function;
}
