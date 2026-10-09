#pragma once
#include "rewrite.x"

macro Stmt $switch_shape(Expr $subject, Stmt $body) { switch ($subject) $body }

/* The index of `label` among `labels`, adding it when it is new. */
meta static int _tswitch_index(List label, Array labels) {
  for (int i = 0; i < labels.len(); i++)
    if (labels[i] == label) return i + 1;
  labels.push(label);
  return labels.len();
}

meta static int _tswitch_literal(List label) {
  match (label) case %(expr (* char) (literal *)): return 1;
  return 0;
}

/* `node` with each owned string label replaced by its index. A nested
   switch owns its own labels. Each other owned label's case is added to
   `others`. */
meta static Var _tswitch_rewrite(Var node, Array labels, Array others) {
  if (node is not <list>) return node;
  List list = node;
  if (!list) return node;
  match (list) {
    case %(switch *): return list;
    case %(case ?label) if (_tswitch_literal(label)):
      return %(case ${x2c_literal_int(_tswitch_index(label, labels))});
    case %(at ? (case ?label)) if (!_tswitch_literal(label)):
      others.push(list);
  }
  Array out = [];
  foreach (Var child, list) out.push(_tswitch_rewrite(child, labels, others));
  return out.list_free();
}

/* `selected == label1 ? 1 : selected == label2 ? 2 : ... : 0`. */
meta static List _tswitch_dispatch(Code selected, Array labels, int i) {
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

/* Whether `type` is named, such as `String`, `Symbol`, or a typedef. */
meta static int _tswitch_named(List type) {
  match (type) case %((!is ? type string)): return 1;
  return 0;
}

/* The string switch `node` becomes, or `node` itself. The subject's type
   must resolve to a C string, which String and its typedefs do; a named
   subject is resolved only once its labels are strings, so other switches
   ask nothing. In a string switch every other label is an error at that
   label. */
$rewrite($switch_shape)
meta Code string_switch(Code node) {
  match (node) case %(switch (!set ?subject (expr ?type ?)) ?body): {
    if (!_tswitch_c_string(type) && !_tswitch_named(type)) return node;
    Array labels = [], others = [];
    List rewritten = _tswitch_rewrite(body, labels, others);
    if (!labels.len()) return node;
    if (!_tswitch_c_string(type) &&
        !_tswitch_c_string(x2c_type_resolve(type)))
      return node;
    if (others.len())
      x2c_diagnostic_fail_at(
        others[0], <macro>,
        "a string switch label must be a string literal", %());
    Code value = x2c_expr_cast(%("String"), subject);
    String selected = "switch_subject";
    Code dispatch = _tswitch_dispatch(x2c_ident(selected), labels, 0);
    return $!{ { String $selected = $value;
      switch ($dispatch) $rewritten;
    } };

  }
  return node;
}
