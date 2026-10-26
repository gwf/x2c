/*  fields.x -- statements that copy or set named fields */

#pragma once
#include "common.x"

/* Returns `to.field = from.field;` for each of `fields`. */
meta List _x2c_field_copies(List to, List from, List fields) {
  if (!fields) return NULL;
  Var field = fields.car();
  return $(
    $!{ $to.$field = $from.$field; },
    @(_x2c_field_copies(to, from, fields.cdr())));
}

/* Returns `to.field = value;` for each of `fields`, evaluating `value`
    each time. */
meta List _x2c_field_sets(List to, List value, List fields) {
  if (!fields) return NULL;
  Var field = fields.car();
  return $(
    $!{ $to.$field = $value; }, @(_x2c_field_sets(to, value, fields.cdr())));
}

macro Stmt $copy_fields(Expr $to, Expr $from, Name @fields) {
  @_x2c_field_copies($to, $from, $fields)
}

macro Stmt $set_fields(Expr $to, Expr $value, Name @fields) {
  @_x2c_field_sets($to, $value, $fields)
}

/* The macro, keyword, and binding state a segment takes from its owner
   and returns to it. */
macro Stmt $segment_state(Expr $to, Expr $from) {
  $copy_fields($to, $from, macros, object_macros, kw_aliases, meta_bindings);
}
