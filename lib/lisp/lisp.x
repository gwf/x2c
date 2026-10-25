/*  lisp.x -- the Lisp runtime: reader, session, and evaluator

    Copyright (c) 2026 Gary William Flake.

    Lisp owns embedded compile-time Lisp sessions: the reader, the evaluator,
    and each session's global environment. Lambdas and natives receive their
    arguments evaluated left to right, macros and special forms receive them
    raw, nil and void are false, and a Lambda captures by value the free
    locals its body reads. Names are canonical Atoms, and `bind` reaches
    native operations through the table that lisp-targets.x builds.

    The session Scope owns the Lisp record, its Maps, Lambdas, and bound Func
    storage, which hold Vars by value without cloning their referents. Those
    referents keep their own pool or caller owners and must outlive every
    session entry that refers to them. A session is not synchronized: its
    caller serializes evaluation and destroys it only after every call has
    returned.
*/

#pragma once

#include "private-keywords.x"
static keyword loop $private.loop;
#include "cleanup.x"
#include "x2c.x"
#include "macrovalue/macrovalue.x"

/** Reads one exact C scalar from `bytes`; a wide result is boxed in
    `owner`. */
typedef Var (*NativeScalarLoad)(const void *bytes, Scope *owner);
/** Writes `value`, converted to one exact C scalar type, to `bytes`. */
typedef void (*NativeScalarStore)(void *bytes, Var value);
/** Describes one exact C scalar type in native bytes: its Var tag, size,
    alignment, load, and store. Compile-time code that keeps C objects in
    bytes, and the compiler's layouts, select a row with
    `native_scalar_access`. */
typedef struct NativeScalarAccess {
  Symbol tag;
  size_t size, alignment;
  NativeScalarLoad load;
  NativeScalarStore store;
} *NativeScalarAccess;

#include "native-scalar-types.x"
$native.scalar.access.all();

static Map native_scalars = %{ ${$native.scalar.access.entries()} };

/** Returns the access record for an exact C scalar type such as
    `(unsigned long)`, or NULL for any other type. */
NativeScalarAccess native_scalar_access(List exact_type) =>
  native_scalars.getdefault(exact_type, NULL).pointer();

/** Represents one isolated embedded `Lisp` session.
    Create it with `Lisp.new` or `Lisp.kernel` and end it with
    `Lisp.destroy`. The module header describes its owned and borrowed state.
    A session is mutable and requires caller serialization.
*/
typedef struct Lisp *Lisp;

macro Expression $lisp._standard.source() =>
  $x2c_embed_text("../../etc/init.xlisp");

$cleanup.by(Lisp, destroy);

#include "meta.x"

/* Lisp form error conditions. Runtime operands retain their original
   detail types, order and source helper ownership. */

static macro Stmt $error.eval.void() {
  raise %(void-op (operation "eval"));
}

static macro Stmt $error.eval.unbound(Expr $expr) {
  raise %(unbound (name ${$expr}));
}

static macro Stmt $error.call.type(Expr $callable) {
  raise %(not-call (actual ${$callable.kind()}));
}

static macro Stmt $error.def.arity(Expr $actual, Expr $args) {
  raise %(bad-arity (operation "def") (expected 2) (actual ${$actual})
          (value ${$args}));
}

static macro Stmt $error.def.protected(Expr $name) {
  raise %(bad-state (operation "def") (name ${$name}));
}

static macro Stmt $error.def.inherited(Expr $name) {
  raise %(bad-state (operation "def") (reason "inherited") (name ${$name}));
}

static macro Stmt $error.def.frozen(Expr $name) {
  raise %(bad-state (operation "def") (reason "frozen") (name ${$name}));
}

static macro Stmt $error.cond.empty() {
  raise %(bad-arity (operation "cond") (expected 1) (actual 0));
}

static macro Stmt $error.cond.type(Expr $clause) {
  raise %(bad-types (operation "cond") (value ${$clause}) (want "List"));
}

static macro Stmt $error.cond.arity(Expr $actual, Expr $clause) {
  raise %(bad-arity (operation "cond-clause") (expected 2)
          (actual ${$actual}) (value ${$clause}));
}

static macro Stmt $error.bind.signature(Expr $signature) {
  raise %(bad-sig (operation "bind") (value ${$signature}));
}

static macro Stmt $error.bind.missing(Expr $name, Expr $sig) {
  raise %(no-symbol (name ${$name}) (sig ${$sig}));
}

static macro Stmt $error.quote.shape(Expr $expr) {
  raise %(bad-arity (operation "quasiquote") (value ${$expr}));
}

static macro Stmt $error.splice.type(Expr $value) {
  raise %(bad-types (operation "quasiquote-splice")
          (actual ${$value.kind()}));
}

static macro Stmt $error.lambda.signature(Expr $operation, Expr $args) {
  raise %(bad-sig (operation ${$operation}) (value ${$args}));
}

static macro Stmt $error.apply.void(Expr $index) {
  raise %(void-op (operation "apply") (index ${$index}));
}

static macro Stmt $error.apply.rest(Expr $body) {
  raise %(bad-sig (operation "apply") (value ${$body}));
}

static macro Stmt $error.apply.arity(Expr $body) {
  raise %(bad-arity (operation "apply") (value ${$body}));
}

static macro Stmt $error.apply.interrupted() {
  raise %(interrupt (operation "apply"));
}

static macro Stmt $error.apply.steps() {
  raise %(call-stack (operation "apply") (reason "steps"));
}

static macro Stmt $error.apply.stack(Expr $body) {
  raise %(call-stack (operation "apply") (value ${$body}));
}

static macro Stmt $error.form.arity(
  Expr $operation, Expr $expected, Expr $actual) {
  raise %(bad-arity (operation ${$operation}) (expected ${$expected})
          (actual ${$actual}));
}

static macro Stmt $error.form.string(Expr $operation, Expr $value) {
  raise %(bad-types (operation ${$operation}) (actual ${$value.kind()})
          (want "String"));
}

static macro Stmt $error.apply.list(Expr $values) {
  raise %(bad-types (operation "apply") (actual ${$values.kind()})
          (want "List"));
}

static macro Stmt $error.apply.procedure(Expr $callable) {
  raise %(not-call (operation "apply") (actual ${$callable.kind()}));
}

/* Lisp session error conditions. Runtime operands retain their original
   detail types, order and source helper ownership. */

static macro Stmt $error.callback.absent(Expr $operation) {
  raise %(bad-state (operation ${$operation}) (reason "no session"));
}

static macro Stmt $error.callback.wrong(Expr $operation) {
  raise %(bad-state (operation ${$operation}) (reason "wrong session"));
}

static macro Stmt $error.entry.null(Expr $operation) {
  raise %(bad-arg (operation ${$operation}));
}

static macro Stmt $error.global.args() {
  raise %(bad-arg (operation "Lisp.set_global"));
}

static macro Stmt $error.global.frozen(Expr $operation) {
  raise %(bad-state (operation ${$operation}) (reason "frozen"));
}

static macro Stmt $error.bind.args() {
  raise %(bad-arg (operation "Lisp.bind"));
}

static macro Stmt $error.source.callable(Expr $callable) {
  raise %(bad-types (operation "lisp_source_function") (want "Lambda")
          (actual ${$callable.kind()}));
}

#include <signal.h>

/* canonical names

   The evaluator retains one canonical value per special-form and reader
   prefix name. A long name is promoted to the outermost String pool, so it
   outlives the pool that interned it. The reader interns its own prefixes
   without constructing a session. */

module Var lsym_quote, lsym_quasiquote, lsym_unquote, lsym_splicing;
static Var lsym_cond, lsym_def, lsym_bind, lsym_eval, lsym_lambda;
static Var lsym_macro, lsym_import, lsym_apply;

module typedef struct LispCanonicalName {
  Symbol special, const char *spelling;
  Var *value;
} LispCanonicalName;

module const LispCanonicalName lisp_canonical_names[] = {
  { <quote>,      "quote",            &lsym_quote },
  { <quasiquote>, "quasiquote",       &lsym_quasiquote },
  { 0,            "unquote",          &lsym_unquote },
  { 0,            "unquote-splicing", &lsym_splicing },
  { <cond>,       "cond",             &lsym_cond },
  { <def>,        "def",              &lsym_def },
  { <bind>,       "bind",             &lsym_bind },
  { <eval>,       "eval",             &lsym_eval },
  { <lambda>,     "lambda",           &lsym_lambda },
  { <macro>,      "macro",            &lsym_macro },
  { <import>,     "import",           &lsym_import },
  { <apply>,      "apply",            &lsym_apply }
};

/* The Lambda record and capture Map storage belong to the session Scope.
   Parameter and body Lists and captured Var referents are borrowed: capture
   copies Var identity, not the referenced object or canonical graph. Their
   owners must outlive the Lambda. */
module typedef struct Lambda {
  List params;
  Var body;
  Map captures;
  int macro, source_function;
} *Lambda;

module struct Lisp {
  Scope scope;          // semantic session scope
  /* The slot user code allocates in while the session evaluates. Code that
     retains, releases, pushes, or pops a Scope acts on this slot, so it
     never frees evaluator bindings or session state, which name `scope`
     explicitly. */
  Scope user;
  Scope *automatic_owner, *result_owner;
  /* A session may read a parent's globals, reserved names and special
     forms. The parent holds definitions built once, before any child
     exists. Lisp definitions cannot replace inherited names. A host
     binding shadows a name only in the child that receives it.
     A parent outlives every child that names it. */
  Lisp parent;
  /* Set once the parent is complete. Nothing a child does may produce a
     value the parent reaches, because a child's values belong to a
     narrower Context than the parent's. */
  int frozen;
  Map globals;          // global bindings, Lisp name -> value
  Map reserved;         // reserved special forms, Lisp name -> <func> Var
  Func specials[
    sizeof(lisp_canonical_names) / sizeof(lisp_canonical_names[0])];
  int call_depth;       // evaluator calls nested on this session
  unsigned long stack_base; // C stack address at the outermost call
  unsigned long stack_allowance; // bytes below stack_base calls may use
  Lambda tail_lambda;   // a tail call waiting for its caller's frame
  Var *tail_values;     // its evaluated arguments, owned by the session
  int tail_count;
  /* Calls made by the evaluation in progress. Each outer entry resets the
     count, so a long translation spends one budget per entry. */
  long call_steps;
  /* The budget ran out or evaluation was interrupted, and no call may renew
     it until the public entry that opened it returns. `Lisp.set_interrupted`
     may set it from a signal handler. */
  volatile sig_atomic_t call_exhausted;
  long call_step_max;   // calls one evaluation may make
  volatile sig_atomic_t interrupted; // stops every call until cleared
  int protect_x2c;      // compiler SDK installed; x2c.* cannot be redefined
};

/* Native value bindings may adapt an interpreted callable to Func. Public
   entries set this thread-local for the whole evaluation. Nested entries
   restore their caller. */
module Lisp threaded lisp_active;
#include "var-adapters.x"

static $(import "../../etc/lisp-bindings.xlisp")

module {
  "evaluate.x",
  "native.x",
  "sessions.x",
  "reader.x",
  "primitives.x",
}
