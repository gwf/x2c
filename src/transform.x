/*  transform.x -- x2c AST transformation pipeline

    Lowers typed expressions, literals, and control flow into the AST forms
    consumed by C emission.

    One recursive normalizer owns expressions and cleanup; `callables.x`
    lowers the lambdas and `Func` conversions it meets. Newly constructed
    nodes normalize locally; complete functions receive their transfer
    cleanup before emission. The active Compiler reports errors.
*/

#pragma once

/* CPP ignores pragma once in its main input. Define the cycle guard only
   during symbol preprocessing, so generated C keeps its declarations. */
#ifndef X2C_TRANSFORM_SOURCE
#ifdef X2CCPP
#define X2C_TRANSFORM_SOURCE
#endif

$(import "../lib/error-macros.xmacro")
#include "compiler.x"
#pragma private

$(import "../src/ast-rewrite.xmacro")
$(import "../src/adapter-memo.xmacro")
#include "meta.x"
$(import "../src/grammar.xmacro")

#include <stdio.h>

#include "ast.x"
#include "type.x"
#include "parse.x"
#include "expressions.x"
#include "string.x"
#include "symbol.x"
#include "var.x"
#include "list.x"
#include "protocol.x"
#include "regions.x"
#include "callables.x"
#include "cleanup.x"

// type coercion passes

static List _to_var(Compiler compiler, List expr) =>
  compiler.convert_expression(expr, %("Var"));

static List _symbol_expression(Symbol value) =>
  %(expr ("Symbol") "${(unsigned long) value}");

static List _truthy_expression(Compiler compiler, List expr) {
  if (!expr) return expr;
  List resolved = compiler.resolve_protocol_member(expr.cadr(), "truth");
  if (!resolved) return expr;
  (List binding, Type signature) = resolved;
  return %(expr (int) (call (expr $signature (ident $binding)) (args $expr)));
}

// call and binding passes

typedef enum PrintfLength {
  _printf_default,
  _printf_hh,
  _printf_h,
  _printf_l,
  _printf_ll,
  _printf_j,
  _printf_z,
  _printf_t,
  _printf_L
} PrintfLength;

static int _iter_immediate_consumer(String name) =>
  name == "Iter_try_next" || name == "Iter_next" ||
         name == "Iter_list" || name == "Iter_array" ||
         name == "Iter_foldl" || name == "Iter_any" ||
         name == "Iter_all" || name == "Iter_find" ||
         name == "Iter_count" || name == "Iter_sum" ||
         name == "Iter_product" || name == "Iter_min" ||
         name == "Iter_max";

static int _printf_has_var(Compiler compiler, List args, int first_value) {
  int index = 0;
  foreach (List arg, args) {
    if (index++ < first_value) continue;
    if (compiler.sym.is_var_type(arg.cadr())) return 1;
  }
  return 0;
}

static void _printf_error(Compiler compiler, String family, String message) {
  String note = "printf-family call: %s".printf(family);
  compiler.report_error(<xform>, message, NULL, %($note));
}

static int _printf_is_digit(int ch) => ch >= '0' && ch <= '9';

static int _printf_valid_length(PrintfLength length, int conversion) {
  switch (conversion) {
    case 'd': case 'i': case 'o': case 'u': case 'x': case 'X':
      return length != _printf_L;
    case 'f': case 'F': case 'e': case 'E':
    case 'g': case 'G': case 'a': case 'A':
      return length == _printf_default || length == _printf_l ||
             length == _printf_L;
    case 'c': case 's':
      return length == _printf_default || length == _printf_l;
    case 'p': return length == _printf_default;
    case 'n': return length != _printf_L;
    default:  return 0;
  }
}

static Type _printf_integer_type(PrintfLength length, int is_unsigned) {
  switch (length) {
    case _printf_j: case _printf_z: case _printf_t: return NULL;
    case _printf_hh: case _printf_h: return %(int);
    case _printf_l:  return is_unsigned ? %(unsigned long) : %(long);
    case _printf_ll:
      return is_unsigned ? %(unsigned long long) : %(long long);
    default: return is_unsigned ? %(unsigned) : %(int);
  }
}

/* Native arguments retain C calling semantics. */
static void _lower_printf_value(
  Compiler compiler, Array values, int index, String family,
  PrintfLength length, int conversion) {
  List arg = values[index];
  if (!compiler.sym.is_var_type(arg.cadr())) return;

  Type target = NULL;
  if (conversion == 'd' || conversion == 'i')
    target = _printf_integer_type(length, 0);
  else if (conversion == 'o' || conversion == 'u' ||
           conversion == 'x' || conversion == 'X')
    target = _printf_integer_type(length, 1);
  else if (conversion == 'f' || conversion == 'F' ||
           conversion == 'e' || conversion == 'E' ||
           conversion == 'g' || conversion == 'G' ||
           conversion == 'a' || conversion == 'A')
    target = length == _printf_L ? %(long double) : %(double);
  else if (conversion == 'c' && length == _printf_default) target = %(int);
  else if (conversion == 's' && length == _printf_default) {
    values[index] = %(expr ("String") (call "Var_str" (args $arg)));
    return;
  }
  if (target) {
    values[index] = compiler.convert_expression(arg, target);
    return;
  }

  String message =
    "cannot infer a native argument for Var at %%%c"
      .printf(conversion);
  _printf_error(
    compiler, family,
    %"$message; use an explicit converter for this format conversion");
}

static void _lower_printf_star(
  Compiler compiler, Array values, int index, String family) {
  if (index >= values.len())
    _printf_error(compiler, family, "format consumes a missing '*' argument");
  List arg = values[index];
  if (compiler.sym.is_var_type(arg.cadr()))
    values[index] = compiler.convert_expression(arg, %(int));
}

typedef struct PrintfWalk {
  Compiler compiler;
  Array values;
  String format, family;
  int cursor, end, value_index;
} PrintfWalk;

static void _printf_position(PrintfWalk *walk) {
  int probe = walk.cursor;
  while (probe < walk.end && _printf_is_digit(walk.format[probe])) probe++;
  if (probe < walk.end && walk.format[probe] == '$')
    _printf_error(
      walk.compiler, walk.family,
      "positional formats cannot infer Var argument types");
}

static void _printf_width(PrintfWalk *walk) {
  while (walk.cursor < walk.end &&
         (walk.format[walk.cursor] == '-' ||
          walk.format[walk.cursor] == '+' ||
          walk.format[walk.cursor] == ' ' ||
          walk.format[walk.cursor] == '#' ||
          walk.format[walk.cursor] == '0'))
    walk.cursor++;
  if (walk.cursor < walk.end && walk.format[walk.cursor] == '*') {
    walk.cursor++;
    _printf_position(walk);
    _lower_printf_star(
      walk.compiler, walk.values, walk.value_index++, walk.family);
  }
  else while (walk.cursor < walk.end &&
              _printf_is_digit(walk.format[walk.cursor])) walk.cursor++;
}

static void _printf_precision(PrintfWalk *walk) {
  if (walk.cursor >= walk.end || walk.format[walk.cursor] != '.') return;
  walk.cursor++;
  if (walk.cursor < walk.end && walk.format[walk.cursor] == '*') {
    walk.cursor++;
    _printf_position(walk);
    _lower_printf_star(
      walk.compiler, walk.values, walk.value_index++, walk.family);
  }
  else while (walk.cursor < walk.end &&
              _printf_is_digit(walk.format[walk.cursor])) walk.cursor++;
}

static PrintfLength _printf_length(PrintfWalk *walk) {
  PrintfLength length = _printf_default;
  if (walk.cursor + 1 < walk.end && walk.format[walk.cursor] == 'h' &&
      walk.format[walk.cursor + 1] == 'h') {
    length = _printf_hh;
    walk.cursor += 2;
  }
  else if (walk.cursor + 1 < walk.end &&
           walk.format[walk.cursor] == 'l' &&
           walk.format[walk.cursor + 1] == 'l') {
    length = _printf_ll;
    walk.cursor += 2;
  }
  else if (walk.cursor < walk.end) {
    switch (walk.format[walk.cursor]) {
      case 'h': length = _printf_h; walk.cursor++; break;
      case 'l': length = _printf_l; walk.cursor++; break;
      case 'j': length = _printf_j; walk.cursor++; break;
      case 'z': length = _printf_z; walk.cursor++; break;
      case 't': length = _printf_t; walk.cursor++; break;
      case 'L': length = _printf_L; walk.cursor++; break;
    }
  }
  return length;
}

static void _printf_conversion(PrintfWalk *walk) {
  _printf_position(walk);
  _printf_width(walk);
  _printf_precision(walk);
  PrintfLength length = _printf_length(walk);
  if (walk.cursor >= walk.end)
    _printf_error(walk.compiler, walk.family, "incomplete format conversion");
  int conversion = walk.format[walk.cursor++];
  if (!_printf_valid_length(length, conversion)) {
    String message =
      "unsupported or malformed format conversion %%%c".printf(conversion);
    _printf_error(walk.compiler, walk.family, message);
  }
  if (walk.value_index >= walk.values.len()) {
    String message =
      "format conversion %%%c consumes a missing argument".printf(conversion);
    _printf_error(walk.compiler, walk.family, message);
  }
  _lower_printf_value(
    walk.compiler, walk.values, walk.value_index++, walk.family,
    length, conversion);
}

static void _printf_scan(PrintfWalk *walk, int raw) {
  while (walk.cursor < walk.end) {
    if (raw && walk.format[walk.cursor] == '\\') {
      walk.cursor += walk.cursor + 1 < walk.end ? 2 : 1;
      continue;
    }
    if (walk.format[walk.cursor++] != '%') continue;
    if (walk.cursor >= walk.end)
      _printf_error(
        walk.compiler, walk.family, "incomplete format conversion");
    if (walk.format[walk.cursor] == '%') {
      walk.cursor++;
      continue;
    }
    _printf_conversion(walk);
  }
}

// Align static format conversions with variadic arguments and lower only
// Var crossings. The parser understands the standard output grammar far
// enough to preserve native arguments around the safe automatic subset.
static List _lower_printf_vars(Compiler c, List ast) {
  (List callee, List args_node) = ast.cdr();
  const PrintfFn *info = callee.printf_family();
  if (!info) return ast;
  List args = args_node.cdr();
  if (!_printf_has_var(c, args, info.first_arg)) return ast;

  Array values = [];
  foreach (Var arg, args) values.push(arg);
  String family = (String) info.name;
  if (info.fmt_arg >= values.len())
    _printf_error(c, family, "call has no format argument");
  List format_arg = values[info.fmt_arg], int raw = 0;
  String format = c.printf_static_format(format_arg, raw);
  if (!format)
    _printf_error(
      c, family,
      "Var arguments require a single static format literal");

  PrintfWalk walk = {
    .compiler = c, .values = values, .format = format, .family = family,
    .cursor = raw ? 1 : 0,
    .end = raw ? format.len() - 1 : format.len(),
    .value_index = info.first_arg,
  };
  _printf_scan(&walk, raw);

  for (int i = walk.value_index; i < values.len(); i++) {
    List arg = values[i];
    if (c.sym.is_var_type(arg.cadr()))
      _printf_error(
        c, family,
        "Var argument has no corresponding format conversion");
  }
  List newargs = values.list_free();
  return %(call $callee (args @newargs));
}

static List _typed_call(
  Compiler compiler, List callee, List params, List args) {
  String callee_name = NULL;
  match (callee) {
    case %(expr ? ${$source_identifier_content(%(?binding))}):
      callee_name = binding_identity_spelling(binding);
  }
  int list_varargs = callee_name == "List_list_n";
  if (compiler.fn_name && _iter_immediate_consumer(callee_name) && args)
    args = cons(compiler.complete_iter_chain(args.car()), args.cdr());
  Array values = [], int arg_index = 0;
  for (List p = params, a = args; a;
       p = p.cdr(), a = a.cdr(), arg_index++) {
    List param = (p ? p.car().list() : NULL), arg = a.car();
    List expected = param;
    if (list_varargs && arg_index > 0) expected = %("Var");
    if (param && param.car() == <param>) expected = param.type_from_ast();
    arg = compiler.maybe_adapt_func_arg(arg, expected);
    List converted = expected
      ? compiler.convert_expression(arg, expected)
      : compiler.lower_lambda_expr(arg);
    values.push(converted);
  }
  List newargs = values.list_free();
  Macro called = $called;
  return compiler.rebuild_expression(
    NULL, called(callee, newargs)).caddr();
}

static List _call(Compiler compiler, List ast) {
  ast = _lower_printf_vars(compiler, ast);
  match (ast)
    case $source_pattern($called, %(?callee *arguments)):
      match (callee.cadr()) {
        case %((func ?parameters) *):
          return _typed_call(compiler, callee, parameters, arguments);
        case %((!or (!quote *) & ^) (func ?parameters) *):
          return _typed_call(compiler, callee, parameters, arguments);
      }
  return ast;
}

/* A resolved bracket read is a semantic marker, distinct from the parsed
   `$indexed` source form. Keep its one structural projection here. */
static int _resolved_index_parts(
  List expr, List &base, Type &base_type, List &selector) {
  match (expr)
    case %(expr ? (getindex (!set ?matched_base (expr ?type ?))
                            ?matched_selector)): {
      base = matched_base;
      base_type = type;
      selector = matched_selector;
      return 1;
    }
  return 0;
}

// Inject conversions so assignment RHS matches the annotated LHS type.
static List _assignment(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  if (lhs.match(%(expr ? (slice *))))
    compiler.report_error(
      <xform>, "slice expressions are not assignable",
      NULL, %("call the collection's setslice method explicitly"));
  List base, index;
  Type base_type;
  if (_resolved_index_parts(lhs, base, base_type, index)) {
    /* String is immutable and interned, so an in-place bracket write
       would mutate shared storage and leave its cached header hash
       stale. A raw write bypasses that invariant, while generic
       setindex returns a copy that this assignment would discard. */
    if (compiler.sym.is_string_type(base_type)) {
      String note = "String is immutable: use the copy-producing " +
                    "String.withindex, or bind a char * to write a " +
                    "transient String.malloc buffer";
      compiler.report_error(
        <xform>, "String does not support bracket assignment", NULL,
        %($note));
    }
    if (!compiler.resolve_protocol_member(base_type, "setindex"))
      compiler.report_error(
        <xform>, %"type $base_type does not support bracket assignment",
        NULL, %("use an explicit copy-producing method where available"));
    return %(setindex $base $index $rhs);
  }
  rhs = compiler.convert_expression(rhs, lhs.cadr());
  return %(op $op $lhs $rhs);
}

static List _declaration(Compiler compiler, List ast) {
  match (ast) {
    case %((!set ?head (!or declare decl)) ?target
           (bindings *bound_list)): {
      Array values = [], List new_bind = NULL;
      foreach (Ast binding, bound_list) {
        new_bind = binding;
        match (binding)
          case %(op = (bind ?var ?mods) ?rhs): {
            Type target_type = %(declare $target
              (bindings (bind $var $mods))).type_from_ast();
            List native_target = %(expr $target_type (ident $var));
            List converted = compiler.convert_initializer(
              rhs, target_type, native_target);
            new_bind = %(
              op = (bind $var $mods) $converted
            );
            if (target_type.type().is_static())
              match (converted)
                case %(expr ("Func")
                       (ident (!set ?dependency (binding ? ?)))):
                  compiler.static_init_deps[var] = %($dependency);
          }
        values.push(new_bind);
      }
      List new_bindings = values.list_free();
      return %($head $target (bindings @new_bindings));
    }
  }
  return ast;
}

// A `Var` subscript of a native pointer or array reads as an integer.
static List _index(Compiler compiler, List ast) {
  Macro indexed = $indexed;
  match (ast)
    case $source_pattern($indexed, %(?base ?selector)):
      match (selector)
        case %(expr ?type ?)
          if (compiler.sym.is_var_type(type)): {
            List converted = compiler.convert_expression(selector, %(long));
            return compiler.rebuild_expression(
              NULL, indexed(base, converted)).caddr();
          }
  return ast;
}

static List _destructure_source(
  Compiler compiler, List source, Type source_type) {
  // An integer, floating, or enumeration source cannot destructure. Reject
  // it before converting so the report names the construct the user wrote;
  // convert_expression would instead diagnose an integer reaching a
  // pointer.
  if (compiler.sym.resolve_numeric_type(source_type.canonicalize()))
    compiler.report_error(
      <type>, "destructuring requires a List source", NULL,
      %(("source type" $source_type)));
  List converted = compiler.convert_expression(source, %("List"));
  Type converted_type = NULL;
  match (converted)
    case %(expr ?type ?): converted_type = type;
  if (!compiler.sym.is_named_value_type(converted_type, "List"))
    compiler.report_error(
      <type>, "destructuring requires a List source", NULL,
      %(("source type" $source_type)));
  return %(code-value "bound" $converted ());
}

// Read one element from the issued List temporary.
static List _destructure_element(List temporary, int index) {
  String text = %"$index";
  return %(expr ("Var")
           (getindex (expr ("List") (ident $temporary))
                     (literal (int) $text)));
}

macro open Expression $destructure_write(
    Expr $target, Expr $value) => $target = $value;

macro open Statement $destructure_targets(
    Type $type, DeclaratorRow $rows...) {
  $type $rows...;
}

macro open Statement $destructure_typed_target(
    Type $type, DeclaratorRow $row, Expr $value) {
  $type $row = $value;
}

macro open Statement $destructure_sequence(Statement $items...) {
  $items...
}

static List _destructure_expression_statement(
  Compiler compiler, List expression) {
  Macro shape = $expression_statement;
  return compiler.rebuild_statement(shape(expression)).cadr();
}

// Preserve typed targets, including the indirection of mutable lambda
// captures, while constructing their writes in source order.
static List _destructure_assignments(
  Compiler compiler, List targets, List temporary) {
  int index = 0;
  Macro shape = $destructure_write;
  return targets.map(
    %!(List target) using &index => {
      match (target)
        case %(expr ?type ?): {
          List value = _destructure_element(temporary, index++);
          List expression = compiler.rebuild_expression(
            type, shape(target, value));
          return _destructure_expression_statement(compiler, expression);
        }
    });
}

macro open Statement $destructure_statement(Name $temporary, Expr $source,
    Statement $assignments...) {
  {
    List $temporary = $source;
    $assignments...
  }
}

macro open Statement $destructure_declarations(
    Name $temporary, Expr $source, Statement $assignments...) {
  List $temporary = $source;
  $assignments...
}

// A discarded destructuring result retains its own block scope.
static List _destructure_statement(Compiler compiler, List ast) {
  match (ast) {
    case %(stmnt (expr ?
             (dstrasgn (targets *targets)
                       (!set ?source (expr ?source_type ?))))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      Macro shape = $destructure_statement;
      return compiler.bind_syntax(
        shape(
          temporary, _destructure_source(compiler, source, source_type),
          _destructure_assignments(compiler, targets, temporary)),
        AST_BLOCK, compiler.return_type);
    }
  }
  return ast;
}

// Keep parser-bound targets out of rebinding so their names retain scope and
// emitted identity; bind only the new temporary and unbound writes.
static List _named_destructure(
  Compiler compiler, Type type, List targets, List source,
  Type source_type) {
  List temporary = compiler.sym.introduce(
    compiler.fresh_name("destructure"));
  Array declarations = [], expressions = [];
  foreach (List ident, targets) {
    declarations.push(%(bind $ident ()));
    expressions.push(%(expr $type (ident $ident)));
  }
  Macro target_shape = $destructure_targets;
  List target_decl = compiler.rebuild_statement(
    target_shape(type, declarations.list_free())).cadr();
  List assignments = _destructure_assignments(
    compiler, expressions.list_free(), temporary);
  Macro shape = $destructure_declarations;
  List tail = compiler.bind_syntax(
    shape(
      temporary, _destructure_source(compiler, source, source_type),
      assignments),
    AST_BLOCK, compiler.return_type);
  Macro sequence = $destructure_sequence;
  return compiler.rebuild_statement(
    sequence(cons(target_decl, tail.cdr())));
}

static List _typed_destructure(
  Compiler compiler, List parameters, List source, Type source_type) {
  List temporary = compiler.sym.introduce(
    compiler.fresh_name("destructure"));
  Array declarations = [];
  int index = 0;
  Macro target_shape = $destructure_typed_target;
  foreach (List parameter, parameters) match (parameter) {
    case %(param ?type ?bind): {
      List value = _destructure_element(temporary, index++);
      declarations.push(
        compiler.rebuild_statement(target_shape(type, bind, value)).cadr());
    }
  }
  Macro shape = $destructure_declarations;
  List temp = compiler.bind_syntax(
    shape(temporary, _destructure_source(compiler, source, source_type)),
    AST_BLOCK, compiler.return_type);
  Macro sequence = $destructure_sequence;
  return compiler.rebuild_statement(
    sequence(cons(temp, declarations.list_free())));
}

static List _destructure_declaration(Compiler compiler, List ast) {
  match (ast) {
    case %(dstrdecl ?type (targets *targets)
                    (!set ?source (expr ?source_type ?))):
      return _named_destructure(
        compiler, type, targets, source, source_type);
    case %(dstrdecl (params *parameters)
                    (!set ?source (expr ?source_type ?))):
      return _typed_destructure(
        compiler, parameters, source, source_type);
  }
  return ast;
}

/* Cell rewriting needs declaration sites, so lower destructuring
   with its existing transformation before analyzing a function body. */
static List _lower_lambda_destructuring(Compiler compiler, List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(dstrdecl *):
      return _destructure_declaration(compiler, ast);
  }
  // The recursion below then only descends into subtrees it will rewrite.
  if (!ast_contains_head(ast, <dstrdecl>)) return ast;
  return Ast.rewrite_children(
    ast, %!(List child) => _lower_lambda_destructuring(compiler, child));
}

static List _value_declaration(Type type, List binding, List value) {
  (List base, List mods) = type.declaration_parts();
  return value
    ? %(declare $base (bindings (op = (bind $binding $mods) $value)))
    : %(declare $base (bindings (bind $binding $mods)));
}

/* Keep the source's exact static type and value in one result temporary,
   then convert it to List once for the left-to-right assignments. */
static List _destructure_value(Compiler compiler, List ast) {
  match (ast) {
    case %(dstrasgn (targets *targets)
                    (!set ?source (expr ?type ?))): {
      List result = compiler.sym.introduce(
        compiler.fresh_name("destructure_result"));
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      List result_expr = %(expr $type (ident $result));
      List converted = _destructure_source(
        compiler, result_expr, type);
      List assignments = _destructure_assignments(
        compiler, targets, temporary);
      Macro shape = macro Statement(
        Type $type, Name $result, Expr $source, Name $temporary,
        Expr $converted) {
        $type $result = $source;
        List $temporary = $converted;
      };
      List bindings = compiler.bind_syntax(
        shape(type, result, %(code-value "bound" $source ()),
          temporary, converted),
        AST_BLOCK, compiler.return_type);
      // x2c has no source spelling for this native statement expression.
      return %(parens (block @{bindings.cdr()} @assignments
                             ${_destructure_expression_statement(
                               compiler, result_expr)}));
    }
  }
  return ast;
}
static List _return(Compiler compiler, List ast) {
  Macro returned = $return_value;
  match (ast)
    case returned(?expression):
      return source_return_content(%(${compiler.convert_expression(
        expression, source_return_type(ast))}));
  return ast;
}

// (match expr ((pattern body) ...))
static List _match_cases(Compiler compiler, List ast) {
  List (expr, cases) = ast.cdr();
  expr = compiler.convert_expression(expr, %("List"));
  Array values = [];
  foreach (List rec, cases) {
    if (rec.car() == <preproc>) values.push(rec);
    else
      values.push(%(${compiler.match_pattern_binders(rec.car(), NULL)} @rec));
  }
  List result = values.list_free();
  return %(matchcases $expr $result);
}

// operator passes

static List _comparison(
  Compiler compiler, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  if (!compiler.sym.is_var_type(lhs_type) &&
      !compiler.sym.is_var_type(rhs_type)) {
    if (op == <===>) return %(op == $lhs $rhs);
    if (op == <!==>) return %(op != $lhs $rhs);
    return ast;
  }
  lhs = compiler.convert_expression(lhs, %("Var"));
  rhs = compiler.convert_expression(rhs, %("Var"));
  switch (op) {
    case <==>:  return %(call "Var_equal" (args $lhs $rhs));
    case <!=>:  return %(expr (int)
                          (op ! (call "Var_equal" (args $lhs $rhs))));
    case <===>: return %(call "Var_same" (args $lhs $rhs));
    case <!==>: return %(expr (int)
                          (op ! (call "Var_same" (args $lhs $rhs))));
  }
  List call = %(call "Var_compare" (args $lhs $rhs));
  List zero = %(expr (int) (literal (int) "0"));
  return %(expr (int) (op $op $call $zero));
}

/* The dynamic binary operators are exactly those with a compound assignment
   spelling; `Var_binary` and `Var_update` accept the same operators. */
static int _dynamic_binary_operator(Symbol op) =>
  op.compound_assignment() != 0;

static int _raw_string_type(Type type) {
  type = type ? type.canonicalize() : NULL;
  return type && type.match(%((!or (dim *) (!quote *)) char));
}

static int _string_operand(Compiler compiler, Type type) =>
  compiler.sym.is_string_type(type)
      || _raw_string_type(type);

// Identify only the built-in helper family. Protocol resolution still
// handles every bracket form.
static Symbol _indexed_builtin_helper(Compiler compiler, Type type) {
  if (compiler.sym.is_array_type(type)) return <array>;
  if (compiler.sym.is_map_type(type)) return <map>;
  return 0;
}

// Helper-backed indexes bypass getindex lowering.
static int _indexed_parts(
  Compiler compiler, List expr, Symbol &owner, List &base, List &selector) {
  Type base_type;
  if (!_resolved_index_parts(expr, base, base_type, selector)) return 0;
  owner = _indexed_builtin_helper(compiler, base_type);
  return 1;
}

static void _convert_indexed_parts(
  Compiler compiler, Symbol owner, List &base, List &selector) {
  if (owner == <array>) {
    base = compiler.convert_expression(base, %("Array"));
    selector = compiler.convert_expression(selector, %(int));
  }
  else {
    base = compiler.convert_expression(base, %("Map"));
    selector = compiler.convert_expression(selector, %("Var"));
  }
}

static int _indexed_rhs_allowed(Compiler compiler, Symbol op, List rhs) {
  Type type = rhs.cadr();
  if (compiler.sym.is_var_type(type)) return 1;
  if (compiler.sym.resolve_numeric_type(type)) return 1;
  return op == <+> && _string_operand(compiler, type);
}

static List _indexed_call_expr(
  Compiler compiler, List resolved, List arguments) {
  (List binding, Type signature) = resolved;
  Macro called = $called;
  List callee = %(expr $signature (ident $binding));
  return compiler.rebuild_expression(
    signature.cdr(), called(callee, arguments));
}

// Preserve x2c source order across C's unspecified call-argument order.
static List _sequenced_protocol_call(
  Compiler compiler, List resolved, List arguments) {
  Type signature = resolved.cadr();
  List parameters = signature.car().list().cadr();
  Array converted = [];
  for (List actual = arguments, expected = parameters;
       actual && expected;
       actual = actual.cdr(), expected = expected.cdr()) {
    List value = compiler.convert_expression(actual.car(), expected.car());
    /* A C macro such as raylib's WHITE expands to an expression x2c has no
       type for, and the sequencing temporary still has to declare one. The
       parameter's type is the type the value is about to be passed as. */
    (Var expr_tag, Type value_type, Var body) = value;
    (void) expr_tag;
    if (!value_type) value = %(expr ${expected.car()} $body);
    converted.push(value);
  }
  Array declarations = [], arguments_out = [];
  foreach (List value, converted) {
    Type type = value.cadr();
    List temporary = compiler.sym.introduce(
      compiler.fresh_name("protocol_arg"));
    declarations.push(_value_declaration(type, temporary, value));
    arguments_out.push(%(expr $type (ident $temporary)));
  }
  converted.free();
  List call = _indexed_call_expr(
    compiler, resolved, arguments_out.list_free());
  return %(parens (block @{declarations.list_free()} (stmnt $call)));
}

/* Compound, prefix and postfix brackets share the same resolved element,
   protocol lookup, and built-in conversion. A missing rhs means postfix. */
static List _indexed_resolution(
  Compiler c, Type base_type, Symbol owner, Symbol op, List rhs) {
  int postfix = !rhs;
  List resolved = c.resolve_protocol_member(
    base_type, postfix ? "postfixindex" : "updateindex");
  if (!resolved) {
    String type = base_type.repr();
    String message = postfix
      ? %"type $type does not support indexed increment or decrement"
      : %"type $type does not support indexed compound assignment";
    c.report_error(<xform>, message, NULL, NULL);
  }
  if (owner && !postfix && !_indexed_rhs_allowed(c, op, rhs)) {
    (Var rhs_tag, Type rhs_type) = rhs;
    (void) rhs_tag;
    String details = %"right type: ${rhs_type.repr()}";
    String message = op == <+>
      ? "indexed += requires a numeric, Var, or String operand"
      : "indexed compound assignment requires a numeric or Var operand";
    c.report_error(<xform>, message, NULL, %($details));
  }
  return resolved;
}

static List _indexed_change(
  Compiler c, List target, Symbol op, List rhs) {
  Symbol owner, List base, selector;
  if (!_indexed_parts(c, target, owner, base, selector)) return NULL;
  int postfix = !rhs;
  (Var base_tag, Type base_type) = base;
  (void) base_tag;
  List resolved = _indexed_resolution(c, base_type, owner, op, rhs);

  List operation = _symbol_expression(op);
  List arguments = postfix
    ? %($base $selector $operation)
    : %($base $selector $operation $rhs);
  if (!owner) return _sequenced_protocol_call(c, resolved, arguments);
  _convert_indexed_parts(c, owner, base, selector);
  String helper = owner == <array>
    ? (postfix ? "Array_postfixindex" : "Array_updateindex")
    : (postfix ? "Map_postfixindex" : "Map_updateindex");
  if (!postfix) rhs = c.convert_expression(rhs, %("Var"));
  arguments = postfix
    ? %($base $selector $operation)
    : %($base $selector $operation $rhs);
  return %(call $helper (args @arguments));
}

static List _dynamic_binary(
  Compiler c, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  int rhs_is_var = c.sym.is_var_type(rhs_type);
  if (!lhs_is_var && !rhs_is_var) return ast;
  int string_plus = op == <+>
                 && (lhs_is_var || _string_operand(c, lhs_type))
                 && (rhs_is_var || _string_operand(c, rhs_type));
  if (!string_plus &&
      ((!lhs_is_var && !c.sym.resolve_numeric_type(lhs_type)) ||
       (!rhs_is_var && !c.sym.resolve_numeric_type(rhs_type)))) {
    String left_type = lhs_type.repr(), right_type = rhs_type.repr();
    String details =
      %"operator: $op left type: $left_type right type: $right_type";
    c.report_error(
      <xform>, "dynamic numeric operators require numeric operands",
      NULL, %($details));
  }
  lhs = c.convert_expression(lhs, %("Var"));
  rhs = c.convert_expression(rhs, %("Var"));
  return %(call "Var_binary" (args $lhs ${_symbol_expression(op)} $rhs));
}

/* One protocol-member update. `x += y`, `++x`, and `x++` all resolve the
   operator's member on the receiver type, convert the right operand to the
   member's declared parameter, and ask for the update helper. A null `rhs`
   is a postfix update, which reads the receiver before the helper runs.
   The converted operand stays in `*rhs` when no helper exists, so a caller
   continues into the dynamic path with the operand it already built. */
static List _update_call(
  List target, List operator, List value, String helper) {
  Type type = target.cadr();
  List address = %(expr ${type.reference()} (op & (parens $target)));
  return value ? %(call $helper (args $address $operator $value))
               : %(call $helper (args $address $operator));
}

static List _protocol_update(
  Compiler c, Type type, Symbol op, List arg, List &?rhs, Symbol spelled) {
  Symbol member = c.operator_member(op);
  if (!member) return NULL;
  String member_name = member;
  List resolved = c.resolve_protocol_member(type, member_name);
  if (!resolved) return NULL;
  if (rhs) {
    List converted = NULL;
    match (resolved)
      case %(? ((func (? ?parameter *)) ?)):
        converted = c.convert_expression(rhs, parameter);
    if (!converted) return NULL;
    rhs = converted;
  }
  String helper = c.protocol_update_helper(type, member_name, !rhs);
  if (!helper) return NULL;
  List spell = _symbol_expression(spelled);
  if (!rhs) return _update_call(arg, spell, NULL, helper);
  List value = rhs;
  return _update_call(arg, spell, value, helper);
}

static void _dynamic_rhs(
  Compiler c, Symbol op, Type lhs_type, Type rhs_type, int rhs_is_var) {
  if (lhs_type.is_bitfield())
    c.report_error(
      <xform>, "dynamic compound assignment cannot target a bitfield",
      NULL, NULL);
  int rhs_allowed = rhs_is_var || c.sym.resolve_numeric_type(rhs_type) ||
                    (op == <+> && _string_operand(c, rhs_type));
  if (!rhs_allowed) {
    String details = %"right type: ${rhs_type.repr()}";
    c.report_error(
      <xform>,
      op == <+>
        ? "dynamic += requires a numeric, Var, or String operand"
        : "dynamic compound assignment requires a numeric or Var operand",
      NULL, %($details));
  }
}

static String _dynamic_helper(Compiler c, Type lhs_type) {
  Type scalar = c.sym.resolve_numeric_type(lhs_type);
  if (scalar && scalar.is_enum())
    c.report_error(
      <xform>, "dynamic compound assignment cannot target an enum",
      NULL, NULL);
  String helper = scalar ? scalar.var_numeric_update_helper() : NULL;
  if (!helper) {
    String details = %"left type: ${lhs_type.repr()}";
    c.report_error(
      <xform>, "dynamic compound assignment requires a numeric lvalue",
      NULL, %($details));
  }
  return helper;
}

static List _dynamic_compound(
  Compiler c, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  int rhs_is_var = c.sym.is_var_type(rhs_type);
  if (_indexed_builtin_helper(c, lhs_type)) {
    String type = lhs_type.repr();
    c.report_error(
      <xform>, %"container type $type does not support compound assignment",
      NULL, %("update an indexed element instead"));
  }
  /* Without this rejection a nonmatching String compound falls through to
     native pointer arithmetic on an interned String. Concatenation itself
     lowers through the protocol member below like any adopter, resolved
     against canonical String because Var(String) adoption is exact while
     String typedefs still spell the same lvalue. */
  Type member_type = lhs_type;
  if (c.sym.is_string_type(lhs_type)) {
    if (op != <+> || !_string_operand(c, rhs_type))
      c.report_error(
        <xform>, "String compound assignment supports only String +=",
        NULL, NULL);
    member_type = %("String");
  }
  if (!lhs_is_var) {
    List updated = _protocol_update(c, member_type, op, lhs, rhs, op);
    if (updated) return updated;
    (rhs_tag, rhs_type) = rhs;
  }
  if (!lhs_is_var && !rhs_is_var) return ast;
  _dynamic_rhs(c, op, lhs_type, rhs_type, rhs_is_var);

  String helper = "x2c_var_update_volatile";
  if (!lhs_is_var) helper = _dynamic_helper(c, lhs_type);

  rhs = c.convert_expression(rhs, %("Var"));
  return _update_call(lhs, _symbol_expression(op), rhs, helper);
}

static List _binary_operator(
  Compiler c, List ast, Symbol operator, List lhs, List rhs) {
  Symbol compound = Symbol.compound_operator(operator);
  if (compound) {
    List indexed = _indexed_change(c, lhs, compound, rhs);
    if (indexed) return indexed;
    return _dynamic_compound(c, ast, compound, lhs, rhs);
  }
  switch (operator) {
    case <=>: return _assignment(c, operator, lhs, rhs);
    case <==>:  case <!=>:  case <===>: case <!==>:
    case <"<">: case <"<=">: case <">">:  case <">=">:
      return _comparison(c, ast, operator, lhs, rhs);
  }
  if (_dynamic_binary_operator(operator))
    return _dynamic_binary(c, ast, operator, lhs, rhs);
  return ast;
}

static List _unary_change(
  Compiler c, List ast, Symbol operator, List argument, Type type) {
  Symbol binary = operator == <++> ? <+> : <->;
  List one = %(expr (int) (literal (int) "1"));
  List indexed = _indexed_change(c, argument, binary, one);
  if (indexed) return indexed;
  if (!c.sym.is_var_type(type)) {
    List updated = _protocol_update(
      c, type, binary, argument, one, binary);
    if (updated) return updated;
  }
  if (c.sym.is_var_type(type)) {
    one = c.convert_expression(one, %("Var"));
    return _update_call(
      argument, _symbol_expression(binary), one,
      "x2c_var_update_volatile");
  }
  return ast;
}

static List _operator(Compiler c, List ast) {
  List truthy = _truthy(c, ast);
  if (truthy != ast) return truthy;
  match (ast) {
    case $source_operator_content(%(?operator
             (!set ?lhs (expr ? ?)) (!set ?rhs (expr ? ?)))):
      return _binary_operator(c, ast, operator, lhs, rhs);
    case $source_operator_content(%(
             (!set ?operator (!or + - ~))
             (!set ?argument (expr ?argument_type ?)))): {
      if (c.sym.is_var_type(argument_type))
        c.report_error(
          <xform>, "dynamic unary numeric operators are not supported",
          NULL, %("use Var.binary with an explicit numeric operand"));
      return ast;
    }
    case $source_operator_content(%(
             (!set ?operator (!or ++ --))
             (!set ?argument (expr ?argument_type ?)))):
      return _unary_change(c, ast, operator, argument, argument_type);
  }
  return ast;
}

static List _postfix(Compiler compiler, List ast) {
  match (ast)
    case $source_postfix_content(%(?operator
           (!set ?argument (expr ?argument_type ?)))): {
      Symbol op = operator, List arg = argument;
      Type type = argument_type;
      List indexed = _indexed_change(compiler, arg, op, NULL);
      if (indexed) return indexed;
      if (!compiler.sym.is_var_type(type)) {
        Symbol binary = op == <++> ? <+> : <->;
        List updated =
          _protocol_update(compiler, type, binary, arg, NULL, op);
        if (updated) return updated;
      }
      if (compiler.sym.is_var_type(type)) {
        List address = %(expr (* "Var") (op & (parens $arg)));
        return %(call "x2c_var_postfix_volatile"
                      (args $address ${_symbol_expression(op)}));
      }
      return ast;
    }
  return ast;
}

static List _truthy(Compiler compiler, List ast) {
  Macro if_then = $if_then, if_else = $if_else;
  Macro while_loop = $while_loop, do_loop = $do_loop;
  Macro for_loop = $for_loop;
  match (ast) {
    case if_then(?condition, ?yes):
      return compiler.rebuild_statement(
        if_then(_truthy_expression(compiler, condition), yes)).cadr();
    case if_else(?condition, ?yes, ?no):
      return compiler.rebuild_statement(
        if_else(_truthy_expression(compiler, condition), yes, no)).cadr();
    case while_loop(?condition, ?body):
      return compiler.rebuild_statement(
        while_loop(_truthy_expression(compiler, condition), body)).cadr();
    case do_loop(?body, ?condition):
      return compiler.rebuild_statement(
        do_loop(body, _truthy_expression(compiler, condition))).cadr();
    case for_loop(?init, ?condition, ?increment, ?body):
      return compiler.rebuild_statement(
        for_loop(
          init, _truthy_expression(compiler, condition), increment,
          body)).cadr();
    case $source_operator_content(%(
           (!set ?operator (!or && ||)) ?lhs ?rhs)): {
      List left = _truthy_expression(compiler, lhs);
      List right = _truthy_expression(compiler, rhs);
      return source_operator_content(%($operator $left $right));
    }
    case $source_operator_content(%(? ?condition ?ontrue ?onfalse)):
      return source_operator_content(%(
        ? ${_truthy_expression(compiler, condition)} $ontrue $onfalse));
    case $source_operator_content(%(! ?condition)):
      return source_operator_content(%(
        ! ${_truthy_expression(compiler, condition)}));
  }
  return ast;
}

// collection passes

/* The converted Var values enter the native counted constructors unchanged.
   Empty literals need only allocate their container. */
macro open Expression $var_array(Expr $count, Expr $values...) =>
  Array.update_n(Array.new(), $count, $values...);

macro open Expression $empty_var_array() => Array.new();

macro open Expression $var_map(Expr $count, Expr $entries...) =>
  Map.update_n(Map.new(), $count, $entries...);

macro open Expression $empty_var_map() => Map.new();

/* The containing typed expression already fixes the result type. */
static List _var_literal_content(Compiler compiler, List application) {
  List bound = compiler.bind_syntax(application, AST_EXPRESSION, NULL);
  match (bound) case %(expr ? ?content): return content;
  __builtin_unreachable();
}

static List _var_array_literal(Compiler compiler, List values) {
  if (!values) {
    Macro empty = $empty_var_array;
    return _var_literal_content(compiler, empty());
  }
  Macro shape = $var_array;
  return _var_literal_content(
    compiler, shape(x2c_literal_int(values.len()), values));
}

static List _var_map_literal(Compiler compiler, List entries) {
  if (!entries) {
    Macro empty = $empty_var_map;
    return _var_literal_content(compiler, empty());
  }
  Macro shape = $var_map;
  return _var_literal_content(
    compiler, shape(x2c_literal_int(entries.len() / 2), entries));
}

// Normalize cons nodes so head and tail carry expected runtime types.
static List _cons(Compiler compiler, List ast) {
  List (head, tail) = ast.cdr();
  head = compiler.convert_expression(head, %("Var"));
  tail = compiler.convert_expression(tail, %("List"));
  return %(cons $head $tail);
}

/* A literal element is a `Var`, and an empty brace there is an empty Map. */
static List _literal_element(Compiler c, List element) {
  if (element.match(%(expr ? (composite (commas)))))
    element = %(expr ("Map") (map));
  return c.convert_expression(element, %("Var"));
}

/** Converts an array literal to source-ordered Var arguments for its
    counted constructor. */
List transform_array_literal(Compiler compiler, List ast) {
  Array values = [];
  foreach (List elem, ast.cdr())
    values.push(_literal_element(compiler, elem));
  return _var_array_literal(compiler, values.list_free());
}

/** Converts a map literal to alternating Var key/value arguments for its
    counted constructor. */
List transform_map_literal(Compiler compiler, List ast) {
  List elems = ast.cdr(), Array values = [];
  foreach (List entry, elems) {
    List (key, val) = entry.cdr();
    values.push(_literal_element(compiler, key));
    values.push(_literal_element(compiler, val));
  }
  return _var_map_literal(compiler, values.list_free());
}

static List _append(Compiler compiler, List ast) {
  List (lhs, rhs) = ast.cdr();
  if (compiler.sym.is_var_type(lhs.cadr()))
    lhs = %(expr ("List") (call "Var_list" (args $lhs)));
  else lhs = compiler.convert_expression(lhs, %("List"));
  return %(append $lhs $rhs);
}

// string passes

static List _process_raw_segment(Compiler compiler, List seg) {
  String raw = seg.cadr(), literal = %"\"${raw.escape()}\"";
  List constructor = compiler.sym.reference(%("String_new"), NULL);
  return %(expr ("String") (call
           (expr ((func ((* char))) "String") (ident $constructor))
           (args (expr (* char) (literal (* char) $literal)))));
}

static List _build_cons_list(List list) {
  if (!list) return %(nil);
  List head = list.car(), tail = _build_cons_list(list.cdr());
  return %(cons $head $tail);
}

static List _segment_value(Compiler compiler, List seg) {
  Symbol kind = seg.car();
  switch (kind) {
    case <segraw>: seg = _process_raw_segment(compiler, seg); break;
    case <segvar>:
    case <segexp>: seg = compiler.convert_segment_to_string(seg.cadr()); break;
    case <cache>: seg = %(expr ("String") $seg); break;
  }
  return compiler.convert_expression(seg, %("Var"));
}

static List _join_segments(
  Compiler compiler, List segments, int segment_count) {
  // Keep nested cons expressions below host-C bracket-depth limits.
  if (segment_count <= 128) {
    segments = _build_cons_list(segments);
    return %("String_join(NULL, " (expr ("List") $segments) ")");
  }
  String count = %"${segment_count}U";
  Type signature = NULL;
  List binding = compiler.sym.reference(%("List_list_n"), signature);
  List list = %(expr ("List")
    (call (expr $signature (ident $binding))
          (args (expr (unsigned) (literal (unsigned) $count)) @segments)));
  return %("String_join(NULL, " $list ")");
}

static List _string_segments(Compiler compiler, List ast) {
  /* A lone constant segment is already the whole string. Reuse the parsed
     literal's cache slot instead of joining a one-element List at runtime.
     Macro-generated literals arrive in this shape. Raise details are
     excluded: their cache slots would fill inside _file_init_ constructors,
     where re-entrant string-pool bootstrap can hand back NULL Strings. */
  match (ast) {
    case $source_string_content(
        %((segexp (expr ("String") (literal ("String") ?text))))):
      if (!compiler.runtime_literals)
        return compiler.cache(
          %(string (expr ("String") (literal ("String") $text))));
  }
  Array values = [];
  foreach (List seg, ast.cdr()) values.push(_segment_value(compiler, seg));
  int segment_count = values.len();
  List segments = values.list_free();
  return _join_segments(compiler, segments, segment_count);
}

// Look through the `(at N ...)` anchors a node arrived wrapped in.
// Every block statement carries one so that a transform-phase diagnostic
// can name its line. A pass that dispatches on a statement tag has to see
// the statement, not the anchor.
static List _without_origin(List ast) {
  while (ast) {
    match (ast) {
      case %(at ? ?inner): ast = inner;
      default: return ast;
    }
  }
  return ast;
}

// Put a replacement statement back under the anchors of the statement it
// replaces, so a rewrite does not lose the node's source position.
static List _rewrap_origin(List original, List replacement) {
  match (original)
    case %(at ?origin ?inner):
      return %(at $origin ${_rewrap_origin(inner, replacement)});
  return replacement;
}

static int _raise_detail_type_allowed(Compiler compiler, Type type) {
  if (!type) return 0;
  with compiler.sym {
    if (_.is_var_type(type) ||
        _.is_string_type(type) ||
        _.is_named_value_type(type, "List") ||
        _.is_named_value_type(type, "Symbol") ||
        _.is_named_value_type(type, "Atom"))
      return 1;
    return !!_.resolve_numeric_type(type);
  }
}

static Type _raise_nested_invalid_type(Compiler compiler, Var node) {
  if (node is not <list>) return NULL;
  List ast = node;
  match (ast)
    case %(expr ?expr_type ?value): {
      Type type = expr_type;
      if (!_raise_detail_type_allowed(compiler, type)) return type;
      if (compiler.sym.is_var_type(type)) {
        List payload = value;
        match (payload)
          case %(call ?(String callee) ?arguments):
            if (callee.endswith("_var"))
              return _raise_nested_invalid_type(compiler, arguments);
        return NULL;
      }
      if (!compiler.sym.is_named_value_type(type, "List")) return NULL;
      return _raise_nested_invalid_type(compiler, value);
    }
  foreach (Var child, ast) {
    Type invalid = _raise_nested_invalid_type(compiler, child);
    if (invalid) return invalid;
  }
  return NULL;
}

static List _raise(
  Compiler compiler, List ast, Var cause, List arguments) {
  Array values = [], int index = 0;
  List code = compiler.convert_expression(cause, %("Symbol"));
  int changed = code != cause;
  foreach (List value, arguments) {
    Type invalid = NULL;
    if (index & 1) value = compiler.promote_string_literal(value);
    if (index & 1)
      match (value)
        case %(expr ?value_type ?content): {
          Type type = value_type;
          if (!_raise_detail_type_allowed(compiler, type)) invalid = type;
          else if (compiler.sym.is_named_value_type(type, "List"))
            invalid = _raise_nested_invalid_type(compiler, content);
        }
    if (invalid) {
      String message = %"raise detail type ${invalid.repr()} is not immutable";
      List location = compiler.origin_location(compiler.origin);
      compiler.diagnostics.report(
        <type>, message, location,
        %("use a numeric value, enum, Symbol, Atom, String, List, or Var"));
      // Null replaces the reported detail, so a later pass never sees it.
      value = %(expr ("Var") (call "Var_null" (args)));
    }
    List converted = compiler.convert_expression(value, %("Var"));
    if (converted != value) changed = 1;
    values.push(converted);
    index++;
  }
  if (!changed) {
    values.free();
    return ast;
  }
  List converted = values.list_free();
  return %(raise $code (args @converted));
}

// Lower bracket reads into helper calls with method-call conversions.
static List _nominal_getindex(Compiler compiler, Type type) {
  if (!type.is_typedef_name()) return NULL;
  if (compiler.sym.is_array_type(type) ||
      compiler.sym.is_map_type(type))
    return NULL;
  match (type)
    case %(?(String nominal)): {
      String source = %"${nominal}_getindex";
      Type signature = compiler.sym.get(%($source));
      match (signature)
        case %((func ($type ?)) ?):
          return %(${compiler.sym.reference(%($source), NULL)}
                   $signature);
    }
  return NULL;
}

static List _cast(Compiler compiler, List ast) {
  match (ast)
    case $source_cast_content(
        %((!set ?declarator (decl *parts))
          (!set ?expression (expr ?source_type ?)))): {
    List declaration = %(declare @parts);
    Type type = declaration.type_from_ast();
    List operand = expression;
    if (operand.match(%(expr ? (composite *)))) {
      Type native = type;
      match (declaration)
        case %(declare ?base (bindings (bind ? ?mods))):
          native = mods.list().append(base);
      return compiler.convert_compound_literal(operand, type, native);
    }
    int source_var = compiler.sym.is_var_type(source_type);
    int target_var = compiler.sym.is_var_type(type);
    int unresolved = 0;
    match (expression)
      case %(expr () ${$source_identifier_content(%(?name))}):
        unresolved = 1;
    int target_func = source_type &&
      compiler.sym.resolve_key(type) === compiler.sym.resolve_key(%("Func"));
    if (type !== %(void) &&
        (source_var || target_func ||
         (target_var && (source_type || unresolved))))
      return compiler.convert_expression(expression, type);
    return %(cast $type $expression);
  }
  match (ast)
    case $source_cast_content(
        %(?target (!set ?value (expr ? (composite *))))):
      return compiler.convert_compound_literal(value, target, target);
  return ast;
}

// transform driver

static List _match_records(Compiler compiler, List records) {
  Array transformed = [];
  foreach (List record, records)
    match (record) {
      case %(preproc ?): transformed.push(record);
      case %(*prefix ?body):
        transformed.push(%(@prefix ${compiler.normalize(body)}));
    }
  return transformed.list_free();
}

/* Only top-level and block sequences absorb `(seq ...)` replacements.
   Children transform left to right, then reverse assembly preserves source
   order while allocating generated splice origins from right to left. */
static Ast _sequence(Compiler compiler, Ast ast) {
  Array transformed = $auto([]);
  foreach (List value, ast) {
    List source = _without_origin(value);
    List lowered = source.match(%(defer ?))
      ? value : compiler.normalize(value);
    if (!compiler.fn_name) lowered = _cleanup_unit(compiler, lowered);
    transformed.push(lowered);
  }
  Ast tail = NULL;
  for (int i = (int) transformed.len() - 1; i >= 0; i--) {
    Ast node = transformed[i];
    List payload = _without_origin(node);
    match (node)
      case %(at ?parent ?):
        match (payload)
          case %(seq *items): {
            Array anchored = [];
            foreach (List item, items) {
              compiler.origins.push(%(generated $parent splice));
              int generated = compiler.origins.len();
              anchored.push(%(at $generated $item));
            }
            tail = anchored.list_free().append(tail);
            continue;
          }
    match (node)
      case %(seq *items): {
        tail = items.append(tail);
        continue;
      }
    tail = cons(node, tail);
  }
  return tail;
}

static Ast _children(Compiler compiler, Ast ast) {
  List child;
  $ast.rewrite_children(ast, child, compiler.normalize(child));
}

/* Normalize synthesized sequences before their containing block absorbs
   pending defer markers. Matches retain their specialized record driver. */
static Ast _finish(Compiler compiler, Ast ast) {
  match (ast) {
    case %(seq *items):
      return %(seq @{_sequence(compiler, items)});
    case %(matchcases ?subject ?records): {
      List new_subject = compiler.normalize(subject);
      List new_records = _match_records(compiler, records);
      return %(matchcases $new_subject $new_records);
    }
    case $source_block_content(%(*body)): {
      List lowered = _sequence(compiler, body);
      List deferred = _rewrite_defer_list(compiler, lowered);
      if (deferred != lowered) lowered = _sequence(compiler, deferred);
      return source_block_content(lowered);
    }
  }
  return _children(compiler, ast);
}

/* A left-leaning operator chain nests one (expr (op ...)) level per source
   term, so child-first transformation would recurse once per term. Walk down
   the spine while each level survives its operator rewrites unchanged,
   transform the deepest term, and rebuild upward. Entered only for chain
   heads, with expression rewrites already applied. */
static List _op_chain_first(List ast) {
  match (ast)
    case %(expr ? ?content):
      match (content)
        case $source_operator_content(%(? ?first *rest)):
          if (first is <list>) {
            List operand = first;
            match (operand)
              case %(expr ? ?inner):
                match (inner)
                  case $source_operator_content(%(*parts)):
                    return operand;
          }
  return NULL;
}

static Ast _op_chain(Compiler compiler, Ast ast) {
  Array levels = $auto([]);
  Array types = $auto([]);
  Ast rebuilt = NULL;
  for (;;) {
    List first = _op_chain_first(ast);
    if (!first) {
      rebuilt = _finish(compiler, ast);
      break;
    }
    Var type = ast.cadr();
    if (type is <list>) type = compiler.normalize(type);
    List opnode = ast.caddr();
    List rewritten = _operator(compiler, opnode);
    if (rewritten != opnode) {
      rebuilt = %(expr $type ${compiler.normalize(rewritten)});
      break;
    }
    types.push(type);
    levels.push(ast);
    ast = compiler.lower_typed_adapter_expr(first);
    ast = compiler.lower_lambda_expr(ast);
  }
  for (int i = (int) levels.len() - 1; i >= 0; i--)
    match (levels[i].caddr())
      case $source_operator_content(%(?operator ? *rest)): {
        Array parts = [];
        if (operator is <list>) parts.push(compiler.normalize(operator));
        else parts.push(operator);
        parts.push(rebuilt);
        foreach (Var operand, rest) {
          if (operand is <list>) parts.push(compiler.normalize(operand));
          else parts.push(operand);
        }
        rebuilt = source_operator_expression(types[i], parts.list_free());
      }
  return rebuilt;
}

/* Callers supply bound, typed canonical nodes, and transform helpers construct
   the normalized shapes consumed by the emitter. A helper rewrites only its
   current node: this dispatcher recurses into returned children, while
   _sequence alone splices `(seq ...)` results into a sequence. */
static Ast _function_node(
  Compiler c, List return_type, List declarator, List binding, List body) {
  String owner = binding_identity_spelling(binding);
  Var stored_owner;
  if (c.semantic_binding_facts().try_get(
    %(defer-ownr $binding), stored_owner))
    owner = stored_owner;
  String previous = c.fn_name;
  int previous_inline = c.inline_header;
  c.fn_name = owner;
  Type function_type = return_type;
  c.inline_header = function_type.is_inline() &&
                    !function_type.is_static();
  List new_return = c.normalize(return_type);
  List new_decl = c.normalize(declarator);
  List prepared_body = _lower_lambda_destructuring(c, body);
  prepared_body = c.prepare_lambda_cells(declarator, prepared_body);
  List new_body = c.normalize(prepared_body);
  List transformed = %(function $new_return $new_decl $new_body);
  c.fn_name = previous;
  c.inline_header = previous_inline;
  return transformed;
}

static Ast _getindex_node(
  Compiler c, List expression, Type type, List index) {
  List resolved = _nominal_getindex(c, type);
  if (!resolved) resolved = c.resolve_protocol_member(type, "getindex");
  if (!resolved)
    c.report_error(
      <xform>, %"type $type does not support bracket indexing", NULL, NULL);
  return c.normalize(
    _indexed_call_expr(c, resolved, %($expression $index)).caddr());
}

static Ast _setindex_node(
  Compiler c, List expression, Type type, List index, List value) {
  List resolved = c.resolve_protocol_member(type, "setindex");
  if (!resolved)
    c.report_error(
      <xform>, %"type $type does not support bracket assignment", NULL, NULL);
  if (!_indexed_builtin_helper(c, type))
    return c.normalize(
      _sequenced_protocol_call(c, resolved, %($expression $index $value)));
  return c.normalize(
    _indexed_call_expr(
      c, resolved, %($expression $index $value)).caddr());
}

static Ast _slice_node(
  Compiler c, List expression, Type type, List start, List stop, List step) {
  String nominal = NULL;
  match (type)
    case %(?(String name)): nominal = name;
  if (!nominal)
    c.report_error(
      <xform>, %"type $type does not support slicing", NULL, NULL);
  String fnname = %"${nominal}_getslice";
  if (!c.sym.get(%($fnname)))
    c.report_error(
      <xform>, %"type $type does not support slicing", NULL, %());
  String none = "-2147483648";
  start = start ? start : %(literal (int) $none);
  stop = stop ? stop : %(literal (int) $none);
  step = step ? step : %(literal (int) "1");
  return c.normalize(%(call "$fnname" (args $expression $start $stop $step)));
}

static Ast _defer_node(Compiler c, Ast ast) {
  match (ast)
    case %(defer ?finalizer):
      return _lower_defer_region(c, source_block_content(%()), finalizer);
  return ast;
}

static Ast _raise_node(Compiler c, Ast ast) {
  // Raise details intern at raise time, never in constructors.
  int old_runtime = c.runtime_literals;
  c.runtime_literals = 1;
  match (ast)
    case %(raise ?cause (args *arguments)):
      ast = _raise(c, ast, cause, arguments);
  ast = _children(c, ast);
  c.runtime_literals = old_runtime;
  return ast;
}

static Ast _block_node(Compiler c, Ast ast) {
  List statements = ast.cdr();
  List body = _rewrite_defer_list(c, statements);
  return body !== statements ? source_block_content(body) : ast;
}

static Ast _step(Compiler c, Ast ast) {
  if (!ast) return NULL;
  match (ast)
    case %(managed-init ?):
      c.report_error(
        <parse>,
        "managed initializer requires a complete block-local initializer",
        NULL, NULL);
  Var head = ast.car();
  if (head is not <symbol>) return _children(c, ast);
  match (ast) {
    case %(at ?origin ?inner): {
      int occurrence = origin;
      List transformed = NULL;
      $let(c.origin, occurrence) {
        transformed = c.normalize(inner);
      }
      if (transformed == inner) return ast;
      c.origins.push(%(generated $occurrence xform));
      int generated = c.origins.len();
      return %(at $generated $transformed);
    }
    case %(function ?return_type
           (!set ?declarator (bind ?binding ?)) ?body):
      return _function_node(c, return_type, declarator, binding, body);
    case %(getindex
           (!set ?expression (expr ?matched_type ?)) ?index):
      return _getindex_node(c, expression, matched_type, index);
    case %(setindex
           (!set ?expression (expr ?matched_type ?)) ?index ?value):
      return _setindex_node(c, expression, matched_type, index, value);
    case %(slice
           (!set ?expression
             (expr (!set ?matched_type (*)) ?))
           ?start ?stop ?step):
      return _slice_node(c, expression, matched_type, start, stop, step);
  }
  Symbol tag = head;
  Ast next = ast;
  switch (tag) {
    case <protocol>: case <adopt>: case <macrodef>: case <literal>:
      return ast;
    case <expr>: {
      Ast expression = c.lower_typed_adapter_expr(ast);
      expression = c.lower_lambda_expr(expression);
      if (_op_chain_first(expression)) return _op_chain(c, expression);
      if (expression != ast) return c.normalize(expression);
      return _finish(c, expression);
    }
    case <array>: case <varray>: next = transform_array_literal(c, ast); break;
    case <map>: case <vmap>: next = transform_map_literal(c, ast); break;
    case <cast>: next = _cast(c, ast); break;
    case <index>: next = _index(c, ast); break;
    case <cons>: next = _cons(c, ast); break;
    case <append>: next = _append(c, ast); break;
    case <var>: next = _to_var(c, ast.cadr()); break;
    case <segments>: next = _string_segments(c, ast); break;
    case <declare>: case <decl>: next = _declaration(c, ast); break;
    case <dstrdecl>: next = _destructure_declaration(c, ast); break;
    case <stmnt>: next = _destructure_statement(c, ast); break;
    case <dstrasgn>: next = _destructure_value(c, ast); break;
    case <match>: next = _match_cases(c, ast); break;
    case <defer>: next = _defer_node(c, ast); break;
    case <block>: next = _block_node(c, ast); break;
    case <return>: next = _return(c, ast); break;
    case <raise>: return _raise_node(c, ast);
    case <if>: case <while>: case <do>: case <for>:
      next = _truthy(c, ast); break;
    case <call>: next = _call(c, ast); break;
    case <op>: next = _operator(c, ast); break;
    case <postfix>: next = _postfix(c, ast); break;
  }
  if (next != ast) return c.normalize(next);
  return _finish(c, ast);
}

/** Normalizes one bound and typed node. Newly constructed syntax is
    normalized where it is produced; children enter the same operation, so
    completed units do not require another unit walk.
*/
Ast Compiler.normalize(Compiler c, Ast ast) {
  return _step(c, ast);
}

/** Lowers a bound and typed top-level AST to the normalized form consumed by
    emission. `compiler` must own the AST's bindings, origins, and conversion
    state. Current-node rewrites finish before child traversal; containing
    blocks absorb cleanup markers produced by declaration rewrites. Early
    declarations are lowered and appended after the input units. The call
    may add generated origins or diagnostics to `compiler`.
*/
List Compiler.transform(Compiler compiler, List ast) {
  /* Regions are read before lowering, while `$scope`, `$auto`, and the
     `defer` beside each region are still the forms the parser produced. */
  compiler.check_regions(ast);
  List newast = _sequence(compiler, ast);
  // Merge and lower synthesized lambda siblings.
  Array generated = [];
  while (compiler.early_decls.len()) {
    List items = compiler.early_decls;
    compiler.early_decls.clear();
    List lowered = _sequence(compiler, items);
    foreach (Var sibling, lowered) generated.push(sibling);
  }
  if (generated.len()) newast = newast.append(generated.list_free());
  return newast;
}

#endif
