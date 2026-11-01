/*  fields.x -- statements that copy or set named fields */

#pragma once
#include "common.x"
#include "compiler-meta.x"

/* A captured Name can be a binding List; keep it as one argument. */
meta List _x2c_field_rows(List fields) {
  Array rows = [];
  foreach (Var field in fields) rows.push($(field));
  return rows.list_free();
}

macro Stmt $copy_fields(Expr $to, Expr $from, Name @fields) {
  expand $_x2c_field_rows($fields)
  macro Stmt(Name $field) { $to.$field = $from.$field; }
}

macro Stmt $set_fields(Expr $to, Expr $value, Name @fields) {
  expand $_x2c_field_rows($fields)
  macro Stmt(Name $field) { $to.$field = $value; }
}

/* The macro, keyword, and binding state a segment takes from its owner
   and returns to it. */
macro Stmt $segment_state(Expr $to, Expr $from) {
  $copy_fields($to, $from, macros, object_macros, kw_aliases, meta_bindings);
}
