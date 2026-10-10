/*  component-raise.x -- raise

    A raise records one structured Error. Its rule converts the code to a
    Symbol and each detail key and value to a Var, promoting a C string
    literal value to a String first. A value whose type is not immutable is
    reported and replaced by null, so the translation goes on and fails
    when it finishes; the runtime rejects what a List or Var detail holds.
    The compiler lowers the converted raise's parts in source order and
    builds their literals when the raise runs.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"

/* Whether a detail of type `type` holds no identity a caught Error could
   share with its raiser. */
meta static int _raise_immutable(Type type) {
  if (!type) return 0;
  foreach (String name, %("Var" "String" "List" "Symbol" "Atom"))
    if (type.is_named(name)) return 1;
  return type.numeric() != NULL;
}

/* A detail value, promoted when it is a C string literal, or null after a
   report when its type is not immutable. What a List or Var detail holds
   is checked when the raise runs. */
meta static Code _raise_value(Code value) {
  value = value.promoted();
  match (value) case %(expr ?matched ?): {
    Type type = matched;
    if (_raise_immutable(type)) return value;
    x2c_diagnostic_error_at(
      NULL, <type>, %"raise detail type ${type.repr()} is not immutable",
      %("use a numeric value, enum, Symbol, Atom, String, List, or Var"));
  }
  return %(expr ("Var") (call "Var_null" (args)));
}

$rewrite($raised)
/** Converts a raise's code and details, or declines a raise whose parts
    already have their types. */
meta Code raise_lowering(Code node) {
  match (node) case $raised(?code, *details): {
    Code symbol = ((Code) code).convert(%("Symbol"));
    int changed = symbol != code, index = 0;
    Array converted = [];
    foreach (Code detail, details) {
      Code part = index++ & 1 ? _raise_value(detail) : detail;
      Code value = part.convert(%("Var"));
      if (value != part) changed = 1;
      converted.push(value);
    }
    if (changed)
      return Code.lowered(%(raise $symbol (args @{converted.list_free()})));
  }
  return node;
}
