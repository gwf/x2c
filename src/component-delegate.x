/*  component-delegate.x -- delegate fields

    A field declared `delegate T name;` answers the method calls its
    aggregate lacks. The parser marks each such field, and the rule below
    is registered for the mark, so only a call that finds no member on a
    receiver whose aggregate declares one tests it. The rule searches the
    receiver's delegate fields depth first in field order and rebuilds the
    call through the one path that finds the method. More than one path, or
    a cycle with no path, is an error.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"

/* The aggregate's tag in a diagnostic, or the leading word of another
   type. */
meta static String _delegate_type_name(Type type) {
  List base = type_base_suffix(type);
  match (base)
    case %((!or struct union)
           (!set ?tag (!or (!not (*)) (gensym ? ?) (binding ? ?)))):
      return tag.str();
  return base.car().str();
}

/* `TYPE.FIELD...`, then `member` when there is one. */
meta static String _delegate_path(Type type, List fields, String member) {
  Array parts = [_delegate_type_name(type)];
  foreach (String field, fields) parts.push(field);
  if (member) parts.push(member);
  return ".".join(parts.list_free());
}

/* Reports a method that imported packages each provide on a delegate
   field's type. */
meta static void _delegate_packages(
  Type outer, Type type, String member, List fields, List packages) {
  Array notes = [%"delegate path: ${_delegate_path(outer, fields, NULL)}"];
  foreach (String package, packages) notes.push(%"package: '$package'");
  String method = %"${_delegate_type_name(type)}.$member";
  x2c_diagnostic_fail_at(
    NULL, <type>,
    %"method '$method' is provided by multiple imported packages",
    notes.list_free());
}

/* Pushes `((FIELD...) BINDING)` for each path through the delegate fields
   of `receiver` that finds `member`, depth first in field order. `reverse`
   holds the fields so far, last first; `cycle` receives the fields of the
   first path that returns to an aggregate it passed. */
meta static void _delegate_search(
  Type outer, String member, Type receiver, List reverse, List seen,
  Array found, List &cycle) {
  Type aggregate = receiver.aggregate();
  if (!aggregate) return;
  if (aggregate in seen) {
    if (!cycle) cycle = reverse.reverse();
    return;
  }
  seen = cons(aggregate, seen);
  foreach (List row, aggregate.marked_fields(<delegate>)) {
    String name = row.car();
    Type type = receiver.resolve_member(name, 0).caddr();
    List path = cons(name, reverse);
    List resolution = type.resolve_member(member, 1);
    match (resolution) {
      case %(method ?binding ?):
        found.push(%(${path.reverse()} $binding));
      case %(ambiguous *packages):
        _delegate_packages(outer, type, member, path.reverse(), packages);
    }
    if (!resolution)
      _delegate_search(outer, member, type, path, seen, found, cycle);
  }
}

/* Reports more than one delegate path that finds `member`. */
meta static void _delegate_ambiguous(Type outer, String member, List paths) {
  Array notes = [];
  foreach (List path, paths) {
    String spelling = x2c_binding_spelling(path.cadr());
    String description = _delegate_path(outer, path.car(), member);
    notes.push(%"delegate path: $description -> $spelling");
  }
  String method = %"${_delegate_type_name(outer)}.$member";
  x2c_diagnostic_fail_at(
    NULL, <type>, %"method '$method' has multiple delegate paths",
    notes.list_free());
}

/* Reports a search that found no path and returned to an aggregate it
   passed through `fields`. */
meta static void _delegate_cycle(Type outer, String member, List fields) {
  String method = %"${_delegate_type_name(outer)}.$member";
  x2c_diagnostic_fail_at(
    NULL, <type>, %"delegation cycle resolving $method",
    %("delegate path: ${_delegate_path(outer, fields, NULL)}"));
}

/* The fields of the one delegate path from an `outer` receiver that finds
   `member`, or NULL when none does. */
meta static List _delegate_fields(Type outer, String member) {
  Array found = [];
  List cycle = NULL;
  _delegate_search(outer, member, outer, NULL, NULL, found, cycle);
  List paths = found.list_free();
  if (paths && paths.cdr()) _delegate_ambiguous(outer, member, paths);
  if (!paths && cycle) _delegate_cycle(outer, member, cycle);
  return paths ? paths.car().car() : NULL;
}

/* A call on a delegating receiver, before member lookup. */
macro Expression $delegate_call(
    Expr $receiver, Name $member, Expr @arguments) =>
  $receiver.$member(@arguments);

$rewrite_marked(<delegate>, $delegate_call)
/** Rebuilds a call that finds no member on its receiver through the one
    delegate field path that provides the method. */
meta Code delegate_member(Code code) {
  match (code) case $delegate_call(?receiver, ?member, *arguments): {
    List fields =
      _delegate_fields(receiver.cadr(), x2c_binding_spelling(member));
    if (!fields) return code;
    Code target = receiver;
    foreach (String field, fields)
      target = %(expr () (op . $target ($field)));
    return $!($target.$member(@arguments));
  }
  return code;
}
