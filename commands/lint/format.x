#pragma indent
/*  format.x -- the whitespace a unit would have after formatting

    Formatting changes only space: it drops trailing space, also inside
    comments, keeps at most one blank line in a row, ends the file with one
    newline, removes space before `,` and `;`, and puts one space after a
    `,` and between `if`, `for`, `foreach`, `while`, or `switch` and its
    `(`. Quoted Lisp forms and interpolated strings keep their spacing, and
    indentation never changes. The result must scan to the same tokens,
    comments compared without trailing space, or it is not used.
*/
#include "lint.x"
#include <string.h>

#pragma private

/* `text` with the space at the end of each line removed. */
static String _trimmed(String text):
  Array lines = []
  foreach String line in text.split("\n"): lines.push(line.rstrip(" \t"))
  return lines.join("\n")

/* The space between the tokens `before` and `after`, reformatted from
   `space`, the text between them. */
static String _gap(Lint l, int before, int after, String space):
  int newlines = 0
  for (char *ch = space ? space : ""; *ch; ch++): newlines += *ch == '\n'
  if newlines:
    char *indent = strrchr(space, '\n') + 1
    return String.new_fill('\n', newlines > 2 ? 2 : newlines) + indent
  if after >= l.count || before < 0: return space
  Token prior = l.at(before), next = l.at(after)
  if l.quoted[before] || l.quoted[after] || !lint_code(prior):
    return space
  if next.type == <","> || next.type == <;> && prior.type != <;>: return ""
  if space: return space
  if prior.type == <","> && next.type != <")"> ||
     (lint_control(prior) || prior.text == "switch") && next.type == <"(">:
    return " "
  return space

/* The text a token compares by: a comment without trailing space. Tokens
   the indentation syntax respells compare by their spelling too. */
static String _compared(Token t) =>
  t.type == <comment> ? _trimmed(t.text) : t.text

/* Whether `a` and `b` scan to the same tokens apart from space. */
static int _same_tokens(Lint a, Lint b):
  int i = a.next(-1), j = b.next(-1)
  for (; i < a.count && j < b.count; i = a.next(i), j = b.next(j)):
    if _compared(a.at(i)) != _compared(b.at(j)): return 0
  return i >= a.count && j >= b.count

/** Returns the formatted text of `l`, or NULL when formatting would change
    a token other than space. */
String Lint.formatted(Lint l):
  Buffer out = $auto(Buffer.new(0))
  int cursor = 0, before = -1
  for (int at = 0; at <= l.count; at++):
    if at < l.count && l.tokens[at].type == <space>: continue
    int start = at < l.count ? l.tokens[at].pos : strlen(l.text)
    String gap = _gap(l, before, at,
                      String.new_len((char *) l.text + cursor, start - cursor))
    if gap: out.write(gap)
    if at == l.count: break
    Token t = l.at(at)
    String text = String.new_len((char *) l.text + t.pos, t.len)
    if t.type == <comment>: text = _trimmed(text)
    if text: out.write(text)
    cursor = t.pos + t.len
    before = at
  String result = out.str().rstrip(" \t\n") + "\n"
  return _same_tokens(l, Lint.new(l.path, result, l.selected)) ? result : NULL

/** Returns the number of lines of `l` that formatting removes or rewrites,
    0 for an empty file, or -1 when it cannot be formatted. */
int Lint.format_changes(Lint l):
  if !l.text: return 0
  String text = l.formatted()
  if !text: return -1
  int changed = 0
  foreach List edit in Diff.lines(l.text, text):
    changed += edit.car() == <delete>
  return changed
