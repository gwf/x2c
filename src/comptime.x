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
#include "path.x"
#include "varconvert.x"
#include <math.h>

/* One lowering. `env` maps a binding id to the Lisp form that produces it;
   `locals` are the ids the function declares, so an id outside it is
   file-scope state. `on_loop` records whether the current point is on a
   loop's iteration path, where a binding form would cost frame reuse.
   `on_break` and `on_continue` are the continuations the nearest enclosing
   loop or `switch` gave, or nothing outside one. */
typedef struct Lowering {
  Compiler compiler;
  Scope scratch;
  Map env, locals, cells, arrays, records, callees, cursors;
  Array definitions;
  String own;
  List on_break, on_continue;
  int declined, on_loop, rejected, uncallable, globals, meta_only;
  int session_globals;
  int automatic;        // the function keeps C objects in frame storage
  int counter;          // the generated names this lowering has made
} *Lowering;

/* The struct a declared spelling names, or NULL when it names none that
   compile-time code can lay out: any complete struct the compiler sees,
   including an anonymous inline one. */
static Type _lower_record_type(Lowering l, Type type) {
  if (!type) return NULL;
  Type key = type.canonicalize();
  if (key.is_pointer() || key.is_array() || key.is_function()) return NULL;
  match (key) case %(struct ?name (fields *)): key = %(struct $name);
  Type resolved = l.compiler.sym.resolve_key(key);
  Type record = resolved ? resolved : key;
  if (!record || record.car() != <struct> ||
      !l.compiler.sym.field_order(record)) return NULL;
  return record;
}

/* A local whose address is taken, and every struct local, is a C object in
   native bytes laid out by `Compiler.meta_type_layout`. Its slot holds the
   pointer to those bytes, boxed the way native code boxes that pointer, so
   `&x` is the slot itself and a native callee receives real storage. */
static List _lower_storage_layout(Lowering l, int id) {
  Var layout;
  return l.cells.try_get(id, &layout) && layout is <list> ? layout : NULL;
}

/* The Var tag of a slot for an object of `layout`: the tag native code
   gives a pointer to it, or `<p48>` where the pointer has no tag of its own.
   A record's slot is its value, which is always `<p48>`; `&` retags it. */
static Symbol _lower_pointer_tag(Lowering l, List layout) {
  Sym sym = l.compiler.sym;
  Symbol tag = 0, untagged = <p48>;
  match (layout) {
    case %(record *): return <p48>;
    case %(scalar ?type ? ? ?exact ?): {
      tag = sym.var_tag_for_type(cons(<*>, type), NULL);
      if (!tag) tag = sym.var_tag_for_type(cons(<*>, exact), NULL);
    }
    case %(pointer ?type *): {
      tag = sym.var_tag_for_type(cons(<*>, type), NULL);
      untagged = <p48*>;
    }
    case %(var ?type *): tag = sym.var_tag_for_type(cons(<*>, type), NULL);
  }
  return tag ? tag : untagged;
}

/* Zeroed automatic storage for one object of `layout`. */
static Var _lower_new_storage(Lowering l, List layout) {
  l.automatic = 1;
  return %(C.at (C.bytes ${layout[2]}) 0
                (quote ${_lower_pointer_tag(l, layout)}));
}

/* A fresh object of `layout` holding `value`, in the running function's
   automatic storage. A record's value is copied from the bytes it names,
   unless `fresh` says its initializer just built those bytes. */
static Var _lower_new_object(
  Lowering l, List layout, Var value, int fresh) {
  match (layout) case %(?kind ? ?size *): {
    if (fresh && kind == <record>) return value;
    Symbol tag = _lower_pointer_tag(l, layout);
    l.automatic = 1;
    return %(C.new $size (quote $tag) (quote $layout) $value);
  }
  return void;
}

/* Only map containers belong here; forms and wide numeric boxes retain the
   caller's lifetime. Map growth follows the scope used at construction. */
static Map _lower_scratch_map(Scope scratch) {
  $scope(&scratch) { return {}; }
}

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

   A loop becomes a session global, and every function shares one session,
   so a loop's name carries the function it belongs to. The count restarts
   with each lowering, so a function lowers to the same forms however much
   the session lowered before it, whether collection walked a unit cold or
   read its interface. The REPL lowers every entry under the one name
   `__repl_eval`, so it keeps one count across its session. Lexical slots use
   shorter names with a hyphen so they cannot shadow an ordinary C
   identifier. */
static int lower_repl_counter;

static Var _lower_name(Lowering l, String stem) {
  int count = l.session_globals ? ++lower_repl_counter : ++l.counter;
  if (stem != "loop" && stem != "after")
    return Atom.intern(%"$stem-$count");
  if (!l.own) return Atom.intern(%"$stem$count");
  return Atom.intern(%"$stem$count-${l.own}");
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
  Array parts = $auto([]);
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
static Var _lower_bare(Var form);

static void _lower_scan_each(Lowering l, List items) {
  foreach (Var item, items) _lower_scan(l, item);
}


/* The ordinary cursor calls emitted by the foreach expansion. Their
   cursor and outputs can occupy frame slots instead of addressed cells. */
struct LowerCursor {
  Symbol kind;
  int object, cursor, item, value;
};

static int _lower_cursor(Var test, struct LowerCursor *walk) {
  match (test) {
    case %(expr ? (call (expr ? (ident (binding ? ?(String name))))
          (args (expr ? (ident (binding ?(int object) ?)))
            (expr ? (op & (expr ? (ident (binding ?(int cursor) ?)))))
            (expr ? (op & (expr ? (ident (binding ?(int item) ?)))))))): {
      if (name != "List_try_next" && name != "Array_try_next") return 0;
      walk.kind = name == "List_try_next" ? <list> : <array>;
      walk.object = object;
      walk.cursor = cursor;
      walk.item = item;
      walk.value = 0;
      return 1;
    }
    case %(expr ? (call (expr ? (ident (binding ? "Map_try_next")))
          (args (expr ? (ident (binding ?(int object) ?)))
            (expr ? (op & (expr ? (ident (binding ?(int cursor) ?)))))
            (expr ? (op & (expr ? (ident (binding ?(int item) ?)))))
            (expr ? (op & (expr ? (ident (binding ?(int value) ?)))))))): {
      walk.kind = <map>;
      walk.object = object;
      walk.cursor = cursor;
      walk.item = item;
      walk.value = value;
      return 1;
    }
  }
  return 0;
}

/* A cursor's storage cannot escape its block or be addressed by the body.
   Direct `try_next` loops whose outputs live after the loop keep their
   storage. */
static int _lower_cursor_addressed(Var form, struct LowerCursor *walk) {
  if (form is not <list>) return 0;
  List items = form;
  match (items)
    case %(op & (expr ? (ident (binding ?(int id) ?)))):
      return id == walk.cursor || id == walk.item || id == walk.value;
  foreach (Var part, items)
    if (_lower_cursor_addressed(part, walk)) return 1;
  return 0;
}

static void _lower_scan_cursor_block(Lowering l, List parts) {
  if (!parts) return;
  struct LowerCursor walk;
  match (_lower_bare(parts.last())) case %(while ?test ?body): {
    if (!_lower_cursor(test, &walk) || _lower_cursor_addressed(body, &walk))
      return;
    Map declared = $auto({});
    for (List rest = parts; rest.cdr(); rest = rest.cdr()) {
      Var part = _lower_bare(rest.car());
      if (_lower_cursor_addressed(part, &walk)) return;
      match (part) case %(declare ? (bindings *bindings)):
        foreach (Var binding, bindings) {
          match (binding) case %(op = ?target ?): binding = target;
          match (binding) case %(bind (binding ?(int id) ?) ?):
            declared[id] = 1;
        }
    }
    if (!declared.contains(walk.cursor) || !declared.contains(walk.item) ||
        (walk.value && !declared.contains(walk.value))) return;
    l.cursors[walk.cursor] = 1;
    l.cursors[walk.item] = 1;
    if (walk.value) l.cursors[walk.value] = 1;
  }
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
      if (l.compiler.meta_values.contains(id)) return;
      if (!l.cursors.contains(id)) {
        Var layout;
        l.cells[id] = l.locals.try_get(id, &layout) ? layout : 1;
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
    case %(bind (binding ?(int id) ?) *):
      if (!l.locals.contains(id)) l.locals[id] = 1;
  }
}

static void _lower_scan_storage_binding(
  Lowering l, Type type, Var declarator) {
  if (type.contains(<static>)) l.globals = 1;
  List binding = NULL;
  match (declarator) {
    case %(op = ?bound ?): binding = bound;
    default: binding = declarator;
  }
  Type declared = %(declare $type (bindings $binding))
    .type_from_ast().declared();
  if (declared.is_enum()) l.globals = 1;
  if (declared.is_array() && _lower_record_type(l, declared.dereference())) {
    (void) _lower_decline(l, "an array of structs");
    return;
  }
  Type record = _lower_record_type(l, declared);
  List layout = l.compiler.meta_type_layout(record ? record : declared);
  match (binding)
    case %(bind (binding ?(int id) ?) *): {
      l.locals[id] = layout ? layout : 1;
      if (record) {
        l.cells[id] = layout ? layout : 1;
        l.records[id] = record;
      }
    }
}

static void _lower_scan_storage_declaration(Lowering l, List form) {
  match (form) {
    case %(declare ?type (bindings *declarators)):
      foreach (Var declarator, declarators)
        _lower_scan_storage_binding(l, type, declarator);
    case %(param ?type ?declarator):
      _lower_scan_storage_binding(l, type, declarator);
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
   native from `etc/comptime.xlisp`, a function this pass installed, or a
   native `meta` function an included unit advertises, bound here on first
   use. The function being lowered is reachable from itself, because the
   definition binds its name before anything calls it. */
static int _lower_known(Lowering l, String name) {
  Var value;
  if (l.own && l.own.equal(name)) return 1;
  if (!l.compiler.macro_lisp.try_get(name, &value) &&
      !l.compiler.bind_native_meta(name)) return 0;
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

/* A union, or a struct with no compile-time layout, is refused here, where
   the reason is still plain. */
static int _lower_scan_aggregate(Lowering l, List items) {
  match (items) {
    case %(declare (union *) *): return 1;
    case %(declare ?type *):
      if (((Type) type).is_aggregate() && !_lower_record_type(l, type))
        return 1;
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
  match (items) case %(repl-init ? ? ?initializer): {
    _lower_scan(l, initializer);
    return;
  }
  _lower_scan_storage_declaration(l, items);
  match (items) case %(expr ?type ?):
    if (((Type) type).is_enum()) l.globals = 1;
  /* Both of these refuse the function outright, so the scan stops rather
     than reporting what the refused statement happens to call. */
  if (head == <defer>) {
    (void) _lower_decline(
      l, "defer, because a compile-time function does not free its "
         "values: the evaluator owns them");
    return;
  }
  if (_lower_scan_aggregate(l, items)) {
    (void) _lower_decline(
      l, "a struct or union, which has no compile-time representation");
    return;
  }
  if (head == <block>) _lower_scan_cursor_block(l, items.cdr());
  if (head == <while> || head == <for> || head == <do>) {
    _lower_scan_each(l, items);
    return;
  }
  if (head == <bind>) _lower_scan_bind(l, items);
  else if (head == <targets>) _lower_scan_targets(l, items.cdr());
  else if (head == <op>) _lower_scan_op(l, items);
  else if (head == <call> || head == <meta-call>) {
    _lower_scan_call(l, cons(<call>, items.cdr()));
    if (head == <meta-call>) l.meta_only = 1;
  }
  else if (head == <tpl-call>) {
    l.meta_only = 1;
    _lower_scan_each(l, items.caddr().cdr());
    return;
  }
  else if (head == <meta-cap>) return;
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

/* Classifies file-scope `id`: 1 for a mutable meta value, 0 for a const one,
   2 for REPL session state, or -1 after declining. An ordinary global has no
   compile-time value: a missing `C._globals` entry must never turn one into
   zero. */
static int _lower_meta_global(Lowering l, int id, int write) {
  Var row;
  if (!l.compiler.meta_values.try_get(id, &row)) {
    if (l.session_globals) return 2;
    (void) _lower_decline(l, "file-scope state not declared meta");
    return -1;
  }
  int mutable = row.list().car().integer();
  if (write && !mutable) {
    (void) _lower_decline(l, "write to a const meta value");
    return -1;
  }
  return mutable;
}

/* Whether an assignment may write local or file-scope `id`. A file-scope
   write makes the function impure. */
static int _lower_writable(Lowering l, int id) {
  if (l.locals.contains(id)) return 1;
  if (_lower_meta_global(l, id, 1) < 0) return 0;
  l.globals = 1;
  return 1;
}

/* An advertised meta value is a C object in session-owned bytes. */
static List _lower_meta_layout(Lowering l, int id) =>
  l.compiler.meta_values[id].list().cadr();

/* A name the function never declares is advertised file-scope state, and
   reading it makes the function impure. */
static Var _lower_read(Lowering l, int id) {
  Var form;
  if (l.env.try_get(id, &form)) return form;
  if (!l.locals.contains(id)) {
    int kind = _lower_meta_global(l, id, 0);
    if (kind < 0) return void;
    l.globals = 1;
    if (kind == 2) return %(C.gread $id);
    return %(C.peek (C.mgaddress $id) 0
                    (quote ${_lower_meta_layout(l, id)}));
  }
  return _lower_decline(l, "unbound local");
}

/* The value a local holds. An object in bytes is read through its slot, and
   a record reads as that address; an evaluator cell loads its Var. Every
   other slot already is the value. */
static Var _lower_value(Lowering l, int id) {
  Var slot = _lower_read(l, id);
  if (_lower_failed(l, slot)) return void;
  List layout = _lower_storage_layout(l, id);
  if (layout && layout.car() == <record>) return slot;
  if (layout) return %(C.peek $slot 0 (quote $layout));
  if (l.cells.contains(id)) return %(C.load $slot);
  return slot;
}

/* --- literals ----------------------------------------------------------- */

static Var _lower_number(Lowering l, List type, String text) {
  Var value = ((Type) type).numeric_literal_value(text);
  if (value is not void) return value;
  return _lower_decline(l, "unreadable numeric literal");
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
    return (char) (body.len() ? body[0] : 0);
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
    case %(expr ? (parens ?inner)):
      return _lower_constant_leaf(l, inner);
    case %(expr ?type (cast ? ?inner)): {
      Var constant = _lower_constant_leaf(l, inner);
      if (constant is void) return void;
      Symbol tag = ((Type) type).scalar_tag();
      return tag ? constant.convert(tag) : constant;
    }
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

/* The slot holding a local's storage, or a meta value's session bytes. */
static Var _lower_address(Lowering l, int id) {
  if (l.compiler.meta_values.contains(id)) return %(C.mgaddress $id);
  Var slot;
  if (!l.env.try_get(id, &slot))
    return _lower_decline(l, "address of an unknown local");
  return slot;
}

/* An object in bytes is addressed by its slot, which native code would box
   the same way; a record's slot is retagged as native code tags its pointer.
   An evaluator cell retags its raw `Var` slot. */
static Var _lower_typed_address(Lowering l, List type, int id) {
  Symbol tag = l.compiler.sym.var_tag_for_type(type, NULL);
  Var slot = void;
  List layout = NULL;
  if (l.compiler.meta_values.contains(id)) layout = _lower_meta_layout(l, id);
  else if (l.locals.contains(id)) layout = _lower_storage_layout(l, id);
  else {
    /* A REPL-persistent record is its session bytes; other file-scope
       state has no address at compile time. */
    Type pointer = l.compiler.sym.resolve_key(type);
    Type record = pointer && pointer.is_pointer()
                ? _lower_record_type(l, pointer.dereference()) : NULL;
    if (!record || !l.session_globals)
      return _lower_decline(l, "the address of file-scope state");
    l.globals = 1;
    slot = %(C.gread $id);
    layout = l.compiler.meta_type_layout(record);
  }
  if (slot is void) slot = _lower_address(l, id);
  if (_lower_failed(l, slot)) return void;
  if (layout && (layout.car() != <record> || !tag)) return slot;
  if (!tag) return _lower_decline(l, "an address with no Var pointer tag");
  return %(C.address $slot (quote $tag));
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
static Var _lower_coerce(Lowering l, List want, Var node, Var value);
static Var _lower_initializer(Lowering l, List type, int id, Var init);

/* Reads the `type` object a place addresses. An object with a native layout
   is read from its bytes, and a record reads as its own address; any other
   place is an evaluator cell. A field place's offset goes to the access
   itself, so reading a field is one native call. */
static Var _lower_load(Lowering l, Type type, Var place) {
  List layout = l.compiler.meta_type_layout(type);
  if (!layout) return %(C.load $place);
  if (layout.car() == <record>) return place;
  Var base = place, offset = 0;
  match (place) case %(C.at ?object ?at ?): (base, offset) = %($object $at);
  return %(C.peek $base $offset (quote $layout));
}

/* Writes `value`, already converted to `type`, where a place addresses. A
   record is copied into the existing bytes, so addresses taken from it stay
   valid, as they do in C. */
static Var _lower_poke(Lowering l, Type type, Var place, Var value) {
  List layout = l.compiler.meta_type_layout(type);
  if (!layout) return %(C.store $place $value);
  Var base = place, offset = 0;
  match (place) case %(C.at ?object ?at ?): (base, offset) = %($object $at);
  return %(C.poke $base $offset (quote $layout) $value);
}

/* The type an expression node carries, or nothing for a node that is not
   one. An lvalue names the type its store converts to. */
static Type _lower_type_of(Var node) {
  match (node) case %(expr ?type ?): return type;
  return NULL;
}

/* Whether a compiler-known expression is an ordinary C object pointer, which
   compares by address alone. Function pointers and handles such as List keep
   their own Var equality. */
static int _lower_object_pointer_type(Lowering l, Type type) {
  Type represented = NULL;
  (void) l.compiler.sym.var_tag_for_type(type, &represented);
  /* A semantic handle such as List or Array owns a non-pointer Type at the
     Var boundary even though its native typedef later resolves to a pointer.
     This fact is process-stable during shallow xmacro lowering, unlike the
     unit-local converter registry. Raw pointer typedefs resolve to a pointer
     here and remain eligible. */
  if (represented && !represented.is_pointer()) return 0;
  Type pointer = type ? l.compiler.sym.resolve_key(type) : NULL;
  if (!pointer || pointer.car() != <*> || !pointer.is_pointer()) return 0;
  Type pointee = pointer.dereference();
  return pointee && !pointee.is_function();
}

/* The byte offset of a resolved field path from its outermost record, and
   the selected field's layout. */
static long _lower_field_offset(Lowering l, List path, List *field_layout) {
  long offset = 0;
  foreach (List frame, path.reverse()) {
    match (frame) {
      case %(? index *): {
        (void) _lower_decline(l, "an array inside a compile-time struct");
        return -1;
      }
      case %(?owner field ?name *):
        match (l.compiler.meta_type_layout(owner))
          case %(record ? ? ? * (field $name ? ?at ?layout) *): {
            offset += at.long_long();
            *field_layout = layout;
            continue;
          }
    }
    (void) _lower_decline(l, "a compile-time struct with no host layout");
    return -1;
  }
  return offset;
}

/* The typed pointer to one field. `a.f` offsets the address `a` reads as,
   and `p->f` offsets the pointer `p`. */
static Var _lower_field_place(
  Lowering l, Symbol access, Var receiver, List field) {
  Type owner = _lower_type_of(receiver);
  if (access == <"->">) {
    Type pointer = l.compiler.sym.resolve_key(owner);
    if (!pointer || !pointer.is_pointer())
      return _lower_decline(l, "field access through a non-pointer");
    owner = pointer.dereference();
  }
  Type record = _lower_record_type(l, owner);
  if (!record)
    return _lower_decline(l, "a struct with no compile-time layout");
  List path = l.compiler.initializer_field_path(record, field);
  if (!path) return _lower_decline(l, "an unknown compile-time struct field");
  List layout = NULL;
  long offset = _lower_field_offset(l, path, &layout);
  if (offset < 0) return void;
  Symbol tag = _lower_pointer_tag(l, layout);
  Var object = _lower_expr(l, receiver);
  if (_lower_failed(l, object)) return void;
  return %(C.at $object $offset (quote $tag));
}

static Var _lower_initializer(Lowering l, List type, int id, Var init);

/* One owner for addressable x2c places. A substitution-only scalar returns
   void and continues through the existing SSA-style local path. */
static Var _lower_place(Lowering l, Var target) {
  match (target) {
    case %(expr ? (ident (binding ?(int id) ?))):
      if (l.compiler.meta_values.contains(id) ||
          (l.locals.contains(id) && l.cells.contains(id)))
        return _lower_address(l, id);
    case %(expr ? (op ?operator ?operand)):
      if (operator == <"*">) return _lower_expr(l, operand);
    /* A struct compound literal is a fresh object, such as the Iter storage
       a `foreach` expansion supplies. */
    case %(expr ?type (cast ? ?literal)):
      if (_lower_record_type(l, type))
        return _lower_initializer(l, type, 0, literal);
    case %(expr ? (op ?access ?receiver ?field)):
      if (access == <.> || access == <"->">)
        return _lower_field_place(l, access, receiver, field);
  }
  return void;
}

/* A value reaching a C scalar type carries that type's `Var` tag, which is
   what makes every later operation behave the way C does: `Var.binary`
   applies the usual arithmetic conversions from the operand tags, so
   unsigned division and comparison, narrow wraparound and the signed shift
   all follow from the destination types the author wrote. `Var.convert` is
   the conversion itself - integer narrowing keeps low bits, floating to
   integer truncates toward zero, and an integer reaching a floating type
   widens - so this pass names a tag and performs no arithmetic of its own.
   A type with no scalar tag, a pointer or a library type, keeps its value.
   A bool is the exception: C converts any nonzero value to 1. */
static Var _lower_to_type(Lowering l, Type want, Var value) {
  if (l.compiler.sym.is_bool_type(want)) return %(C.bool $value);
  Type resolved = l.compiler.sym.resolve_numeric_type(want);
  Symbol tag = resolved ? resolved.scalar_tag() : 0;
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
  Array values = $auto([]);
  for (List p = params, a = args; a; p = p.cdr(), a = a.cdr()) {
    List argument = a.car();
    match (argument) case %(expr (void) ()): continue;
    Var value = _lower_expr(l, argument);
    if (_lower_failed(l, value)) return NULL;
    values.push(_lower_coerce(l, _lower_param_type(p), argument, value));
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
  Array values = $auto([]);
  foreach (List part, parts) {
    Var value = _lower_expr(l, part);
    if (_lower_failed(l, value)) return void;
    values.push(value);
  }
  return values.list();
}

/* `Var.binary` applies the usual arithmetic conversions itself for the
   arithmetic operators, so only a comparison needs them written out: `==`
   and `!=` compare represented values there, which 1.0 and 1 fail, and the
   relations compare the values as written rather than as C converts them,
   so a negative signed operand does not become the large unsigned one C
   makes of it. */
static int _lower_relation(Var operator) =>
  operator == <==> || operator == <!=> || operator == <"<"> ||
  operator == <"<="> || operator == <">"> || operator == <">=">;

/* The C scalar type a value of `type` has in arithmetic, or NULL. A bool or
   enum value is the int C promotes it to. */
static Type _lower_numeric_type(Lowering l, Type type) {
  Type numeric = type ? l.compiler.sym.resolve_numeric_type(type) : NULL;
  if (numeric && numeric.scalar_tag()) return numeric;
  if ((numeric && numeric.is_enum()) ||
      (type && l.compiler.sym.is_bool_type(type)))
    return %(int);
  return NULL;
}

/* Whether two operands are scalars of different families. An equal pair,
   which is nearly every pair, needs no conversion and is left alone. */
static int _lower_mixed_scalars(Lowering l, List operands) {
  if (operands.len() != 2) return 0;
  Type left = _lower_numeric_type(l, _lower_type_of(operands.car()));
  Type right = _lower_numeric_type(l, _lower_type_of(operands.cadr()));
  Symbol a = left.scalar_tag(), b = right.scalar_tag();
  return a && b && a != b;
}

/* `NULL`, which the compiler never declares, or a literal zero. */
static int _lower_null_constant(Var operand) {
  match (operand) {
    case %(expr () (ident (binding ? "NULL"))): return 1;
    case %(expr ? (literal ? "0")): return 1;
  }
  return 0;
}

/* Two object pointers, or one and a null pointer constant, compare by
   address as C compares them. */
static int _lower_object_pointer_operands(Lowering l, List operands) {
  if (operands.len() != 2) return 0;
  Var left = operands.car(), right = operands.cadr();
  int a = _lower_object_pointer_type(l, _lower_type_of(left));
  int b = _lower_object_pointer_type(l, _lower_type_of(right));
  return (a && b) || (a && _lower_null_constant(right)) ||
         (b && _lower_null_constant(left));
}

static Var _lower_operands(
  Lowering l, Type result, Var operator, List operands) {
  Array values = $auto([]);
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
    /* C compares object pointers by address alone, while each Var carries
       its pointee's tag, so both sides compare as untyped addresses. */
    if (_lower_relation(operator) &&
        _lower_object_pointer_operands(l, operands))
      return %(_binary (C.address $left (quote <p48>))
                      (quote $operator) (C.address $right (quote <p48>)));
    if (_lower_relation(operator) && _lower_mixed_scalars(l, operands))
      return %(C.compare $left (quote $operator) $right);
    return %(_binary $left (quote $operator) $right);
  }
  if (values.len() == 3) {
    Var test = values[0], a = values[1], b = values[2];
    a = _lower_coerce(l, result, operands.cadr(), a);
    b = _lower_coerce(l, result, operands.caddr(), b);
    return %(C.ternary $test $a $b);
  }
  return _lower_decline(l, "unsupported operator arity");
}

/* A lambda's free locals are substituted, which is the by-value snapshot
   x2c gives a captured scalar. Its parameters get fresh slots. */
static Var _lower_lambda(Lowering l, List params, List held, Var body) {
  Array names = $auto([]);
  Array saved = $auto([]);
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
  Array shadowed = $auto([]);
  Map previous = $auto({});
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

/* The layout of the object a pointer indexes, or nothing when `receiver` is
   not a pointer to a type with one. The pointer may hold a local C array's
   `Array` or native bytes, and only evaluation can tell them apart, so
   `C.index` decides there. */
static List _lower_pointee_layout(Lowering l, Var receiver) {
  Type type = _lower_type_of(receiver);
  Type pointer = type ? l.compiler.sym.resolve_key(type) : NULL;
  if (!pointer || !pointer.is_pointer()) return NULL;
  return l.compiler.meta_type_layout(pointer.dereference());
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
  List layout = is_c_array ? _lower_pointee_layout(l, receiver) : NULL;
  match (layout) case %(? ? ?size *):
    return %(C.index $target $index $size (quote $layout));
  return %(${Atom.intern(container + "_getindex")} $target $index);
}

/* One `match` over the expression grammar. The compiler turns it into a
   decision tree, so reading the productions costs nothing extra. */
static Var _lower_expr(Lowering l, Var form) {
  if (l.declined) return void;
  match (form) {
    case %(at ? ?node):                   return _lower_expr(l, node);
    /* A tag the compiler supplies to a `Var` conversion, such as the one a
       typed `foreach` output reads through, is the Symbol's code. */
    case %(expr ("Symbol") ?(String code)):
      return %(quote ${(Symbol) strtoul(code, NULL, 10)});
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
    case %(literal ("Var") "void"): return %(C.void);
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
      /* A name with no type has no declaration the compiler read: it is a
         preprocessor macro. The null pointer constant and `stdbool.h`'s
         truth values are the ones C code writes as plain names. */
      if (!type && !l.locals.contains(id)) {
        if (name == "NULL" || name == "false") return 0;
        if (name == "true") return 1;
        return _lower_decline(l, "a name with no declaration: " + name);
      }
      return _lower_value(l, id);
    }
    case %(parens (block *)):             return _lower_application(l, content);
    case %(parens ?inner):                return _lower_expr(l, inner);
    /* A cast is a conversion the author wrote, and the type it names is the
       one the surrounding `expr` node already carries. */
    case %(cast ? ?inner): {
      Var value = _lower_expr(l, inner);
      if (_lower_failed(l, value)) return void;
      Type target = l.compiler.sym.resolve_numeric_type(type);
      if (target && target.scalar_tag())
        return _lower_to_type(l, target, value);
      return _lower_coerce(l, type, inner, value);
    }
    case %(expr ?inner ?within):          return _lower_content(l, inner, within);
    case %(at ? ?node):                   return _lower_content(l, type, node);
    case %(op & (expr ? (ident (binding ?(int id) ?)))):
      return _lower_typed_address(l, type, id);
    case %(op & ?target): {
      Var place = _lower_place(l, target);
      if (l.declined) return void;
      if (place is void)
        return _lower_decline(l, "an address of a value with no storage");
      Symbol tag = l.compiler.sym.var_tag_for_type(type, NULL);
      return tag ? %(C.address $place (quote $tag)) : place;
    }
    /* `*` is a sequence binder in a pattern, so a unary deref is matched by
       arity and then by its operator. */
    case %(op ?operator ?operand): {
      if (operator == <"*">) {
        Var pointer = _lower_expr(l, operand);
        if (_lower_failed(l, pointer)) return void;
        return _lower_load(l, type, pointer);
      }
      return _lower_operands(l, type, operator, %($operand));
    }
    case %(call (expr ? (ident (binding ? "Func_apply"))) ?):
      return _lower_application(l, content);
    case %(meta-cap ?captured): return %(quote $captured);
    case %(tpl-call ?definition (args *arguments)): {
      List values = _lower_args(l, NULL, arguments);
      return %(_x2c.tpl-call (quote $definition) (list @values));
    }
    case %(meta-call (expr ?callee (ident (binding ? ?(String name))))
                    (args *args)):
      return _lower_call(l, callee, name, args);
    case %(call (expr ?callee (ident (binding ? ?(String name))))
                (args *args)):
      return _lower_call(l, callee, name, args);
    case %(call ?(String name) (args *args)):
      return _lower_call(l, NULL, name, args);
    case %(op ?access ?receiver ?field): {
      if (access != <.> && access != <"->">)
        return _lower_operands(l, type, access, %($receiver $field));
      Var place = _lower_field_place(l, access, receiver, field);
      if (_lower_failed(l, place)) return void;
      return _lower_load(l, type, place);
    }
    case %(op ?operator *operands):
      return _lower_operands(l, type, operator, operands);
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
  Map copy = _lower_scratch_map(l.scratch);
  foreach (Var (id, form), l.env) copy[id] = form;
  return copy;
}

static void _lower_env_restore(Lowering l, Map saved) {
  l.env = saved;
}

static Var _lower_apply_k(Lowering l, List k) {
  match (k) {
    case %(end): return %(C.void);
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
      Array values = $auto([]);
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

/* The equality adapters box Lisp equality as an int. A guard needs only
   the equality, without boxing and retesting it. Other values still need
   C.true?: even a typed parameter may arrive through an uncoerced Lisp call. */
static Var _lower_truth(Lowering l, Var test) {
  Var value = _lower_expr(l, test);
  if (_lower_failed(l, value)) return void;
  match (value) {
    case %(Var_equal ?a ?b): return %(eq? $a $b);
    case %(List_equal ?a ?b): return %(eq? $a $b);
  }
  return %(C.true? $value);
}

/* Substitution can move, repeat, or discard evaluation. Only the known
   arithmetic and control operations below allow it when their operands do.
   Other calls need a binding regardless of their spelling; quoted data is
   already a value, not an expression to inspect. */
static int _lower_pure(Var form) {
  if (form is not <list>) return 1;
  List items = form;
  if (!items) return 1;
  Var head = items.car();
  if (head is not <lsym> && head is not <symbol>) return 0;
  String name = head.str();
  if (name == "quote") return 1;
  if (name != "_binary" && name != "C.conv" && name != "C.compare" &&
      name != "C.nonzero?" && name != "C.true?" && name != "C.not" &&
      name != "C.and" && name != "C.or" && name != "C.ternary" &&
      name != "not" && name != "eq?")
    return 0;
  foreach (Var operand, items.cdr()) if (!_lower_pure(operand)) return 0;
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

/* A fixed-arity lambda discards an effect's result and keeps the rest of the
   block in tail position. Its raw parameter slot can transport `void`; the
   variadic `begin` helper cannot, because packing rest arguments into a List
   deliberately rejects `void`. */
static Var _lower_effect(Lowering l, Var effect, List rest, List k) {
  Var after = _lower_block(l, rest, k);
  if (_lower_failed(l, after)) return void;
  Var discarded = _lower_name(l, "discard");
  return %((lambda ($discarded) $after) $effect);
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
  Array binders = $auto([]);
  _lower_binders(pattern, binders);
  Map saved = _lower_env_copy(l);
  foreach (Var binder, binders) {
    String name = NULL;
    _lower_binder(binder, &name);
    Array ids = $auto([]);
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
        out.push(id);
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
  Array boxes = $auto([]);
  _lower_loop_cells(l, body, boxes);
  Map used = $auto({});
  _lower_referenced(test, used);
  _lower_referenced(body, used);
  _lower_referenced(step, used);
  _lower_referenced(rest, used);
  _lower_referenced(k, used);
  /* The element is read where it is used, so the loop does not carry it. */
  struct LowerCursor walk;
  int walking = _lower_cursor(test, &walk) && l.cursors.contains(walk.cursor);
  if (walking) {
    used.del(walk.item);
    if (walk.value) used.del(walk.value);
  }
  Array ids = $auto([]);
  Array slots = $auto([]);
  Array entry = [];
  foreach (Var (id, form), l.env) {
    if (!used.contains(id)) continue;
    ids.push(id);
    if (walking && walk.kind == <map> && id == walk.cursor) {
      Var object = _lower_value(l, walk.object);
      form = %(if (number? $form) (Map.list $object) $form);
    }
    entry.push(form);
  }
  Map inside = _lower_scratch_map(l.scratch);
  foreach (Var id, ids) {
    Var slot = _lower_name(l, "live");
    slots.push(slot);
    inside[id] = slot;
  }
  Map outer = l.env;
  l.env = inside;
  /* List and Map carry the remaining list; Array carries an index and
     observes its current length each turn, just as its cursor operation
     does. Outputs read the current element before advancing the cursor. */
  Var guard;
  if (walking && inside.contains(walk.cursor)) {
    Var cursor = inside[walk.cursor];
    if (walk.kind == <array>) {
      Var object = _lower_value(l, walk.object);
      guard = %(< $cursor (Array.len $object));
      l.env[walk.item] = %(Array.getindex $object $cursor);
      l.env[walk.cursor] = %(+ $cursor 1);
    }
    else {
      guard = %(C.true? $cursor);
      l.env[walk.item] = walk.kind == <map>
        ? %(car (car $cursor)) : %(car $cursor);
      if (walk.value) l.env[walk.value] = %(cadr (car $cursor));
      l.env[walk.cursor] = %(cdr $cursor);
    }
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
  Array names = $auto([]);
  Array storage = $auto([]);
  foreach (Var id, boxes) {
    names.push(l.env[id]);
    List layout = _lower_storage_layout(l, id);
    storage.push(layout ? _lower_new_storage(l, layout) : %(C.cell 0));
  }
  return %((lambda ${names.list()} $call) @{storage.list()});
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
  Array arms = $auto([]);
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
  Array clauses = $auto([]);
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

/* An object in bytes gets fresh storage at its declaration, and an
   evaluator cell boxes its value. Every other local keeps the value itself. */
static Var _lower_boxed(Lowering l, int id, Var value, int fresh) {
  if (_lower_failed(l, value)) return void;
  List layout = _lower_storage_layout(l, id);
  if (layout) return _lower_new_object(l, layout, value, fresh);
  if (l.cells.contains(id)) return %(C.cell $value);
  return value;
}

/* A C array's dimension, read at lowering time so a partly written one is
   zero-filled the way C fills it. A computed dimension has no such answer. */
static int _lower_dimension(Lowering l, int id, int *out) {
  Var size;
  if (!l.arrays.try_get(id, &size)) return 0;
  match (size)
    case %(expr ? (literal ?(List type) ?(String text))): {
      Var count = ((Type) type).numeric_literal_value(text);
      if (count is not void && count >= 0 && count <= (int) INT_MAX) {
        *out = (int) count;
        return 1;
      }
    }
  return 0;
}

static Var _lower_coerce(Lowering l, List want, Var node, Var value);

/* A record's storage is zeroed bytes, the way C zero-fills an object whose
   initializer names no field. `into` names storage a loop already holds for
   the record, which is zeroed in place; otherwise the bytes are new. */
static Var _lower_record_zero(Lowering l, Type type, Var into) {
  Type record = _lower_record_type(l, type);
  match (record ? l.compiler.meta_type_layout(record) : NULL)
    case %(? ? ?size *): {
      l.automatic = 1;
      if (into is not void) return %(C.zero $into $size);
      return %(C.bytes $size);
    }
  return _lower_decline(l, "a compile-time struct with no host layout");
}

/* Each initializer row stores one field value at its offset. */
static Var _lower_record_braced(
  Lowering l, Type type, List items, Var into) {
  Type record = _lower_record_type(l, type);
  Var fresh = _lower_record_zero(l, record, into);
  if (_lower_failed(l, fresh) || !items) return fresh;
  Var slot = _lower_name(l, "record");
  Array stores = $auto([]);
  foreach (List row, l.compiler.initializer_rows(record, items, NULL)) {
    List choices = row.cadr();
    if (!choices || choices.cdr())
      return _lower_decline(
        l, "a native-dependent compile-time struct initializer");
    List choice = choices.car();
    List condition = choice.car(), path = choice.cadr();
    Type destination = choice.caddr();
    List input = choice[3];
    if (condition || !destination || !path)
      return _lower_decline(
        l, "an unsupported compile-time struct initializer");
    List layout = NULL;
    long offset = _lower_field_offset(l, path, &layout);
    if (offset < 0) return void;
    Var value = _lower_initializer(l, destination, 0, input);
    if (_lower_failed(l, value)) return void;
    stores.push(%(C.poke $slot $offset (quote $layout) $value));
  }
  return %((lambda ($slot) (begin @{stores.list()} $slot)) $fresh);
}

/* A braced initializer carries no type of its own, so the declared type
   decides which container it builds. */
static Var _lower_braced(Lowering l, List type, int id, List items) {
  if (_lower_record_type(l, type))
    return _lower_record_braced(l, type, items, void);
  if (l.arrays.contains(id)) {
    Type declared = type;
    Type element = declared.is_array() ? declared.dereference() : declared;
    int size = 0;
    if (!_lower_dimension(l, id, &size))
      return _lower_decline(l, "an array dimension that is not a literal");
    Array values = _lower_values(l, items);
    if (l.declined) return void;
    if (values.len() > size) {
      values.free();
      return _lower_decline(l, "more initializers than the array holds");
    }
    int index = 0;
    foreach (Var item, items) {
      values[index] = _lower_coerce(l, element, item, values[index]);
      index++;
    }
    Var zero = _lower_to_type(l, element, _lower_zero(element));
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
static Var _lower_coerce(Lowering l, List want, Var node, Var value) {
  match (node)
    case %(expr ?from ?): {
      Type target_record = _lower_record_type(l, want);
      Type source_record = _lower_record_type(l, from);
      if (target_record || source_record) {
        if (!target_record || !source_record ||
            !target_record.equal(source_record)) {
          String types = %"${want.repr()} from ${from.repr()}";
          return _lower_decline(
            l, "incompatible compile-time struct types: " + types);
        }
        return value;
      }
      if (want.equal(from)) return value;
      if (l.compiler.sym.is_bool_type(want))
        return _lower_to_type(l, want, value);
      if (want.equal(%("List")) && from.equal(%("Array")))
        return %(Array_list $value);
      if (want.equal(%("Array")) && from.equal(%("List")))
        return %(List_array $value);
      if (want.equal(%("String")) && from.equal(%("Symbol")))
        return %(Symbol_str $value);
      /* A C pointer with no Var tag of its own, such as `&storage` for a
         `struct Iter`, takes the tag native code gives its destination. */
      Symbol want_tag = l.compiler.sym.var_tag_for_type(want, NULL);
      Type want_pointer = l.compiler.sym.resolve_key(want);
      Type from_pointer = l.compiler.sym.resolve_key(from);
      if (want_tag && want_pointer && want_pointer.is_pointer() &&
          from_pointer && from_pointer.is_pointer() &&
          _lower_object_pointer_type(l, want) &&
          _lower_object_pointer_type(l, from) &&
          want_tag != l.compiler.sym.var_tag_for_type(from, NULL))
        return %(C.address $value (quote $want_tag));
      if (l.compiler.sym.is_named_value_type(want, "Symbol") &&
          _lower_numeric_type(l, from))
        return %(C.address $value (quote <symbol>));
      Type target = _lower_numeric_type(l, want);
      Type source = _lower_numeric_type(l, from);
      Symbol tag = target ? target.scalar_tag() : 0;
      if (tag && source && tag != source.scalar_tag())
        return _lower_to_type(l, target, value);
    }
  return value;
}

/* An array literal knows it is an `Array`, so only a `List` destination
   needs the conversion. A braced initializer knows nothing, so its
   destination decides outright. */
/* Whether an initializer is braced, so the value it lowers to is new. */
static int _lower_braced_init(Var init) {
  match (init) case %(expr ? (composite *)): return 1;
  return 0;
}

static Var _lower_initializer(Lowering l, List type, int id, Var init) {
  match (init) {
    case %(expr ? (composite (commas *items))):
      return _lower_braced(l, type, id, items);
    case %(expr ? (composite)): return _lower_braced(l, type, id, %());
  }
  Var value = _lower_expr(l, init);
  if (_lower_failed(l, value)) return void;
  return _lower_coerce(l, type, init, value);
}

static Var _lower_declarator(
  Lowering l, List type, List declarator, List rest, List k) {
  match (declarator) {
    case %(op = (!set ?bound (bind (binding ?(int id) ?) *)) ?init): {
      Type declared = %(declare $type (bindings $bound))
        .type_from_ast().declared();
      /* A record in a loop's storage is initialized where it is. */
      if (l.records.contains(id) && l.env.contains(id)) {
        Var into = _lower_address(l, id);
        match (init) {
          case %(expr ? (composite (commas *items))):
            return _lower_effect(
              l, _lower_record_braced(l, declared, items, into), rest, k);
          case %(expr ? (composite)):
            return _lower_effect(
              l, _lower_record_zero(l, declared, into), rest, k);
        }
      }
      Var value = _lower_initializer(l, declared, id, init);
      if (l.cells.contains(id) && l.env.contains(id)) {
        if (_lower_failed(l, value)) return void;
        return _lower_effect(
          l, _lower_poke(l, declared, _lower_address(l, id), value), rest, k);
      }
      Var boxed = _lower_boxed(l, id, value, _lower_braced_init(init));
      return _lower_bind_value(l, id, boxed, rest, k);
    }
    case %(!set ?bound (bind (binding ?(int id) ?) *)): {
      Type declared = %(declare $type (bindings $bound))
        .type_from_ast().declared();
      Var initial;
      int filled = l.cells.contains(id) && l.env.contains(id);
      if (l.arrays.contains(id)) initial = _lower_braced(l, declared, id, %());
      else if (l.records.contains(id))
        initial = _lower_record_zero(
          l, declared, filled ? _lower_address(l, id) : void);
      else initial = _lower_zero(declared);
      if (_lower_failed(l, initial)) return void;
      if (filled && l.records.contains(id))
        return _lower_effect(l, initial, rest, k);
      /* A box the enclosing loop already allocated is filled, not rebound.
         A `foreach` inside a `foreach` declares its output cell with no
         initializer, so without this a nested loop cannot lower. */
      if (filled)
        return _lower_effect(
          l, _lower_poke(l, declared, _lower_address(l, id), initial),
          rest, k);
      return _lower_bind_value(
        l, id, _lower_boxed(l, id, initial, 1), rest, k);
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
  source = _lower_coerce(l, %("List"), init, source);
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
  Var store = %(${Atom.intern(container + "_setindex")} $target $index $value);
  List layout = is_c_array ? _lower_pointee_layout(l, receiver) : NULL;
  match (layout) case %(? ? ?size *):
    store = %(C.index.set $target $index $size (quote $layout) $value);
  return _lower_effect(l, store, rest, k);
}

static Var _lower_store(
  Lowering l, Var target, Var value, List rest, List k) {
  match (target) {
    case %(expr ? (getindex ?receiver ?key)):
      return _lower_setindex(l, receiver, key, 0, value, rest, k);
    case %(expr ? (index ?receiver ?key)):
      return _lower_setindex(l, receiver, key, 1, value, rest, k);
  }
  int id = _lower_target(target);
  Type type = _lower_type_of(target);
  if (id >= 0 && !_lower_writable(l, id)) return void;
  Var place = _lower_place(l, target);
  if (l.declined || _lower_failed(l, value)) return void;
  if (place is not void)
    return _lower_effect(l, _lower_poke(l, type, place, value), rest, k);
  if (id < 0) return _lower_decline(l, "assignment to a computed place");
  if (!l.locals.contains(id)) {
    match (l.compiler.meta_type_layout(type))
      case %(record ? ?size *):
        return _lower_effect(
          l, %(C.grecord.write $id $value $size), rest, k);
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
  if (_lower_failed(l, right)) return void;
  Type want = _lower_type_of(target);
  if (id >= 0 && !_lower_writable(l, id)) return void;
  Var place = _lower_place(l, target);
  if (l.declined) return void;
  if (place is not void) {
    Var slot = _lower_name(l, "place");
    Var combined = _lower_to_type(l, want, %(
      _binary ${_lower_load(l, want, slot)} (quote $operator) $right));
    return _lower_effect(
      l, %((lambda ($slot) ${_lower_poke(l, want, slot, combined)}) $place),
      rest, k);
  }
  if (id < 0) return _lower_decline(l, "update of a computed place");
  if (!l.locals.contains(id)) {
    Var combined = _lower_to_type(
      l, want, %(_binary (C.gread $id) (quote $operator) $right));
    return _lower_effect(l, %(C.gwrite $id $combined), rest, k);
  }
  Var current = _lower_value(l, id);
  if (_lower_failed(l, current)) return void;
  Var combined = _lower_to_type(
    l, want, %(_binary $current (quote $operator) $right));
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
        value = _lower_coerce(l, _lower_type_of(target), rhs, value);
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
      Var result = _lower_initializer(l, want, 0, value);
      if (_lower_failed(l, result) || !_lower_record_type(l, want))
        return result;
      match (l.compiler.meta_type_layout(want)) case %(? ? ?size *): {
        l.automatic = 1;
        return %(C.record.result $result $size);
      }
      return result;
    }
    case %(return):        return %(C.void);
    case %(repl-init ?type
                     (bind (binding ?(int id) ?name) ?mods) ?initializer): {
      List bound = %(bind (binding $id $name) $mods);
      Type declared = %(declare $type (bindings $bound))
        .type_from_ast().declared();
      Var value = _lower_initializer(l, declared, id, initializer);
      if (_lower_failed(l, value)) return void;
      l.globals = 1;
      match (_lower_record_type(l, declared)
             ? l.compiler.meta_type_layout(declared) : NULL)
        case %(? ? ?size *):
          return _lower_effect(
            l, %(C.grecord.write $id $value $size), rest, k);
      return _lower_effect(l, %(C.gwrite $id $value), rest, k);
    }
    case %(declare ?type (bindings ?declarator)):
      return _lower_declarator(l, type, declarator, rest, k);
    /* Phase 3 owns these two cases; the rest of the statement grammar is
       Phase 2's. */
    case %(dstrdecl ? (targets *targets) ?init):
      return _lower_destructure(l, targets, init, rest, k);
    case %(dstrdecl (params *params) ?init):
      return _lower_destructure(l, params, init, rest, k);
    case %(declare ?type (bindings *declarators)): {
      Array expanded = $auto([]);
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

/* Shared lowering for ordinary compile-time functions and the REPL's
   private execution wrapper. */
static List _lower_function(
  Compiler compiler, List fn, int session_globals) {
  Scope scratch = $auto(Scope.new());
  struct Lowering state = {
    .compiler = compiler, .scratch = scratch,
    .env = _lower_scratch_map(scratch), .locals = _lower_scratch_map(scratch),
    .cells = _lower_scratch_map(scratch), .arrays = _lower_scratch_map(scratch),
    .records = _lower_scratch_map(scratch),
    .callees = _lower_scratch_map(scratch), .cursors = _lower_scratch_map(scratch),
    .definitions = [],
    .declined = 0,
    .own = NULL, .on_break = NULL, .on_continue = NULL, .on_loop = 0,
    .rejected = 0, .uncallable = 0, .globals = 0,
    .meta_only = 0, .session_globals = session_globals
  };
  Lowering l = &state;
  lower_reached_globals = 1;
  lower_reached_meta = 0;
  match (fn) {
    case %(function ?spec (bind (binding ? ?(String name))
                            ((fnmod (params *params)) *)) (block *items)): {
      (void) spec;
      lower_declined_reason = NULL;
      lower_session_callees = NULL;
      l.own = name;
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
      Array slots = $auto([]);
      Array boxes = $auto([]);
      Array boxed_values = $auto([]);
      foreach (List parameter, params) {
        match (parameter)
          case %(param ? (bind (binding ?(int id) ?) *)): {
            Var slot = _lower_name(l, "arg");
            slots.push(slot);
            l.env[id] = slot;
            if (!l.cells.contains(id)) continue;
            /* A parameter in bytes is the callee's own copy, as a C
               argument is; any other addressed parameter gets a cell. */
            Var box = _lower_name(l, "box");
            boxes.push(box);
            boxed_values.push(_lower_boxed(l, id, slot, 0));
            l.env[id] = box;
          }
      }
      Var body = _lower_block(l, items, %(end));
      if (_lower_failed(l, body)) {
        l.definitions.free();
        return NULL;
      }
      if (boxes.len())
        body = %((lambda ${boxes.list()} $body) @{boxed_values.list()});
      Var definition = %(def ${Atom.intern(name)}
                             (lambda ${slots.list()} $body));
      l.definitions.push(
        l.automatic ? %(C.source-function $definition) : definition);
      lower_reached_globals = l.globals;
      lower_reached_meta = l.meta_only;
      lower_session_callees = l.callees.keys();
      return l.definitions.list_free();
    }
  }
  l.definitions.free();
  return NULL;
}

/** Lowers one compile-time function into the forms the macro session
    evaluates, or returns `NULL` when the substitution cannot carry it.
    The result is the loop definitions the body needed followed by the
    function's own, in evaluation order. This method does not open a
    semantic transaction.
*/
List Compiler.lower_comptime(Compiler compiler, List fn) =>
  _lower_function(compiler, fn, 0);

/** Lowers a REPL execution wrapper whose unresolved bindings name the
    session's persistent value table rather than program file-scope state. */
List Compiler.lower_repl(Compiler compiler, List fn) =>
  _lower_function(compiler, fn, 1);

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

   Process cache: "path#name" -> `(forms callees globals meta regions)`.
   The facts travel with the forms because a reused entry installs without
   lowering: the caller reads the first two to decide folding and emission,
   and `regions` is the summary the definition's lifetime check recorded
   before it was lowered, so a reused entry carries that check's result.
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

/** Restores the shared definitions' derived call restrictions into a fresh
    compiler pass. Reads existing process tables without opening Lisp or
    creating a lowering cache in the unit's Context.
*/
void Compiler.inherit_shared_meta(Compiler compiler) {
  if ((void *) lowered_defs == NULL) return;
  Map definitions = compiler.shared_definitions();
  if (!definitions) return;
  foreach (String key, definitions.keys())
    match (lowered_defs[key])
      case %(? ? ?(int globals) ?(int meta) ?(List regions)): {
        String name = key.rpartition("#")[2];
        if (globals) compiler.meta_impure[name] = 1;
        if (meta) compiler.meta_comptime[name] = 1;
        compiler.meta_regions[name] = regions;
      }
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

static void _retain_lowering(
  String key, List forms, List callees, List regions) {
  List entry = %(
    $forms $callees $lower_reached_globals $lower_reached_meta $regions
  );
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

/* The process cache key of a definition, "path#name", or NULL for one
   without a file. `*name` is the definition's name. */
static String _lowering_key(Compiler compiler, List fn, String *name) {
  match (fn)
    case %(function ? (bind (binding ? ?(String own)) ?) ?): {
      *name = own;
      if (compiler.filename)
        return %"${Path.absolute(compiler.filename)}#$own";
    }
  return NULL;
}

/** Returns the region summary an earlier install of `fn` from the same file
    recorded with its lowering, or NULL when the process has none. */
List Compiler.lowered_meta_regions(Compiler compiler, List fn) {
  String name = NULL, key = _lowering_key(compiler, fn, &name);
  if (!key || (void *) lowered_defs == NULL) return NULL;
  match (lowered_defs[key]) case %(? ? ? ? ?(List regions)): return regions;
  return NULL;
}

/** Lowers `fn` and evaluates the result in the macro session, so the
    function is callable from compile-time Lisp under its own name.
    Returns whether the lowering succeeded. This method mutates the macro
    session and does not open a semantic transaction.
*/
int Compiler.install_comptime(Compiler compiler, List fn) {
  String own = NULL, key = _lowering_key(compiler, fn, &own);
  /* The shared session installed this definition, from this file, before any
     unit opened. Installing it again would only try to replace a name an
     ancestor binds; the unit reads the shared one. */
  if (key && compiler.shared_definition(key))
    match (_lowered_defs()[key])
      case %(? ? ?(int shared_globals) ?(int shared_meta) ?): {
        lower_reached_globals = shared_globals;
        lower_reached_meta = shared_meta;
        return _installed_comptime(compiler, own);
      }
  /* A recursive call resolves against the name before the body is lowered,
     the way a C prototype lets a function call itself. */
  if (own) compiler.macro_lisp.eval(%(def ${Atom.intern(own)} (lambda () 0)));
  if (key)
    match (_lowered_defs()[key])
      case %(?(List forms) ?(List callees) ?(int globals) ?(int meta) ?):
        if (_lowered_callable(compiler, callees)) {
          foreach (Var form, forms) compiler.macro_lisp.eval(form);
          lower_reached_globals = globals;
          lower_reached_meta = meta;
          return _installed_comptime(compiler, own);
        }
  List forms = compiler.lower_comptime(fn);
  if (!forms) return 0;
  if (key)
    _retain_lowering(
      key, forms, lower_session_callees, compiler.meta_regions[own]);
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

/** Lowers one advertised file-scope initializer to a new object holding its
    value. Evaluated outside any function, the object's bytes belong to the
    macro session. The declaration parser has already installed its binding
    and checked that its type has a native layout. */
Var Compiler.lower_meta_initializer(
  Compiler c, Type type, int id, List initializer) {
  struct Lowering state = {
    .compiler = c, .env = {}, .locals = {}, .cells = {},
    .arrays = {}, .records = {}, .callees = {}, .cursors = {},
    .definitions = []
  };
  lower_declined_reason = NULL;
  _lower_scan(&state, initializer);
  Var result = _lower_initializer(&state, type, id, initializer);
  if (!_lower_failed(&state, result))
    result = _lower_new_object(
      &state, c.meta_type_layout(type), result,
      _lower_braced_init(initializer));
  state.definitions.free();
  if (state.uncallable)
    return _lower_decline(&state, "no binding for " + lower_missing_callee);
  return state.declined ? void : result;
}

/** Lowers a closed expression for explicit compile-time evaluation. */
Var Compiler.lower_meta_expression(Compiler c, List expression) {
  struct Lowering state = {
    .compiler = c, .env = {}, .locals = {}, .cells = {},
    .arrays = {}, .records = {}, .callees = {}, .cursors = {},
    .definitions = []
  };
  lower_declined_reason = NULL;
  _lower_scan(&state, expression);
  Var result = _lower_expr(&state, expression);
  state.definitions.free();
  if (state.uncallable)
    return _lower_decline(&state, "no binding for " + lower_missing_callee);
  return state.declined ? void : result;
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

/* Untyped Lisp numbers retain their native Var family at the code boundary. */
static Type _meta_value_type(Var value) {
  switch (value.tag()) {
    case <i8>: return %(signed char);
    case <u8>: return %(unsigned char);
    case <i16>: return %(short);
    case <u16>: return %(unsigned short);
    case <i32>: return %(int);
    case <u32>: return %(unsigned);
    case <long>: return %(long);
    case <ulong>: return %(unsigned long);
    case <llong>: return %(long long);
    case <ullong>: return %(unsigned long long);
    case <f32>: return %(float);
    case <ldouble>: return %(long double);
  }
  if (value.is_floating()) return %(double);
  if (value.is_integer()) {
    long n = value.integer();
    return n == (int) n ? %(int) : %(long long);
  }
  return NULL;
}

/** Returns literal code preserving `declared` when supplied.
    `mutable_root` permits a fresh Array or Map at an explicit code boundary;
    its descendants must be immutable representable values. Returns NULL for
    code Lists or values without the requested literal representation.
*/
List Compiler.meta_value_expression(
  Compiler c, Type declared, Var value, int mutable_root) {
  Type type = declared ? declared : _meta_value_type(value);
  if (c.sym.is_var_type(type)) type = %("Var");
  else c.sym.var_tag_for_type(type, &type);
  if ((value.is_integer() || value.is_floating()) &&
      type !== %("Var")) {
    type = c.sym.resolve_numeric_type(type);
    Symbol tag = type ? type.scalar_tag() : 0;
    if (!tag) return NULL;
    value = value.convert(tag);
    if (type.scalar() === %(int)) {
      long n = value.integer();
      Type result = declared ? declared : type;
      List literal = %(expr $result (literal (int) ${value.str()}));
      if (n == INT_MIN)
        return %(expr $result (parens (expr $result (cast (int) $literal))));
      return n < 0 ? %(expr $result (parens $literal)) : literal;
    }
    X2CVarNumeric number;
    value.numeric_decode(&number);
    String text;
    Type literal_type;
    if (number.floating) {
      literal_type = %(long double);
      long double n = number.floating_value;
      if (isnan(n)) text = "__builtin_nanl(\"\")";
      else if (isinf(n))
        text = n < 0 ? "(-__builtin_infl())" : "__builtin_infl()";
      else text = "%LaL".printf(n);
    }
    else {
      literal_type = %(unsigned long long);
      text = "%lluULL".printf(number.raw);
    }
    List literal = %(expr $literal_type (literal $literal_type $text));
    Type result = declared ? declared : type;
    return %(expr $result (parens (expr $result (cast $type $literal))));
  }
  if (declared && type === %("Var")) {
    Type inner = value is <string> ? %("String")
      : value is <symbol> ? %("Symbol")
      : value is <list> ? %("List")
      : value is <array> ? %("Array")
      : value is <map> ? %("Map") : _meta_value_type(value);
    if (!inner) return NULL;
    List expression = c.meta_value_expression(inner, value, mutable_root);
    return expression ? c.convert_expression(expression, declared) : NULL;
  }
  if (declared && type === %("List") && value is <list>) {
    List result = %(expr ("List") (nil));
    foreach (Var item, value.list().reverse()) {
      List head = c.meta_value_expression(%("Var"), item, 0);
      if (!head) return NULL;
      result = %(expr ("List") (cons $head $result));
    }
    return result;
  }
  if (mutable_root && value is <array> &&
      (!declared || type === %("Array"))) {
    Array items = [];
    foreach (Var item, value.array()) {
      List expression = c.meta_value_expression(%("Var"), item, 0);
      if (!expression) { items.free(); return NULL; }
      items.push(expression);
    }
    return %(expr ("Array") (array @{items.list_free()}));
  }
  if (mutable_root && value is <map> &&
      (!declared || type === %("Map"))) {
    Array entries = [];
    foreach (Var (key, item), value.map()) {
      List key_code = c.meta_value_expression(%("Var"), key, 0);
      List value_code = c.meta_value_expression(%("Var"), item, 0);
      if (!key_code || !value_code) { entries.free(); return NULL; }
      entries.push(%(map-entry $key_code $value_code));
    }
    // Bucket layout must not change the emitted code.
    return %(expr ("Map") (map @{entries.sort().list_free()}));
  }
  if (value is <string>) {
    if (!declared || type === %(* char))
      return %(expr (* char) (literal (* char) ${value.repr()}));
    if (type === %("String"))
      return %(expr $declared (literal ("String") $value));
  }
  if (value is <symbol> && (!declared || type === %("Symbol")))
    return %(expr ("Symbol") (literal ("Symbol")
                  ${value.symbol().str()} ${value.symbol()}));
  return NULL;
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
  Array values = $auto([]);
  for (List p = parameters, a = arguments; p; p = p.cdr(), a = a.cdr()) {
    List argument = a.car();
    Type declared = p.car(), supplied = argument.cadr();
    if (!c.sym.resolve_key(declared).equal(c.sym.resolve_key(supplied)))
      return NULL;
    Var value = _meta_constant(c, argument);
    if (value is void) return NULL;
    /* The parameter type belongs to the call site, so apply its conversion
       before passing a constant to the lowered body. */
    Type numeric = c.sym.resolve_numeric_type(declared);
    Symbol tag = numeric ? numeric.scalar_tag() : 0;
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
  return c.meta_value_expression(result, answer, 0);
}
