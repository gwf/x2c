#pragma once
#include "meta.x"

/* member-alias.x -- a project member-resolution fallback over facts.

   `$alias_member("Outer", "fetch", "inner", "get")` records an `alias`
   fact; afterward `outer.fetch()` calls `outer.inner.get()`. Run with
   `x2c run member-alias.x member-alias-test.x`, which prints `7 5 0`. */

/* Records that `outer.member()` calls `target` on the field `field`. */
meta List alias_member(
  String outer, String member, String field, String target) {
  List subject = x2c_type_resolve(%($outer));
  x2c_fact_record(subject, <alias>, member, %($field $target));
  return x2c_literal_int(0);
}

/* A member-resolution fallback that reads `alias` facts. */
meta List alias_fallback(List type, String member) {
  if (!member) return %();
  List fact = x2c_fact_lookup(x2c_type_resolve(type), <alias>, member);
  match (fact) case %(alias ?field ?target): return %(($field) $target);
  return %();
}

hook <member> alias_fallback;
