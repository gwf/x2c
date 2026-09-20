/* Standard Lisp algorithms; generate with tools/gen-lisp-init.py. */
#include "x2c.x"

$(def write-file (bind "lisp_write_file" nil))
$(def init.forms (Array.new))
$(defun init.emit (fn)
  (let ((forms (x2c.comptime.lower fn)))
    (if forms
        (begin (Array.push init.forms forms) (list fn))
        (x2c.diagnostic.fail "cannot lower initial-environment function" nil))))
macro Decorator $init.emit(Unit $fn) => {
  $(init.emit $fn)...
}

$init.emit()
List filter(Func keep, List values) {
  if (values.equal(%())) return values;
  Var value = values.car();
  if (keep(value).equal(%())) return filter(keep, values.cdr());
  return value.cons(filter(keep, values.cdr()));
}

$init.emit()
List map(Func procedure, List values) {
  if (values.equal(%())) return values;
  return procedure(values.car()).cons(map(procedure, values.cdr()));
}

$init.emit()
Var foldl(Func procedure, Var initial, List values) {
  if (values.equal(%())) return initial;
  return foldl(procedure, procedure(initial, values.car()), values.cdr());
}

$init.emit()
Var _last(List values) {
  if (values.equal(%())) return %();
  if (values.cdr().equal(%())) return values.car();
  return _last(values.cdr());
}

$init.emit()
List member(Var value, List values) {
  if (values.equal(%())) return values;
  if (value.equal(values.car())) return values;
  return member(value, values.cdr());
}

$init.emit()
Var assoc(Var key, List pairs) {
  if (pairs.equal(%())) return %();
  Var pair = pairs.car();
  if (lisp_pair(pair).equal(%())) return assoc(key, pairs.cdr());
  if (key.equal(pair.car())) return pair;
  return assoc(key, pairs.cdr());
}

$init.emit()
List _append2(List left, List right) {
  if (left.equal(%())) return right;
  return left.car().cons(_append2(left.cdr(), right));
}

/* Lisp append returns its last argument verbatim, even when it is not a list. */
$init.emit()
Var _append_lists(List lists) {
  if (lists.equal(%())) return %();
  if (lists.cdr().equal(%())) return lists.car();
  return _append2(lists.car(), _append_lists(lists.cdr()));
}

$init.emit()
Var init_not(Var value) {
  if (value.equal(%())) return <true>;
  return %();
}

$init.emit()
Var init_null(Var value) => init_not(value);

$init.emit()
Var sub(Var a, Var b) => a.binary(<->, b);
$init.emit()
Var mul(Var a, Var b) => a.binary(<*>, b);
$init.emit()
Var init_div(Var a, Var b) => a.binary(</>, b);
$init.emit()
Var mod(Var a, Var b) => a.binary(<%>, b);

$init.emit()
Var caar(Var value) => value.car().car();
$init.emit()
Var cadr(Var value) => value.cdr().car();
$init.emit()
List cdar(Var value) => value.car().cdr();
$init.emit()
List cddr(Var value) => value.cdr().cdr();
$init.emit()
Var caaar(Var value) => value.car().car().car();
$init.emit()
Var caadr(Var value) => value.cdr().car().car();
$init.emit()
Var cadar(Var value) => value.car().cdr().car();
$init.emit()
Var caddr(Var value) => value.cdr().cdr().car();
$init.emit()
List cdaar(Var value) => value.car().car().cdr();
$init.emit()
List cdadr(Var value) => value.cdr().car().cdr();
$init.emit()
List cddar(Var value) => value.car().cdr().cdr();
$init.emit()
List cdddr(Var value) => value.cdr().cdr().cdr();

List init_match_native(Var subject, Var pattern);
Var init_type(Var value);
Var init_longer(int left, int right);

$init.emit()
List init_match(Var subject, Var pattern) {
  if (lisp_list(subject).equal(%())) return %();
  return init_match_native(subject, pattern);
}

$init.emit()
Var bound(List bindings, Var binder) {
  return assoc(binder, bindings).cdr().car();
}

$init.emit()
Var init_search_replace(List subject, Var pattern, Var template) {
  if (init_match(subject, pattern).equal(%()))
    return subject.search_replace(pattern, template);
  return lisp_match_replace(subject, pattern, template);
}

/* Bare wildcards bind nothing; long binder names remain Lisp atoms. */
$init.emit()
Var init_binder(Var value) {
  if (lisp_symbol(value).equal(%())) {
    if (lisp_eq(init_type(value), <lsym>).equal(%())) return %();
  }
  String spelling = value.str();
  Var prefix = lisp_substring(spelling, 0, 1);
  if (member(prefix, %("?" "*")).equal(%())) return %();
  return init_longer(spelling.len(), 1);
}

List init_binders(Var pattern);

$init.emit()
static List init_binder_parts(Var parts) {
  if (parts.equal(%())) return parts;
  return _append2(init_binders(parts.car()), init_binder_parts(parts.cdr()));
}

$init.emit()
List init_binders(Var pattern) {
  if (lisp_list(pattern).equal(%())) {
    if (init_binder(pattern).equal(%())) return %();
    return pattern.cons(%());
  }
  return init_binder_parts(pattern);
}

$init.emit()
List init_binder_lets(Var source, List binders) {
  if (binders.equal(%())) return binders;
  Var binder = binders.car();
  Var binding = %($binder (bound $source (quote $binder)));
  return binding.cons(init_binder_lets(source, binders.cdr()));
}

$(write-file "init-generated.xlisp"
  (foldl string-append ""
    (map (lambda (form) (string-append (repr form) "\n"))
      (foldl append nil (Array.list init.forms)))))
