/*  string-switch.x -- a switch over String with string-literal labels

    `$strings.switch(subject) { case "red": ... }` keeps C switch control
    flow. Each owned label becomes its index, and the subject, evaluated
    once into a fresh temporary, selects the index whose label it equals.
    A switch without string-literal labels stays an ordinary switch, and
    in a string switch every other label is an error.

    Including this file hooks every following source `switch` statement,
    so `switch (s) { case "red": ... }` works without the `$strings.`
    spelling. */

#pragma once
#include "meta.x"

/* The index of `label` among `labels`, adding it when it is new. */
meta int _sswitch_index(List label, Array labels) {
  for (int i = 0; i < labels.len(); i++)
    if (labels[i] == label) return i + 1;
  labels.push(label);
  return labels.len();
}

meta int _sswitch_literal(List label) {
  match (label) case %(expr (* char) (literal *)): return 1;
  return 0;
}

/* `node` with each owned string label replaced by its index. A nested
   switch owns its own labels. Each other owned label's case is added to
   `others`. */
meta Var _sswitch_rewrite(Var node, Array labels, Array others) {
  if (node is not <list>) return node;
  List list = node;
  if (!list) return node;
  match (list) {
    case %(switch *): return list;
    case %(case ?label) if (_sswitch_literal(label)):
      return %(case ${x2c_literal_int(_sswitch_index(label, labels))});
    case %(at ? (case ?label)) if (!_sswitch_literal(label)):
      others.push(list);
  }
  Array out = [];
  foreach (Var child, list) out.push(_sswitch_rewrite(child, labels, others));
  return out.list_free();
}

/* `selected == label1 ? 1 : selected == label2 ? 2 : ... : 0`. */
meta List _sswitch_dispatch(Atom selected, Array labels, int i) {
  if (i == labels.len()) return x2c_literal_int(0);
  List label = labels[i], index = x2c_literal_int(i + 1);
  List rest = _sswitch_dispatch(selected, labels, i + 1);
  return $!( $selected == $label ? $index : $rest );
}

/* The string switch, or the unchanged switch when no label is a string
   literal. */
meta List _sswitch(List subject, List body) {
  Array labels = [], others = [];
  List rewritten = _sswitch_rewrite(body, labels, others);
  if (!labels.len()) return %(${$!{ switch ($subject) $body }});
  if (others.len())
    x2c_diagnostic_fail_at(
      others[0], <macro>,
      "a string switch label must be a string literal", %());
  Atom selected = x2c_fresh_name("selected");
  List dispatch = _sswitch_dispatch(selected, labels, 0);
  return x2c_code(
    $!{ { String $selected = $subject; switch ($dispatch) $rewritten } },
    %(${x2c_effect_name(selected)}));
}

/* A switch whose string-literal labels, if any, select by String
   equality. */
macro Decorator $strings.switch(Stmt $body, Expr $subject) {
  @_sswitch($subject, $body)
}

hook switch $strings.switch;
