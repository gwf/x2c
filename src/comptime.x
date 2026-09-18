/*  comptime.x -- translating a compile-time x2c function into Lisp

    Copyright (c) 2026 Gary William Flake.

    A function marked for compile-time use is lowered here into the Lisp the
    macro session evaluates. The evaluator reuses a frame only for a direct
    self tail call, so a loop must reach its recursive call with nothing in
    between: no binding form, no continuation call. A block is therefore
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
   loop's iteration path, where a binding form would cost frame reuse. */
typedef struct Lowering {
  Compiler compiler;
  Map env, locals, cells, arrays;
  Array definitions;
  String own;
  int counter, declined, on_loop, in_loop, rejected, uncallable;
} *Lowering;

/* Why the last lowering declined, for the diagnostic at the invocation, and
   the callee that has no compile-time binding when that is the reason. */
static String lower_declined_reason;
static String lower_missing_callee;

/* --- names ------------------------------------------------------------- */

/* `Atom.intern` gives an `lsym` for a spelling too long to pack into a
   Symbol, so a generated name is readable and cannot collide by truncation.
   Every function shares one macro session, so the name carries the function
   it belongs to: a counter alone made two functions with the same shape
   define the same loop, and the second silently replaced the first. */
static Var _lower_name(Lowering l, String stem) {
  l.counter++;
  return Atom.intern(%"$stem${l.counter}-${l.own}");
}

/* --- the single scan --------------------------------------------------- */

static void _lower_scan(Lowering l, Var form);

static void _lower_scan_each(Lowering l, List items) {
  foreach (Var item, items) _lower_scan(l, item);
}

/* A call's result and a cell's contents cannot be substituted, so a local
   the loop assigns one to would need a binding form on the iteration path.
   It gets a cell instead, where the assignment is an ordinary effect. The
   scan runs twice so this sees the cells the first pass found. */
static int _lower_scan_impure(Lowering l, Var form) {
  if (form is not <list>) return 0;
  List items = form;
  if (!items) return 0;
  if (items.car() == <call>) return 1;
  match (items)
    case %(ident (binding ?(int id) ?)): return l.cells.contains(id);
  foreach (Var part, items) if (_lower_scan_impure(l, part)) return 1;
  return 0;
}

/* Address-of is the one-operand `&`; three operands is bitwise and. */
static void _lower_scan_op(Lowering l, List form) {
  match (form) {
    case %(op & (expr ? (ident (binding ?(int id) ?)))): {
      l.cells[id] = 1;
      return;
    }
    case %(op ?operator ?target ?value): {
      if (!l.in_loop || !_lower_scan_impure(l, value)) return;
      if (operator != <"="> && operator != <"+="> && operator != <"-="> &&
          operator != <"*="> && operator != <"/=">)
        return;
      match (target) {
        case %(expr ? (ident (binding ?(int id) ?))): l.cells[id] = 1;
        case %(bind (binding ?(int id) ?) *):         l.cells[id] = 1;
      }
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

/* A callee is reachable when the macro session already binds its name: a
   native from `etc/comptime.xlisp`, or a function this pass installed. The
   function being lowered is reachable from itself, because the definition
   binds its name before anything calls it. */
static int _lower_known(Lowering l, String name) {
  Var value;
  if (l.own && l.own.equal(name)) return 1;
  return l.compiler.macro_lisp.try_get(name, &value);
}

static void _lower_scan_call(Lowering l, List form) {
  match (form) {
    case %(call (expr ? (ident (binding ? ?(String name)))) ?): {
      if (!_lower_known(l, name)) {
        l.uncallable = 1;
        lower_missing_callee = name;
      }
      return;
    }
    case %(call ?(String name) ?): {
      if (!_lower_known(l, name)) {
        l.uncallable = 1;
        lower_missing_callee = name;
      }
      return;
    }
  }
  l.uncallable = 1;
}

/* Everything the lowering needs before it starts, in one pass: which locals
   need a memory cell, which are arrays, which ids the function declares,
   whether it uses a construct the substitution cannot carry, and whether
   every callee has a compile-time binding. */
static void _lower_scan(Lowering l, Var form) {
  if (form is not <list>) return;
  List items = form;
  if (!items) return;
  Var head = items.car();
  if (head == <while> || head == <for>) {
    int was = l.in_loop;
    l.in_loop = 1;
    _lower_scan_each(l, items);
    l.in_loop = was;
    return;
  }
  if (head == <bind>) _lower_scan_bind(l, items);
  else if (head == <op>) _lower_scan_op(l, items);
  else if (head == <call>) _lower_scan_call(l, items);
  else if (head == <switch> || head == <do> || head == <break> ||
           head == <continue> || head == <goto>)
    l.rejected = 1;
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
  if (!l.locals.contains(id)) return %(C.gread $id);
  return _lower_decline(l, "unbound local");
}

/* --- literals ----------------------------------------------------------- */

static Var _lower_number(Lowering l, List type, String text) {
  long integer;
  double floating;
  if (type.match(%((!or double float))) || text.contains(".") ||
      text.contains("e") || text.contains("E")) {
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
static Var _lower_text(String spelling) {
  int len = spelling.len();
  if (len >= 2 && spelling[0] == '"')
    return String.new_len(spelling + 1, len - 2).unescape();
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
  /* Folding leaves an expression in place when it needs a conversion at run
     time, as a typed capture in a pattern does. There is no compile-time
     value to read back, so the caller declines rather than treating the
     unfolded node as data. */
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

static List _lower_args(Lowering l, List args) {
  Array values = [];
  defer values.free();
  foreach (List argument, args) {
    match (argument) case %(expr (void) ()): continue;
    Var value = _lower_expr(l, argument);
    if (_lower_failed(l, value)) return NULL;
    values.push(value);
  }
  return values;
}

/* A call is a direct Lisp call: the callee's name is a session global, so
   the lowered code pays a lookup and nothing more. */
static Var _lower_call(Lowering l, String name, List args) {
  List values = _lower_args(l, args);
  if (l.declined) return void;
  return cons(Atom.intern(name), values);
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
  foreach (List parameter, params) {
    match (parameter)
      case %(param ? (bind (binding ?(int id) ?) *)): {
        Var slot = _lower_name(l, "arg");
        names.push(slot);
        saved.push(%($id $slot));
      }
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
    case %(ident (binding ?(int id) ?)):
      return l.cells.contains(id) ? %(C.load ${_lower_read(l, id)})
                                  : _lower_read(l, id);
    case %(parens ?inner):                return _lower_expr(l, inner);
    case %(cast ? ?inner):                return _lower_expr(l, inner);
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
    case %(call (expr ? (ident (binding ? ?(String name)))) (args *args)):
      return _lower_call(l, name, args);
    case %(call ?(String name) (args *args)):
      return _lower_call(l, name, args);
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

/* nil is the only false value in Lisp, so a C zero has to be compared. A
   numeric test inlines that; anything else asks for x2c truth, because a
   nil List is false and zero is not a meaningful comparison there. */
static Var _lower_truth(Lowering l, Var test) {
  Var value = _lower_expr(l, test);
  if (_lower_failed(l, value)) return void;
  match (test)
    case %(expr (!or (int) (long) (char) (short) (unsigned)
                     (double) (float)) ?):
      return %(not (eq? $value 0));
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
  if (l.on_loop)
    return _lower_decline(l, "a value needing a binding is on a loop path");
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
   direct self call, the only shape the evaluator runs in constant space,
   and its exit inlines the rest of the block rather than calling a
   continuation, which would accumulate environment once per loop. */
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

static Var _lower_loop(
  Lowering l, Var test, List body, List rest, List k) {
  Var name = _lower_name(l, "loop");
  Array boxes = [];
  defer boxes.free();
  _lower_loop_cells(l, body, boxes);
  Array ids = [];
  defer ids.free();
  Array slots = [];
  defer slots.free();
  Array entry = [];
  foreach (Var (id, form), l.env) {
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
  Var guard = _lower_truth(l, test);
  int was_on_loop = l.on_loop;
  l.on_loop = 1;
  Map before = _lower_env_copy(l);
  Var iterate = _lower_block(l, body, %(again $name ${ids.list()}));
  _lower_env_restore(l, before);
  l.on_loop = was_on_loop;
  Var leave = _lower_block(l, rest, k);
  l.env = outer;
  if (_lower_failed(l, guard) || _lower_failed(l, iterate) ||
      _lower_failed(l, leave))
    return void;
  l.definitions.push(
    %(def $name (lambda ${slots.list()} (cond ($guard $iterate)
                                              (true $leave)))));
  Var call = cons(name, entry.list_free());
  if (!boxes.len()) return call;
  Array empty = [];
  foreach (Var box, boxes) {
    (void) box;
    empty.push(%(C.cell 0));
  }
  return %((lambda ${boxes.list()} $call) @{empty.list_free()});
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

/* A declaration and a return both name a type the value has to reach, and
   neither carries the conversion the transform would insert later. An
   assignment does carry it, so this sees only the two places that do not.
   Only the pairs a Lisp value can tell apart need one: a `Symbol` is not a
   `String`, and an `Array` is not a `List`. */
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
      if (l.arrays.contains(id)) {
        Var empty = _lower_braced(l, type, id, %());
        return _lower_bind_value(l, id, _lower_boxed(l, id, empty), rest, k);
      }
      Var zero = _lower_zero(type);
      return _lower_bind_value(l, id, _lower_boxed(l, id, zero), rest, k);
    }
  }
  return _lower_decline(l, "unsupported declarator");
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
  if (!l.locals.contains(id))
    return _lower_effect(l, %(C.gwrite $id $value), rest, k);
  return _lower_bind_value(l, id, value, rest, k);
}

/* `right` is already lowered: a step supplies its own one, and a compound
   assignment supplies its lowered right-hand side. */
static Var _lower_update(
  Lowering l, Var target, Var operator, Var right, List rest, List k) {
  int id = _lower_target(target);
  if (id < 0) return _lower_decline(l, "update of a computed place");
  if (_lower_failed(l, right)) return void;
  if (!l.locals.contains(id)) {
    Var combined = %(_binary (C.gread $id) (quote $operator) $right);
    return _lower_effect(l, %(C.gwrite $id $combined), rest, k);
  }
  Var current = _lower_read(l, id);
  if (_lower_failed(l, current)) return void;
  Var combined = %(_binary $current (quote $operator) $right);
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
    case %(expr ? (op = ?target ?rhs)):
      return _lower_store(l, target, _lower_expr(l, rhs), rest, k);
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
      return _lower_loop(l, test, %($body), rest, k);
    case %(match ?subject ?arms):
      return _lower_arms(l, subject, arms, rest, k);
    /* A `for` is the same loop with its step at the end of the body; the
       subset has no `continue`, so nothing can skip that step. */
    case %(for ?init ?test ?step ?body): {
      List start = init ? %(${_lower_for_init(init)}) : %();
      List turn = step ? %($body (stmnt $step)) : %($body);
      List guard = test ? test : %(expr (int) (literal (int) "1"));
      return _lower_block(
        l, %(@start (while $guard (block @turn)) @rest), k);
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
    .arrays = {}, .definitions = [], .counter = 0, .declined = 0,
    .own = NULL, .on_loop = 0, .in_loop = 0, .rejected = 0, .uncallable = 0
  };
  Lowering l = &state;
  match (fn) {
    case %(function ?spec (bind (binding ? ?(String name))
                            ((fnmod (params *params)))) (block *items)): {
      (void) spec;
      lower_declined_reason = NULL;
      l.own = name;
      _lower_scan(l, fn);
      _lower_scan(l, fn);
      if (l.rejected) lower_declined_reason = "unsupported construct";
      else if (l.uncallable)
        lower_declined_reason = "no binding for " + lower_missing_callee;
      if (l.rejected || l.uncallable) {
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

/** Lowers `fn` and evaluates the result in the macro session, so the
    function is callable from compile-time Lisp under its own name.
    Returns whether the lowering succeeded. This method mutates the macro
    session and does not open a semantic transaction.
*/
int Compiler.install_comptime(Compiler compiler, List fn) {
  /* A recursive call resolves against the name before the body is lowered,
     the way a C prototype lets a function call itself. */
  match (fn)
    case %(function ? (bind (binding ? ?(String name)) ?) ?):
      compiler.macro_lisp.eval(%(def ${Atom.intern(name)} (lambda () 0)));
  List forms = compiler.lower_comptime(fn);
  if (!forms) return 0;
  foreach (Var form, forms) compiler.macro_lisp.eval(form);
  return 1;
}
