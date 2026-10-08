/*  typed-switch.x -- a typed-phase switch over strings

    Including this file registers `string_switch` for every bound and typed
    `switch` statement that follows. A switch whose subject is a named type
    or a C string, and whose owned labels are string literals, becomes a
    switch over label indices: each label becomes its index, the subject is
    evaluated once into a String, and the first label it equals by String
    `==` selects the index. A null C string becomes a null String, which
    equals `""`. Every other switch is declined and emits as before. */

#pragma once
#include "meta.x"

/* The index of `label` among `labels`, adding it when it is new. */
meta static int _tswitch_index(List label, Array labels) {
  for (int i = 0; i < labels.len(); i++)
    if (labels[i] == label) return i + 1;
  labels.push(label);
  return labels.len();
}

/* `node` with each owned string label replaced by its index. A nested
   switch owns its own labels. */
meta static Var _tswitch_rewrite(Var node, Array labels) {
  if (node is not <list>) return node;
  List list = node;
  if (!list) return node;
  match (list) {
    case %(switch *): return list;
    case %(case (!set ?label (expr (* char) (literal *)))):
      return %(case ${x2c_literal_int(_tswitch_index(label, labels))});
  }
  Array out = [];
  foreach (Var child, list) out.push(_tswitch_rewrite(child, labels));
  return out.list_free();
}

/* `selected == label1 ? 1 : selected == label2 ? 2 : ... : 0`. */
meta static List _tswitch_dispatch(List selected, Array labels, int i) {
  if (i == labels.len()) return x2c_literal_int(0);
  List label = labels[i], index = x2c_literal_int(i + 1);
  List rest = _tswitch_dispatch(selected, labels, i + 1);
  return $!( $selected == $label ? $index : $rest );
}

/* Whether `type` is a pointer to or array of `char`. */
meta static int _tswitch_c_string(List type) {
  List element = NULL;
  match (type) {
    case %((!quote *) *rest): element = rest;
    case %((dim *) *rest): element = rest;
  }
  match (element) case %(!or (char) (const char)): return 1;
  return 0;
}

/* Whether `type` is named, such as `String` or a typedef of it. */
meta static int _tswitch_named(List type) {
  match (type) case %((!is ? type string)): return 1;
  return 0;
}

/* The string switch `node` becomes, or `node` itself. Project meta code
   cannot resolve a typedef, so a named subject converts to String where
   the result binds; only a string subject has string-literal labels. */
meta List string_switch(List node) {
  match (node) case %(switch (!set ?subject (expr ?type ?)) ?body): {
    int c_string = _tswitch_c_string(type);
    if (!c_string && !_tswitch_named(type)) return node;
    Array labels = [];
    List rewritten = _tswitch_rewrite(body, labels);
    if (!labels.len()) return node;
    List name = x2c_ident("_tswitch_subject");
    List value = c_string ? x2c_expr_cast(%("String"), subject) : subject;
    List dispatch = _tswitch_dispatch(x2c_expr_ident(name), labels, 0);
    return $!{ { String $name = $value; switch ($dispatch) $rewritten } };
  }
  return node;
}

hook <switch> string_switch;
