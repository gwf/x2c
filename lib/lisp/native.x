/*  native.x -- Lisp native

    Copyright (c) 2026 Gary William Flake.
*/

/* callbacks

   A native operation that takes a Func, such as `List.map`, calls an
   interpreted callable through a Func whose context holds the session and
   the callable. A callback runs only inside the session that made it. */

static typedef struct LispCallback {
  Lisp lisp;
  Var callable;
  String operation;
  unsigned arity;
} LispCallback;

static List unary_signature = $!Type{ Var (Var) };
static List binary_signature = $!Type{ Var (Var, Var) };

static Func _unary_callback(Var callable) =>
  _callback(callable, _call, 1, "Lisp callback");
static Func _binary_callback(Var callable) =>
  _callback(callable, _call, 2, "Lisp callback");
static Func _predicate_callback(Var callable) =>
  _callback(callable, _predicate_call, 1, "Lisp callback");

/* A Func that meta code can keep, as a value or inside a lazy Iter, lives as
   long as the session that runs it, whatever region is active when it is
   made. A callback used only during one call stays in the active region.
   `Iter` keeps it in its existing auxiliary field; the native pull ABI
   remains the library's IterNextFn, and the callback carries its iterator
   and output-cell arguments into the interpreted source function. */
static Func _iter_callback(Var callable) {
  Func fn = _callback(callable, _call, 2, "Lisp iterator callback");
  if (fn) Scope.move(fn, &lisp_active.scope);
  return fn;
}

/* A Func of `arity` value arguments that runs `callable` in the active
   session, or NULL for a nil callable. */
static Func _callback(
  Var callable, FuncAdapter adapter, unsigned arity, String operation) {
  if (callable.is_nil()) return NULL;
  if (!lisp_active)
    $error.callback.absent(operation);
  LispCallback context = { lisp_active, callable, operation, arity };
  List signature = arity == 1 ? unary_signature : binary_signature;
  return Func.new_context(adapter, signature, &context, sizeof context);
}

static Var _call(Func fn, const FuncArg *args) {
  LispCallback *context = _callback_context(fn);
  List values = NULL;
  for (unsigned i = context.arity; i--;)
    values = cons(x2c_func_value_argument(fn, args, i, <var>), values);
  return _apply_values(context.lisp, context.callable, values, NULL);
}

/* A call to _call here would add a C frame to every nested predicate
   call. */
static Var _predicate_call(Func fn, const FuncArg *args) {
  LispCallback *context = _callback_context(fn);
  Var value = x2c_func_value_argument(fn, args, 0, <var>);
  return lisp_truth(
    _apply_values(context.lisp, context.callable, %($value), NULL));
}

static LispCallback *_callback_context(Func fn) {
  LispCallback *context = (void *) fn.context();
  if (!lisp_active || lisp_active != context.lisp)
    $error.callback.wrong(context.operation);
  return context;
}

static int _iter_next(Iter iter, Var *out) =>
  iter.aux.apply_values(iter, Var.new(<var*>, out)).int();

// callback targets

static List _list_map(List values, Var callable) =>
  values.map(_unary_callback(callable));
static List _list_filter(List values, Var callable) =>
  values.filter(_unary_callback(callable));
static int _list_any(List values, Var callable) =>
  values.any(_unary_callback(callable));
static int _list_all(List values, Var callable) =>
  values.all(_unary_callback(callable));
static List _list_map2(List left, List right, Var callable) =>
  left.map2(right, _binary_callback(callable));
static List _list_sort_by(List values, Var callable) =>
  values.sort_by(_unary_callback(callable));
static List _list_sort_with(List values, Var callable) =>
  values.sort_with(_binary_callback(callable));
static List _list_zip_with(List left, List right, Var callable) =>
  left.zip_with(right, _binary_callback(callable));
static Var _list_foldl(List values, Var seed, Var callable) =>
  values.foldl(seed, _binary_callback(callable));
static Var _list_find(List values, Var callable) =>
  values.find(_unary_callback(callable));

static Array _array_map(Array values, Var callable) =>
  values.map(_unary_callback(callable));
static Array _array_map2(Array left, Array right, Var callable) =>
  left.map2(right, _binary_callback(callable));
static Array _array_sort_by(Array values, Var callable) =>
  values.sort_by(_unary_callback(callable));
static Array _array_sort_with(Array values, Var callable) =>
  values.sort_with(_binary_callback(callable));
static Var _array_foldl(Array values, Var seed, Var callable) =>
  values.foldl(seed, _binary_callback(callable));

static String _string_map(String value, Var callable) =>
  value.map(_unary_callback(callable));
static String _string_filter(String value, Var callable) =>
  value.filter(_unary_callback(callable));

/* A compile-time call gets fresh Iter storage from `C.iterator.call`. Only
   a callable argument needs this session's Func bridge. */
static Iter _iter_init(
  Iter destination, Var object, Var callable, Var state) {
  if (!destination) return NULL;
  Func callback = _iter_callback(callable);
  destination.init(object, callback ? _iter_next : NULL, state);
  destination.aux = callback;
  return destination;
}

static Iter _iter_map_into(
  Iter iter, Var callable, Iter destination) =>
  iter.map(_unary_callback(callable), destination);
static Iter _iter_filter_into(
  Iter iter, Var callable, Iter destination) =>
  iter.filter(_unary_callback(callable), destination);
static Iter _iter_zip_with_into(
  Iter left, Iter right, Var callable, Iter destination) =>
  left.zip_with(right, _binary_callback(callable), destination);
static Iter _iter_map2_into(
  Iter left, Iter right, Var callable, Iter destination) =>
  left.map2(right, _binary_callback(callable), destination);
static Iter _iter_scan_into(
  Iter iter, Var seed, Var callable, Iter destination) =>
  iter.scan(seed, _binary_callback(callable), destination);
static int _iter_any(Iter iter, Var callable) =>
  iter.any(_unary_callback(callable));
static int _iter_all(Iter iter, Var callable) =>
  iter.all(_unary_callback(callable));
static Var _iter_foldl(Iter iter, Var seed, Var callable) =>
  iter.foldl(seed, _binary_callback(callable));
static Var _iter_find(Iter iter, Var callable) =>
  iter.find(_unary_callback(callable));

/* The x2c bindings above preserve native Var truth. Lisp surface calls adapt
   predicate results through Lisp truth before native collection code observes
   them, so nil and void are false while every other value remains true. */
static List _predicate_list_filter(List values, Var callable) =>
  values.filter(_predicate_callback(callable));
static int _predicate_list_any(List values, Var callable) =>
  values.any(_predicate_callback(callable));
static int _predicate_list_all(List values, Var callable) =>
  values.all(_predicate_callback(callable));
static Var _predicate_list_find(List values, Var callable) =>
  values.find(_predicate_callback(callable));
static String _predicate_string_filter(String value, Var callable) =>
  value.filter(_predicate_callback(callable));
static Iter _predicate_iter_filter(Iter iter, Var callable) =>
  iter.filter(_predicate_callback(callable), Iter.new());
static int _predicate_iter_any(Iter iter, Var callable) =>
  iter.any(_predicate_callback(callable));
static int _predicate_iter_all(Iter iter, Var callable) =>
  iter.all(_predicate_callback(callable));
static Var _predicate_iter_find(Iter iter, Var callable) =>
  iter.find(_predicate_callback(callable));

/* native targets

   `bind` resolves a name through the callback targets above, then through
   the table `lisp-targets.x` builds. That unit includes the optional modules
   the evaluator binds, which the implicit prelude must not carry, so this
   C-only declaration reaches its table without entering the x2c interface. */

static macro Unit $lisp.native.declarations() {
  @(quote ((preproc "extern Map lisp_native_targets(void);")))
}

$lisp.native.declarations();

$x2c.foreign.alias(lisp_native_targets)
static Map _library_targets(void);
static macro Expression $lisp.callback.target.map() => $(lisp.native.targets `(
  (_list_map (as List_map))
  (_list_filter (as List_filter))
  (_list_any (as List_any))
  (_list_all (as List_all))
  (_list_map2 (as List_map2))
  (_list_sort_by (as List_sort_by))
  (_list_sort_with (as List_sort_with))
  (_list_zip_with (as List_zip_with))
  (_list_foldl (as List_foldl))
  (_list_find (as List_find))
  (_array_map (as Array_map))
  (_array_map2 (as Array_map2))
  (_array_sort_by (as Array_sort_by))
  (_array_sort_with (as Array_sort_with))
  (_array_foldl (as Array_foldl))
  (_string_map (as String_map))
  (_string_filter (as String_filter))
  // Iterator operations are declared `meta` in iter.x and adopted with
  // `meta protocol` in protocols.x, which generates their `_into` targets.
  // One that takes a callback binds here through its adapter.
  (_iter_init (as Iter_init))
  (_iter_map_into (as Iter_map_into))
  (_iter_filter_into (as Iter_filter_into))
  (_iter_zip_with_into (as Iter_zip_with_into))
  (_iter_map2_into (as Iter_map2_into))
  (_iter_scan_into (as Iter_scan_into))
  (_iter_any (as Iter_any))
  (_iter_all (as Iter_all))
  (_iter_foldl (as Iter_foldl))
  (_iter_find (as Iter_find))
  (_predicate_list_filter (as Lisp_List_filter))
  (_predicate_list_any (as Lisp_List_any))
  (_predicate_list_all (as Lisp_List_all))
  (_predicate_list_find (as Lisp_List_find))
  (_predicate_string_filter (as Lisp_String_filter))
  (_predicate_iter_filter (as Lisp_Iter_filter))
  (_predicate_iter_any (as Lisp_Iter_any))
  (_predicate_iter_all (as Lisp_Iter_all))
  (_predicate_iter_find (as Lisp_Iter_find))
));

static Map callback_targets = $lisp.callback.target.map();

module Func _native_target(String name) {
  Var target;
  if (!callback_targets.try_get(name, target) &&
      !_library_targets().try_get(name, target)) return NULL;
  return (Func) target.pointer();
}
