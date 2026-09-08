/*  transform.x -- x2c AST transformation pipeline

    Lowers typed expressions, literals, and control flow into the AST forms
    consumed by C emission.

    Each pass transforms a typed AST and returns an immutable `List` tree.
    The driver repeats the passes until the tree stops changing, using
    structural identity to detect changes. The active Compiler reports errors.
*/

#pragma once

$(import "../lib/error-macros.xmacro")
#include "compiler.x"
#pragma private

$(import "../src/ast-rewrite.xmacro")

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
#include "lambda.x"

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

typedef struct PrintfFn {
  const char *name, int fmt_arg, first_arg, unresolved;
} PrintfFn;

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

static const PrintfFn printf_family_info[] = {
  { "printf",        0, 1, 1 },
  { "fprintf",       1, 2, 1 },
  { "sprintf",       1, 2, 1 },
  { "snprintf",      2, 3, 1 },
  { "String_printf", 0, 1, 0 },
  { "File_printf",   1, 2, 0 },
  { "Buffer_printf", 1, 2, 0 }
};

// Identify printf-family calls without claiming a resolved user function
// that happens to use a libc spelling.
static const PrintfFn *_printf_family(List callee) {
  match (callee)
    case %(expr ?type (ident ?binding)): {
      String name = binding_identity_spelling(binding);
      int count = sizeof(printf_family_info) / sizeof(printf_family_info[0]);
      for (int i = 0; i < count; i++) {
        const PrintfFn *info = &printf_family_info[i];
        if (!String.equal(name, (String) info->name)) continue;
        if (info->unresolved && type.list()) return NULL;
        return info;
      }
    }
  return NULL;
}

static int _iter_immediate_consumer(String name) =>
  name == %"Iter_try_next" || name == %"Iter_next" ||
         name == %"Iter_list" || name == %"Iter_array" ||
         name == %"Iter_reduce" ||
         name == %"Iter_foldl" || name == %"Iter_any" ||
         name == %"Iter_all" || name == %"Iter_find" ||
         name == %"Iter_count" || name == %"Iter_sum" ||
         name == %"Iter_product" || name == %"Iter_min" ||
         name == %"Iter_max";

// Recover a format known at compile time. Raw C spelling is retained so
// escaped percent bytes stay outside this first pass.
static String _printf_static_format(Compiler compiler, List expr, int *raw) {
  match (expr) {
    case %(expr (* char) (literal (* char) ?format)): {
      String spelling = format.str();
      int length = spelling ? spelling.len() : 0;
      if (length < 2 || spelling[0] != '"' || spelling[length - 1] != '"')
        return NULL;
      *raw = 1;
      return spelling;
    }
    case %(expr ("String") (cache ?id)): {
      List key = compiler.id_keys[id.integer()];
      match (key)
        case %(string (expr ("String") (literal ("String") ?format))): {
          *raw = 0;
          return format.str();
        }
      return NULL;
    }
  }
  return NULL;
}

static int _printf_has_var(Compiler compiler, List args, int first_value) {
  int index = 0;
  foreach (List arg, args) {
    if (index++ < first_value) continue;
    if (compiler.sym.is_var_type(arg.cadr())) return 1;
  }
  return 0;
}

static void _printf_error(Compiler compiler, String family, String message) {
  String note = %"printf-family call: %s".printf(family);
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
    %"cannot infer a native argument for Var at %%%c"
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

// Align static format conversions with variadic arguments and lower only
// Var crossings. The parser understands the standard output grammar far
// enough to preserve native arguments around the safe automatic subset.
static List _lower_printf_vars(Compiler c, List ast) {
  (List callee, List args_node) = ast.cdr();
  const PrintfFn *info = _printf_family(callee);
  if (!info) return ast;
  List args = args_node.cdr();
  if (!_printf_has_var(c, args, info->first_arg)) return ast;

  Array values = %[];
  foreach (Var arg, args) values.push(arg);
  String family = (String) info->name;
  if (info->fmt_arg >= values.len())
    _printf_error(c, family, "call has no format argument");
  List format_arg = values[info->fmt_arg], int raw = 0;
  String format = _printf_static_format(c, format_arg, &raw);
  if (!format)
    _printf_error(
      c, family,
      "Var arguments require a single static format literal");

  int cursor = raw ? 1 : 0, end = raw ? format.len() - 1 : format.len();
  int value_index = info->first_arg;
  while (cursor < end) {
    if (raw && format[cursor] == '\\') {
      cursor += cursor + 1 < end ? 2 : 1;
      continue;
    }
    if (format[cursor++] != '%') continue;
    if (cursor >= end)
      _printf_error(c, family, "incomplete format conversion");
    if (format[cursor] == '%') {
      cursor++;
      continue;
    }

    int probe = cursor;
    while (probe < end && _printf_is_digit(format[probe])) probe++;
    if (probe < end && format[probe] == '$')
      _printf_error(
        c, family,
        "positional formats cannot infer Var argument types");

    while (cursor < end &&
           (format[cursor] == '-' || format[cursor] == '+' ||
            format[cursor] == ' ' || format[cursor] == '#' ||
            format[cursor] == '0'))
      cursor++;

    if (cursor < end && format[cursor] == '*') {
      cursor++;
      probe = cursor;
      while (probe < end && _printf_is_digit(format[probe])) probe++;
      if (probe < end && format[probe] == '$')
        _printf_error(
          c, family,
          "positional formats cannot infer Var argument types");
      _lower_printf_star(c, values, value_index++, family);
    }
    else while (cursor < end && _printf_is_digit(format[cursor])) cursor++;

    if (cursor < end && format[cursor] == '.') {
      cursor++;
      if (cursor < end && format[cursor] == '*') {
        cursor++;
        probe = cursor;
        while (probe < end && _printf_is_digit(format[probe])) probe++;
        if (probe < end && format[probe] == '$')
          _printf_error(
            c, family,
            "positional formats cannot infer Var argument types");
        _lower_printf_star(c, values, value_index++, family);
      }
      else while (cursor < end && _printf_is_digit(format[cursor])) cursor++;
    }

    PrintfLength length = _printf_default;
    if (cursor + 1 < end && format[cursor] == 'h' &&
        format[cursor + 1] == 'h') {
      length = _printf_hh;
      cursor += 2;
    }
    else if (cursor + 1 < end && format[cursor] == 'l' &&
             format[cursor + 1] == 'l') {
      length = _printf_ll;
      cursor += 2;
    }
    else if (cursor < end) {
      switch (format[cursor]) {
        case 'h': length = _printf_h; cursor++; break;
        case 'l': length = _printf_l; cursor++; break;
        case 'j': length = _printf_j; cursor++; break;
        case 'z': length = _printf_z; cursor++; break;
        case 't': length = _printf_t; cursor++; break;
        case 'L': length = _printf_L; cursor++; break;
      }
    }
    if (cursor >= end)
      _printf_error(c, family, "incomplete format conversion");
    int conversion = format[cursor++];
    if (!_printf_valid_length(length, conversion)) {
      String message =
        %"unsupported or malformed format conversion %%%c"
          .printf(conversion);
      _printf_error(c, family, message);
    }
    if (value_index >= values.len()) {
      String message =
        %"format conversion %%%c consumes a missing argument"
          .printf(conversion);
      _printf_error(c, family, message);
    }
    _lower_printf_value(
      c, values, value_index++, family, length, conversion);
  }

  for (int i = value_index; i < values.len(); i++) {
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
  Compiler compiler, List ast, List params, List args) {
  String callee_name = NULL;
  match (ast.cadr()) {
    case %(expr ? (ident ?binding)):
      callee_name = binding_identity_spelling(binding);
  }
  int list_varargs = callee_name == %"List_list_n";
  if (compiler.fn_name && _iter_immediate_consumer(callee_name) && args)
    args = cons(compiler.complete_iter_chain(args.car()), args.cdr());
  Array values = %[], int arg_index = 0;
  for (List p = params, a = args; a;
       p = cdr(p), a = cdr(a), arg_index++) {
    List param = (p ? car(p).list() : NULL), arg = car(a);
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
  return %(call ${ast.cadr()} (args @newargs));
}

// Align call arguments with parameter annotations by inserting conversions.
static List _call(Compiler compiler, List ast) {
  ast = _lower_printf_vars(compiler, ast);
  match (ast) {
    case %(call (expr ((func ?matched_params) *) ?) (args *args)): {
      return _typed_call(
        compiler, ast, matched_params, args);
    }
    case %(call (expr ((!or (!quote *) & ^) (func ?pointer_params) *) ?)
                 (args *pointer_args)): {
      return _typed_call(
        compiler, ast, pointer_params, pointer_args);
    }
  }
  return ast;
}

// Inject conversions so assignment RHS matches the annotated LHS type.
static List _assignment(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  if (lhs.match(%(expr ? (slice *))))
    compiler.report_error(
      <xform>, "slice expressions are not assignable",
      NULL, %("call the collection's setslice method explicitly"));
  match (lhs) {
    case %(expr ? (getindex (!set ?base (expr ?btype ?)) ?index)): {
      List base_type = btype;
      /* String is immutable and interned, so an in-place bracket write
         would mutate shared storage and leave its cached header hash
         stale. A raw write bypasses that invariant, while generic
         setindex returns a copy that this assignment would discard. */
      if (compiler.sym.is_string_type(base_type))
        compiler.report_error(
          <xform>, "String does not support bracket assignment", NULL,
          %("String is immutable: use the copy-producing String.withindex, or bind a char * to write a transient String.malloc buffer"));
      if (!compiler.resolve_protocol_member(base_type, "setindex"))
        compiler.report_error(
          <xform>, %"type $base_type does not support bracket assignment",
          NULL, %("use an explicit copy-producing method where available"));
      return %(setindex $base $index $rhs);
    }
  }
  rhs = compiler.convert_expression(rhs, lhs.cadr());
  return %(op $op $lhs $rhs);
}

// Normalize declaration bindings to match declared type metadata.
static List _declaration(Compiler compiler, List ast) {
  match (ast) {
    case %(declare ?target (bindings *bound_list)): {
      Array values = %[], List new_bind = NULL;
      foreach (Ast binding, bound_list) {
        new_bind = binding;
        match (binding)
          case %(op = (bind ?var ?mods) ?rhs): {
            List target_type = %(@{mods} @target);
            List converted = compiler.convert_expression(
              rhs, target_type);
            new_bind = %(
              op = (bind ${var.list()} ${mods.list()}) $converted
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
      return %(declare $target (bindings @new_bindings));
    }
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
  return converted;
}

// Build the List index expression used by each lowered target.
static List _element_at(List source, int index) {
  String text = %"$index";
  return %(expr ("Var") (getindex $source (literal (int) $text)));
}

static List _destructure_element(List temporary, int index) =>
  _element_at(%(expr ("List") (ident $temporary)), index);

// Expand predeclared assignment targets into left-to-right statements.
static List _destructure_assignments(List targets, List temporary) {
  int index = 0;
  return targets.map(%!(List target) using &index => {
    match (target)
      case %(expr ?type ?): {
        List value = _destructure_element(temporary, index++);
        return %(stmnt (expr $type (op = $target $value)));
      }
  });
}

// A discarded destructuring result retains the compact block lowering used
// before assignment destructuring became expression-valued.
static List _destructure_statement(Compiler compiler, List ast) {
  match (ast) {
    case %(stmnt (expr ?
             (dstrasgn (targets *targets)
                       (!set ?source (expr ?source_type ?))))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      List temp_decl = %(declare ("List")
        (bindings (op = (bind $temporary ())
                      ${_destructure_source(
                          compiler, source, source_type.list())})));
      List assignments = _destructure_assignments(targets, temporary);
      return %(block $temp_decl @assignments);
    }
  }
  return ast;
}

// Lower declarations without a containing block so names retain outer scope.
static List _destructure_declaration(Compiler compiler, List ast) {
  match (ast) {
    case %(dstrdecl ?type (targets *targets)
                    (!set ?source (expr ?source_type ?))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));

      Array declarations = %[], expressions = %[];
      foreach (List ident, targets) {
        declarations.push(%(bind $ident ()));
        expressions.push(%(expr $type (ident $ident)));
      }
      List target_decl =
        %(declare $type (bindings @{declarations.list_free()}));
      List temp_decl = %(declare ("List")
        (bindings (op = (bind $temporary ())
                      ${_destructure_source(
                          compiler, source, source_type.list())})));
      List assignments =
        _destructure_assignments(expressions.list_free(), temporary);
      List result = %(seq $target_decl $temp_decl @assignments);
      return result;
    }
    case %(dstrdecl (params *parameters)
                    (!set ?source (expr ?source_type ?))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      List temp_decl = %(declare ("List")
        (bindings (op = (bind $temporary ())
                      ${_destructure_source(
                          compiler, source, source_type.list())})));
      Array declarations = %[];
      declarations.push(temp_decl);
      int index = 0;
      foreach (List parameter, parameters) match (parameter) {
        case %(param ?type ?bind): {
          List value = _destructure_element(temporary, index++);
          declarations.push(%( declare $type (bindings (op = $bind $value)) ));
        }
      }
      return %(seq @{declarations.list_free()});
    }
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

/* Keep the source's exact static type and value in one result temporary, then
   convert that temporary to List once for the left-to-right assignments. */
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
        compiler, result_expr, type.list());
      List assignments = _destructure_assignments(targets, temporary);
      return %(dstrvalue $type $result $source $temporary $converted
               @assignments);
    }
  }
  return ast;
}
// Ensure return expressions respect the function return annotation.
static List _return(Compiler compiler, List ast) {
  match (ast)
    case %(return ?rtype ?expression):
      return %(return ${compiler.convert_expression(expression, rtype)});
  return ast;
}

// (match expr ((pattern body) ...))
static List _match_cases(Compiler compiler, List ast) {
  List (expr, cases) = ast.cdr();
  expr = compiler.convert_expression(expr, %("List"));
  Array values = %[];
  foreach (List rec, cases) {
    List binders = compiler.match_pattern_binders(rec.car(), NULL);
    values.push(%($binders @rec));
  }
  List result = values.list_free();
  return %(matchcases $expr $result);
}

// (catchcases ((pattern body) ...))
static List _catch_cases(Compiler compiler, List ast) {
  Array values = %[];
  foreach (List rec, ast.cadr()) {
    List pattern = rec.car();
    List binders = pattern ?
      compiler.match_pattern_binders(pattern, NULL) : NULL;
    values.push(%($binders @rec));
  }
  List result = values.list_free();
  return %(catcharms $result);
}

// operator passes

// Lower the comparison family from one typed operand match.
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
  Sym.is_string_type(compiler.sym, type)
      || _raw_string_type(type);

// Identify only the built-in helper family. Protocol resolution still
// handles every bracket form.
static Symbol _indexed_builtin_helper(Compiler compiler, Type type) {
  if (Sym.is_array_type(compiler.sym, type)) return <array>;
  if (Sym.is_map_type(compiler.sym, type)) return <map>;
  return 0;
}

// Unwrap only the syntax that is transparent for a direct indexed source.
static List _transparent_source(List expr) {
  while (expr) {
    if (expr.car() == <at>) {
      expr = expr.caddr();
      continue;
    }
    match (expr) {
      case %(expr ? (parens ?inner)): {
        expr = inner;
        continue;
      }
    }
    break;
  }
  return expr;
}

// Helper-backed indexes bypass getindex lowering.
static int _indexed_parts(
  Compiler compiler, List expr, int transparent, Symbol *owner, List *base,
  List *selector) {
  if (transparent) expr = _transparent_source(expr);
  match (expr)
    case %(expr ? (getindex (!set ?matched_base (expr ?type ?))
                            ?matched_selector)): {
      *owner = _indexed_builtin_helper(compiler, type.list());
      *base = matched_base;
      *selector = matched_selector;
      return 1;
    }
  return 0;
}

static void _convert_indexed_parts(
  Compiler compiler, Symbol owner, List *base, List *selector) {
  if (owner == <array>) {
    *base = compiler.convert_expression(*base, %("Array"));
    *selector = compiler.convert_expression(*selector, %(int));
  }
  else {
    *base = compiler.convert_expression(*base, %("Map"));
    *selector = compiler.convert_expression(*selector, %("Var"));
  }
}

static int _indexed_rhs_allowed(Compiler compiler, Symbol op, List rhs) {
  Type type = rhs.cadr();
  if (compiler.sym.is_var_type(type)) return 1;
  if (compiler.sym.resolve_numeric_type(type)) return 1;
  return op == <+> && _string_operand(compiler, type);
}

// Preserve x2c source order across C's unspecified call-argument order.
static List _sequenced_protocol_call(
  Compiler compiler, List resolved, List arguments) {
  (List binding, Type signature) = resolved;
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr(), Array converted = %[];
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
  List args = %(args @{converted.list_free()});
  return %(vseqcall $result (expr $signature (ident $binding)) $args);
}

static List _indexed_update(
  Compiler c, List lhs, Symbol op, List rhs) {
  Symbol owner, List base, selector;
  if (!_indexed_parts(c, lhs, 0, &owner, &base, &selector)) return NULL;
  (Var base_tag, Type base_type) = base;
  (void) base_tag;
  List resolved = c.resolve_protocol_member(base_type, "updateindex");
  if (!resolved) {
    String type = base_type.repr();
    c.report_error(
      <xform>, %"type $type does not support indexed compound assignment",
      NULL, NULL);
  }
  if (owner && !_indexed_rhs_allowed(c, op, rhs)) {
    (Var rhs_tag, Type rhs_type) = rhs;
    (void) rhs_tag;
    String details = %"right type: ${rhs_type.repr()}";
    String message = op == <+>
      ? "indexed += requires a numeric, Var, or String operand"
      : "indexed compound assignment requires a numeric or Var operand";
    c.report_error(<xform>, message, NULL, %($details));
  }

  Symbol source_owner, List source_base, source_selector;
  if (owner && _indexed_parts(
    c, rhs, 1, &source_owner, &source_base, &source_selector) &&
      source_owner) {
    _convert_indexed_parts(c, owner, &base, &selector);
    _convert_indexed_parts(c, source_owner, &source_base, &source_selector);
    String helper;
    if (owner == <array> && source_owner == <array>)
      helper = "x2c_array_updateindex_from_array";
    else if (owner == <array>) helper = "x2c_array_updateindex_from_map";
    else if (source_owner == <array>)
      helper = "x2c_map_updateindex_from_array";
    else helper = "x2c_map_updateindex_from_map";
    return %(call $helper (args
      $base $selector ${_symbol_expression(op)}
      $source_base $source_selector
    ));
  }

  if (!owner)
    return _sequenced_protocol_call(
      c, resolved,
      %($base $selector ${_symbol_expression(op)} $rhs));

  _convert_indexed_parts(c, owner, &base, &selector);
  rhs = c.convert_expression(rhs, %("Var"));
  String helper = owner == <array> ? "Array_updateindex" : "Map_updateindex";
  return %(
    call $helper (args $base $selector ${_symbol_expression(op)} $rhs));
}

static List _indexed_postfix(
  Compiler compiler, List arg, Symbol op) {
  Symbol owner, List base, selector;
  if (!_indexed_parts(compiler, arg, 0, &owner, &base, &selector)) return NULL;
  (Var base_tag, Type base_type) = base;
  (void) base_tag;
  List resolved =
    compiler.resolve_protocol_member(base_type, "postfixindex");
  if (!resolved) {
    String type = base_type.repr();
    compiler.report_error(
      <xform>, %"type $type does not support indexed increment or decrement",
      NULL, NULL);
  }
  if (!owner)
    return _sequenced_protocol_call(
      compiler, resolved,
      %($base $selector ${_symbol_expression(op)}));
  _convert_indexed_parts(compiler, owner, &base, &selector);
  String helper = owner == <array> ? "Array_postfixindex" : "Map_postfixindex";
  return %(call $helper (args $base $selector ${_symbol_expression(op)}));
}

static List _indexed_prefix(Compiler compiler, List arg, Symbol op) {
  List one = %(expr (int) (literal (int) "1"));
  Symbol binary = op == <++> ? <+> : <->;
  return _indexed_update(compiler, arg, binary, one);
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
    Symbol member = c.operator_member(op);
    if (member) {
      String member_name = member;
      List resolved =
        c.resolve_protocol_member(member_type, member_name);
      if (resolved) {
        Type signature = resolved.cadr();
        List parameters = signature.car().list().cadr();
        rhs = c.convert_expression(rhs, parameters.cadr());
        (rhs_tag, rhs_type) = rhs;
        String helper = c.protocol_update_helper(
          member_type, member_name, 0);
        if (helper)
          return %(vcompound $lhs ${_symbol_expression(op)} $rhs $helper);
      }
    }
  }
  if (!lhs_is_var && !rhs_is_var) return ast;
  if (lhs_type.is_bitfield())
    c.report_error(
      <xform>, "dynamic compound assignment cannot target a bitfield",
      NULL, NULL);
  int rhs_allowed = rhs_is_var
                 || c.sym.resolve_numeric_type(rhs_type)
                 || (op == <+> && _string_operand(c, rhs_type));
  if (!rhs_allowed) {
    String details = %"right type: ${rhs_type.repr()}";
    c.report_error(
      <xform>,
      op == <+>
        ? "dynamic += requires a numeric, Var, or String operand"
        : "dynamic compound assignment requires a numeric or Var operand",
      NULL, %($details));
  }

  String helper = "Var_update";
  if (!lhs_is_var) {
    Type scalar = c.sym.resolve_numeric_type(lhs_type);
    if (scalar && scalar.is_enum())
      c.report_error(
        <xform>, "dynamic compound assignment cannot target an enum",
        NULL, NULL);
    helper = scalar ? scalar.var_numeric_update_helper() : NULL;
    if (!helper) {
      String details = %"left type: ${lhs_type.repr()}";
      c.report_error(
        <xform>, "dynamic compound assignment requires a numeric lvalue",
        NULL, %($details));
    }
  }

  rhs = c.convert_expression(rhs, %("Var"));
  return %(vcompound $lhs ${_symbol_expression(op)} $rhs $helper);
}

// Dispatch operator rewrites that rely on Var semantics.
static List _operator(Compiler c, List ast) {
  List truthy = _truthy(c, ast);
  if (truthy != ast) return truthy;
  match (ast) {
    case %(op ?operator (!set ?lhs (expr ? ?))
             (!set ?rhs (expr ? ?))): {
      Symbol compound = Symbol.compound_operator(operator);
      if (compound) {
        List indexed = _indexed_update(
          c, lhs, compound, rhs);
        if (indexed) return indexed;
        return _dynamic_compound(
          c, ast, compound, lhs, rhs);
      }
      switch (operator.symbol()) {
        case <=>:
          return _assignment(
            c, operator, lhs, rhs);
        case <==>:  case <!=>:  case <===>: case <!==>:
        case <"<">: case <"<=">: case <">">:  case <">=">:
          return _comparison(
            c, ast, operator, lhs, rhs);
      }
      if (_dynamic_binary_operator(operator))
        return _dynamic_binary(
          c, ast, operator, lhs, rhs);
      return ast;
    }
    case %(op (!set ?operator (!or + - ~))
             (!set ?argument (expr ?argument_type ?))): {
      if (c.sym.is_var_type(argument_type.list()))
        c.report_error(
          <xform>, "dynamic unary numeric operators are not supported",
          NULL, %("use Var.binary with an explicit numeric operand"));
      return ast;
    }
    case %(op (!set ?operator (!or ++ --))
             (!set ?argument (expr ?argument_type ?))): {
      Type type = argument_type.list(), List arg = argument;
      List indexed = _indexed_prefix(c, arg, operator);
      if (indexed) return indexed;
      if (!c.sym.is_var_type(type)) {
        Symbol binary = operator == <++> ? <+> : <->;
        Symbol member = c.operator_member(binary);
        if (member) {
          String member_name = member;
          List resolved = c.resolve_protocol_member(type, member_name);
          match (resolved)
            case %(? ((func (? ?parameter *)) ?)): {
              List one = %(expr (int) (literal (int) "1"));
              one = c.convert_expression(one, parameter.list());
              String helper = c.protocol_update_helper(
                type, member_name, 0);
              if (helper)
                return %(vcompound
                  $arg ${_symbol_expression(binary)} $one $helper);
            }
        }
      }
      if (c.sym.is_var_type(type)) {
        List one = %(expr (int) (literal (int) "1"));
        one = c.convert_expression(one, %("Var"));
        Symbol binary = operator == <++> ? <+> : <->;
        return %(vcompound
          $arg ${_symbol_expression(binary)} $one "Var_update"
        );
      }
      return ast;
    }
  }
  return ast;
}

static List _postfix(Compiler compiler, List ast) {
  match (ast)
    case %(postfix ?operator
                   (!set ?argument (expr ?argument_type ?))): {
      Symbol op = operator, List arg = argument;
      Type type = argument_type.list();
      List indexed = _indexed_postfix(compiler, arg, op);
      if (indexed) return indexed;
      if (!compiler.sym.is_var_type(type)) {
        Symbol binary = op == <++> ? <+> : <->;
        Symbol member = compiler.operator_member(binary);
        if (member) {
          String member_name = member;
          if (compiler.resolve_protocol_member(type, member_name)) {
            String helper = compiler.protocol_update_helper(
              type, member_name, 1);
            if (helper)
              return %(vpostfix $arg ${_symbol_expression(op)} $helper);
          }
        }
      }
      if (compiler.sym.is_var_type(type)) {
        List address = %(expr (* "Var") (op & (parens $arg)));
        return %(call "Var_postfix"
                      (args $address ${_symbol_expression(op)}));
      }
      return ast;
    }
  return ast;
}

static List _truthy(Compiler compiler, List ast) {
  match (ast) {
    case %(if ?condition *body):
      return %(if ${_truthy_expression(compiler, condition)} @body);
    case %(while ?condition ?body):
      return %(while ${_truthy_expression(compiler, condition)} $body);
    case %(do ?body ?condition):
      return %(do $body ${_truthy_expression(compiler, condition)});
    case %(for ?init ?condition ?increment ?body):
      return %(for $init ${_truthy_expression(compiler, condition)}
                   $increment $body);
    case %(op (!set ?operator (!or && ||)) ?lhs ?rhs): {
      List left = _truthy_expression(compiler, lhs);
      List right = _truthy_expression(compiler, rhs);
      return %(op $operator $left $right);
    }
    case %(op ? ?condition ?ontrue ?onfalse):
      return %(op ? ${_truthy_expression(compiler, condition)}
                   $ontrue $onfalse);
    case %(op ! ?condition):
      return %(op ! ${_truthy_expression(compiler, condition)});
  }
  return ast;
}

// collection passes

// Normalize cons nodes so head and tail carry expected runtime types.
static List _cons(Compiler compiler, List ast) {
  List (head, tail) = ast.cdr();
  head = compiler.convert_expression(head, %("Var"));
  tail = compiler.convert_expression(tail, %("List"));
  return %(cons $head $tail);
}

/** Converts an `(array ...)` or `(varray ...)` node to source-ordered
    `(varray ...)` form, converting every typed element to `Var`.
*/
List transform_array_literal(Compiler compiler, List ast) {
  List elems = cdr(ast), Array values = %[];
  foreach (List elem, elems) {
    List velem = compiler.convert_expression(elem, %("Var"));
    values.push(velem);
  }
  List velems = values.list_free();
  return %(varray @velems);
}

/** Converts a `(map ...)` or `(vmap ...)` node to source-ordered
    `(vmap (vpair ...))` form, converting every typed key and value to
    `Var`.
*/
List transform_map_literal(Compiler compiler, List ast) {
  List elems = cdr(ast), Array values = %[];
  foreach (List entry, elems) {
    List (key, val) = entry.cdr();
    List vkey = compiler.convert_expression(key, %("Var"));
    List vval = compiler.convert_expression(val, %("Var"));
    values.push(%(vpair $vkey $vval));
  }
  List velems = values.list_free();
  return %(vmap @velems);
}

// Ensure append targets operate on typed list operands.
static List _append(Compiler compiler, List ast) {
  List (lhs, rhs) = ast.cdr();
  if (compiler.sym.is_var_type(lhs.cadr()))
    lhs = %(expr ("List") (call "Var_list" (args $lhs)));
  else lhs = compiler.convert_expression(lhs, %("List"));
  return %(append $lhs $rhs);
}

// string passes

static List _process_raw_segment(Compiler compiler, List seg) {
  String raw = seg.cadr().str(), literal = %"\"${raw.escape()}\"";
  List constructor = compiler.sym.reference(%("String_new"), NULL);
  return %(expr ("String") (call
           (expr ((func ((* char))) "String") (ident $constructor))
           (args (expr (* char) (literal $literal)))));
}

static List _build_cons_list(List list) {
  if (!list) return %(nil);
  List head = car(list), tail = _build_cons_list(cdr(list));
  return %(cons $head $tail);
}

static List _string_segments(Compiler compiler, List ast) {
  /* A lone constant segment is already the whole string. Reuse the parsed
     literal's cache slot instead of joining a one-element List at runtime.
     Macro-generated literals arrive in this shape. Raise details are
     excluded: their cache slots would fill inside _file_init_ constructors,
     where re-entrant string-pool bootstrap can hand back NULL Strings. */
  match (ast) {
    case %(segments (segexp (expr ("String") (literal ("String") ?text)))):
      if (!compiler.runtime_literals)
        return compiler.cache(
          %(string (expr ("String") (literal ("String") $text))));
  }
  Array values = %[];
  foreach (List seg, ast.cdr()) {
    Symbol kind = seg.car();
    switch (kind) {
      case <segraw>: seg = _process_raw_segment(compiler, seg);
        break;
      case <segvar>:
      case <segexp>:
        seg = compiler.convert_segment_to_string(seg.cadr());
        break;
      case <cache>: seg = %(expr ("String") $seg); break;
    }
    seg = compiler.convert_expression(seg, %("Var"));
    values.push(seg);
  }
  int segment_count = values.len();
  List segments = values.list_free();
  // Keep nested cons expressions below host-C bracket-depth limits.
  if (segment_count <= 128) {
    segments = _build_cons_list(segments);
    return %("String_join(NULL, " (expr ("List") $segments) ")");
  }
  String count = %"${segment_count}U";
  Type signature = NULL;
  List binding = compiler.sym.reference(%("List_list_n"), &signature);
  List list = %(expr ("List")
    (call (expr $signature (ident $binding))
          (args (expr (unsigned) (literal (unsigned) $count)) @segments)));
  return %("String_join(NULL, " $list ")");
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

// defer passes

static int _defer_needs_landing(List ast) {
  if (!ast) return 0;
  match (ast)
    case %((!or return break continue goto try catcharms catchcases
                 match matchcases) *): return 1;
  foreach (Var child, ast)
    if (child is <list> && _defer_needs_landing(child)) return 1;
  return 0;
}

// File-static cleanup thunks cannot name block-local or variably-sized types.
// Keep the existing landing-frame lowering for those uncommon cases.
static int _defer_type_hoistable(Compiler compiler, Type type) {
  if (!type) return 0;
  Type flat = type.flatten_all();
  if (flat.contains(<register>) || flat.contains(<dim>)) return 0;
  Type base = type.base_type();
  if (!base) return 0;
  Var first = base.car();
  if (first is <string>) return compiler.sym.get(%($first)) != NULL;
  if (first == <struct> || first == <union> || first == <enum>)
    return base.len() == 2 && compiler.sym.get(base) != NULL;
  return 1;
}

static List _defer_direct_binding(Var value) {
  if (value is not <list>) return NULL;
  List ast = value;
  match (ast) {
    case %(ident ?binding): return binding;
    case %(expr ? ?inner):  return _defer_direct_binding(inner);
    case %(parens ?inner):  return _defer_direct_binding(inner);
    case %(op . ?inner *):  return _defer_direct_binding(inner);
  }
  return NULL;
}

static void _defer_collect_captures(
  Compiler compiler, List ast, List *declared, Map captures, Array records,
  List *written, int *unsupported) {
  if (!ast || *unsupported) return;
  match (ast)
    case %(bind ?bound *): {
      List binding = bound, known = *declared;
      if (!known.contains(binding)) *declared = cons(binding, known);
    }
  match (ast)
    case %(expr ? (ident ?bound)): {
      List binding = bound;
      Var automatic, existing, stored_type;
      if (binding && !(*declared).contains(binding) &&
          compiler.semantic_binding_facts().try_get(
            %(automatic $binding), &automatic) &&
          !captures.try_get(binding, &existing)) {
        stored_type = compiler.semantic_binding_facts()[%(type $binding)];
        if (!_defer_type_hoistable(compiler, stored_type.list())) {
          *unsupported = 1;
          return;
        }
        String field_name = compiler.fresh_name("defer_capture");
        List field = compiler.sym.introduce(field_name);
        captures[binding] = field;
        records.push(%($binding ${stored_type.list()} $field));
      }
      return;
    }
  List modified = NULL;
  match (ast) {
    case %(op ?operator ?target *):
      if (operator is <symbol> && ast_changes_left_operand(operator))
        modified = _defer_direct_binding(target);
    case %((!or vcompound vpostfix) ?target *):
      modified = _defer_direct_binding(target);
    case %(postfix ? ?target): modified = _defer_direct_binding(target);
  }
  foreach (Var child, ast)
    if (child is <list>)
      _defer_collect_captures(
        compiler, child, declared, captures, records, written,
        unsupported);
  Var field;
  List changed = *written;
  if (modified && captures.try_get(modified, &field) &&
      !changed.contains(modified))
    *written = cons(modified, changed);
}

// Replace captured object references with pointer dereferences through the
// thunk environment. Expression types remain the source expression's type.
static List _defer_rewrite_captures(
  List ast, Map captures, List written, String env_name) {
  if (!ast) return ast;
  match (ast)
    case %(expr ?captured_type (ident ?bound)): {
      List binding = bound;
      Var field_var;
      if (captures.try_get(binding, &field_var)) {
        String field_name = binding_identity_spelling(field_var);
        Type type = captured_type.list(), target = type;
        if (written.contains(binding) &&
            !type.flatten_all().contains(<volatile>))
          target = cons(<volatile>, type);
        Type pointer = cons(<*>, target);
        String reference = %"$env_name->$field_name";
        List source = %(expr (* const void) $reference);
        List cast = %(expr $pointer (cast $pointer $source));
        List dereference = %(expr $type (op * $cast));
        return %(expr $type (parens $dereference));
      }
      return ast;
    }
  Array rewritten = %[];
  foreach (Var child, ast) {
    if (child is <list>)
      child = _defer_rewrite_captures(
        child, captures, written, env_name);
    rewritten.push(child);
  }
  return rewritten.list_free();
}

static List _lower_callable_defer(
  Compiler c, List body, List finalizer) {
  List declared = NULL, written = NULL;
  Map captures = %{}, Array records = %[], int unsupported = 0;
  _defer_collect_captures(
    c, finalizer, &declared, captures, records, &written, &unsupported);
  if (unsupported) {
    records.free();
    return %(try $body () $finalizer);
  }

  List env_binding = NULL, env_local = NULL, String env_name = NULL;
  List record_list = records;
  if (record_list) {
    env_name = c.fresh_name("defer_env");
    env_binding = c.sym.introduce(env_name);
    env_local = c.sym.introduce(c.fresh_name("defer_data"));
    Array fields = %[];
    foreach (List record, record_list) {
      List field = record.caddr();
      fields.push(%(declare (const void) (bindings (bind $field (*)))));
    }
    List env_type = %(
      typedef (struct $env_name (fields @{fields.list_free()}))
              (bindings (bind $env_binding ()))
    );
    c.add_early(env_type);
  }

  List opaque = c.sym.introduce(c.fresh_name("defer_opaque"));
  List callback = c.sym.introduce(c.fresh_name("defer_cleanup"));
  String env_local_name = env_local
                        ? binding_identity_spelling(env_local) : NULL;
  List rewritten = env_local_name
                 ? _defer_rewrite_captures(
                   finalizer, captures, written, env_local_name)
                 : finalizer;
  List setup = NULL;
  if (env_binding) {
    List opaque_expr = %(expr (* void) (ident $opaque));
    List cast = %(expr (* $env_name) (cast (* $env_name) $opaque_expr));
    setup = %(declare ($env_name)
              (bindings (op = (bind $env_local (*)) $cast)));
  }
  List callback_body = setup
                     ? %(block $setup $rewritten)
                     : %(block $rewritten);
  List callback_bind = %(
    bind $callback
      ((fnmod (params (param (void) (bind $opaque (*))))))
  );
  List callback_func = %(
    function (static void) $callback_bind $callback_body);
  c.add_early(callback_func);
  if (c.fn_name)
    c.semantic_binding_facts()[%(defer-ownr $callback)] =
      c.fn_name;

  records.free();
  return %(defer $body $env_binding $callback $record_list $written);
}

// Choose the callable chain for ordinary cleanup statements and retain the
// landing-frame path for lexical transfers or unsupported capture types.
static List _lower_defer_region(
  Compiler compiler, List body, List finalizer) {
  if (_defer_needs_landing(finalizer))
    return %(try $body () $finalizer);
  return _lower_callable_defer(compiler, body, finalizer);
}

static List _rewrite_defer_list(Compiler compiler, List stmts) {
  if (!stmts) return stmts;
  int has_defer = 0;
  foreach (List statement, stmts) {
    List head = _without_origin(statement);
    match (head) case %(defer ?): has_defer = 1;
    if (has_defer) break;
  }
  if (!has_defer) return stmts;
  Array suffixes = %[];
  defer suffixes.free();
  for (List suffix = stmts; suffix; suffix = suffix.cdr())
    suffixes.push(suffix);
  List result = stmts;
  int tail_changed = 0;
  for (int i = (int) suffixes.len() - 1; i >= 0; i--) {
    List suffix = suffixes[i];
    List anchored = suffix.car();
    List tail = tail_changed ? result : suffix.cdr();
    List head = _without_origin(anchored);
    match (head) case %(defer ?final_stmt): {
      List body = %(block @tail), finalizer = final_stmt;
      List region = _lower_defer_region(compiler, body, finalizer);
      result = %( ${_rewrap_origin(anchored, region)} );
      tail_changed = 1;
      continue;
    }
    if (tail_changed) result = cons(anchored, result);
  }
  return result;
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
      Type type = expr_type.list();
      if (!_raise_detail_type_allowed(compiler, type)) return type;
      if (compiler.sym.is_var_type(type)) {
        List payload = value;
        match (payload)
          case %(call (!is ?callee type string) ?arguments):
            if (callee.string().endswith("_var"))
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

// Normalize raise detail crossings to the counted runtime's Var pairs.
static List _raise(
  Compiler compiler, List ast, Var cause, List arguments) {
  Array values = %[], int changed = 0, index = 0;
  foreach (List value, arguments) {
    Type invalid = NULL;
    if (index & 1)
      match (value)
        case %(expr ?value_type ?content): {
          Type type = value_type.list();
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
  return %(raise $cause (args @converted));
}

// Lower bracket reads into helper calls with method-call conversions.
static List _nominal_getindex(Compiler compiler, Type type) {
  if (!type.is_typedef_name()) return NULL;
  if (Sym.is_array_type(compiler.sym, type) ||
      Sym.is_map_type(compiler.sym, type))
    return NULL;
  match (type)
    case %((!is ?nominal type string)): {
      String source = %"${nominal.str()}_getindex";
      Type signature = compiler.sym.get(%($source));
      match (signature)
        case %((func ($type ?)) ?):
          return %(${compiler.sym.reference(%($source), NULL)}
                   $signature);
    }
  return NULL;
}

// Replace the parser's abstract cast declarator with its declared type.
static List _cast(Compiler compiler, List ast) {
  match (ast)
    case %(cast (!set ?declarator (decl *parts))
                (!set ?expression (expr ?source_type ?))): {
    List declaration = %(declare @parts);
    Type type = declaration.type_from_ast();
    int source_var = compiler.sym.is_var_type(source_type.list());
    int target_var = compiler.sym.is_var_type(type);
    int unresolved = 0;
    match (expression)
      case %(expr () (ident ?)): unresolved = 1;
    if (type != %(void) &&
        (source_var || (target_var && (source_type || unresolved))))
      return compiler.convert_expression(expression, type);
    return %(cast $type $expression);
  }
  return ast;
}

// transform driver

static List _match_records(Compiler compiler, List records) {
  Array transformed = %[];
  foreach (List record, records)
    match (record)
      case %(*prefix ?body):
        transformed.push(%(@prefix ${_node(compiler, body.list())}));
  return transformed.list_free();
}

/* Only top-level and block sequences absorb `(seq ...)` replacements.
   Children transform left to right, then reverse assembly preserves source
   order while allocating generated splice origins from right to left. */
static Ast _sequence(Compiler compiler, Ast ast) {
  Array transformed = %[];
  defer transformed.free();
  foreach (List value, ast) transformed.push(_node(compiler, value));
  Ast tail = NULL;
  for (int i = (int) transformed.len() - 1; i >= 0; i--) {
    Ast node = transformed[i].list();
    List payload = _without_origin(node);
    match (node)
      case %(at ?parent ?):
        match (payload)
          case %(seq *items): {
            Array anchored = %[];
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
  $ast.rewrite_children(ast, child, _node(compiler, child));
}

/* The dispatcher tail _op_chain applies to its base and rewritten nodes,
   mirroring _node: sequences pass through, match records and blocks reach
   their own drivers, and everything else transforms its children. */
static Ast _finish(Compiler compiler, Ast ast) {
  match (ast) {
    case %(seq *): return ast;
    case %(matchcases ?subject ?records): {
      List new_subject = _node(compiler, subject.list());
      List new_records = _match_records(compiler, records);
      return %(matchcases $new_subject $new_records);
    }
    case %(block *body):
      return %(block @{_sequence(compiler, body)});
  }
  return _children(compiler, ast);
}

/* A left-leaning operator chain nests one (expr (op ...)) level per source
   term, so child-first transformation would recurse once per term. Walk down
   the spine while each level survives its operator rewrites unchanged,
   transform the deepest term, and rebuild upward. Entered only for chain
   heads, with expression rewrites already applied. */
static Ast _op_chain(Compiler compiler, Ast ast) {
  Array levels = %[];
  Array types = %[];
  defer levels.free();
  defer types.free();
  Ast rebuilt = NULL;
  for (;;) {
    List first = NULL;
    match (ast)
      case %(expr ? (op ? (!is ?matched type list) *)): {
        List candidate = matched;
        if (candidate.match(%(expr ? (op *)))) first = candidate;
      }
    if (!first) {
      rebuilt = _finish(compiler, ast);
      break;
    }
    Var type = ast.cadr();
    if (type is <list>) type = _node(compiler, type.list());
    List opnode = ast.caddr();
    List rewritten = _operator(compiler, opnode);
    if (rewritten != opnode) {
      rebuilt = %(expr $type ${_finish(compiler, rewritten)});
      break;
    }
    types.push(type);
    levels.push(ast);
    ast = compiler.lower_typed_adapter_expr(first);
    ast = compiler.lower_lambda_expr(ast);
  }
  for (int i = (int) levels.len() - 1; i >= 0; i--)
    match (levels[i])
      case %(expr ? (op ?operator ? *rest)): {
        Array parts = %[];
        if (operator is <list>) parts.push(_node(compiler, operator.list()));
        else parts.push(operator);
        parts.push(rebuilt);
        foreach (Var operand, rest) {
          if (operand is <list>) parts.push(_node(compiler, operand.list()));
          else parts.push(operand);
        }
        rebuilt = %(expr ${types[i]} (op @{parts.list_free()}));
      }
  return rebuilt;
}

/* Callers supply bound, typed canonical nodes, and transform helpers construct
   the normalized shapes consumed by the emitter. A helper rewrites only its
   current node: this dispatcher recurses into returned children, while
   _sequence alone splices `(seq ...)` results into a sequence. */
static Ast _node(Compiler c, Ast ast) {
  if (!ast) return NULL;
  Var head = ast.car();
  if (head is not <symbol>) return _children(c, ast);
  match (ast) {
    case %(at ?origin ?inner): {
      // An anchored statement that already reached its fixed point yields
      // itself. Recording that keeps the driver's later passes from
      // rebuilding the whole unit to rediscover it.
      if (c.fixed.contains(ast)) return ast;
      int occurrence = origin.integer(), previous = c.origin;
      List transformed = NULL;
      c.origin = occurrence;
      {
        defer c.origin = previous;
        transformed = _node(c, inner.list());
      }
      if (transformed == inner) {
        c.fixed[ast] = 1;
        return ast;
      }
      c.origins.push(%(generated $occurrence xform));
      int generated = c.origins.len();
      return %(at $generated $transformed);
    }
    case %(function ?return_type
           (!set ?declarator (bind ?binding ?)) ?body): {
      String owner = binding_identity_spelling(binding);
      Var stored_owner;
      if (c.semantic_binding_facts().try_get(
        %(defer-ownr ${binding.list()}), &stored_owner))
        owner = stored_owner.str();
      String previous = c.fn_name;
      int previous_inline = c.inline_header;
      c.fn_name = owner;
      Type function_type = return_type;
      c.inline_header = function_type.is_inline() &&
                        !function_type.is_static();
      List new_return = _node(c, return_type.list());
      List new_decl = _node(c, declarator.list());
      List prepared_body = _lower_lambda_destructuring(
        c, body);
      prepared_body = c.prepare_lambda_cells(
        declarator, prepared_body);
      List new_body = _node(c, prepared_body);
      List transformed = %(function $new_return
                           $new_decl $new_body);
      c.fn_name = previous;
      c.inline_header = previous_inline;
      return transformed;
    }
    case %(getindex
           (!set ?expression (expr ?matched_type ?)) ?index): {
      Type type = matched_type.list();
      List resolved = _nominal_getindex(c, type);
      if (!resolved) resolved = c.resolve_protocol_member(type, "getindex");
      if (!resolved)
        c.report_error(
          <xform>,
          %"type $type does not support bracket indexing", NULL, NULL);
      (List binding, Type signature) = resolved;
      return _children(
        c,
        %(call (expr $signature (ident $binding))
               (args $expression $index))
      );
    }
    case %(setindex
           (!set ?expression (expr ?matched_type ?)) ?index ?value): {
      Type type = matched_type.list();
      List resolved = c.resolve_protocol_member(type, "setindex");
      if (!resolved)
        c.report_error(
          <xform>,
          %"type $type does not support bracket assignment", NULL, NULL);
      if (!_indexed_builtin_helper(c, type))
        return _children(
          c,
          _sequenced_protocol_call(
            c, resolved, %($expression $index $value))
        );
      (List binding, Type signature) = resolved;
      return _children(
        c,
        %(call (expr $signature (ident $binding))
               (args $expression $index $value))
      );
    }
    case %(slice
           (!set ?expression
             (expr (!set ?matched_type (*)) ?))
           ?start ?stop ?step): {
      Type type = matched_type.list();
      String nominal = NULL;
      match (type)
        case %((!is ?name type string)): nominal = name;
      if (!nominal)
        c.report_error(
          <xform>, %"type $type does not support slicing", NULL, NULL);
      String fnname = %"${nominal.str()}_getslice";
      if (!c.sym.get(%($fnname)))
        c.report_error(
          <xform>,
          %"type $type does not support slicing", NULL, %());
      String none = "-2147483648";
      start = start ? start : List_var(%(literal (int) $none));
      stop = stop ? stop : List_var(%(literal (int) $none));
      step = step ? step : List_var(%(literal (int) "1"));
      return _children(
        c,
        %(call "$fnname" (args $expression $start $stop $step)));
    }
  }
  switch (head.symbol()) {
    case <protocol>: case <adopt>: case <macrodef>: return ast;
    case <literal>:  return ast;
    case <expr>: ast = c.lower_typed_adapter_expr(ast);
      ast = c.lower_lambda_expr(ast);
      match (ast)
        case %(expr ? (op ? (!is ?first type list) *)):
          if (first.list().match(%(expr ? (op *))))
            return _op_chain(c, ast);
      break;
    case <array>:    ast = transform_array_literal(c, ast);     break;
    case <map>:      ast = transform_map_literal(c, ast);       break;
    case <cast>:     ast = _cast(c, ast);             break;
    case <cons>:     ast = _cons(c, ast);             break;
    case <append>:   ast = _append(c, ast);           break;
    case <var>:      ast = _to_var(c, ast.cadr());    break;
    case <segments>: ast = _string_segments(c, ast);  break;
    case <declare>:  ast = _declaration(c, ast);      break;
    case <dstrdecl>:
      ast = _destructure_declaration(c, ast);        break;
    case <stmnt>:    ast = _destructure_statement(
      c,
      ast);     break;
    case <dstrasgn>:
      ast = _destructure_value(c, ast);              break;
    case <match>:    ast = _match_cases(c, ast);      break;
    case <catchcases>:
      ast = _catch_cases(c, ast);                     break;
    case <defer>: {
      match (ast)
        case %(defer ?finalizer):
          ast = _lower_defer_region(c, %(block), finalizer);
      break;
    }
    case <raise>: {
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
    case <block>: {
      List statements = ast.cdr();
      List body = _rewrite_defer_list(c, statements);
      if (body !== statements) ast = %(block @body);
      break;
    }
    case <return>:   ast = _return(c, ast);           break;
    case <if>: case <while>: case <do>: case <for>:
      ast = _truthy(c, ast);                           break;
    case <call>:     ast = _call(c, ast);             break;
    case <op>:       ast = _operator(c, ast);         break;
    case <postfix>:  ast = _postfix(c, ast);          break;
  }
  match (ast) {
    case %(seq *): return ast;
    case %(matchcases ?subject ?records): {
      List new_subject = _node(c, subject.list());
      List new_records = _match_records(c, records);
      return %(matchcases $new_subject $new_records);
    }
    case %(block *body):
      return %(block @{_sequence(c, body)});
  }
  return _children(c, ast);
}

/** Lowers a bound and typed top-level AST to the normalized form consumed by
    emission. `compiler` must own the AST's bindings, origins, and conversion
    state. The call drives the input and synthesized early declarations to
    identity fixed points, appends those declarations after the input units,
    and may add generated origins or diagnostics to `compiler`.
*/
List Compiler.transform(Compiler compiler, List ast) {
  List newast = _sequence(compiler, ast);
  while (newast != ast) {
    ast = newast;
    newast = _sequence(compiler, ast);
  }
  // Merge and lower synthesized lambda siblings.
  Array generated = %[];
  while (compiler.early_decls.len()) {
    List items = compiler.early_decls;
    compiler.early_decls.clear();
    List siblings = items, lowered = _sequence(compiler, siblings);
    while (lowered != siblings) {
      siblings = lowered;
      lowered = _sequence(compiler, siblings);
    }
    foreach (Var sibling, lowered) generated.push(sibling);
  }
  if (generated.len()) newast = newast.append(generated.list_free());
  return newast;
}
