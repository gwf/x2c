// generated names and initializers

/** Allocates the next compiler-private C spelling for `stem`.
    Related compilers increment the same per-stem counter.
*/
String Compiler.fresh_name(Compiler c, String stem) {
  String key = stem;
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored : 0;
  String name = %"_x2c_${key}_${count++}";
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
    ? home_portable_path(c.canonical_path(c.filename)) : "";
  String key = %"gensym:$owner";
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored.int() + 1 : 1;
  c.names.counters[key] = count;
  c.names.issued++;
  return %((gensym $owner $count));
}

/** Appends a declaration the kernel generated to the unit's pending
    support. It is implementation, so its definitions are written. */
void Compiler.add_early(Compiler c, List decl) {
  c.add_support(written_definitions(decl));
}

/** Appends the declaration `decl` to the unit's pending support as it is:
    a definition offered to every function rule, or a written one. */
void Compiler.add_support(Compiler c, List decl) {
  c.pending.area(<support>).push(decl);
}

/** `decl` with each function definition in it marked `kernel` as written,
    which the transform strips before it offers the definition only to
    shipped function rules. */
List written_definitions(List decl) {
  match (decl) {
    case %(function ? (bind ? ?) ?): return %(function @{decl.cdr()} kernel);
    case %((!or at seq) *):
      return Ast.rewrite_children(decl, written_definitions);
  }
  return decl;
}

/** Appends the lowered statement `stmt` to the file initialization area
    `phase`. Bound code that still needs lowering, such as a `String`
    literal, would reach C as is. */
void Compiler.add_init(Compiler c, Symbol phase, List stmt) {
  c.pending.area(phase).push(stmt);
}

/** Gives every destination fresh, empty storage. */
void Pending.reset(Pending &p) {
  for (int i = 0; i < PENDING_AREAS; i++) p.areas[i] = [];
}

/** Returns the storage of the destination `area`. */
Array Pending.area(Pending &p, Symbol area) =>
  p.areas[%<<support protocol prepare statics finish>>.index(area)];

/** Whether any file initialization area holds a statement. */
int Pending.initializes(Pending &p) {
  for (int i = 1; i < PENDING_AREAS; i++) if (p.areas[i]) return 1;
  return 0;
}

/** Returns the mark that `restore` returns every destination to. */
PendingMark Pending.checkpoint(Pending &p) {
  PendingMark mark;
  for (int i = 0; i < PENDING_AREAS; i++)
    mark.lengths[i] = p.areas[i].len();
  return mark;
}

/** Drops the code queued since `mark`. */
void Pending.restore(Pending &p, PendingMark mark) {
  for (int i = 0; i < PENDING_AREAS; i++)
    p.areas[i].resize(mark.lengths[i]);
}
