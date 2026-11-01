/*  names.x -- compiler-generated names

    Allocates private C spellings per stem and anonymous aggregate identities
    per source file; identities are never emitted.
*/

/** Allocates the next compiler-private C spelling for `stem`.
    Related compilers increment the same per-stem counter.
*/
String Compiler.fresh_name(Compiler c, String stem) {
  String key = stem;
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored : 0;
  String name = %"_x2c_gensym_$(key)_$(count++)";
  c.names.counters[key] = count;
  c.names.issued++;
  return name;
}

/** Returns a fresh semantic identity for an anonymous aggregate.
    Identities are scoped to the compiler's current file and numbered per
    file, so every process mints the same sequence for one file and two
    files never share an identity. No emission path prints one.
*/
List Compiler.gensym(Compiler c) {
  String owner = c.filename
    ? Compiler.portable_path(c.canonical_path(c.filename)) : "";
  String key = %"gensym:$owner";
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored.int() + 1 : 1;
  c.names.counters[key] = count;
  c.names.issued++;
  return %((gensym $owner $count));
}
