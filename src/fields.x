#pragma once
#include "common.x"

/*  fields.x -- statements that copy or set named fields */

/* `to.field = from.field;` for each of `fields`. */
meta List _field_copies(List to, List from, List fields) {
  if (!fields) return NULL;
  Var field = fields.car();
  return %(${$!{ $to.$field = $from.$field; }}
           @{_field_copies(to, from, fields.cdr())});
}

/* `to.field = value;` for each of `fields`, evaluating `value` each time. */
meta List _field_sets(List to, List value, List fields) {
  if (!fields) return NULL;
  Var field = fields.car();
  return %(${$!{ $to.$field = $value; }}
           @{_field_sets(to, value, fields.cdr())});
}

macro Stmt $copy_fields(Expr $to, Expr $from, Name @fields) {
  @_field_copies($to, $from, $fields)
}

macro Stmt $set_fields(Expr $to, Expr $value, Name @fields) {
  @_field_sets($to, $value, $fields)
}

/* The macro, import, keyword, and Lisp state a segment takes from its
   owner and returns to it. */
macro Stmt $segment_state(Expr $to, Expr $from) {
  $copy_fields($to, $from, macros, object_macros, imports, kw_aliases,
               typed_hooks, macro_lisp, declaration_effects,
               evaluated_effects);
}
