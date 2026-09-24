#pragma indent
/*  fix.x -- apply the proposed fixes that leave the generated C unchanged

    A fix is proven when the compiler this command was built with translates
    the file before and after it to byte-identical C and headers. The file
    is rewritten in place for each translation, because its path and
    directory decide its includes and header guard, and it ends with the
    original text or the proven edits.
*/
#include "lint.x"
#include "path.x"
#include "process.x"

#pragma private

/* Returns `text` with the sorted `(START END TEXT)` `edits` applied. An
   edit that overlaps an earlier one is dropped, for a later run. */
static String _apply(String text, List edits):
  Buffer out = $auto(Buffer.new(0))
  int cursor = 0
  foreach List edit in edits:
    Var (start, end, replacement) = edit
    if start.int() < cursor: continue
    out.write_len(text + cursor, start.int() - cursor)
    out.write(replacement.string())
    cursor = end.int()
  out.write(text + cursor)
  return out

/* The C source and header that `translate` generates for `path` in
   `work`, or NULL when the file does not translate. */
static String _generated(List translate, Path path, Path work):
  Path.remove_tree(work)
  Path.make_dirs(work)
  List command = translate.append(%("--out-dir" $work $path))
  if command.job().options({stderr: <capture>}).status(): return NULL
  String stem = path.stem()
  return work.join(%"$stem.c").read_text() + work.join(%"$stem.h").read_text()

/* Whether `edits` leave the generated C of `l`'s file equal to `base`. */
static int _proves(Lint l, List edits, List translate, Path work,
                   String base):
  Path file = l.path
  file.write_text(_apply(l.text, edits))
  return _generated(translate, file, work) == base

/** Applies to `l`'s file the proposed edits that `translate`, a translate
    command without its output directory and input, proves by comparing
    generated C in the directory `work`. All edits are tried together, and
    each alone when together they change the C. Returns the number applied,
    or -1 when the original file does not translate.
*/
int Lint.apply_fixes(Lint l, List translate, Path work):
  Path file = l.path
  List edits = l.edits.list_free().sort()
  String base = _generated(translate, file, work)
  if !edits || !base: return base ? 0 : -1
  List kept = edits
  if !_proves(l, edits, translate, work, base):
    Array proven = []
    foreach List edit in edits:
      if _proves(l, %($edit), translate, work, base): proven.push(edit)
    kept = proven.list_free()
    if kept && !_proves(l, kept, translate, work, base): kept = NULL
  file.write_text(_apply(l.text, kept))
  return kept.len()
