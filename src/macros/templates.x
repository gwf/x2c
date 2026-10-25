/*  templates.x -- template evaluation, rebuilding and landing */

/* quoted syntax

   A quotation whose template applies no other template builds that
   template where it is written, as `("x2c.quoted" FRESH SYNTAX)`. Each
   use of a hole is `("x2c.hole" HOLE PROJECTION VALUE)`, holding the
   local's value, and each origin anchor is `("x2c.at" NODE)`. A FRESH
   row is `(BINDER SPELLING FILE)`, where FILE marks a name that a
   file-scope row declares with linkage. Landing fills the syntax as an
   expansion fills its template: it names the private binders, projects
   each hole as a capture row would, and keeps anchors only where an
   invocation lands it. Recovery gives binding a semantic transaction.
   It counts no expansion, since the template applies nothing. */

/* One landing of quoted syntax. `retain` keeps each hole's value as the
   syntax it is, as a rebuild does. */
static typedef struct Landing {
  Compiler c, Map names, Token site, int anchored, retain;
} Landing;

/* template slots

   A slot in a template, `$(...)` or a meta call, runs while its expansion
   binds. Its value fills the slot, and a splice slot's List becomes rows. */

/** Evaluates an active template's `(macro-slot ...)` value, or a pending
    Macro value application into the invocation that expands it.
    Non-slots and slots outside an expansion are returned unchanged. A splice
    slot's `List` result is wrapped as `(seq ...)` for its syntax position.
*/
Var Compiler.evaluate_macro_slot(Compiler c, Var value) {
  if (value is not <list>) return value;
  List slot = value;
  if (slot.car() == "x2c.template") return _helper_result(c, value);
  if (slot.car() != <macro-slot>) return value;
  if (c.macro_holes || !c.macro_stack) return value;
  return _slot_value(c, slot);
}

/* A Lisp form evaluates with the active expansion's bindings, and a meta
   call runs. A construction requirement travels with an identifier the
   slot built, and a splice slot around a Unit target replaces the target
   among the items it produced. */
static Var _slot_value(Compiler c, List slot) {
  int splice = slot.cadr();
  Var form = slot.caddr();
  List active = c.macro_stack.car();
  (List definition, Var input, List bindings, Token invocation) = active;
  (void) input;
  String source_file = _definition_file(definition);
  Var required = slot.assoc(<construct>);
  Var result = form is <list>
    ? c.evaluate_meta_value(form, invocation, 1)
    : _eval_template_form(
      c, form, bindings, invocation, source_file, required);
  result = _helper_result(c, result);
  Var construction = slot.assoc(<target>);
  if (required is not void && splice) {
    construction = required;
    result = _replace_target(result, _source_unwrap(required), required);
  }
  if (construction is not void)
    result = _constructed_identifier(result, construction);
  return splice && result is <list> ? _slot_rows(result) : result;
}

static Var _constructed_identifier(Var result, Var construction) {
  String exact = NULL;
  match (result)
    case %("x2c.ident" ?(String spelling)):
      exact = spelling;
  if (exact) return %($construction $exact);
  return result;
}

static Var _slot_rows(Var result) {
  match (result) {
    case %(code-value ? ? ?): return result;
    case %(!or (macro-invoke ? ? ?) ("x2c.quoted" ? ?)):
      return %(seq $result);
    case %(seq *): return result;
  }
  return %(seq @{result});
}

/** Evaluates a macro slot and returns its syntax as a row sequence.
    `(seq ...)` contributes its children; every other result contributes one
    row.
*/
List Compiler.evaluate_macro_rows(Compiler c, Var value) {
  value = c.evaluate_macro_slot(value);
  return value is <list> && !value.is_nil() &&
         value.list().car() == <seq>
       ? value.list().cdr() : %($value);
}

/* Scratch names for one template evaluation. The count is process-wide: a
   shared parent session holds every name its filling bound, and a child
   cannot rebind an inherited one, so a count per compiler would refuse the
   second compiler that expanded the same macro. */
static unsigned long template_serial = 0;

/* Evaluates a template's Lisp form, which reads each captured binding
   through a scratch global. */
static Var _eval_template_form(
  Compiler c, String form, List bindings, Token invocation,
  String source_file, Var construction) {
  c.run_declaration_effects();
  c.ensure_macro_lisp();
  unsigned long serial = template_serial++;
  /* Provenance lookup uses captured Var identity. Structural equality must
     not let constructed or selected syntax acquire a caller's source text. */
  Map source_captures = _source_captures(bindings);
  List references = _bind_references(c, serial, bindings);
  if (references) form = _rewrite_references(form, references);
  if (construction is not void)
    form = _with_construction(c, serial, form, construction);
  MetaContext *context = MetaContext.current();
  with (context.has_bindings = !!references,
        context.captures = source_captures,
        context.definition_file = source_file,
        context.expander = c) {
    return _eval_string(c, form, invocation);
  }
}

/** Evaluates the explicit meta call `expression` at `site` with the active
    expansion's captures visible to the SDK. A nonzero `slot` marks a
    template slot, which reports a call the project meta build leaves. */
Var Compiler.evaluate_meta_value(
  Compiler c, List expression, Token site, int slot) {
  if (!c.collect_protocols) c.run_declaration_effects();
  List active = c.macro_stack ? c.macro_stack.car() : NULL;
  List bindings = active ? active.caddr() : NULL;
  String source_file = active ? _definition_file(active.car()) : c.filename;
  MetaContext *context = MetaContext.current();
  with (context.has_bindings = !!bindings,
        context.captures = _source_captures(bindings),
        context.definition_file = source_file,
        context.expander = c,
        context.evaluator = c,
        context.site = site) {
    return c.run_meta_call(expression, site, slot);
  }
}

/* Both entry forms expose source only for complete captures in the active
   expansion. The keys are the same unwrapped values passed to the helper. */
static Map _source_captures(List bindings) {
  Map captures = {};
  foreach (List pair in bindings) {
    List source;
    Var syntax;
    if (pair && _source_capture_parts(pair.cadr(), source, syntax))
      captures[((ulong) syntax.u64)] = source;
  }
  return captures;
}

/* Binds each captured value to a scratch global and returns the
   `(spelling global)` rows, newest first. */
static List _bind_references(
  Compiler c, unsigned long serial, List bindings) {
  List references = NULL;
  foreach (List pair in bindings) {
    if (!pair) continue;
    Var (binder, syntax) = pair;
    String spelling = binder.str()[1:];
    String temporary = %"_x2c_gensym_meta_${serial}_$spelling";
    Var unwrapped;
    if (!_source_capture_parts(syntax, NULL, unwrapped))
      unwrapped = _source_unwrap(syntax);
    c.macro_lisp.set_global(temporary, unwrapped);
    references = cons(%($spelling $temporary), references);
  }
  return references;
}

/* Replaces each `$name` the references bind with its scratch global. */
static String _rewrite_references(String form, List references) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Buffer rewritten = auto Buffer.new(0);
  int copied = 0;
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type != <$>) {
      token = tokenizer.next();
      continue;
    }
    Token name = tokenizer.next();
    Var replacement = name && name.type == <ident>
                    ? references.assoc(name.text) : void;
    String temporary = replacement is <string> ? replacement : NULL;
    if (temporary) {
      rewritten.write_len(form + copied, token.pos - copied);
      rewritten.write(temporary);
      copied = name.pos + name.len;
      name = tokenizer.next();
    }
    token = name;
  }
  rewritten.write_len(form + copied, form.len() - copied);
  return rewritten;
}

/* `x2c.ident` in the form builds a name that carries the construction
   requirement. */
static String _with_construction(
  Compiler c, unsigned long serial, String form, Var construction) {
  String temporary = %"_x2c_gensym_meta_${serial}_construction";
  c.macro_lisp.set_global(temporary, construction);
  return %"(let ((x2c.ident (lambda (name)
      (list $temporary name)))) $form)";
}

/* The decorator target is a value to find among the produced items, so a
   comparison finds it. Interpolating it into a pattern would read a
   binder-shaped symbol inside it, such as the `*=` operator, as a sequence
   binder. A foreign alias wraps its target, so Match recognizes that
   wrapper and the comparison still owns the target. */
static Var _replace_target(Var produced, Var target, Var required) {
  if (produced is not <list>) return void;
  List produced_items = produced;
  Array items = auto produced_items;
  int at = produced_items.index(target);
  if (at >= 0) {
    items[at] = required;
    return items.list();
  }
  for (int i = 0; i < (int) items.len(); i++)
    match (items[i]) case %(falias ?found ?native):
      if (found == target) {
        items[i] = %(falias $required $native);
        return items.list();
      }
  return void;
}

/** Evaluates a declaration recipe after its owning source is collected.
    The callback is a Lisp name and arguments are retained canonical values.
*/
Var Compiler.evaluate_declaration_recipe(
  Compiler c, Atom callback, List arguments) {
  Token invocation = c.token;
  match (c.macro_stack)
    case %((? ? ? ?token) *): invocation = token;
  c.run_declaration_effects();
  return c.apply_meta_function(callback.str(), arguments, invocation);
}

/* template calls and rebuilds

   Compile-time code calls a template by name with its argument values, and
   the compiler rebuilds a pending Macro value application from bound
   children without binding them again. */

/** Returns the syntax that invokes the template `stored`, a macro name
    spelled as a String or a local definition, with `values`: what a template
    call in a staged `meta` body evaluates to. */
List x2c_template_call(Var stored, List values) =>
  _sdk_template_call(
    stored is <string> ? Atom.intern(stored.str()) : stored, values);

static List _sdk_template_call(Var stored, List values) {
  Compiler c = Compiler.expanding();
  Token site = MetaContext.current().site;
  List definition = stored.is_atom() ? _lookup(c, stored, site) : stored;
  return %(macro-invoke $stored
    ${_template_arguments(c, definition, values, site, 0)}
    m-invoke);
}

/* The capture rows of a template call's values. A scalar Lisp value in an
   Expr hole lifts to an expression first. */
static List _template_arguments(
  Compiler c, List definition, List values, Token invocation,
  int retain_syntax) {
  Array rows = [];
  List holes = definition.assoc(<parameters>);
  for (; holes; holes = holes.cdr(), values = values.cdr())
    rows.push(
      _hole_row(c, holes.car(), values.car(), invocation, retain_syntax));
  return %(args @{rows.list_free()});
}

/* One hole's capture row of `value`. Each scalar Lisp value an Expr hole
   or sequence holds lifts to an expression first. A Type hole's type names
   its type with a String. */
static List _hole_row(
  Compiler c, List hole, Var value, Token invocation, int retain_syntax) {
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  String error = kind == <type> && value is <list>
               ? type_name_error(value) : NULL;
  if (error) $fail.macros_type_name(c, invocation, error);
  if (!hole.assoc(<sequence>).int())
    return _capture_row_project(
      c,
      hole, %(${lifts ? _lifted(c, value, invocation) : value}),
      retain_syntax);
  List sources = value;
  if (lifts) {
    Array lifted = [];
    foreach (Var item in sources) lifted.push(_lifted(c, item, invocation));
    sources = lifted.list_free();
  }
  return _capture_row_project(c, hole, sources, retain_syntax);
}

/* A number, String, or Symbol becomes the literal expression that holds
   it; other values are already syntax. */
static Var _lifted(Compiler c, Var value, Token invocation) =>
  value.is_integer() || value.is_floating() || value is <string> ||
  value is <symbol> ? c.lift_macro_lisp_expression(value, invocation) : value;

/* A helper's result with each template call the helper left for the
   compiler replaced by its invocation. */
module Var _helper_result(Compiler c, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %((!or macrodef "x2c.quoted") *): return value;
    case %(code-value "lowered" *): return value;
    case $source_literal_content(%(*)): return value;
  }
  match (value) {
    case %("x2c.template" ?stored ?(List values)): {
      stored = _helper_result(c, stored);
      values = _helper_result(c, values);
      Token site = c.macro_invocation_site(<m-invoke>);
      if (!site) site = c.token;
      MetaContext *context = MetaContext.current();
      with (context.expander = c, context.site = site) {
        return _sdk_template_call(
          stored is <string> ? Atom.intern(stored.str()) : stored, values);
      }
    }
  }
  List child;
  $ast.rewrite_children(value.list(), child, _helper_result(c, child));
}

/** Rebuilds an expression from a pending Macro value application, preserving
    its established root `type`, child stage, and source wrappers. Binding,
    capture collection, hygiene, and effects do not run, and a statement
    expression's template-origin wrappers are omitted. */
List Compiler.rebuild_expression(Compiler c, Type type, List application) {
  List rebuilt = _rebuild(c, application, NULL);
  return %(expr $type @{rebuilt.cddr()});
}

/** Rebuilds a statement template as a canonical unbraced `seq`. Bound
    children keep their identities and origins; template-origin wrappers
    are omitted because this path does not open an invocation. */
List Compiler.rebuild_statement(Compiler c, List application) =>
  _rebuild(c, application, NULL);

/** Constructs a fresh function from a Unit template after lowering. The
    caller supplies its bound name and lowered children; binding does not
    run. */
List Compiler.rebuild_unit_function(Compiler c, List application) {
  List function = _rebuild(c, application, NULL).cadr();
  match (function) case %(api-source ? ? ?inner): return inner;
  return function;
}

/** Rebuilds a bound function through a Function decorator without binding it
    again. The template keeps the target's return type and declarator. */
List Compiler.rebuild_function(Compiler c, List target, List application) =>
  _rebuild(c, application, target).cadr();

/* Substitute bound syntax into a structural template without binding it.
   The caller supplies complete children and a template with no free names,
   computed slots, or nested applications. The definition's rebuild row
   holds the template and, for each hole, the binders of the projections
   it uses. Quoted syntax fills its own holes and keeps their values. */
static List _rebuild(
  Compiler c, List application, List target) {
  match (application) case %("x2c.quoted" ? ?syntax): {
    Landing landing = {.c = c, .site = c.token, .retain = 1};
    return _fill_syntax(landing, syntax);
  }
  (Var marker, List definition, List values) = application;
  (void) marker;
  List rebuild = definition.assoc(<rebuild>);
  (List template, List keys) = rebuild;
  List rows = _template_arguments(c, definition, values, c.token, 1).cdr();
  if (target)
    rows = rows.append(
      %(
        ${_capture_row_project(
          c, definition.assoc(<targetp>), %($target), 1)}));
  List bindings = NULL;
  foreach (List row in rows) {
    bindings = _row_bindings(keys.car(), row, bindings);
    keys = keys.cdr();
  }
  return template.replace(bindings);
}

static List _row_bindings(List keys, List row, List bindings) {
  List fields = _row_fields(row);
  foreach (Atom binder in keys) {
    if (binder != <?>) bindings = %(($binder ${fields.car()}) @bindings);
    fields = fields.cdr();
  }
  return bindings;
}

/* A capture row's source, value, expression, splice, return, and
   declarator projections. A sequence's value stands for its expression
   and splice, and a singular Function hole's value also supplies its
   return type and declarator. */
static List _row_fields(List row) {
  match (row) {
    case %(capture (source *sources) (value *values)):
      return %($sources $values $values $values () ());
    case %(capture (source ?source) (value ?value) (expression ?expression)
                   (splice *splice)): {
      List result = NULL, declarator = NULL;
      match (value) case %(function ?returned ?declared ?): {
        result = returned;
        declarator = declared;
      }
      return %($source $value $expression $splice $result $declarator);
    }
  }
  return NULL;
}

/** Binds quoted `syntax` with its `fresh` rows at `position`, as the
    expansion of its quotation would. */
List Compiler.land_quotation(
  Compiler c, List fresh, Var syntax, Symbol position, Type return_type) {
  Token site = c.macro_invocation_site(<m-invoke>);
  Landing landing = {
    .c = c, .site = site ? site : c.token, .anchored = !!site};
  List bound = NULL;
  with (c.macro_application = c.macro_application + 1) {
    SymTxn transaction = { 0 };
    if (c.recovery_depth > 0)
      transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    landing.names = _private_names(c, fresh);
    Var filled = _fill_syntax(landing, c.thaw_declaration_syntax(syntax));
    with (c.token = site, c.origin = c.record_origin(site)) {
      bound = c.bind_syntax(filled, position, return_type);
    }
    transaction.commit();
  }
  if (position == <block> || position == <statement> ||
      position == <unit>)
    match (bound) case %(seq ?item): return item;
  return bound;
}

/* Each fresh binder's private name. */
static Map _private_names(Compiler c, List fresh) {
  if (!fresh) return NULL;
  Map names = {};
  // The outermost active row's fourth field is its invocation token.
  Token root = c.macro_stack ? c.macro_stack.last().list()[3] : NULL;
  int file_scope = c.sym.at_file_scope();
  foreach (List row in fresh) {
    (Var binder, Var spelling, Var file) = row;
    names[binder] = _private_name(
      c, spelling.str(), file_scope && file.int() ? root : NULL);
  }
  return names;
}

/* The filled syntax. A hole that is a sequence or a splice contributes
   its items to the List that holds it. */
static Var _fill_syntax(Landing &l, Var syntax) {
  Var name;
  if (syntax.is_binder())
    return (void *) l.names && l.names.try_get(syntax, name) ? name : syntax;
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  List node = syntax;
  // Only the quoted forms have a String head.
  if (node.car() is <string>)
    match (node) {
      case %("x2c.at" ?inner): {
        Var filled = _fill_syntax(l, inner);
        return l.anchored ? %(at m-origin $filled).var() : filled;
      }
      case %("x2c.hole" ?(List hole) ?projection ?value):
        return _project_hole(l, hole, projection, value);
    }
  Array items = NULL;
  int index = 0;
  foreach (Var item in node) {
    List spliced = NULL;
    int splices = _splices(l, item, spliced);
    Var filled = splices ? void : _fill_syntax(l, item);
    if (!(void *) items && (splices || filled != item)) {
      items = [];
      List prior = node;
      for (int i = 0; i < index; i++, prior = prior.cdr())
        items.push(prior.car());
    }
    if (splices) foreach (Var each in spliced) items.push(each);
    else if ((void *) items) items.push(filled);
    index++;
  }
  Var filled = (void *) items ? items.list_free().var() : syntax;
  return l.retain && node.car() == <declare>
    ? _retained_declaration(filled) : filled;
}

/* A retained declaration with its base's pointer, array, and function
   modifiers moved onto each declarator, as parsing moves them. */
static Var _retained_declaration(List declaration) {
  match (declaration) case %(declare ?specifiers (bindings *rows)): {
    List modifiers = NULL;
    List base = Type.declaration_base(specifiers, modifiers);
    if (!modifiers) return declaration;
    Array moved = [];
    foreach (List row in rows)
      moved.push(Ast.append_modifiers(row, modifiers));
    return %(declare $base (bindings @{moved.list_free()}));
  }
  return declaration;
}

/* Whether `item` is a sequence or splice hole, whose items it sets. */
static int _splices(Landing &l, Var item, List &spliced) {
  if (item is not <list> || item.is_nil() || item.list().car() is not <string>)
    return 0;
  match (item) case %("x2c.hole" ?(List hole) ?projection ?value):
    if (projection == <splice> || hole.assoc(<sequence>).int()) {
      spliced = _project_hole(l, hole, projection, value);
      return 1;
    }
  return 0;
}

/* A hole's projection of its value, as an expansion's capture row holds
   it. A shell is an Expr hole's expression in an expression position,
   which a rebuild leaves bare. */
static Var _project_hole(Landing &l, List hole, Symbol projection, Var value) {
  Compiler c = l.c;
  if (projection == <member>) return _member_spelling(c, value);
  if (!l.retain) value = _helper_result(c, value);
  List row = _hole_row(c, hole, value, l.site, l.retain);
  Symbol field = projection == <shell> ? <expression> : projection;
  Var projected = _row_fields(row)[
    %(source value expression splice).index(field)];
  if (projection != <shell> || l.retain) return projected;
  return %(expr (<macro-expr>) $projected);
}
