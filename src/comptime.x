/*  comptime.x -- translating a compile-time x2c function into Lisp

    Copyright (c) 2026 Gary William Flake.

    A function marked for compile-time use is lowered here into the Lisp the
    macro session evaluates. A call in tail position reuses the frame it
    stands in, so a loop runs in constant space when its recursive call is
    in tail position and nothing accumulates around it. A block is therefore
    reduced by substitution to one expression per live local, and an
    iteration ends in `(loop e1 e2 ...)` directly.

    Locals are Lisp values held in an environment mapping each binding id to
    the expression that currently produces it. A value the substitution
    cannot carry is bound with a real lambda when it is off a loop's
    iteration path, and declines the function when it is on one.
  */
#pragma once
#include "compiler.x"
#pragma private
#include "type.x"
#include "var.x"
#include "string.x"
#include "lisp.x"
#include "atom.x"
#include "logger.x"

/* One lowering. `env` maps a binding id to the Lisp form that produces it;
   `locals` are the ids the function declares, so an id outside it is
   file-scope state. `on_loop` records whether the current point is on a
   loop's iteration path, where a binding form would cost frame reuse.
   `on_break` and `on_continue` are the continuations the nearest enclosing
   loop or `switch` gave, or nothing outside one. */
typedef struct Lowering {
  Compiler compiler;
  Map env, locals, cells, arrays, callees, cursors;
  Array definitions;
  String own;
  List on_break, on_continue;
  int declined, on_loop, in_loop, rejected, uncallable, globals, meta_only;
} *Lowering;

/* Why the last lowering declined, for the diagnostic at the invocation, and
   the callee that has no compile-time binding when that is the reason. */
static String lower_declined_reason;
static String lower_missing_callee;

/* Whether the last lowering reached file-scope state, directly or through a
   callee that does. The compile-time form reads its own `C._globals`, which
   no unit initializer writes, so the two forms of such a function answer
   differently and a call to it cannot be folded. */
static int lower_reached_globals;

/* Whether the last lowering reached a `Meta` operation, directly or through a
   callee that does. Those operations exist only inside a compiler, so such a
   function has no valid runtime form: the unit emits no definition for it and
   a call to it is never folded. */
static int lower_reached_meta;

/* The callee names the last successful lowering resolved through the macro
   session, which is the only unit-dependent input it had. */
static List lower_session_callees;

/* --- names ------------------------------------------------------------- */

/* `Atom.intern` gives an `lsym` for a spelling too long to pack into a
   Symbol, so a generated name is readable and cannot collide by truncation.

   A loop becomes a session global, and every function shares one session, so
   a counter that restarted with each function made two functions of the same
   shape define the same loop and the second silently replaced the first. The
   counter runs across the session, which makes the name unique on its own;
   the function it belongs to follows, which makes the lowered Lisp readable
   when something goes wrong. */
static int lower_counter;

static Var _lower_name(Lowering l, String stem) {
  lower_counter++;
  if (!l.own) return Atom.intern(%"$stem${lower_counter}");
  return Atom.intern(%"$stem${lower_counter}-${l.own}");
}

/* --- a dynamic Func call ------------------------------------------------ */

static Var _lower_decline(Lowering l, String why);

/* `f(x)` is not a call in the AST. `_resolve_func_call` in
   `src/expressions.x` expands it into a statement expression that stores the
   callee once, queries a reference carrier per argument through
   `x2c_func_reference_type`, boxes each argument into a `FuncArg`, and
   reaches `Func_apply` last. None of that has a compile-time meaning: a
   `Func` here is the Lisp lambda this pass lowered, and a Lisp lambda takes
   its arguments by value, so the expansion collapses back to the application
   it stands for. Only the callee and each argument's value form survive.

   The reference branch is dropped rather than lowered. A `Func` whose
   signature declares a reference parameter would take that branch at run
   time and its value branch at compile time, so the two forms of a `meta`
   function disagree there; every `Func` a compile-time session can produce
   is a lowered lambda over values, where they agree.

   One recognition serves the scan as well, which needs it: scanning the
   expansion would read the reference branch's `&argument` as an
   address-taken local and put an ordinary parameter in a cell, and would
   refuse the function over the four callees the expansion names. The
   argument count `Func_apply` receives cross-checks the groups this found,
   so a block of another shape answers nothing rather than a truncated call.

   An argument whose type has no `Var` tag is boxed by
   `x2c_func_unrepresentable_argument` instead, and cannot cross to the
   compile-time form at all. That is refused here, where the reason is still
   plain: the scan runs first, and reading the expansion instead would report
   whichever of its callees the session happens not to bind. */

/* The argument one group boxes by value, or nothing where that stand-in
   took its place. */
static Var _lower_func_value(Var boxed) {
  match (boxed)
    case %(expr ("FuncArg")
           (call (expr ? (ident (binding ? "FuncArg_value"))) (args ?value))):
      return value;
  return void;
}

static List _lower_func_block(Lowering l, List body) {
  Array parts = [];
  defer parts.free();
  if (!body) return NULL;
  match (body.car())
    case %(declare ("Func") (bindings (op = (bind ? ()) ?callee))):
      parts.push(callee);
  if (!parts.len()) return NULL;
  List rest = body.cdr();
  for (; rest && rest.cdr(); rest = rest.cdr())
    match (rest.car())
      case %(if ? ? (stmnt (expr ("FuncArg") (op = ? ?boxed)))): {
        Var value = _lower_func_value(boxed);
        if (value is void) {
          (void) _lower_decline(
            l, "a dynamic Func call whose argument has a type with no "
               "compile-time representation");
          return NULL;
        }
        parts.push(value);
      }
  if (!rest) return NULL;
  match (rest.car())
    case %(stmnt (expr ?
                  (call (expr ? (ident (binding ? "Func_apply")))
                        (args ? (expr ? (literal ? ?(String count))) ?)))): {
      long arity;
      if (!count.try_long(&arity) || arity != parts.len() - 1) return NULL;
      return parts;
    }
  return NULL;
}

/* The callee followed by the argument values, or nothing where this is not a
   dynamic `Func` call. A call with no arguments needs no locals, so
   `_resolve_func_call` returns the bare `Func_apply` for it. */
static List _lower_func_parts(Lowering l, Var content) {
  match (content) {
    case %(parens (block *body)): return _lower_func_block(l, body);
    case %(call (expr ? (ident (binding ? "Func_apply")))
                (args ?callee (expr ? (literal ? "0"))
                      (expr ? (ident (binding ? "NULL"))))):
      return %($callee);
  }
  return NULL;
}

/* --- the single scan --------------------------------------------------- */

static void _lower_scan(Lowering l, Var form);
static Var _lower_decline(Lowering l, String why);

static void _lower_scan_each(Lowering l, List items) {
  foreach (Var item, items) _lower_scan(l, item);
}


/* The `foreach` over a `List` that `foreach.cursor-loop` expands to, whose
   test steps a cursor and writes an element through two pointers. Answers
   the two locals it addresses, so the lowering can walk the list itself
   instead: the cursor is the list that remains and the element is its head,
   neither of which needs a cell. */
static int _lower_list_cursor(Var test, int *cursor, int *item) {
  match (test)
    case %(expr ? (call (expr ? (ident (binding ? "List_try_next")))
                        (args ?
                          (expr ? (op & (expr ? (ident (binding ?(int c) ?)))))
                          (expr ? (op & (expr ? (ident (binding ?(int i) ?)))))
                        ))): {
      *cursor = c;
      *item = i;
      return 1;
    }
  return 0;
}

/* Address-of is the one-operand `&`; three operands is bitwise and.

   A local whose address is taken has to live somewhere a pointer can reach,
   which is a cell. An ordinary assignment does not, even on a loop's
   iteration path and even when its value comes from a call: the binding it
   needs is an immediately applied lambda, and the lowering puts one of those
   in the frame's own slots. */
static void _lower_scan_op(Lowering l, List form) {
  match (form) {
    case %(op & (expr ? (ident (binding ?(int id) ?)))): {
      if (!l.cursors.contains(id)) l.cells[id] = 1;
      return;
    }
  }
}

static void _lower_scan_bind(Lowering l, List form) {
  match (form) {
    /* A local C array is a mutable buffer, so it lives in a cell the way an
       address-taken local does, holding an `Array` of its declared size. */
    case %(bind (binding ?(int id) ?) ((dim ?size) *)): {
      l.locals[id] = 1;
      l.cells[id] = 1;
      l.arrays[id] = size;
      return;
    }
    case %(bind (binding ?(int id) ?) *): l.locals[id] = 1;
  }
}

/* A destructuring declaration names its targets directly rather than through
   `bind`, so this is where they join the locals. Without them a later write
   would read as file-scope state. */
static void _lower_scan_targets(Lowering l, List targets) {
  foreach (List target, targets)
    match (target) case %(binding ?(int id) ?): l.locals[id] = 1;
}

/* A callee is reachable when the macro session already binds its name: a
   native from `etc/comptime.xlisp`, or a function this pass installed. The
   function being lowered is reachable from itself, because the definition
   binds its name before anything calls it. */
static int _lower_known(Lowering l, String name) {
  Var value;
  if (l.own && l.own.equal(name)) return 1;
  if (!l.compiler.macro_lisp.try_get(name, &value)) return 0;
  l.callees[name] = 1;
  return 1;
}

/* The Lisp spelling of the compiler operation an x2c name stands for. The
   rule is mechanical, each `_` after the prefix becoming a `.`, and these
   four rows are the whole exception list: two Lisp names carry a hyphen, and
   two operations need an adapter, one to spread a rest parameter and one to
   answer an `int` where Lisp answers a truth value. */
static String _lower_operation_name(String name) {
  if (name == "x2c_expr_call")         return "_x2c.expr.call-list";
  if (name == "x2c_type_value")        return "_x2c.type.value-int";
  if (name == "x2c_type_tag_name")     return "x2c.type.tag-name";
  if (name == "x2c_type_reverse_name") return "x2c.type.reverse-name";
  return name.replace("_", ".");
}

/* Whether a callee names a compiler operation rather than a function this
   translation has. `lib/meta.x` declares the surface as `x2c_*` prototypes
   with no body, so a name with no definition whose Lisp operation the session
   binds is one. A prefix does not decide it: give one of those declarations a
   `meta` body and the body is found first, below. */
static int _lower_compiler_operation(Lowering l, String name) {
  if (!name.startswith("x2c_")) return 0;
  Var value;
  return l.compiler.macro_lisp.try_get(_lower_operation_name(name), &value);
}

/* The name a lowered call names in Lisp. A definition wins over the compiler
   surface, so this maps only what the session cannot answer directly. */
static String _lower_callee_name(Lowering l, String name) {
  Var value;
  if (l.own && l.own.equal(name)) return name;
  if (l.compiler.macro_lisp.try_get(name, &value)) return name;
  if (_lower_compiler_operation(l, name)) return _lower_operation_name(name);
  return name;
}

/* A callee this pass already installed carries its own reach to file-scope
   state and to the compiler surface, so the caller inherits both. A callee is
   always installed first: the scan refuses a name the session does not
   bind. */
static void _lower_scan_callee(Lowering l, String name) {
  if (!_lower_known(l, name)) {
    if (_lower_compiler_operation(l, name)) {
      l.meta_only = 1;
      return;
    }
    l.uncallable = 1;
    lower_missing_callee = name;
    return;
  }
  if (l.compiler.meta_impure.contains(name)) l.globals = 1;
  if (l.compiler.meta_comptime.contains(name)) l.meta_only = 1;
}

/* A function named where a value is wanted rather than called: `Func f = g;`
   or `g` handed to an operation that calls it. The scan sees no `call`, so
   this is where that callee is established, and it carries the same reach as
   a call to it would. A local of function-pointer type holds a value rather
   than naming a definition. */
static void _lower_scan_function_value(Lowering l, List form) {
  match (form)
    case %(expr ((func *) *) (ident (binding ?(int id) ?(String name)))): {
      if (!l.locals.contains(id)) _lower_scan_callee(l, name);
    }
}

static void _lower_scan_call(Lowering l, List form) {
  match (form) {
    case %(call (expr ? (ident (binding ? ?(String name)))) ?): {
      _lower_scan_callee(l, name);
      return;
    }
    case %(call ?(String name) ?): {
      _lower_scan_callee(l, name);
      return;
    }
  }
  l.uncallable = 1;
}

/* A struct has no compile-time representation. Making one a `Map` keyed by
   field name would give a value reference semantics, so a declaration and a
   field read are both refused here, where the reason is still plain. */
static int _lower_scan_aggregate(List items) {
  match (items) {
    case %(declare (!or (struct *) (union *)) *): return 1;
    case %(op . ? *):                             return 1;
  }
  return 0;
}

/* Everything the lowering needs before it starts, in one pass: which locals
   need a memory cell, which are arrays, which ids the function declares,
   whether it uses a construct the substitution cannot carry, and whether
   every callee has a compile-time binding. */
static void _lower_scan(Lowering l, Var form) {
  if (form is not <list>) return;
  List items = form;
  if (!items) return;
  /* A dynamic `Func` call is scanned as the application it stands for, so
     the machinery its expansion names is never read. */
  List application = _lower_func_parts(l, items);
  if (application) {
    _lower_scan_each(l, application);
    return;
  }
  Var head = items.car();
  /* Both of these refuse the function outright, so the scan stops rather
     than reporting what the refused statement happens to call. */
  if (head == <defer>) {
    (void) _lower_decline(
      l, "defer, because a compile-time function does not free its "
         "values: the evaluator owns them");
    return;
  }
  if (_lower_scan_aggregate(items)) {
    (void) _lower_decline(
      l, "a struct or union, which has no compile-time representation");
    return;
  }
  if (head == <while> || head == <for> || head == <do>) {
    int was = l.in_loop;
    l.in_loop = 1;
    match (items) case %(while ?test ?): {
      int cursor = 0, item = 0;
      if (_lower_list_cursor(test, &cursor, &item)) {
        l.cursors[cursor] = 1;
        l.cursors[item] = 1;
      }
    }
    _lower_scan_each(l, items);
    l.in_loop = was;
    return;
  }
  if (head == <bind>) _lower_scan_bind(l, items);
  else if (head == <targets>) _lower_scan_targets(l, items.cdr());
  else if (head == <op>) _lower_scan_op(l, items);
  else if (head == <call>) _lower_scan_call(l, items);
  else if (head == <expr>) _lower_scan_function_value(l, items);
  else if (head == <goto>) l.rejected = 1;
  _lower_scan_each(l, items);
}

/* --- declining ---------------------------------------------------------- */

static Var _lower_decline(Lowering l, String why) {
  if (!l.declined) {
    l.declined = 1;
    lower_declined_reason = why;
  }
  return void;
}

static int _lower_failed(Lowering l, Var value) =>
  l.declined || value is void;

/* --- environment -------------------------------------------------------- */

/* A name the function never declares is file-scope state. Its value is not
   substitutable, because a write between two reads changes it, so a read
   stays a read. */
static Var _lower_read(Lowering l, int id) {
  Var form;
  if (l.env.try_get(id, &form)) return form;
  if (!l.locals.contains(id)) {
    l.globals = 1;
    return %(C.gread $id);
  }
  return _lower_decline(l, "unbound local");
}

/* The value a local holds. A cell's slot is its box, so reading one loads
   through it; every other slot already is the value. */
static Var _lower_value(Lowering l, int id) {
  Var slot = _lower_read(l, id);
  if (_lower_failed(l, slot)) return void;
  if (l.cells.contains(id)) return %(C.load $slot);
  return slot;
}

/* --- literals ----------------------------------------------------------- */

/* A hexadecimal spelling carries `e` and `E` as digits, so the exponent
   test has to skip it: `0x000E` is fourteen, not a floating literal. */
static Var _lower_number(Lowering l, List type, String text) {
  long integer;
  double floating;
  int hex = text.startswith("0x") || text.startswith("0X");
  if (type.match(%((!or double float))) ||
      (!hex && (text.contains(".") ||
                text.contains("e") || text.contains("E")))) {
    if (text.try_double(&floating)) return floating;
    return _lower_decline(l, "unreadable floating literal");
  }
  if (text.try_long(&integer)) {
    if (integer == (int) integer) return (int) integer;
    return integer;
  }
  return _lower_decline(l, "unreadable integer literal");
}

/* A String literal arrives as its source spelling, quotes included. */
/* `*` is a sequence binder in a pattern, so the `(* char)` that selects a C
   string also matches a plain `(char)`. The spelling settles it: a string
   carries its double quote and a character literal its single quote, and a
   character is its code, not its text. */
static Var _lower_text(String spelling) {
  int len = spelling.len();
  if (len >= 2 && spelling[0] == '"')
    return String.new_len(spelling + 1, len - 2).unescape();
  if (len >= 3 && spelling[0] == '\'') {
    String body = String.new_len(spelling + 1, len - 2).unescape();
    return body.len() ? body[0] : 0;
  }
  return spelling;
}

/* --- folded constants --------------------------------------------------- */

/* Literal folding hoists a constant `List`, `String` or `Var` into the
   compiler cache and leaves `(cache ID)` behind, so a `match` pattern and a
   template's constant head are not visible in the syntax. The cache is a
   graph of ids over `cons`, `var` and `string` leaves. */
static Var _lower_constant(Lowering l, Var node);

static Var _lower_constant_leaf(Lowering l, List value) {
  match (value) {
    case %(expr ? (!set ?node (cache ?))):      return _lower_constant(l, node);
    case %(expr ? (!set ?node (expr ? (cache ?)))):
      return _lower_constant(l, node);
    case %(expr ? (nil)):                       return %();
    case %(expr ? (expr ? (nil))):              return %();
    case %(expr ? (literal ? ? ?symbol)): return symbol;
    case %(expr ("String") (call ? (args ?inner))):
      return _lower_constant_leaf(l, inner);
    case %(expr ("String") (literal ? ?(String text))): return text;
    case %(expr (* char) (literal ? ?(String text))): return _lower_text(text);
    case %(expr ?type (literal ? ?(String text))):
      return _lower_number(l, type, text);
  }
  /* Folding leaves an expression in place when the value is only known at
     run time, as a pattern that interpolates a local does. There is no
     compile-time value to read back, so the caller declines rather than
     treating the unfolded node as data. */
  if (value && value.car() == <expr>) return void;
  return value;
}

static Var _lower_constant(Lowering l, Var node) {
  match (node) {
    case %(cache ?(int id)): {
      List key = l.compiler.id_keys[id];
      match (key) {
        case %(cons ?head ?tail):
          return cons(_lower_constant(l, head), _lower_constant(l, tail));
        case %(var ?value):    return _lower_constant_leaf(l, value);
        case %(string ?value): return _lower_constant_leaf(l, value);
        case %(nil): return %();
      }
      return key;
    }
    case %(cons ?head ?tail):
      return cons(_lower_constant(l, head), _lower_constant(l, tail));
    case %(nil): return %();
  }
  return _lower_constant_leaf(l, node);
}

/* A local whose address is taken lives in a cell: one box allocated at its
   declaration, read with `C.load` and written with `C.store`. Taking its
   address yields the box, so an out-parameter is an ordinary argument. */
static Var _lower_address(Lowering l, int id) {
  Var slot;
  if (!l.env.try_get(id, &slot))
    return _lower_decline(l, "address of an unknown local");
  return slot;
}

/* An interpolated string joins its parts; each part already carries the
   conversion the type needs. */
static Var _lower_segments(Lowering l, List parts) {
  Array values = [];
  foreach (List part, parts) {
    Var inner = part;
    match (part) case %(!or (segvar ?node) (segexp ?node)): inner = node;
    Var value = _lower_expr(l, inner);
    if (_lower_failed(l, value)) {
      values.free();
      return void;
    }
    values.push(value);
  }
  return cons(Atom.intern("string-append"), values.list_free());
}

/* A folded constant used as a value. */
static Var _lower_quoted(Lowering l, Var node) {
  Var value = _lower_constant(l, node);
  if (value is void) return _lower_decline(l, "a constant did not fold");
  return %(quote $value);
}

/* --- expressions -------------------------------------------------------- */

static Var _lower_expr(Lowering l, Var form);
static Var _lower_coerce(List want, Var node, Var value);

/* The type an expression node carries, or nothing for a node that is not
   one. An lvalue names the type its store converts to. */
static Type _lower_type_of(Var node) {
  match (node) case %(expr ?type ?): return type;
  return NULL;
}

/* A value reaching a C scalar type carries that type's `Var` tag, which is
   what makes every later operation behave the way C does: `Var.binary`
   applies the usual arithmetic conversions from the operand tags, so
   unsigned division and comparison, narrow wraparound and the signed shift
   all follow from the destination types the author wrote. `Var.convert` is
   the conversion itself - integer narrowing keeps low bits, floating to
   integer truncates toward zero, and an integer reaching a floating type
   widens - so this pass names a tag and performs no arithmetic of its own.
   A type with no scalar tag, a pointer or a library type, keeps its value. */
static Var _lower_to_type(Type want, Var value) {
  Symbol tag = want.scalar_tag();
  if (!tag) return value;
  return %(C.conv $value (quote $tag));
}

/* The parameter type at one argument's position, or nothing where the callee
   declares none: a variadic tail, or a call the compiler constructed. The two
   spellings are the ones `_typed_call` aligns its conversions against. */
static List _lower_param_type(List params) {
  if (!params) return NULL;
  List param = params.car();
  if (param && param.car() == <param>) return param.type_from_ast();
  return param;
}

static List _lower_args(Lowering l, List params, List args) {
  Array values = [];
  defer values.free();
  for (List p = params, a = args; a; p = p.cdr(), a = a.cdr()) {
    List argument = a.car();
    match (argument) case %(expr (void) ()): continue;
    Var value = _lower_expr(l, argument);
    if (_lower_failed(l, value)) return NULL;
    values.push(_lower_coerce(_lower_param_type(p), argument, value));
  }
  return values;
}

/* A call is a direct Lisp call: the callee's name is a session global, so
   the lowered code pays a lookup and nothing more. Its type carries the
   parameter types the arguments have to reach, and carries none where the
   compiler constructed the call itself. */
static Var _lower_call(Lowering l, List callee, String name, List args) {
  List params = NULL;
  match (callee) case %((func ?declared) *): params = declared;
  List values = _lower_args(l, params, args);
  if (l.declined) return void;
  return cons(Atom.intern(_lower_callee_name(l, name)), values);
}

/* The application a dynamic `Func` call stands for. The callee is an
   expression rather than a name, which the evaluator applies the way it
   applies a lambda this pass already puts in head position. The scan reached
   this form first and kept whatever reason it refused for; the decline here
   only answers a statement expression no producer writes today. */
static Var _lower_application(Lowering l, Var content) {
  List parts = _lower_func_parts(l, content);
  if (!parts) return _lower_decline(l, "not a dynamic Func call");
  Array values = [];
  defer values.free();
  foreach (List part, parts) {
    Var value = _lower_expr(l, part);
    if (_lower_failed(l, value)) return void;
    values.push(value);
  }
  return values.list();
}

/* `Var.binary` applies the usual arithmetic conversions itself for the
   arithmetic operators, so only a comparison needs them written out: `==`
   and `!=` compare `Var` identity there, which 1.0 and 1 fail, and the
   relations compare the values as written rather than as C converts them,
   so a negative signed operand does not become the large unsigned one C
   makes of it. */
static int _lower_relation(Var operator) =>
  operator == <==> || operator == <!=> || operator == <"<"> ||
  operator == <"<="> || operator == <">"> || operator == <">=">;

/* Whether two operands are scalars of different families. An equal pair,
   which is nearly every pair, needs no conversion and is left alone. */
static int _lower_mixed_scalars(List operands) {
  if (operands.len() != 2) return 0;
  Type left = _lower_type_of(operands.car());
  Type right = _lower_type_of(operands.cadr());
  Symbol a = left.scalar_tag(), b = right.scalar_tag();
  return a && b && a != b;
}

static Var _lower_operands(Lowering l, Var operator, List operands) {
  Array values = [];
  defer values.free();
  foreach (Var operand, operands) {
    Var value = _lower_expr(l, operand);
    if (_lower_failed(l, value)) return void;
    values.push(value);
  }
  if (values.len() == 1) {
    Var only = values[0];
    if (operator == <->) return %(_binary 0 (quote <->) $only);
    if (operator == <+>) return only;
    if (operator == <~>) return %(_binary -1 (quote <^>) $only);
    if (operator == <!>) return %(C.not $only);
    return _lower_decline(l, "unsupported unary operator");
  }
  if (values.len() == 2) {
    Var left = values[0], right = values[1];
    if (operator == <&&>) return %(C.and $left $right);
    if (operator == <||>) return %(C.or $left $right);
    if (_lower_relation(operator) && _lower_mixed_scalars(operands))
      return %(C.compare $left (quote $operator) $right);
    return %(_binary $left (quote $operator) $right);
  }
  if (values.len() == 3) {
    Var test = values[0], a = values[1], b = values[2];
    return %(C.ternary $test $a $b);
  }
  return _lower_decline(l, "unsupported operator arity");
}

/* A lambda's free locals are substituted, which is the by-value snapshot
   x2c gives a captured scalar. Its parameters get fresh slots. */
static Var _lower_lambda(Lowering l, List params, List held, Var body) {
  Array names = [];
  defer names.free();
  Array saved = [];
  defer saved.free();
  foreach (List capture, held) {
    match (capture)
      case %(capture (binding ?(int id) ?) ? ?source): {
        Var value = _lower_expr(l, source);
        if (_lower_failed(l, value)) return void;
        saved.push(%($id $value));
      }
  }
  /* A declared parameter carries its type; a bare one is the binding
     itself, which the book documents as a `Var`. Both name a local. */
  foreach (List parameter, params) {
    int id = 0, int named = 0;
    match (parameter) {
      case %(param ? (bind (binding ?(int declared) ?) *)): {
        id = declared;
        named = 1;
      }
      case %(binding ?(int bare) ?): {
        id = bare;
        named = 1;
      }
    }
    if (!named) continue;
    Var slot = _lower_name(l, "arg");
    names.push(slot);
    saved.push(%($id $slot));
  }
  Array shadowed = [];
  defer shadowed.free();
  Map previous = {};
  defer previous.cleanup();
  foreach (List pair, saved) {
    Var (id, value) = pair;
    Var was;
    if (l.env.try_get(id, &was)) previous[id] = was;
    shadowed.push(id);
    l.env[id] = value;
  }
  Var lowered = _lower_expr(l, body);
  foreach (Var id, shadowed) {
    Var was;
    if (previous.try_get(id, &was)) l.env[id] = was;
    else l.env.del(id);
  }
  if (_lower_failed(l, lowered)) return void;
  return %(lambda ${names.list()} $lowered);
}

/* --- collections -------------------------------------------------------- */

/* A container operation is chosen by the receiver's own type, which the type
   pass already put on its `expr` node. */
static String _lower_container(List type) {
  if (type.equal(%("List")))   return "List";
  if (type.equal(%("Array")))  return "Array";
  if (type.equal(%("Map")))    return "Map";
  if (type.equal(%("String"))) return "String";
  return NULL;
}

/* A declared local starts at its type's zero. The two branches cannot share
   a conditional expression: C would promote the `int` to `double` and every
   uninitialized local would come back floating. */
static Var _lower_zero(List type) {
  if (type.match(%((!or double float)))) return 0.0;
  return 0;
}

/* The caller owns the result and frees it, or hands it to `_lower_sequence`.
   Failure is reported through `declined`, because an empty Array is a
   legitimate result and is falsy. */
static Array _lower_values(Lowering l, List items) {
  Array values = [];
  foreach (Var item, items) {
    Var value = _lower_expr(l, item);
    if (_lower_failed(l, value)) {
      values.free();
      _lower_decline(l, "an element that is not an expression");
      return NULL;
    }
    values.push(value);
  }
  return values;
}

/* Elements as a Lisp List, which is what every container is built from. */
static Var _lower_sequence(Lowering l, List items) {
  Array values = _lower_values(l, items);
  if (l.declined) return void;
  return cons(<list>, values.list_free());
}

/* `[a, b]` is an array literal wherever it appears, including an argument
   position where no destination names a type, so it lowers to an `Array`
   and a `List` destination converts. Lowering it to a Lisp List instead
   would hand an argument the wrong container without saying so. */
static Var _lower_array(Lowering l, List items) {
  Var values = _lower_sequence(l, items);
  if (_lower_failed(l, values)) return void;
  return %(List_array $values);
}

static Var _lower_map(Lowering l, List entries) {
  Array flat = [];
  foreach (List entry, entries) {
    match (entry)
      case %(map-entry ?key ?value): {
        Var k = _lower_expr(l, key);
        Var v = _lower_expr(l, value);
        if (_lower_failed(l, k) || _lower_failed(l, v)) {
          flat.free();
          return void;
        }
        flat.push(k);
        flat.push(v);
        continue;
      }
    flat.free();
    return _lower_decline(l, "unsupported map entry");
  }
  return %(Map_of ${cons(<list>, flat.list_free())});
}

/* The container a bracket names. A local C array is always an `Array`,
   because its declaration allocated one; every other receiver carries its
   own type. */
static String _lower_indexed(Var receiver, int is_c_array) {
  if (is_c_array) return "Array";
  match (receiver) case %(expr ?type ?): return _lower_container(type);
  return NULL;
}

/* `xs[i]` and `m[k]`. The C-array form is the same read through the cell the
   declaration allocated, which `_lower_expr` already loads. */
static Var _lower_getindex(
  Lowering l, Var receiver, Var key, int is_c_array) {
  String container = _lower_indexed(receiver, is_c_array);
  if (!container)
    return _lower_decline(l, "indexing a type with no compile-time meaning");
  Var target = _lower_expr(l, receiver);
  Var index = _lower_expr(l, key);
  if (_lower_failed(l, target) || _lower_failed(l, index)) return void;
  return %(${Atom.intern(container + "_getindex")} $target $index);
}

/* One `match` over the expression grammar. The compiler turns it into a
   decision tree, so reading the productions costs nothing extra. */
static Var _lower_expr(Lowering l, Var form) {
  if (l.declined) return void;
  match (form) {
    case %(at ? ?node):                   return _lower_expr(l, node);
    case %(expr ?type ?content):          return _lower_content(l, type, content);
    /* A literal template builds its List with `cons`, and folding replaced
       only its constant parts, so each part is lowered as an expression. */
    case %(cons ?head ?tail):
      return %(cons ${_lower_expr(l, head)} ${_lower_expr(l, tail)});
    case %(append ?head ?tail):
      return %(append ${_lower_expr(l, head)} ${_lower_expr(l, tail)});
    case %(nil):     return %(quote ());
    case %(cache ?): return _lower_quoted(l, form);
  }
  return _lower_decline(l, "not an expression");
}

static Var _lower_content(Lowering l, List type, Var content) {
  match (content) {
    case %(literal ("Symbol") ? ?symbol): return %(quote $symbol);
    /* x2c `void` has no Lisp counterpart; nil is the falsy stand-in, so a
       lowered function cannot tell `void` from an empty List. */
    case %(literal ("Var") "void"): return %(quote ());
    case %(literal (* char) ?(String text)):
      return _lower_text(text);
    case %(literal ("String") ?(String text)): return text;
    case %(literal ?ltype ?(String text)):
      return _lower_number(l, ltype, text);
    case %(literal ?ltype ?(String text) ?):
      return _lower_number(l, ltype, text);
    case %(segments *parts):              return _lower_segments(l, parts);
    /* A function named where a value is wanted is the Lisp definition this
       pass installed, and its own name names it. The scan established that
       the session binds it. */
    case %(ident (binding ?(int id) ?(String name))): {
      if (!l.locals.contains(id) && type.match(%((func *) *)))
        return Atom.intern(name);
      /* An enumerator's value lives only in the enum declaration it was
         written in: the symbol table records the enum type and that the name
         is an enumerator, never the number. Reading it as file-scope state
         answered zero, which is a wrong value rather than a refusal. */
      Type named = type;
      if (!l.locals.contains(id) && named.is_enum())
        return _lower_decline(l, "an enum constant has no compile-time value");
      return _lower_value(l, id);
    }
    case %(parens (block *)):             return _lower_application(l, content);
    case %(parens ?inner):                return _lower_expr(l, inner);
    /* A cast is a conversion the author wrote, and the type it names is the
       one the surrounding `expr` node already carries. */
    case %(cast ? ?inner): {
      Var value = _lower_expr(l, inner);
      if (_lower_failed(l, value)) return void;
      return _lower_coerce(type, inner, value);
    }
    case %(expr ?inner ?within):          return _lower_content(l, inner, within);
    case %(at ? ?node):                   return _lower_content(l, type, node);
    case %(op & (expr ? (ident (binding ?(int id) ?)))):
      return _lower_address(l, id);
    /* `*` is a sequence binder in a pattern, so a unary deref is matched by
       arity and then by its operator. */
    case %(op ?operator ?operand): {
      if (operator == <"*">) return %(C.load ${_lower_expr(l, operand)});
      return _lower_operands(l, operator, %($operand));
    }
    case %(call (expr ? (ident (binding ? "Func_apply"))) ?):
      return _lower_application(l, content);
    case %(call (expr ?callee (ident (binding ? ?(String name))))
                (args *args)):
      return _lower_call(l, callee, name, args);
    case %(call ?(String name) (args *args)):
      return _lower_call(l, NULL, name, args);
    case %(op ?operator *operands):
      return _lower_operands(l, operator, operands);
    case %(array *items):                 return _lower_array(l, items);
    case %(map *entries):                 return _lower_map(l, entries);
    case %(getindex ?receiver ?key):
      return _lower_getindex(l, receiver, key, 0);
    case %(index ?receiver ?key):
      return _lower_getindex(l, receiver, key, 1);
    case %(postfix ? ?): return _lower_decline(l, "postfix in an expression");
    case %(lambda (params *params) (captures *held) ?body):
      return _lower_lambda(l, params, held, body);
    case %(lambda (params *params) ?body):
      return _lower_lambda(l, params, %(), body);
    case %(cons ?head ?tail):
      return %(cons ${_lower_expr(l, head)} ${_lower_expr(l, tail)});
    case %(append ?head ?tail):
      return %(append ${_lower_expr(l, head)} ${_lower_expr(l, tail)});
    case %(nil):     return %(quote ());
    case %(cache ?): return _lower_quoted(l, content);
  }
  return _lower_decline(l, "unsupported expression");
}

/* --- statements --------------------------------------------------------- */

/* The continuation after a block is data, not a closure: either the end of
   the function, or one more turn of the loop it sits inside. */
static Var _lower_block(Lowering l, List items, List k);

static Map _lower_env_copy(Lowering l) {
  Map copy = {};
  foreach (Var (id, form), l.env) copy[id] = form;
  return copy;
}

static void _lower_env_restore(Lowering l, Map saved) {
  l.env = saved;
}

static Var _lower_apply_k(Lowering l, List k) {
  match (k) {
    case %(end): return 0;
    /* Statements to run before the continuation they were given: a loop's
       step, or the block a `switch` exits into. Inlining them keeps the
       `again` that may follow a direct self call. They carry the `break`
       that was in force where they were written, because a step belongs to
       its loop however deep inside the body the continuation is reached. */
    case %(then ?(List steps) ?(List next) ?(List breaking)): {
      List was = l.on_break;
      l.on_break = breaking;
      Var result = _lower_block(l, steps, next);
      l.on_break = was;
      return result;
    }
    case %(again ?name (*ids)): {
      Array values = [];
      defer values.free();
      values.push(name);
      foreach (Var id, ids) {
        Var value = _lower_read(l, id);
        if (_lower_failed(l, value)) return void;
        values.push(value);
      }
      return values.list();
    }
  }
  return _lower_decline(l, "unknown continuation");
}

/* nil is the only false value in Lisp, so a C zero has to be compared.
   `C.true?` owns that comparison for every family: an inlined `(eq? v 0)`
   here answered true for a `double` zero, because a boxed 0.0 is not the
   `int` 0 that `eq?` tests. */
static Var _lower_truth(Lowering l, Var test) {
  Var value = _lower_expr(l, test);
  if (_lower_failed(l, value)) return void;
  return %(C.true? $value);
}

/* Substitution duplicates an expression at every read, so a value that
   cannot be duplicated is bound instead. A binding costs one lambda, which
   is free once per entry and fatal once per iteration, so on a loop's path
   the function is declined. */
static int _lower_pure(Var form) {
  if (form is not <list>) return 1;
  List items = form;
  if (!items) return 1;
  Var head = items.car();
  if (head == <C.gread> || head == <C.load> || head == <C.cell> ||
      head == <lambda>)
    return 0;
  if (head is <lsym> || head is <symbol>) {
    String spelling = head.str();
    if (spelling && !spelling.startswith("C.") && !spelling.startswith("_") &&
        spelling != "quote" && spelling != "not" && spelling != "eq?")
      return 0;
  }
  foreach (Var part, items) if (!_lower_pure(part)) return 0;
  return 1;
}

static Var _lower_bind_value(
  Lowering l, int id, Var value, List rest, List k) {
  if (_lower_failed(l, value)) return void;
  if (_lower_pure(value)) {
    Var previous = void;
    l.env.try_get(id, &previous);
    l.env[id] = value;
    return _lower_block(l, rest, k);
  }
  Var slot = _lower_name(l, "hold");
  l.env[id] = slot;
  Var after = _lower_block(l, rest, k);
  if (_lower_failed(l, after)) return void;
  return %((lambda ($slot) $after) $value);
}

/* An effect runs on a `cond` test that always fails, which keeps the rest
   of the block in tail position and introduces no binding form. */
static Var _lower_effect(Lowering l, Var effect, List rest, List k) {
  Var after = _lower_block(l, rest, k);
  if (_lower_failed(l, after)) return void;
  return %(cond ((begin $effect false) ()) (true $after));
}

static Var _lower_stmnt(Lowering l, Var form, List rest, List k);

/* --- match -------------------------------------------------------------- */

/* A binder is an atom spelled `?name` or `*name`; a bare `?` or `*` is a
   wildcard and names nothing. */
static int _lower_binder(Var value, String *name) {
  if (!value.is_atom()) return 0;
  String spelling = value.str();
  if (!spelling || spelling.len() < 2) return 0;
  if (spelling[0] != '?' && spelling[0] != '*') return 0;
  if (name) *name = String.new_len(spelling + 1, spelling.len() - 1);
  return 1;
}

static void _lower_binders(Var pattern, Array found) {
  if (pattern is <list>) {
    List items = pattern;
    foreach (Var part, items) _lower_binders(part, found);
    return;
  }
  if (_lower_binder(pattern, NULL)) found.push(pattern);
}

/* The compiler bound each `?name` to an ordinary local, so the arm's body
   refers to it by binding id. Those ids are what the environment needs. */
static void _lower_arm_ids(Var form, String name, Array found) {
  if (form is not <list>) return;
  List items = form;
  if (!items) return;
  match (items)
    case %(binding ?(int id) ?(String spelling)): {
      if (spelling == name) found.push(id);
      return;
    }
  foreach (Var part, items) _lower_arm_ids(part, name, found);
}

/* A `case` pattern was folded into the compiler cache, so it reads back as
   the List the source wrote and goes straight to the matcher. A binder
   repeats the match rather than naming its result: matching is pure, and an
   arm free of a binding form stays usable on a loop's iteration path. */
static Var _lower_arms(
  Lowering l, Var subject, List arms, List rest, List k) {
  if (!arms) return _lower_block(l, rest, k);
  List arm = arms.car();
  Var pattern = _lower_constant(l, arm.car());
  if (pattern is void) return _lower_decline(l, "case pattern is not folded");
  Var value = _lower_expr(l, subject);
  if (_lower_failed(l, value)) return void;
  Var result = %(match $value (quote $pattern));
  Array binders = [];
  defer binders.free();
  _lower_binders(pattern, binders);
  Map saved = _lower_env_copy(l);
  foreach (Var binder, binders) {
    String name = NULL;
    _lower_binder(binder, &name);
    Array ids = [];
    defer ids.free();
    _lower_arm_ids(arm.cadr(), name, ids);
    foreach (Var id, ids) l.env[id] = %(bound $result (quote $binder));
  }
  Var taken = _lower_block(l, %(${arm.cadr()} @rest), k);
  _lower_env_restore(l, saved);
  if (_lower_failed(l, taken)) return void;
  Map second = _lower_env_copy(l);
  Var other = _lower_arms(l, subject, arms.cdr(), rest, k);
  _lower_env_restore(l, second);
  if (_lower_failed(l, other)) return void;
  return %(cond ($result $taken) (true $other));
}

/* Both arms continue with the same remaining statements, so the rest of the
   block appears in each. `cond` keeps every path in tail position. */
static Var _lower_branch(
  Lowering l, Var test, List then, List alt, List rest, List k) {
  Var guard = _lower_truth(l, test);
  if (_lower_failed(l, guard)) return void;
  Map saved = _lower_env_copy(l);
  Var taken = _lower_block(l, %(@then @rest), k);
  _lower_env_restore(l, saved);
  if (_lower_failed(l, taken)) return void;
  Map second = _lower_env_copy(l);
  Var other = _lower_block(l, %(@alt @rest), k);
  _lower_env_restore(l, second);
  if (_lower_failed(l, other)) return void;
  return %(cond ($guard $taken) (true $other));
}

/* A loop is a global function over the live locals. Its body ends in a
   self call in tail position, which reuses the frame, and its exit inlines
   the rest of the block rather than calling a continuation, which would
   accumulate environment once per loop. */
/* A cell the body declares is allocated once before the loop runs, so the
   declaration inside it is a store rather than a binding form. */
static void _lower_loop_cells(Lowering l, Var form, Array out) {
  if (form is not <list>) return;
  List items = form;
  if (!items) return;
  match (items)
    case %(bind (binding ?(int id) ?) *): {
      if (l.cells.contains(id) && !l.env.contains(id)) {
        l.env[id] = _lower_name(l, "box");
        out.push(l.env[id]);
      }
      return;
    }
  foreach (Var part, items) _lower_loop_cells(l, part, out);
}

/* A `break` binds to the nearest enclosing loop or `switch`, so this stops
   at one rather than counting a `break` that belongs to it. */
static int _lower_breaks(Var form) {
  if (form is not <list>) return 0;
  List items = form;
  if (!items) return 0;
  Var head = items.car();
  if (head == <break>) return 1;
  if (head == <while> || head == <for> || head == <do> || head == <switch>)
    return 0;
  foreach (Var part, items) if (_lower_breaks(part)) return 1;
  return 0;
}

/* The locals a loop has to carry: the ones its own forms name, the ones it
   declares in a cell, and the ones an enclosing loop's continuation will ask
   for. Carrying the whole environment instead spends a parameter on every
   local in scope, and the word machine refuses a lambda of more than
   `LISP_AUTO_PARAM_MAX`, so an unrelated local nine deep drops the loop onto
   the evaluator. A local left out is never read, and would decline rather
   than answer wrongly if that were wrong. */
static void _lower_referenced(Var form, Map used) {
  if (form is not <list>) return;
  List items = form;
  if (!items) return;
  match (items) {
    case %(ident (binding ?(int id) ?)):   used[id] = 1;
    case %(bind (binding ?(int id) ?) *):  used[id] = 1;
    case %(again ? (*ids)): foreach (Var id, ids) used[id] = 1;
  }
  foreach (Var part, items) _lower_referenced(part, used);
}

static Var _lower_loop(
  Lowering l, Var test, List body, List step, List rest, List k) {
  Var name = _lower_name(l, "loop");
  Array boxes = [];
  defer boxes.free();
  _lower_loop_cells(l, body, boxes);
  Map used = {};
  defer used.cleanup();
  _lower_referenced(test, used);
  _lower_referenced(body, used);
  _lower_referenced(step, used);
  _lower_referenced(rest, used);
  _lower_referenced(k, used);
  /* The element is read where it is used, so the loop does not carry it. */
  int walk_cursor = 0, walk_item = 0;
  if (_lower_list_cursor(test, &walk_cursor, &walk_item))
    used.del(walk_item);
  Array ids = [];
  defer ids.free();
  Array slots = [];
  defer slots.free();
  Array entry = [];
  foreach (Var (id, form), l.env) {
    if (!used.contains(id)) continue;
    ids.push(id);
    entry.push(form);
  }
  Map inside = {};
  foreach (Var id, ids) {
    Var slot = _lower_name(l, "live");
    slots.push(slot);
    inside[id] = slot;
  }
  Map outer = l.env;
  l.env = inside;
  /* A `foreach` over a `List` walks the list itself: the cursor is the list
     that remains, so the test is its own truth, the element is its head, and
     the next turn carries its tail. Nothing is addressed, so nothing is
     boxed, and the loop carries one parameter instead of three. */
  int cursor_id = 0, item_id = 0;
  Var guard;
  if (_lower_list_cursor(test, &cursor_id, &item_id) &&
      inside.contains(cursor_id)) {
    Var walk = inside[cursor_id];
    guard = %(C.true? $walk);
    l.env[item_id] = %(car $walk);
    l.env[cursor_id] = %(cdr $walk);
  }
  else guard = _lower_truth(l, test);
  /* The exit is a function over the same live locals only when a `break`
     reaches it from inside the body; otherwise the cond inlines it. */
  Var exit = 0;
  List breaking = NULL;
  if (_lower_breaks(body) || _lower_breaks(step)) {
    exit = _lower_name(l, "after");
    breaking = %(again $exit ${ids.list()});
  }
  List turn = %(again $name ${ids.list()});
  if (step) turn = %(then ${step} ${turn} ${breaking});
  List saved_break = l.on_break, saved_continue = l.on_continue;
  l.on_break = breaking;
  l.on_continue = turn;
  int was_on_loop = l.on_loop;
  l.on_loop = 1;
  Map before = _lower_env_copy(l);
  Var iterate = _lower_block(l, body, turn);
  _lower_env_restore(l, before);
  l.on_loop = was_on_loop;
  l.on_break = saved_break;
  l.on_continue = saved_continue;
  Var leave = _lower_block(l, rest, k);
  l.env = outer;
  if (_lower_failed(l, guard) || _lower_failed(l, iterate) ||
      _lower_failed(l, leave))
    return void;
  /* One List of the live locals serves every definition below, so the
     mutable Array itself never leaves this frame. */
  List live = slots;
  Var exiting = leave;
  if (breaking) {
    l.definitions.push(%(def $exit (lambda $live $leave)));
    exiting = cons(exit, live);
  }
  l.definitions.push(
    %(def $name (lambda $live (cond ($guard $iterate)
                                    (true $exiting)))));
  Var call = cons(name, entry.list_free());
  if (!boxes.len()) return call;
  Array empty = [];
  foreach (Var box, boxes) {
    (void) box;
    empty.push(%(C.cell 0));
  }
  return %((lambda ${boxes.list()} $call) @{empty.list_free()});
}

/* --- switch ------------------------------------------------------------- */

/* A statement without the position its parser recorded, so a `switch` label
   reads the same whether or not it carries one. */
static Var _lower_bare(Var form) {
  match (form) case %(at ? ?node): return _lower_bare(node);
  return form;
}

/* C runs on into the arm below when one does not transfer control. This
   pass refuses that rather than reordering the arms into a state machine,
   so every arm but the last has to end by transferring control. */
static int _lower_terminated(List body) {
  if (!body) return 0;
  match (_lower_bare(body.last())) {
    case %(block *items): return _lower_terminated(items);
    case %(!or (break) (continue) (return *)): return 1;
  }
  return 0;
}

/* One arm: the case values that select it, and its statements. This takes
   both arrays over. A `default` selects on no value, so it carries none
   even where a `case` label shares the arm with it. */
static Var _lower_arm(Array tests, Array body, int fallback) {
  if (!fallback) return %(${tests.list_free()} ${body.list_free()});
  tests.free();
  return %(() ${body.list_free()});
}

/* A `switch` is a `cond` over the subject, which the labels compare against
   and the arms never read, so it is bound only when it cannot be repeated.
   The arms sit in one flat block with their labels as markers, so an arm is
   the statements between one label run and the next. */
static Var _lower_switch(
  Lowering l, Var subject, List items, List rest, List k) {
  Var value = _lower_expr(l, subject);
  if (_lower_failed(l, value)) return void;
  int bound = !_lower_pure(value);
  if (bound && l.on_loop)
    return _lower_decline(l, "a switch subject needing a binding is on a "
                             "loop path");
  Var slot = value;
  if (bound) slot = _lower_name(l, "subject");
  Array arms = [];
  defer arms.free();
  Array tests = [];
  Array body = [];
  int fallback = 0;
  foreach (Var item, items) {
    Var label = 0;
    int is_case = 0, is_default = 0;
    match (_lower_bare(item)) {
      case %(case ?node): {
        label = node;
        is_case = 1;
      }
      case %(default): is_default = 1;
    }
    if (!is_case && !is_default) {
      body.push(item);
      continue;
    }
    if (body.len()) {
      arms.push(_lower_arm(tests, body, fallback));
      tests = [];
      body = [];
      fallback = 0;
    }
    if (is_case) tests.push(label);
    else fallback = 1;
  }
  if (tests.len() || body.len() || fallback)
    arms.push(_lower_arm(tests, body, fallback));
  else {
    tests.free();
    body.free();
  }
  List exit = %(then ${rest} ${k} ${l.on_break});
  List saved_break = l.on_break;
  l.on_break = exit;
  Array clauses = [];
  defer clauses.free();
  Var otherwise = void;
  int count = (int) arms.len();
  for (int i = 0; i < count; i++) {
    List arm = arms[i];
    List cases = arm.car();
    List statements = arm.cadr();
    if (i + 1 < count && !_lower_terminated(statements)) {
      _lower_decline(l, "a switch arm that falls through into the next");
      break;
    }
    Array conditions = [];
    foreach (Var node, cases) {
      Var constant = _lower_expr(l, node);
      if (_lower_failed(l, constant)) break;
      conditions.push(%(equal? $slot $constant));
    }
    Map saved = _lower_env_copy(l);
    Var taken = _lower_block(l, statements, exit);
    _lower_env_restore(l, saved);
    List tested = conditions.list_free();
    if (_lower_failed(l, taken)) break;
    if (!tested) {
      otherwise = taken;
      continue;
    }
    Var test = tested.car();
    if (tested.cdr()) test = cons(<or>, tested);
    clauses.push(%($test $taken));
  }
  l.on_break = saved_break;
  if (l.declined) return void;
  Var chain = otherwise;
  if (chain is void) {
    Map saved = _lower_env_copy(l);
    chain = _lower_block(l, rest, k);
    _lower_env_restore(l, saved);
    if (_lower_failed(l, chain)) return void;
  }
  clauses.push(%(true $chain));
  List arms = clauses;
  Var result = cons(<cond>, arms);
  if (!bound) return result;
  return %((lambda ($slot) $result) $value);
}

/* A cell local's declaration allocates its box; every other local keeps the
   value itself. */
static Var _lower_boxed(Lowering l, int id, Var value) {
  if (_lower_failed(l, value)) return void;
  return l.cells.contains(id) ? %(C.cell $value) : value;
}

/* A C array's dimension, read at lowering time so a partly written one is
   zero-filled the way C fills it. A computed dimension has no such answer. */
static int _lower_dimension(Lowering l, int id, int *out) {
  Var size;
  if (!l.arrays.try_get(id, &size)) return 0;
  match (size)
    case %(expr ? (literal ? ?(String text))): {
      long count;
      if (text.try_long(&count) && count >= 0 && count == (int) count) {
        *out = (int) count;
        return 1;
      }
    }
  return 0;
}

/* A braced initializer carries no type of its own, so the declared type
   decides which container it builds. */
static Var _lower_braced(Lowering l, List type, int id, List items) {
  if (l.arrays.contains(id)) {
    int size = 0;
    if (!_lower_dimension(l, id, &size))
      return _lower_decline(l, "an array dimension that is not a literal");
    Array values = _lower_values(l, items);
    if (l.declined) return void;
    if (values.len() > size) {
      values.free();
      return _lower_decline(l, "more initializers than the array holds");
    }
    Var zero = _lower_zero(type);
    while (values.len() < size) values.push(zero);
    return %(List_array ${cons(<list>, values.list_free())});
  }
  if (type.equal(%("Map"))) {
    if (items) return _lower_decline(l, "a braced Map initializer needs keys");
    return %(Map_new);
  }
  if (type.equal(%("Array"))) return _lower_array(l, items);
  if (type.equal(%("List")))  return _lower_sequence(l, items);
  return _lower_decline(l, "a braced initializer for this type");
}

/* A declaration, a cast, an assignment, a return and an argument each name a
   type the value has to reach, and none of them carries the conversion the
   transform would insert later. Beyond the numeric families, the pairs a
   Lisp value can tell apart need one: a `Symbol` is not a `String`, and an
   `Array` is not a `List`. Without the argument case an `Array` reached a
   `List` parameter and the native adapter refused it. */
static Var _lower_coerce(List want, Var node, Var value) {
  match (node)
    case %(expr ?from ?): {
      if (want.equal(from)) return value;
      if (want.equal(%("List")) && from.equal(%("Array")))
        return %(Array_list $value);
      if (want.equal(%("Array")) && from.equal(%("List")))
        return %(List_array $value);
      if (want.equal(%("String")) && from.equal(%("Symbol")))
        return %(Symbol_str $value);
      Type target = want, source = from;
      Symbol tag = target.scalar_tag();
      if (tag && source.scalar_tag() && tag != source.scalar_tag())
        return _lower_to_type(want, value);
    }
  return value;
}

/* An array literal knows it is an `Array`, so only a `List` destination
   needs the conversion. A braced initializer knows nothing, so its
   destination decides outright. */
static Var _lower_initializer(Lowering l, List type, int id, Var init) {
  match (init) {
    case %(expr ? (composite (commas *items))):
      return _lower_braced(l, type, id, items);
    case %(expr ? (composite)): return _lower_braced(l, type, id, %());
  }
  Var value = _lower_expr(l, init);
  if (_lower_failed(l, value)) return void;
  return _lower_coerce(type, init, value);
}

static Var _lower_declarator(
  Lowering l, List type, List declarator, List rest, List k) {
  match (declarator) {
    case %(op = (bind (binding ?(int id) ?) *) ?init): {
      Var value = _lower_initializer(l, type, id, init);
      if (l.cells.contains(id) && l.env.contains(id)) {
        if (_lower_failed(l, value)) return void;
        return _lower_effect(
          l, %(C.store ${_lower_address(l, id)} $value), rest, k);
      }
      return _lower_bind_value(l, id, _lower_boxed(l, id, value), rest, k);
    }
    case %(bind (binding ?(int id) ?) *): {
      Var initial;
      if (l.arrays.contains(id)) initial = _lower_braced(l, type, id, %());
      else initial = _lower_zero(type);
      if (_lower_failed(l, initial)) return void;
      /* A box the enclosing loop already allocated is filled, not rebound.
         A `foreach` inside a `foreach` declares its output cell with no
         initializer, so without this a nested loop cannot lower. */
      if (l.cells.contains(id) && l.env.contains(id))
        return _lower_effect(
          l, %(C.store ${_lower_address(l, id)} $initial), rest, k);
      return _lower_bind_value(l, id, _lower_boxed(l, id, initial), rest, k);
    }
  }
  return _lower_decline(l, "unsupported declarator");
}

/* A destructuring names its targets bare when one type covers them all and
   through `param` when each carries its own. The type decides nothing
   either way, because a Lisp value already is a `Var`. */
static int _lower_destructure_id(Var target, int *out) {
  match (target) {
    case %(!or (binding ?(int id) ?)
               (param ? (bind (binding ?(int id) ?) *))): {
      *out = id;
      return 1;
    }
  }
  return 0;
}

/* `Var (a, b) = pair` converts its source to a `List` once and reads each
   target out of it by position, which is what the transform does with the
   same declaration. An element read is duplicable, so every target
   substitutes; only a source that is not is held in a binding first. */
static Var _lower_destructure(
  Lowering l, List targets, Var init, List rest, List k) {
  Var source = _lower_expr(l, init);
  if (_lower_failed(l, source)) return void;
  source = _lower_coerce(%("List"), init, source);
  int hold = !_lower_pure(source);
  if (hold && l.on_loop)
    return _lower_decline(l, "a value needing a binding is on a loop path");
  Var held = hold ? _lower_name(l, "hold") : source;
  int index = 0;
  foreach (List target, targets) {
    int id;
    if (!_lower_destructure_id(target, &id))
      return _lower_decline(l, "unsupported destructuring target");
    if (l.cells.contains(id))
      return _lower_decline(l, "a destructured local that needs a cell");
    l.env[id] = %(List_getindex $held $index);
    index++;
  }
  Var after = _lower_block(l, rest, k);
  if (_lower_failed(l, after)) return void;
  if (!hold) return after;
  return %((lambda ($held) $after) $source);
}

/* The binding id an lvalue names, or -1 when it is not a plain local. */
static int _lower_target(Var form) {
  match (form)
    case %(expr ? (ident (binding ?(int id) ?))): return id;
  return -1;
}

/* `m[k] = v` and `a[i] = v`. A `List` has no indexed write, so a store
   through one declines rather than silently dropping. */
static Var _lower_setindex(
  Lowering l, Var receiver, Var key, int is_c_array, Var value, List rest,
  List k) {
  String container = _lower_indexed(receiver, is_c_array);
  if (!container)
    return _lower_decline(l, "indexing a type with no compile-time meaning");
  if (container.equal("List") || container.equal("String"))
    return _lower_decline(l, "indexed write to a List or String");
  Var target = _lower_expr(l, receiver);
  Var index = _lower_expr(l, key);
  if (_lower_failed(l, target) || _lower_failed(l, index) ||
      _lower_failed(l, value))
    return void;
  return _lower_effect(
    l, %(${Atom.intern(container + "_setindex")} $target $index $value),
    rest, k);
}

static Var _lower_store(
  Lowering l, Var target, Var value, List rest, List k) {
  match (target) {
    case %(expr ? (op ?operator ?operand)): {
      if (operator == <"*">) {
        Var box = _lower_expr(l, operand);
        if (_lower_failed(l, box) || _lower_failed(l, value)) return void;
        return _lower_effect(l, %(C.store $box $value), rest, k);
      }
    }
    case %(expr ? (getindex ?receiver ?key)):
      return _lower_setindex(l, receiver, key, 0, value, rest, k);
    case %(expr ? (index ?receiver ?key)):
      return _lower_setindex(l, receiver, key, 1, value, rest, k);
  }
  int id = _lower_target(target);
  if (id < 0) return _lower_decline(l, "assignment to a computed place");
  if (_lower_failed(l, value)) return void;
  if (l.cells.contains(id))
    return _lower_effect(
      l, %(C.store ${_lower_address(l, id)} $value), rest, k);
  if (!l.locals.contains(id)) {
    l.globals = 1;
    return _lower_effect(l, %(C.gwrite $id $value), rest, k);
  }
  return _lower_bind_value(l, id, value, rest, k);
}

/* `right` is already lowered: a step supplies its own one, and a compound
   assignment supplies its lowered right-hand side. The operation promotes,
   so the result converts back to the place's own type, which is what
   `$native.update` in `lib/varops.x` does for each family. */
static Var _lower_update(
  Lowering l, Var target, Var operator, Var right, List rest, List k) {
  int id = _lower_target(target);
  if (id < 0) return _lower_decline(l, "update of a computed place");
  if (_lower_failed(l, right)) return void;
  Type want = _lower_type_of(target);
  if (!l.locals.contains(id)) {
    l.globals = 1;
    Var combined = _lower_to_type(
      want, %(_binary (C.gread $id) (quote $operator) $right));
    return _lower_effect(l, %(C.gwrite $id $combined), rest, k);
  }
  Var current = _lower_value(l, id);
  if (_lower_failed(l, current)) return void;
  Var combined = _lower_to_type(
    want, %(_binary $current (quote $operator) $right));
  if (l.cells.contains(id))
    return _lower_effect(
      l, %(C.store ${_lower_address(l, id)} $combined), rest, k);
  return _lower_bind_value(l, id, combined, rest, k);
}

/* The operator a compound assignment applies, or the zero Symbol. */
static Symbol _lower_compound(Var operator) {
  Symbol zero = 0;
  if (operator == <"+=">) return <+>;
  if (operator == <"-=">) return <->;
  if (operator == <"*=">) return <*>;
  if (operator == <"/=">) return </>;
  if (operator == <"%=">) return <%>;
  if (operator == <"&=">) return <&>;
  if (operator == <"|=">) return <|>;
  if (operator == <"^=">) return <^>;
  if (operator == <"<<=">) return <"<<">;
  if (operator == <">>=">) return <">>">;
  return zero;
}

/* A step of one in the target's own type: an `int` counter must not become
   a `double`, or the next bitwise operation on it has no meaning. */
static Var _lower_step_of(Var target) {
  match (target)
    case %(expr (!or (double) (float)) ?): return 1.0;
  return 1;
}

static Var _lower_expression_stmnt(
  Lowering l, Var e, List rest, List k) {
  match (e) {
    case %(expr ? (op = ?target ?rhs)): {
      Var value = _lower_expr(l, rhs);
      if (!_lower_failed(l, value))
        value = _lower_coerce(_lower_type_of(target), rhs, value);
      return _lower_store(l, target, value, rest, k);
    }
    case %(expr ? (!or (op ++ ?target) (postfix ++ ?target))):
      return _lower_update(l, target, <+>, _lower_step_of(target), rest, k);
    case %(expr ? (!or (op -- ?target) (postfix -- ?target))):
      return _lower_update(
        l, target, <->, _lower_step_of(target), rest, k);
    case %(expr ? (op ?operator ?target ?rhs)): {
      Symbol applied = _lower_compound(operator);
      if (!applied)
        return _lower_decline(l, "statement with no effect on a local");
      return _lower_update(
        l, target, applied, _lower_expr(l, rhs), rest, k);
    }
  }
  match (e) {
    /* A call's result can be discarded: it runs for what it writes. */
    case %(expr ? (call ? ?)):
      return _lower_effect(l, _lower_expr(l, e), rest, k);
    /* A cast to `void` discards the result but not the work: `(void) x;`
       marks a local used and does nothing, while `(void) f();` still calls
       `f`. Discarding the operand instead would silently drop its effect. */
    case %(expr (void) (cast (decl (void) ?) ?operand)): {
      Var value = _lower_expr(l, operand);
      if (_lower_failed(l, value)) return void;
      if (_lower_pure(value)) return _lower_block(l, rest, k);
      return _lower_effect(l, value, rest, k);
    }
  }
  return _lower_decline(l, "statement with no effect on a local");
}

static Var _lower_stmnt(Lowering l, Var form, List rest, List k) {
  if (l.declined) return void;
  match (form) {
    case %(at ? ?node):    return _lower_stmnt(l, node, rest, k);
    case %(empty):         return _lower_block(l, rest, k);
    case %(block *items):  return _lower_block(l, %(@items @rest), k);
    case %(return ?want ?value): {
      Var result = _lower_expr(l, value);
      if (_lower_failed(l, result)) return void;
      return _lower_coerce(want, value, result);
    }
    case %(return ?):      return 0;
    case %(declare ?type (bindings ?declarator)):
      return _lower_declarator(l, type, declarator, rest, k);
    /* Phase 3 owns these two cases; the rest of the statement grammar is
       Phase 2's. */
    case %(dstrdecl ? (targets *targets) ?init):
      return _lower_destructure(l, targets, init, rest, k);
    case %(dstrdecl (params *params) ?init):
      return _lower_destructure(l, params, init, rest, k);
    case %(declare ?type (bindings *declarators)): {
      Array expanded = [];
      defer expanded.free();
      foreach (List declarator, declarators)
        expanded.push(%(declare $type (bindings $declarator)));
      return _lower_block(l, %(@{expanded.list()} @rest), k);
    }
    case %(stmnt ?e):      return _lower_expression_stmnt(l, e, rest, k);
    case %(if ?test ?then):
      return _lower_branch(l, test, %($then), %(), rest, k);
    case %(if ?test ?then ?alt):
      return _lower_branch(l, test, %($then), %($alt), rest, k);
    case %(while ?test ?body):
      return _lower_loop(l, test, %($body), %(), rest, k);
    case %(match ?subject ?arms):
      return _lower_arms(l, subject, arms, rest, k);
    case %(switch ?subject (block *items)):
      return _lower_switch(l, subject, items, rest, k);
    case %(break): {
      if (!l.on_break)
        return _lower_decline(l, "break outside a loop or switch");
      return _lower_apply_k(l, l.on_break);
    }
    case %(continue): {
      if (!l.on_continue) return _lower_decline(l, "continue outside a loop");
      return _lower_apply_k(l, l.on_continue);
    }
    /* `do BODY while (TEST)` checks the test after the body, which is the
       same loop with the test as its step: the body's end and every
       `continue` reach it, and a failing test leaves through its `break`. */
    case %(do ?body ?test):
      return _lower_loop(
        l, %(expr (int) (literal (int) "1")), %($body),
        %((if $test (empty) (break))), rest, k);
    /* A `for` is the same loop with its step as the continuation the body
       and every `continue` reach, so nothing can skip it. The init declares
       into the enclosing block, so it is lowered ahead of the loop. */
    case %(for ?init ?test ?step ?body): {
      if (init)
        return _lower_block(
          l, %(${_lower_for_init(init)} (for () $test $step $body) @rest), k);
      List guard = test ? test : %(expr (int) (literal (int) "1"));
      return _lower_loop(
        l, guard, %($body), step ? %((stmnt $step)) : %(), rest, k);
    }
  }
  return _lower_decline(l, "unsupported statement");
}

static List _lower_for_init(List init) {
  match (init) {
    case %(decl ?type (bindings *declarators)):
      return %(declare $type (bindings @declarators));
  }
  return %(stmnt $init);
}

static Var _lower_block(Lowering l, List items, List k) {
  if (l.declined) return void;
  if (!items) return _lower_apply_k(l, k);
  return _lower_stmnt(l, items.car(), items.cdr(), k);
}

/* --- the function ------------------------------------------------------- */

/** Lowers one compile-time function into the forms the macro session
    evaluates, or returns `NULL` when the substitution cannot carry it.
    The result is the loop definitions the body needed followed by the
    function's own, in evaluation order. This method does not open a
    semantic transaction.
*/
List Compiler.lower_comptime(Compiler compiler, List fn) {
  struct Lowering state = {
    .compiler = compiler, .env = {}, .locals = {}, .cells = {},
    .arrays = {}, .callees = {}, .cursors = {}, .definitions = [],
    .declined = 0,
    .own = NULL, .on_break = NULL, .on_continue = NULL, .on_loop = 0,
    .in_loop = 0, .rejected = 0, .uncallable = 0, .globals = 0,
    .meta_only = 0
  };
  Lowering l = &state;
  lower_reached_globals = 1;
  lower_reached_meta = 0;
  match (fn) {
    case %(function ?spec (bind (binding ? ?(String name))
                            ((fnmod (params *params)))) (block *items)): {
      (void) spec;
      lower_declined_reason = NULL;
      lower_session_callees = NULL;
      l.own = name;
      _lower_scan(l, fn);
      _lower_scan(l, fn);
      /* The scan records its own wording for a construct refused by
         decision; `rejected` now means only `goto`. */
      if (!l.declined) {
        if (l.rejected) lower_declined_reason = "a goto has no lowering";
        else if (l.uncallable)
          lower_declined_reason = "no binding for " + lower_missing_callee;
      }
      if (l.declined || l.rejected || l.uncallable) {
        l.definitions.free();
        return NULL;
      }
      Array slots = [];
      defer slots.free();
      foreach (List parameter, params) {
        match (parameter)
          case %(param ? (bind (binding ?(int id) ?) *)): {
            Var slot = _lower_name(l, "arg");
            slots.push(slot);
            l.env[id] = slot;
          }
      }
      Var body = _lower_block(l, items, %(end));
      if (_lower_failed(l, body)) {
        l.definitions.free();
        return NULL;
      }
      l.definitions.push(
        %(def ${Atom.intern(name)} (lambda ${slots.list()} $body)));
      lower_reached_globals = l.globals;
      lower_reached_meta = l.meta_only;
      lower_session_callees = l.callees.keys();
      return l.definitions.list_free();
    }
  }
  l.definitions.free();
  return NULL;
}

/** Returns why the last `Compiler.lower_comptime` declined, or `NULL`. */
String Compiler.lower_declined(Compiler compiler) {
  (void) compiler;
  return lower_declined_reason;
}

/* --- the process lowering cache ----------------------------------------- */

/* A unit's collection pass and its full parse each read the same source, and
   one process translates many units, so a `meta` function in an imported
   `.xmacro` lowers once per pass per importing unit. The lowering reads the
   definition's syntax, the literal values behind its `(cache id)` nodes, and
   which callee names the macro session binds, so the forms it produces are
   the same wherever that file is read. They are kept for the process and
   evaluated again in each unit, because a Lisp session belongs to one unit.

   Process cache: "path#name" -> `(forms callees globals meta)`. The two
   facts travel with the forms because a reused entry installs without
   lowering, and the caller reads them to decide folding and emission.
   Entries outlive the per-unit `Context`, so a retained entry belongs to
   `lowered_scope` and to the outermost value pools. */
static Map lowered_defs = NULL, static Scope lowered_scope = NULL;

static void _lowered_shutdown(void) {
  lowered_scope.destroy();
  lowered_scope = NULL;
  lowered_defs = NULL;
}

static Map _lowered_defs(void) {
  if ((void *) lowered_defs != NULL) return lowered_defs;
  Scope.push(&lowered_scope);
  Scope.shutdown_hook(_lowered_shutdown);
  lowered_defs = {};
  Scope.pop();
  return lowered_defs;
}

/* A wide numeric leaf, which a literal too large for an `int` produces, owns
   a box in the unit's `Scope` that promotion to the value pools does not
   reach. Such a lowering is not retained and is repeated in the next unit. */
static int _lowered_portable(Var form) {
  if (form.is_wide()) return 0;
  if (form is not <list>) return 1;
  for (List cur = form; cur; cur = cur.cdr())
    if (!_lowered_portable(cur.car())) return 0;
  return 1;
}

/* The session names the lowering resolved are its only unit-dependent input,
   so a unit whose session lacks one lowers again and reports the refusal its
   author would have seen without the cache. */
static int _lowered_callable(Compiler compiler, List callees) {
  Var value;
  foreach (String name, callees)
    if (!compiler.macro_lisp.try_get(name, &value)) return 0;
  return 1;
}

static void _retain_lowering(String key, List forms, List callees) {
  List entry =
    %($forms $callees $lower_reached_globals $lower_reached_meta);
  if (!_lowered_portable(entry) || !key.try_own() || !entry.try_own()) return;
  _lowered_defs()[key] = entry;
}

/* Every install records a function that reached file-scope state, whichever
   spelling installed it, because `_lower_scan_callee` reads that back to
   give a caller the same reach. Both spellings reach the same lowering, so
   the recording belongs here rather than beside one of them. */
static int _installed_comptime(Compiler compiler, String name) {
  if (name && lower_reached_globals) compiler.meta_impure[name] = 1;
  return 1;
}

/** Lowers `fn` and evaluates the result in the macro session, so the
    function is callable from compile-time Lisp under its own name.
    Returns whether the lowering succeeded. This method mutates the macro
    session and does not open a semantic transaction.
*/
int Compiler.install_comptime(Compiler compiler, List fn) {
  String key = NULL, own = NULL;
  match (fn)
    case %(function ? (bind (binding ? ?(String name)) ?) ?): {
      own = name;
      if (compiler.filename) key = %"${compiler.filename}#$name";
    }
  /* The shared session installed this definition, from this file, before any
     unit opened. Installing it again would only try to replace a name an
     ancestor binds; the unit reads the shared one. */
  if (key && compiler.shared_definition(key))
    match (_lowered_defs()[key])
      case %(? ? ?(int shared_globals) ?(int shared_meta)): {
        lower_reached_globals = shared_globals;
        lower_reached_meta = shared_meta;
        return _installed_comptime(compiler, own);
      }
  /* A recursive call resolves against the name before the body is lowered,
     the way a C prototype lets a function call itself. */
  if (own) compiler.macro_lisp.eval(%(def ${Atom.intern(own)} (lambda () 0)));
  if (key)
    match (_lowered_defs()[key])
      case %(?(List forms) ?(List callees) ?(int globals) ?(int meta)):
        if (_lowered_callable(compiler, callees)) {
          foreach (Var form, forms) compiler.macro_lisp.eval(form);
          lower_reached_globals = globals;
          lower_reached_meta = meta;
          return _installed_comptime(compiler, own);
        }
  List forms = compiler.lower_comptime(fn);
  if (!forms) return 0;
  if (key) _retain_lowering(key, forms, lower_session_callees);
  foreach (Var form, forms) compiler.macro_lisp.eval(form);
  return _installed_comptime(compiler, own);
}

/** Returns whether the last `Compiler.install_comptime` reached file-scope
    state, directly or through a callee already recorded as reaching it.
*/
int Compiler.lower_reached_globals(Compiler compiler) {
  (void) compiler;
  return lower_reached_globals;
}

/** Returns whether the last `Compiler.install_comptime` reached a `Meta`
    operation, directly or through a callee already recorded as reaching one.
*/
int Compiler.lower_reached_meta(Compiler compiler) {
  (void) compiler;
  return lower_reached_meta;
}

/** Returns whether `fn` is a `meta` function this compiler recorded as
    compile-time only, whose runtime form the unit does not emit.
*/
int Compiler.meta_is_comptime_only(Compiler c, List fn) {
  match (fn)
    case %(function ? (bind (binding ? ?(String name)) *) ?):
      return c.meta_comptime.contains(name);
  return 0;
}

/* --- constant-argument folding ------------------------------------------ */

/* The compile-time value behind a bound expression, or `void` when the
   expression has none. This is the reader the lowering already uses for a
   literal and for the `(cache id)` a folded constant leaves behind; a
   throwaway `Lowering` gives it the key table and somewhere to decline. */
static Var _meta_constant(Compiler compiler, List expression) {
  struct Lowering state = { .compiler = compiler, .declined = 0 };
  return _lower_constant(&state, expression);
}

/* A folded result substitutes for the call, so it has to occupy the same
   syntax an ordinary literal does. `int` is the one return type whose value
   spells itself: a narrower or unsigned type would need the C conversion
   written out, and `String`, `List` and `Map` results have no literal form
   that also carries the ownership the call would have returned. A negative
   value is parenthesized so it cannot join a preceding `-` into `--`. */
static List _meta_result(Compiler c, Type result, Var value) {
  if (!value.is_integer()) return NULL;
  Type scalar = c.sym.resolve_key(result).scalar();
  if (scalar !== %(int)) return NULL;
  long number = value.integer();
  if (number != (int) number) return NULL;
  List literal = %(expr $result (literal (int) ${%"$number"}));
  if (number < 0) return %(expr $result (parens $literal));
  return literal;
}

/** Refuses a run-time call to a `meta` function this compiler derived
    compile-time only.

    Such a function reaches a `Meta` operation, so it exists only inside a
    compiler and the unit emits no definition for it. The call used to reach
    the linker as an undefined symbol, which names the C spelling and not the
    source. Another `meta` function may call it: calling one is what makes
    the caller compile-time only too, so a body being parsed under the marker
    is left alone.
*/
void Compiler.check_meta_call(Compiler c, List callee, Token origin) {
  if (c.meta_body || !c.meta_comptime.len()) return;
  match (callee)
    case %(expr ? (ident (binding ? ?(String name)))):
      if (c.meta_comptime.contains(name))
        c.report_error(
          <macro>, %"'$name' can only be called at compile time", origin,
          %("reason: it reaches a compiler operation, so no unit emits a"
            "definition for it; call it from a macro or another meta"
            "function"));
}

/** Answers a call to a `meta` function from its compile-time form when every
    argument is a compile-time constant of the parameter's own type, or
    returns `NULL` to leave the call alone.

    `callee` is the resolved callee expression, `signature` its function type
    and `result` the call's type. Only a `meta` function this compiler
    installed folds, so an import's runtime definition keeps the run-time
    call that designates the unit emitting it. Evaluation runs in the macro
    session; a raise there leaves the call.
*/
List Compiler.fold_meta_call(
  Compiler c, List callee, Type signature, Type result, List arguments) {
  if (!c.meta_folds.len() || c.macro_holes) return NULL;
  String name = NULL;
  match (callee)
    case %(expr ? (ident (binding ?(int id) ?(String spelling)))):
      if (c.meta_folds.contains(id)) name = spelling;
  Var callable;
  if (!name || !c.macro_lisp.try_get(name, &callable)) return NULL;
  List parameters = NULL;
  match (signature) case %((func ?params) *): parameters = params;
  if (arguments === %((expr (void) ()))) arguments = NULL;
  if (parameters === %((void))) parameters = NULL;
  if (parameters.len() != arguments.len()) return NULL;
  Array values = [];
  defer values.free();
  for (List p = parameters, a = arguments; p; p = p.cdr(), a = a.cdr()) {
    List argument = a.car();
    Type declared = p.car(), supplied = argument.cadr();
    if (!c.sym.resolve_key(declared).equal(c.sym.resolve_key(supplied)))
      return NULL;
    Var value = _meta_constant(c, argument);
    if (value is void) return NULL;
    /* The lowered body converts at every conversion position the source
       has, and a parameter is one the call site owns: a character literal
       reaching a `char` is its code as an `int` until this converts it. */
    Symbol tag = declared.scalar_tag();
    if (tag) {
      try value = value.convert(tag);
      catch: return NULL;
    }
    values.push(value);
  }
  Var answer;
  /* An ordinary decline keeps the call and says nothing: the two forms
     simply did not agree here. Running out of call depth is different. The
     compile-time form did not finish, and the developer wrote something the
     compiler cannot answer, so the call stays and the reason is reported. */
  try answer = c.macro_lisp.apply(callable, values);
  catch %(call-stack * (why "steps") *): {
    c.report_warning(
      <macro>, %"'$name' was not answered at compile time", c.token,
      %("reason: its compile-time form made too many calls and was stopped;"
        "the call stays and runs at run time"));
    return NULL;
  }
  catch %(call-stack *): {
    c.report_warning(
      <macro>, %"'$name' was not answered at compile time", c.token,
      %("reason: its compile-time form nested too deep and was stopped;"
        "the call stays and runs at run time"));
    return NULL;
  }
  catch: return NULL;
  return _meta_result(c, result, answer);
}
