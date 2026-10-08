/*  string-switch.x -- a switch over String with string-literal labels

    `$strings.switch(subject) { case "red": ... }` keeps C switch control
    flow. Each owned label becomes its index, and the subject, evaluated
    once, selects the index whose label it equals. A switch without
    string-literal labels stays an ordinary switch.

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

/* `node` with each owned string label replaced by its index. A nested
   switch owns its own labels. */
meta Var _sswitch_rewrite(Var node, Array labels) {
  if (node is not <list>) return node;
  List list = node;
  if (!list) return node;
  match (list) {
    case %(switch *): return list;
    case %(case (!set ?label (expr (* char) (literal *)))):
      return %(case ${x2c_literal_int(_sswitch_index(label, labels))});
  }
  Array out = [];
  foreach (Var child, list) out.push(_sswitch_rewrite(child, labels));
  return out.list_free();
}

/* `selected == label1 ? 1 : selected == label2 ? 2 : ... : 0`. */
meta List _sswitch_dispatch(List selected, Array labels, int i) {
  if (i == labels.len()) return x2c_literal_int(0);
  List label = labels[i], index = x2c_literal_int(i + 1);
  List rest = _sswitch_dispatch(selected, labels, i + 1);
  return $!( $selected == $label ? $index : $rest );
}

meta List _sswitch(List selected, List body) {
  Array labels = [];
  List rewritten = _sswitch_rewrite(body, labels);
  List dispatch = _sswitch_dispatch(selected, labels, 0);
  return %(${$!{ switch ($dispatch) $rewritten }});
}

/* A switch over a String subject with string-literal labels. */
macro Decorator $strings.string_switch(Stmt $body, Expr $subject) {
  {
    String selected = $subject;
    @_sswitch(selected, $body)
  }
}

/* The string switch, or the unchanged switch when no label is a string
   literal. */
meta List _sswitch_or_plain(List subject, List body) {
  Array labels = [];
  (void) _sswitch_rewrite(body, labels);
  if (!labels.len()) return %(${$!{ switch ($subject) $body }});
  return %(${$!{ $strings.string_switch($subject) $body }});
}

/* A switch whose string-literal labels, if any, select by String
   equality. */
macro Decorator $strings.switch(Stmt $body, Expr $subject) {
  @_sswitch_or_plain($subject, $body)
}

hook switch $strings.switch;
