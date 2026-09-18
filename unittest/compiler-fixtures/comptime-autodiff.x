/*  comptime-autodiff.x -- lib/autodiff.xmacro written as compile-time x2c

    Forward and reverse mode, the primitive derivative table, and both
    decorators, as `$comptime()` functions the lowering pass compiles to
    Lisp. Every derivative the decorators emit is checked here against a
    central finite difference, so a regression in the pass shows up as a
    number rather than as a decline.

    `horner` covers a `for` loop with a nested `if`; `guarded` covers a
    `while` with `break` and `continue`; `mixed` covers the primitives.
    Checkpointed loops and calls to an earlier differentiated sibling are not
    ported; see `plans/comptime-x2c-generalization.md`.
*/

#include "x2c.x"
#include "typed-array.x"
#include <math.h>

macro Decorator $comptime(Unit $fn) => { $(x2c.comptime.install $fn)... }

$(def ad_tangent (lambda (. rest) 0))
$(def ad_adjoint (lambda (. rest) 0))
$(def ad_rev_item (lambda (. rest) 0))
$(def ad_fwd_item (lambda (. rest) 0))
$(def ad_declared_join (lambda (. rest) 0))

/* Forward mode from lib/autodiff.xmacro, as compile-time x2c. */

$comptime()
List ad_zero(void) { return %(expr (double) (literal (double) "0.0")); }

$comptime()
List ad_one(void) { return %(expr (double) (literal (double) "1.0")); }

$comptime()
int ad_is_zero(List e) { return e.equal(ad_zero()); }

$comptime()
int ad_is_one(List e) { return e.equal(ad_one()); }

$comptime()
List ad_raw(Var op, List a, List b) { return %(expr () (op $op $a $b)); }

$comptime()
List ad_neg(List a) {
  if (ad_is_zero(a)) return a;
  return %(expr () (op - $a));
}

$comptime()
List ad_add(List a, List b) {
  if (ad_is_zero(a)) return b;
  if (ad_is_zero(b)) return a;
  return ad_raw(<+>, a, b);
}

$comptime()
List ad_sub(List a, List b) {
  if (ad_is_zero(b)) return a;
  if (ad_is_zero(a)) return ad_neg(b);
  return ad_raw(<->, a, b);
}

$comptime()
List ad_mul(List a, List b) {
  if (ad_is_zero(a)) return a;
  if (ad_is_zero(b)) return b;
  if (ad_is_one(a)) return b;
  if (ad_is_one(b)) return a;
  return ad_raw(<*>, a, b);
}

$comptime()
List ad_div(List a, List b) {
  if (ad_is_zero(a)) return a;
  if (ad_is_one(b)) return a;
  return ad_raw(</>, a, b);
}

$comptime()
int ad_is_double(List e) { return e.match(%(expr (double) ?)) != NULL; }

$comptime()
int ad_is_double_spec(List type) { return type.equal(%(double)); }

$comptime()
String ad_dot(String name) { return name + "_dot"; }

$comptime()
List ad_id(String name) { return %(expr () (ident ($name))); }

$comptime()
List ad_unbind(Var form) {
  if (!form.is(<list>)) return form;
  List items = form;
  if (!items) return items;
  match (items) {
    case %(binding ? ?name): return %($name);
    case %(at ? ?node): return ad_unbind(node);
  }
  return items.map(%!(Var part) => ad_unbind(part));
}

$comptime()
Var ad_var_name(List e) {
  match (e) {
    case %(expr ? (ident (binding ? ?n))): return n;
    case %(expr ? (ident (?n))): return n;
  }
  return void;
}

$comptime()
List ad_assign(String name, List value) {
  return %(stmnt (expr () (op = ${ad_id(name)} $value)));
}

/* --- the primitive derivative table ------------------------------------- */

$comptime()
List ad_lit(String text) { return %(expr (double) (literal (double) $text)); }

$comptime()
List ad_int(String text) { return %(expr (int) (literal (int) $text)); }

$comptime()
List ad_call(String name, List args) {
  return %(expr () (call (expr () (ident ($name))) (args @args)));
}

$comptime()
List ad_call1(String name, List a) { return ad_call(name, %($a)); }

$comptime()
List ad_select(List test, List a, List b) {
  return %(expr () (op ? $test $a $b));
}

$comptime()
List ad_less(List a, List b) { return %(expr () (op < $a $b)); }

$comptime()
List ad_less_eq(List a, List b) { return %(expr () (op <= $a $b)); }

$comptime()
List ad_square(List a) { return ad_mul(a, a); }

$comptime()
List ad_recip(List e) { return ad_div(ad_lit("1.0"), e); }

$comptime()
List ad_plus_one(List e) { return ad_add(ad_lit("1.0"), e); }

$comptime()
List ad_minus_one(List e) { return ad_sub(ad_lit("1.0"), e); }

$comptime()
List ad_sum_squares(List a) {
  return ad_add(ad_square(a[0]), ad_square(a[1]));
}

/* One partial per argument, indexed from zero, over the unbound argument
   list. The table holds every primitive's derivative; an argument the
   primitive does not have reads as nil, and an unknown name gives nil. */
$comptime()
List ad_partial(String name, int i, List a) {
  List x = a[0];
  List y = a[1];
  Map table = {
    "sin":   ad_call("cos", a),
    "cos":   ad_neg(ad_call("sin", a)),
    "tan":   ad_recip(ad_square(ad_call("cos", a))),
    "asin":  ad_recip(ad_call1("sqrt", ad_minus_one(ad_square(x)))),
    "acos":  ad_neg(ad_recip(ad_call1("sqrt", ad_minus_one(ad_square(x))))),
    "atan":  ad_recip(ad_plus_one(ad_square(x))),
    "atan2": i == 0 ? ad_div(y, ad_sum_squares(a))
                    : ad_neg(ad_div(x, ad_sum_squares(a))),
    "sinh":  ad_call("cosh", a),
    "cosh":  ad_call("sinh", a),
    "tanh":  ad_minus_one(ad_square(ad_call("tanh", a))),
    "asinh": ad_recip(ad_call1("sqrt", ad_plus_one(ad_square(x)))),
    "acosh": ad_recip(ad_call1("sqrt", ad_sub(ad_square(x), ad_lit("1.0")))),
    "atanh": ad_recip(ad_minus_one(ad_square(x))),
    "exp":   ad_call("exp", a),
    "exp2":  ad_mul(ad_call("exp2", a), ad_lit("0.6931471805599453")),
    "expm1": ad_call("exp", a),
    "log":   ad_recip(x),
    "log2":  ad_recip(ad_mul(x, ad_lit("0.6931471805599453"))),
    "log10": ad_recip(ad_mul(x, ad_lit("2.302585092994046"))),
    "log1p": ad_recip(ad_plus_one(x)),
    "sqrt":  ad_div(ad_lit("0.5"), ad_call("sqrt", a)),
    "cbrt":  ad_recip(ad_mul(ad_lit("3.0"), ad_square(ad_call("cbrt", a)))),
    "hypot": ad_div(i == 0 ? x : y, ad_call("hypot", a)),
    "fabs":  ad_select(ad_less(x, ad_lit("0.0")),
                       ad_lit("-1.0"), ad_lit("1.0")),
    "fmin":  i == 0
               ? ad_select(ad_less_eq(x, y), ad_lit("1.0"), ad_lit("0.0"))
               : ad_select(ad_less(y, x), ad_lit("1.0"), ad_lit("0.0")),
    "fmax":  i == 0
               ? ad_select(ad_less_eq(y, x), ad_lit("1.0"), ad_lit("0.0"))
               : ad_select(ad_less(x, y), ad_lit("1.0"), ad_lit("0.0")),
    "pow":   i == 0
               ? ad_mul(y, ad_call("pow", %($x ${ad_sub(y, ad_lit("1.0"))})))
               : ad_mul(ad_call("pow", a), ad_call1("log", x)),
  };
  return table[name];
}

/* The chain rule over a primitive's arguments. */
$comptime()
List ad_call_tangent(String name, List args, List names) {
  List unbound = ad_unbind(args);
  List total = ad_zero();
  int i = 0;
  foreach (List argument, args) {
    List partial = ad_partial(name, i, unbound);
    if (partial)
      total = ad_add(total, ad_mul(partial, ad_tangent(argument, names)));
    i = i + 1;
  }
  return total;
}

/* The tangent of an expression, given the names being differentiated. */
$comptime()
List ad_tangent(List e, List names) {
  if (!ad_is_double(e)) return ad_zero();
  match (e) {
    case %(expr ? (literal ? ?)): return ad_zero();
    case %(expr ? (ident ?)): {
      Var n = ad_var_name(e);
      if (n)
        if (n in names) return ad_id(ad_dot(n));
      return ad_zero();
    }
    case %(expr ? (parens ?a)): return ad_tangent(a, names);
    case %(expr ? (cast ? ?a)): return ad_tangent(a, names);
    case %(expr ? (op - ?a)):   return ad_neg(ad_tangent(a, names));
    case %(expr ? (op + ?a)):   return ad_tangent(a, names);
    case %(expr ? (call (expr ? (ident (binding ? ?fname))) (args *cargs))):
      return ad_call_tangent(fname, cargs, names);
    case %(expr ? (op ?o ?a ?b)): {
      List da = ad_tangent(a, names);
      List db = ad_tangent(b, names);
      List ua = ad_unbind(a);
      List ub = ad_unbind(b);
      if (o == <+>) return ad_add(da, db);
      if (o == <->) return ad_sub(da, db);
      if (o == <*>) return ad_add(ad_mul(da, ub), ad_mul(ua, db));
      if (o == </>)
        return ad_div(ad_sub(ad_mul(da, ub), ad_mul(ua, db)),
                      ad_mul(ub, ub));
      return ad_zero();
    }
  }
  return ad_zero();
}

/* An assignment, compound assignment, or step, normalised to (name rhs). */
$comptime()
List ad_step(Var op, List target) {
  Var n = ad_var_name(target);
  if (!n) return %();
  List one = ad_is_double(target) ? ad_lit("1.0") : ad_int("1");
  return %($n (expr () (op $op $target $one)));
}

$comptime()
List ad_update(List e) {
  match (e) {
    case %(expr ? (op ++ ?target)):      return ad_step(<+>, target);
    case %(expr ? (op -- ?target)):      return ad_step(<->, target);
    case %(expr ? (postfix ++ ?target)): return ad_step(<+>, target);
    case %(expr ? (postfix -- ?target)): return ad_step(<->, target);
    case %(expr ? (op = ?target ?rhs)): {
      Var n = ad_var_name(target);
      if (!n) return %();
      return %($n $rhs);
    }
    case %(expr ?t (op += ?target ?rhs)): {
      Var n = ad_var_name(target);
      if (!n) return %();
      return %($n (expr $t (op + $target $rhs)));
    }
    case %(expr ?t (op -= ?target ?rhs)): {
      Var n = ad_var_name(target);
      if (!n) return %();
      return %($n (expr $t (op - $target $rhs)));
    }
  }
  return %();
}

$comptime()
List ad_fwd_decl(List declarator, List names) {
  match (declarator) {
    case %(op = (bind (binding ? ?name) ()) ?init):
      return %(declare (double)
                (bindings (op = (bind (${ad_dot(name)}) ())
                           ${ad_tangent(init, names)})));
    case %(bind (binding ? ?name) ()):
      return %(declare (double)
                (bindings (op = (bind (${ad_dot(name)}) ()) ${ad_zero()})));
  }
  return %();
}

$comptime()
List ad_fwd_update(List s, List update, List names) {
  if (!update) return %(${ad_unbind(s)});
  Var n = update.car();
  if (!names.contains(n)) return %(${ad_unbind(s)});
  List tangent = ad_assign(ad_dot(n), ad_tangent(update.getindex(1), names));
  return %($tangent ${ad_unbind(s)});
}

$comptime()
List ad_fwd_items(List items, List names) {
  List out = %();
  foreach (List item, items) out = %(@out @{ad_fwd_item(item, names)});
  return out;
}

$comptime()
List ad_fwd_body(List s, List names) {
  match (s) {
    case %(block *items): return %(block @{ad_fwd_items(items, names)});
  }
  return %(block @{ad_fwd_item(s, names)});
}

$comptime()
List ad_fwd_item(List s, List names) {
  match (s) {
    case %(at ? ?node): return ad_fwd_item(node, names);
    case %(declare ?type (bindings ?d)): {
      if (ad_is_double_spec(type))
        return %(${ad_unbind(s)} ${ad_fwd_decl(d, names)});
      return %(${ad_unbind(s)});
    }
    case %(stmnt ?e): return ad_fwd_update(s, ad_update(e), names);
    case %(if ?c ?then): {
      List one = %(if ${ad_unbind(c)} ${ad_fwd_body(then, names)});
      return %($one);
    }
    case %(if ?c ?then ?alt): {
      List one = %(if ${ad_unbind(c)} ${ad_fwd_body(then, names)}
                      ${ad_fwd_body(alt, names)});
      return %($one);
    }
    case %(while ?c ?body): {
      List one = %(while ${ad_unbind(c)} ${ad_fwd_body(body, names)});
      return %($one);
    }
    case %(block *items): {
      List one = %(block @{ad_fwd_items(items, names)});
      return %($one);
    }
    case %(return (double) ?e): {
      List one = %(return (double) ${ad_tangent(e, names)});
      return %($one);
    }
    case %(empty): return %();
  }
  return %(${ad_unbind(s)});
}

/* A declarator's name, for the declared-double scan. */
$comptime()
List ad_declarator_names(List decls) {
  Array names = [];
  foreach (List d, decls) {
    match (d) {
      case %(op = (bind (binding ? ?n) ()) ?): names.push(n);
      case %(bind (binding ? ?n) ()): names.push(n);
    }
  }
  return names;
}

/* Every plain double declaration in the body is differentiated too; any
   other double identifier is a constant. */
$comptime()
List ad_declared_doubles(Var form) {
  if (!form.is(<list>)) return %();
  List items = form;
  if (!items) return %();
  match (items) {
    case %(declare ?type (bindings *decls)): {
      if (ad_is_double_spec(type)) return ad_declarator_names(decls);
      return %();
    }
    case %(decl ?type (bindings *decls)): {
      if (ad_is_double_spec(type)) return ad_declarator_names(decls);
      return %();
    }
  }
  return ad_declared_join(items);
}

$comptime()
List ad_declared_join(List items) {
  if (!items) return %();
  List head = ad_declared_doubles(items.car());
  List tail = ad_declared_join(items.cdr());
  return %(@head @tail);
}

/* Every double parameter is a name to differentiate. */
$comptime()
List ad_param_doubles(List params) {
  Array names = [];
  foreach (List param, params) {
    match (param) {
      case %(param (double) (bind (binding ? ?n) ())): names.push(n);
    }
  }
  return names;
}

/* A double parameter is followed by its tangent. */
$comptime()
List ad_fwd_params(List params) {
  Array out = [];
  foreach (List param, params) {
    match (param) {
      case %(param (double) (bind (binding ? ?n) ())): {
        out.push(%(param (double) (bind ($n) ())));
        out.push(%(param (double) (bind (${ad_dot(n)}) ())));
        continue;
      }
    }
    out.push(ad_unbind(param));
  }
  return out;
}

$comptime()
List ad_forward(List fn) {
  match (fn) {
    case %(function ?spec (bind (binding ? ?name)
                            ((fnmod (params *params)))) ?body): {
      List params_doubles = ad_param_doubles(params);
      List body_doubles = ad_declared_doubles(body);
      List names = %(@params_doubles @body_doubles);
      List one = %(function $spec
                    (bind (${ad_dot(name)})
                      ((fnmod (params @{ad_fwd_params(params)}))))
                    ${ad_fwd_body(body, names)});
      return %($one);
    }
  }
  return %();
}


/* --- reverse mode ------------------------------------------------------- */

/* Compile-time state for one derivation. `ad_reverse` resets all of it
   before reading a function, the way the Lisp original rebinds its
   module-level definitions. */
static List ad_locals;
static int ad_counter;
static List ad_loop_step;

$comptime()
String ad_bar(Var name) { return name + "_bar"; }

$comptime()
String ad_grad(Var name) { return name + "_grad"; }

$comptime()
List ad_stmnt(List e) { return %(stmnt $e); }

$comptime()
List ad_accum(Var name, List value) {
  return ad_stmnt(%(expr () (op += ${ad_id(name)} $value)));
}

$comptime()
List ad_set(Var name, List value) {
  return ad_stmnt(%(expr () (op = ${ad_id(name)} $value)));
}

$comptime()
List ad_cast(List type, List e) {
  return %(expr () (cast (decl $type (bindings (bind () ()))) $e));
}

$comptime()
List ad_declare(List type, Var name, List init) {
  if (init) return %(declare $type (bindings (op = (bind ($name) ()) $init)));
  return %(declare $type (bindings (bind ($name) ())));
}

$comptime()
List ad_zero_of(List type) {
  if (ad_is_double_spec(type)) return ad_zero();
  return ad_int("0");
}

$comptime()
Var ad_local(List type, Var name) {
  List entry = %($name $type);
  ad_locals = %($entry @ad_locals);
  return name;
}

$comptime()
Var ad_fresh(String stem, List type) {
  ad_counter = ad_counter + 1;
  return ad_local(type, %"$stem${ad_counter}");
}

$comptime()
String ad_code(void) {
  ad_counter = ad_counter + 1;
  return %"${ad_counter}.0";
}

$comptime()
List ad_local_type(Var name) {
  foreach (List entry, ad_locals)
    if (entry.car() == name) return entry[1];
  return %(double);
}

$comptime()
List ad_push(List e) {
  return ad_stmnt(ad_call("ArrayDbl_push", %(${ad_id("_ad_tape")} $e)));
}

$comptime()
List ad_pop(void) {
  return ad_call("ArrayDbl_take_last", %(${ad_id("_ad_tape")}));
}

$comptime()
List ad_restore(Var name, List type) {
  if (ad_is_double_spec(type)) return ad_set(name, ad_pop());
  return ad_set(name, ad_cast(type, ad_pop()));
}

/* An item's forward statements, its reverse statements, and one entry per
   exit inside it. */
$comptime()
List ad_triple(List fwd, List rev, List exits) {
  return %($fwd $rev $exits);
}

$comptime()
List ad_none(void) { return %(() () ()); }

$comptime()
List ad_fwd_of(List t) { return t.car(); }

$comptime()
List ad_rev_of(List t) { return t.cdr().car(); }

$comptime()
List ad_exits_of(List t) { return t.cdr().cdr().car(); }

$comptime()
List ad_exit(Var code, Var kind, List pruned) {
  return %($code $kind $pruned);
}

$comptime()
Var ad_exit_code(List x) { return x.car(); }

$comptime()
Var ad_exit_kind(List x) { return x.cdr().car(); }

$comptime()
List ad_exit_pruned(List x) { return x.cdr().cdr().car(); }

$comptime()
List ad_with_pruned(List x, List pruned) {
  return ad_exit(ad_exit_code(x), ad_exit_kind(x), pruned);
}

/* An exit inside item i has run items 1..i-1 completely, so its pruned
   reverse gains everything already reversed. */
$comptime()
List ad_move_exits(List exits, List rev) {
  Array out = [];
  foreach (List x, exits)
    out.push(ad_with_pruned(x, %(@{ad_exit_pruned(x)} @rev)));
  return out;
}

$comptime()
List ad_sequence(List triples) {
  List fwd = %();
  List rev = %();
  List exits = %();
  foreach (List t, triples) {
    exits = %(@exits @{ad_move_exits(ad_exits_of(t), rev)});
    fwd = %(@fwd @{ad_fwd_of(t)});
    rev = %(@{ad_rev_of(t)} @rev);
  }
  return ad_triple(fwd, rev, exits);
}

/* --- adjoints ----------------------------------------------------------- */

$comptime()
List ad_call_adjoint(Var name, List args, List seed, List names) {
  List unbound = ad_unbind(args);
  List out = %();
  int i = 0;
  foreach (List argument, args) {
    List partial = ad_partial(name, i, unbound);
    if (partial)
      out = %(@out @{ad_adjoint(argument, ad_mul(seed, partial), names)});
    i = i + 1;
  }
  return out;
}

$comptime()
List ad_binary_adjoint(Var o, List x, List y, List seed, List names) {
  List a = ad_unbind(x);
  List b = ad_unbind(y);
  if (o == <+>) {
    List da = ad_adjoint(x, seed, names);
    List db = ad_adjoint(y, seed, names);
    return %(@da @db);
  }
  if (o == <->) {
    List da = ad_adjoint(x, seed, names);
    List db = ad_adjoint(y, ad_neg(seed), names);
    return %(@da @db);
  }
  if (o == <*>) {
    List da = ad_adjoint(x, ad_mul(seed, b), names);
    List db = ad_adjoint(y, ad_mul(seed, a), names);
    return %(@da @db);
  }
  if (o == </>) {
    List da = ad_adjoint(x, ad_div(seed, b), names);
    List db = ad_adjoint(
      y, ad_neg(ad_div(ad_mul(seed, a), ad_mul(b, b))), names);
    return %(@da @db);
  }
  return %();
}

/* The adjoint statements for `e` scaled by `seed`. */
$comptime()
List ad_adjoint(List e, List seed, List names) {
  if (!ad_is_double(e)) return %();
  match (e) {
    case %(expr ? (literal ? ?)): return %();
    case %(expr ? (ident ?)): {
      Var n = ad_var_name(e);
      if (n)
        if (n in names) return %(${ad_accum(ad_bar(n), seed)});
      return %();
    }
    case %(expr ? (parens ?a)): return ad_adjoint(a, seed, names);
    case %(expr ? (cast ? ?a)): return ad_adjoint(a, seed, names);
    case %(expr ? (op - ?a)):   return ad_adjoint(a, ad_neg(seed), names);
    case %(expr ? (op + ?a)):   return ad_adjoint(a, seed, names);
    case %(expr ? (op ?o ?c ?a ?b)): {
      if (o != <"?">) return %();
      List then = ad_adjoint(a, seed, names);
      List alt = ad_adjoint(b, seed, names);
      return %((if ${ad_unbind(c)} (block @then) (block @alt)));
    }
    case %(expr ? (call (expr ? (ident (binding ? ?fname))) (args *cargs))):
      return ad_call_adjoint(fname, cargs, seed, names);
    case %(expr ? (op ?o ?a ?b)):
      return ad_binary_adjoint(o, a, b, seed, names);
  }
  return %();
}

/* --- statements --------------------------------------------------------- */

$comptime()
List ad_rev_assign(Var name, List rhs, List names) {
  List type = ad_local_type(name);
  List fwd = %(${ad_push(ad_id(name))} ${ad_set(name, ad_unbind(rhs))});
  if (ad_is_double_spec(type))
    if (name in names) {
      List back = ad_adjoint(rhs, ad_id("_ad_seed"), names);
      return ad_triple(fwd,
        %(${ad_restore(name, type)}
          ${ad_set("_ad_seed", ad_id(ad_bar(name)))}
          ${ad_set(ad_bar(name), ad_zero())} @back), %());
    }
  return ad_triple(fwd, %(${ad_restore(name, type)}), %());
}

$comptime()
List ad_rev_decl(List type, List d, List names) {
  match (d) {
    case %(op = (bind (binding ? ?n) ()) ?init): {
      ad_local(type, n);
      return ad_rev_assign(n, init, names);
    }
    case %(bind (binding ? ?n) ()): {
      ad_local(type, n);
      return ad_none();
    }
  }
  return ad_none();
}

$comptime()
List ad_rev_decls(List type, List decls, List names) {
  Array out = [];
  foreach (List d, decls) out.push(ad_rev_decl(type, d, names));
  return out;
}

$comptime()
List ad_rev_items(List items, List names) {
  Array out = [];
  foreach (List item, items) out.push(ad_rev_item(item, names));
  return out;
}

$comptime()
List ad_rev_block(List items, List names) {
  return ad_sequence(ad_rev_items(items, names));
}

$comptime()
List ad_rev_body(List s, List names) {
  match (s) {
    case %(block *items): return ad_rev_block(items, names);
  }
  return ad_rev_item(s, names);
}

/* A branch pushes its flag after the body, so a completed `if` pops it
   first. */
$comptime()
List ad_rev_if(List c, List then, List alt, List names) {
  List t = ad_rev_body(then, names);
  List e = alt ? ad_rev_body(alt, names) : ad_none();
  List taken = %(@{ad_fwd_of(t)} ${ad_push(ad_lit("1.0"))});
  List other = %(@{ad_fwd_of(e)} ${ad_push(ad_lit("0.0"))});
  List back = %((if (expr () (op != ${ad_pop()} ${ad_lit("0.0")}))
                    (block @{ad_rev_of(t)}) (block @{ad_rev_of(e)})));
  return ad_triple(
    %((if ${ad_unbind(c)} (block @taken) (block @other))), back,
    %(@{ad_exits_of(t)} @{ad_exits_of(e)}));
}

$comptime()
List ad_code_is(Var code) {
  return %(expr () (op == ${ad_id("_ad_code")} ${ad_lit(code)}));
}

/* The dispatch after popping one region's exit code. */
$comptime()
List ad_dispatch(List normal, List exits) {
  List chain = %(block @normal);
  foreach (List x, exits.reverse())
    chain = %(if ${ad_code_is(ad_exit_code(x))}
                 (block @{ad_exit_pruned(x)}) $chain);
  return chain;
}

$comptime()
int ad_is_loop_exit(List x) {
  Var kind = ad_exit_kind(x);
  return kind == <break> || kind == <continue>;
}

$comptime()
List ad_loop_exits(List exits, int want) {
  Array out = [];
  foreach (List x, exits)
    if (ad_is_loop_exit(x) == want) out.push(x);
  return out;
}

$comptime()
List ad_return_exits(List exits) {
  Array out = [];
  foreach (List x, exits)
    if (ad_exit_kind(x) == <return>) out.push(x);
  return out;
}

$comptime()
List ad_count(Var n, Var op) {
  return ad_set(n, ad_raw(op, ad_id(n), ad_int("1")));
}

$comptime()
List ad_countdown(Var n, List dispatch) {
  return %(while (expr () (op > ${ad_id(n)} ${ad_int("0")}))
                 (block @dispatch));
}

/* `continue` also runs the step, so its pruned reverse begins with the
   step's reverse. */
$comptime()
List ad_pruned_exit(List x, List s) {
  if (ad_exit_kind(x) != <continue>) return x;
  return ad_with_pruned(x, %(@{ad_rev_of(s)} @{ad_exit_pruned(x)}));
}

/* One iteration: count, body, step, then the exit code. */
$comptime()
List ad_pruned_exits(List exits, List s) {
  Array out = [];
  foreach (List x, exits) out.push(ad_pruned_exit(x, s));
  return out;
}

$comptime()
List ad_loop_parts(List c, List body, List step, List names) {
  List saved = ad_loop_step;
  ad_loop_step = %();
  List s = step ? ad_rev_item(step, names) : ad_none();
  ad_loop_step = ad_fwd_of(s);
  List b = ad_rev_body(body, names);
  ad_loop_step = saved;
  Var n = ad_fresh("_ad_trip", %(int));
  List own = ad_loop_exits(ad_exits_of(b), 1);
  List through = ad_loop_exits(ad_exits_of(b), 0);
  List iteration = %(${ad_count(n, <+>)} @{ad_fwd_of(b)} @{ad_fwd_of(s)}
                     ${ad_push(ad_lit("0.0"))});
  List pruned = ad_pruned_exits(own, s);
  List normal = %(@{ad_rev_of(s)} @{ad_rev_of(b)});
  List dispatch = %(${ad_set("_ad_code", ad_pop())}
                    ${ad_dispatch(normal, pruned)} ${ad_count(n, <->)});
  return %($n $iteration $dispatch $through ${ad_unbind(c)});
}

$comptime()
List ad_through_exits(List exits, Var n, List dispatch) {
  Array out = [];
  foreach (List x, exits)
    out.push(ad_with_pruned(x, %(@{ad_exit_pruned(x)} ${ad_count(n, <->)}
                                 ${ad_countdown(n, dispatch)})));
  return out;
}

$comptime()
List ad_rev_loop(List init, List c, List step, List body, List names) {
  List head = init ? ad_rev_item(init, names) : ad_none();
  List parts = ad_loop_parts(c, body, step, names);
  Var n = parts.car();
  List iteration = parts.cdr().car();
  List dispatch = parts.cdr().cdr().car();
  List through = parts.cdr().cdr().cdr().car();
  List condition = parts.cdr().cdr().cdr().cdr().car();
  List fwd = %(${ad_set(n, ad_int("0"))}
               (while $condition (block @iteration)) ${ad_push(ad_id(n))});
  List rev = %(${ad_restore(n, %(int))} ${ad_countdown(n, dispatch)});
  List exits = ad_through_exits(through, n, dispatch);
  List loop = ad_triple(fwd, rev, exits);
  return ad_sequence(%($head $loop));
}

$comptime()
List ad_rev_item(List s, List names) {
  match (s) {
    case %(at ? ?node): return ad_rev_item(node, names);
    case %(declare ?type (bindings *decls)):
      return ad_sequence(ad_rev_decls(type, %(@decls), names));
    case %(decl ?type (bindings *decls)):
      return ad_sequence(ad_rev_decls(type, %(@decls), names));
    case %(stmnt ?e): {
      List update = ad_update(e);
      if (update)
        return ad_rev_assign(update.car(), update.cdr().car(), names);
      return ad_triple(%(${ad_unbind(s)}), %(), %());
    }
    case %(expr ? ?):         return ad_rev_item(%(stmnt $s), names);
    case %(if ?c ?then):      return ad_rev_if(c, then, %(), names);
    case %(if ?c ?then ?alt): return ad_rev_if(c, then, alt, names);
    case %(while ?c ?body):   return ad_rev_loop(%(), c, %(), body, names);
    case %(for ?init ?c ?step ?body):
      return ad_rev_loop(init, c, step, body, names);
    case %(block *items):     return ad_rev_block(items, names);
    case %(break): {
      String code = ad_code();
      return ad_triple(%(${ad_push(ad_lit(code))} $s), %(),
                       %(${ad_exit(code, <break>, %())}));
    }
    case %(continue): {
      String code = ad_code();
      return ad_triple(%(@ad_loop_step ${ad_push(ad_lit(code))} $s), %(),
                       %(${ad_exit(code, <continue>, %())}));
    }
    case %(return (double) ?e): {
      String code = ad_code();
      List back = ad_adjoint(e, ad_lit("1.0"), names);
      return ad_triple(
        %(${ad_set("_ad_result", ad_unbind(e))} ${ad_push(ad_lit(code))}
          (goto ("_ad_reverse"))), %(),
        %(${ad_exit(code, <return>, back)}));
    }
    case %(empty): return ad_none();
  }
  return ad_none();
}

/* --- the emitted sibling ------------------------------------------------ */

$comptime()
List ad_grad_slots_params(List params) {
  Array slots = [];
  foreach (List param, params) {
    match (param) {
      case %(param (double) (bind (binding ? ?n) ())):
        slots.push(%(param (double) (bind (${ad_grad(n)}) (*))));
    }
  }
  return slots;
}

$comptime()
List ad_grad_params(List params) {
  List unbound = ad_unbind(params);
  List slots = ad_grad_slots_params(params);
  return %(@unbound @slots);
}

$comptime()
List ad_param_locals(List params) {
  Array locals = [];
  foreach (List param, params) {
    match (param) {
      case %(param ?type (bind (binding ? ?n) ())): locals.push(%($n $type));
    }
  }
  return locals;
}

$comptime()
List ad_param_names(List params) {
  Array names = [];
  foreach (List param, params) {
    match (param) {
      case %(param ? (bind (binding ? ?n) ())): names.push(n);
    }
  }
  return names;
}

$comptime()
List ad_write_slot(Var n) {
  return ad_stmnt(%(expr () (op = (expr () (op * ${ad_id(ad_grad(n))}))
                                  ${ad_id(ad_bar(n))})));
}

$comptime()
List ad_hoisted(List locals, List params) {
  Array out = [];
  foreach (List entry, locals)
    if (!(entry.car() in params)) out.push(entry);
  return out;
}

$comptime()
List ad_declare_locals(List locals) {
  Array out = [];
  foreach (List entry, locals) {
    List type = entry[1];
    out.push(ad_declare(type, entry.car(), ad_zero_of(type)));
  }
  return out;
}

$comptime()
List ad_declare_bars(List names) {
  Array out = [];
  foreach (Var name, names)
    out.push(ad_declare(%(double), ad_bar(name), ad_zero()));
  return out;
}

$comptime()
List ad_write_slots(List inputs) {
  Array out = [];
  foreach (Var name, inputs) out.push(ad_write_slot(name));
  return out;
}

$comptime()
List ad_reverse_function(List spec, Var name, List params, List items) {
  List inputs = ad_param_doubles(params);
  List declared = ad_declared_doubles(%(block @items));
  List names = %(@inputs @declared);
  List sweep = ad_rev_block(items, names);
  List returns = ad_return_exits(ad_exits_of(sweep));
  List hoisted = ad_hoisted(ad_locals.reverse(), ad_param_names(params));
  List decls = ad_declare_locals(hoisted);
  List bars = ad_declare_bars(names);
  List writes = ad_write_slots(inputs);
  return %(function $spec
            (bind (${ad_grad(name)})
              ((fnmod (params @{ad_grad_params(params)}))))
            (block
              ${ad_declare(%("ArrayDbl"), "_ad_tape",
                           ad_call("ArrayDbl_new", %()))}
              ${ad_declare(%(double), "_ad_result", ad_zero())}
              ${ad_declare(%(double), "_ad_seed", ad_zero())}
              ${ad_declare(%(double), "_ad_code", ad_zero())}
              @decls @bars
              @{ad_fwd_of(sweep)}
              (label ("_ad_reverse"))
              ${ad_set("_ad_code", ad_pop())}
              ${ad_dispatch(%(), returns)}
              @writes
              ${ad_stmnt(ad_call("ArrayDbl_free", %(${ad_id("_ad_tape")})))}
              (return (double) ${ad_id("_ad_result")})));
}

$comptime()
List ad_reverse(List fn) {
  match (fn) {
    case %(function ?spec (bind (binding ? ?name) ((fnmod (params *params))))
                    (block *items)): {
      ad_locals = ad_param_locals(params);
      ad_counter = 0;
      ad_loop_step = %();
      List one = ad_reverse_function(spec, name, params, items);
      return %($one);
    }
  }
  return %();
}

/* The decorator emits the function and the derivative the ported forward
   mode built for it. */
$(defun derive (fn) (cons fn (ad_forward fn)))
macro Decorator $c.derive(Unit $fn) => { $(derive $fn)... }
$(defun gradient (fn) (cons fn (ad_reverse fn)))
macro Decorator $c.gradient(Unit $fn) => { $(gradient $fn)... }

$c.derive()
double square(double x) {
  double y = x * x;
  return y + x;
}

$c.derive()
double poly(double x) {
  double acc = 0.0;
  double term = x * x * x;
  acc = term + x * x;
  return acc + x;
}

$c.derive()
double mixed(double x) {
  double a = sin(x) * exp(x);
  double b = sqrt(x) + log(x);
  return a + b + pow(x, 3.0) + fabs(x) + atan2(x, 2.0);
}

$c.gradient()
double energy(double x, double y) {
  double a = x * y;
  double b = sin(x) + a * a;
  return b / (1.0 + y * y);
}

$c.gradient()
double horner(double x, double y) {
  double acc = 0.0;
  for (int i = 0; i < 4; i++) {
    acc = acc * x + y;
    if (i == 2) acc = acc * acc;
  }
  return acc;
}

$c.gradient()
double guarded(double x, double y) {
  double acc = 1.0;
  int i = 0;
  while (i < 6) {
    i = i + 1;
    if (i == 2) continue;
    if (i == 5) break;
    acc = acc * (x + y * acc);
  }
  return acc;
}

/* Printing a tolerance verdict rather than the digits keeps the expectation
   stable across platforms. */
static int failures = 0;

static void check(const char *what, double got, double expected) {
  double scale = fabs(expected) > 1.0 ? fabs(expected) : 1.0;
  if (fabs(got - expected) / scale < 1e-6) printf("ok   %s\n", what);
  else {
    printf("FAIL %s got %.9f expected %.9f\n", what, got, expected);
    failures++;
  }
}

int main(void) {
  double e = 1e-6, gx = 0.0, gy = 0.0;

  check("square_dot", square_dot(3.0, 1.0), 7.0);
  check("poly_dot", poly_dot(2.0, 1.0), 17.0);

  energy_grad(1.1, 0.7, &gx, &gy);
  check("energy_grad/x", gx, (energy(1.1 + e, 0.7) - energy(1.1 - e, 0.7)) / (2.0 * e));
  check("energy_grad/y", gy, (energy(1.1, 0.7 + e) - energy(1.1, 0.7 - e)) / (2.0 * e));

  horner_grad(0.9, 1.2, &gx, &gy);
  check("horner_grad/x", gx, (horner(0.9 + e, 1.2) - horner(0.9 - e, 1.2)) / (2.0 * e));
  check("horner_grad/y", gy, (horner(0.9, 1.2 + e) - horner(0.9, 1.2 - e)) / (2.0 * e));

  guarded_grad(0.8, 0.3, &gx, &gy);
  check("guarded_grad/x", gx, (guarded(0.8 + e, 0.3) - guarded(0.8 - e, 0.3)) / (2.0 * e));
  check("guarded_grad/y", gy, (guarded(0.8, 0.3 + e) - guarded(0.8, 0.3 - e)) / (2.0 * e));

  check("mixed_dot", mixed_dot(1.3, 1.0),
        (mixed(1.3 + e) - mixed(1.3 - e)) / (2.0 * e));

  printf(failures ? "FAILURES %d\n" : "all derivatives match\n", failures);
  return failures != 0;
}
