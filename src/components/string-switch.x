/*  string-switch.x -- switches on a String

    A switch on a String selects its case by content. Each label the switch
    owns becomes its index, so the body stays an ordinary integer switch on
    a helper's result. The helper returns the index of the first label equal
    to the selector under ordinary `==`, or 0. Switches on the same type
    with the same labels share one helper. It is static, except for the
    switches in public inline functions, whose bodies the header publishes:
    they share one with external linkage.

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

/* Whether `type` is the type of a C string literal. `lib/type.x` spells it
   `Type.is_char_pointer_like`, which a component cannot include; see
   `Compiler.prelude_sources`. */
meta static int _string_case_text(Type type) =>
  type ~= %((!or (dim *) (!quote *)) char) ||
  type ~= %((!or (dim *) (!quote *)) const char);

/* A label's content: the bytes its literals spell, in quotes, or the name
   of a native macro x2c types as a string literal. NULL for any other
   label. */
meta static String _string_case_key(List label) {
  match (label) {
    case %(expr ? $($grouped(?inner))): return _string_case_key(inner);
    case %(expr ? (literal ?type ?text)): {
      String spelling = text;
      if (_string_case_text(type)) {
        Code text = %(expr (* char) (literal (* char) $spelling));
        return text.format() ? text.value().repr() : spelling;
      }
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
   expression holds none. The root is a statement; rewrite_children visits
   only Lists. */
meta static List _string_cases(
  List node, Map indices, Array labels, List site) {
  if (!node) return node;
  match (node) {
    case %((!or expr switch match) *): return node;
    case %(at ? ?inner):
      return %(at $(node.cadr())
               $(_string_cases(inner, indices, labels, node)));
    case %(case ?label):
      return %(case $(_string_case_index(label, indices, labels, site)));
  }
  List child;
  $ast.rewrite_children(
    node, child, _string_cases(child, indices, labels, site));
}

/* Whether the function holding the switch is public inline, so that the
   header publishes its body. */
meta static int _switch_in_public_inline(void) {
  if (x2c_enclosing(<function>) ~= %(function ?(Type type) *))
    return type ~= %(* inline *) && !(type ~= %(* static *));
  return 0;
}

/* The role naming a helper with external linkage, which carries the hash
   of the unit's path so that units whose public inline functions share a
   header link together. */
meta static String _string_switch_public_role(void) {
  if (x2c_enclosing(<unit>) ~=
      %(expr ? (segments (segexp (expr ? (literal ? ?(String path)))))))
    return %"string_switch_$("%08x".printf(path.hash()))";
  return "string_switch";
}

/* The helper shared by switches on `type` with the same `labels`, with
   external linkage when a public inline function holds the switch. */
meta static Code _string_switch_helper(Type type, List labels) {
  int public = _switch_in_public_inline();
  List key = %(string-switch $type $labels $public);
  String role = public ? _string_switch_public_role() : "string_switch";
  List name = x2c_binding_for(key, role), s = x2c_ident("s");
  List declared = public ? %(int) : %(static int);
  Array tests = [];
  int index = 0;
  foreach (List label in labels)
    tests.push($!{ if ($s == $label) return $(++index); });
  x2c_place(
    %(unit-support $key),
    $!Unit{ $declared $name($type $s) { @(tests.list_free()) return 0; } });
  Type callable = %((func ($type)) int);
  return $!($callable){ $name };
}

$rewrite($switched)
/** Lowers a switch on a String to an integer switch on its selector's
    index among the labels it owns, or declines another switch.
*/
meta Code string_switch_lowering(Code node) {
  if (node ~= $switched(?selector, ?body)) {
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
