/*  pending.x -- pending support declarations and file initialization */

/** Appends a declaration the kernel generated to the unit's pending
    support. It is implementation, so its definitions are written.
*/
void Compiler.add_early(Compiler c, List decl) {
  c.add_support(Ast.written_definitions(decl));
}

/** Appends the declaration `decl` to the unit's pending support as it is:
    a definition offered to every function rule, or a written one.
*/
void Compiler.add_support(Compiler c, List decl) {
  c.pending.area(<support>).push(decl);
}

/** Appends the lowered statement `stmt` to the file initialization area
    `phase`. Bound code that still needs lowering, such as a `String`
    literal, would reach C as is.
*/
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
