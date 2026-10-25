#pragma once

meta List string_len_call(List value) {
  List method = Type.resolve_member(Code.type(value), "len", 1);
  return %(expr () (call (expr $(method[2]) (ident $(method[1])))
    (args $value)));
}

meta int has_member(Type type, String name) =>
  Type.resolve_member(type, name, 1) != NULL;

macro Expression $string_len(Expr $value) => $string_len_call($value);

macro Expression $has_method(Type $type, Name $name) =>
  $has_member($type, $name);
