/*  string-switch.x -- switches on a String

    A switch on a String selects its case by content. Each label the switch
    owns becomes its index, so the body stays an ordinary integer switch on
    a helper's result. The helper returns the index of the first label equal
    to the selector under ordinary `==`, or 0. Switches on the same type
    with the same labels share one helper.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"
#include "ast-rewrite.x"

/* The linked meta copies include these diagnostics from this owner. */
macro Stmt $report.string_switch_case(Expr $site) =>
  x2c_diagnostic_error_at(
    $site, <xform>, "a case in a String switch takes a string literal",
    %("compare computed values with an if chain or match"));

/* Adjacent literals join after each decodes its own escapes, as in C. */
meta static String _string_case_bytes(String spelling) {
  const char *p = spelling;
  String bytes = "\"";
  while ((p = strchr(p, '"'))) {
    const char *start = ++p;
    while (*p != '"') p += *p == '\\' ? 2 : 1;
    bytes += String.new_len(start, p - start).unescape();
    p++;
  }
  return bytes + "\"";
}

/* Whether `type` is the type of a C string literal. `lib/type.x` spells it
   `Type.is_char_pointer_like`, which a component cannot include; see
   `Compiler.prelude_sources`. */
meta static int _string_case_text(Type type) =>
  type.match(%((!or (dim *) (!quote *)) char)) ||
  type.match(%((!or (dim *) (!quote *)) const char));

/* A label's content: the bytes its literals spell, in quotes, or the name
   of a native macro x2c types as a string literal. NULL for any other
   label. */
meta static String _string_case_key(List label) {
  match (label) {
    case %(expr ? $($grouped(?inner))): return _string_case_key(inner);
    case %(expr ? (literal ?type ?text)): {
      String spelling = text;
      if (_string_case_text(type))
        return "\"" in spelling ? _string_case_bytes(spelling) : spelling;
    }
  }
  return NULL;
}

/* The index of `label` among `labels`. Equal labels share an index, so C
   rejects a duplicate as it rejects a duplicate integer label. Another
   label is reported at `site`, and the translation continues to report
   the rest. */
meta static List _string_case_index(
  List label, Map indices, Array labels, List site) {
  String key = _string_case_key(label);
  if (!key) {
    $report.string_switch_case(site);
    return label;
  }
  if (!(key in indices)) {
    labels.push(label);
    indices[key] = labels.len();
  }
  int index = indices[key];
  return $!int{ $index };
}

/* `node` with each label the switch owns replaced by its index; `site` is
   the innermost origin around it. A nested switch owns its labels, and an
   expression holds none. */
meta static Var _string_cases(
  Var node, Map indices, Array labels, List site) {
  if (node is not <list> || node.is_nil()) return node;
  match (node) {
    case %((!or expr switch match) *): return node;
    case %(at ? ?inner):
      return %(at $(node.cadr())
               $(_string_cases(inner, indices, labels, node)));
    case %(case ?label):
      return %(case $(_string_case_index(label, indices, labels, site)));
  }
  Var child;
  $ast.rewrite_children(
    node, child, _string_cases(child, indices, labels, site));
}

/* The helper shared by switches on `type` with the same `labels`. */
meta static Code _string_switch_helper(Type type, List labels) {
  List key = %(string-switch $type $labels);
  List name = x2c_binding_for(key, "string_switch"), s = x2c_ident("s");
  Array tests = [];
  int index = 0;
  foreach (List label in labels) {
    List value = $!int{ $(++index) };
    tests.push($!{ if ($s == $label) return $value; });
  }
  List body = tests.list_free();
  x2c_place(
    %(unit-support $key),
    $!Unit{ static int $name($type $s) { @body return 0; } });
  Type callable = %((func ($type)) int);
  return $!($callable){ $name };
}

$rewrite($switched)
/** Lowers a switch on a String to an integer switch on its selector's
    index among the labels it owns, or declines another switch. */
meta Code string_switch_lowering(Code node) {
  match (node) case $switched(?selector, ?body): {
    Type type = selector.cadr();
    if (!type.is_named("String")) return node;
    Map indices = {};
    Array labels = [];
    List numbered = _string_cases(body, indices, labels, NULL);
    Code helper = _string_switch_helper(type, labels.list_free());
    return Code.lowered(
      %(switch $($!int{ $helper($selector) }) $numbered), NULL);
  }
  return node;
}
