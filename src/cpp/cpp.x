/*  cpp.x -- the C preprocessing x2c performs before parsing

    Copyright (c) 2026 Gary William Flake.

    x2c expands the C macros it can see and decides the conditional groups
    it can before the parser reads a token, so a macro body is translated
    like any other source. A macro is visible when the unit, a file that
    x2c reads through its own include search, or the command line defines
    it; a system header's macros stay for the C compiler. A condition is
    decided when every name it tests is visible, known never to be defined,
    or a literal. Every arm of an undecided group parses, and a macro that
    such a group defines or undefines is conditionally defined after it,
    which leaves its uses to the C compiler. Directives stay in the token
    stream, so generated C keeps them where they were written.
*/
#pragma once
#include "compiler/compiler.x"
#include "collect/collect.x"
#include <ctype.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

/** Holds the C preprocessor state at one point of a source: the macro
    table and the open conditional groups. `macros` maps a name to its
    definition List, to `<undef>` after an `#undef`, or to `<cond>` when an
    undecided group changed it or x2c cannot read its body. A definition is
    `(object NAME BODY SITE)` or `(function NAME PARAMETERS VARIADIC BODY
    SITE)`, where `SITE` is `(FILE LINE)`. An `isolated` state leaves the
    table unchanged at an `#include`. The state belongs to the Scope that
    creates it; `Cpp.copy` makes an independent one.
*/
module typedef struct Cpp {
  Map macros;
  Block groups;
  int serial, isolated;
} *Cpp;

/* One open conditional group. `state` is the current arm's: `<taken>`,
   `<hidden>`, or `<maybe>` when its condition is undecided. `taken` and
   `doubtful` record whether an earlier arm was taken or may have been.
   `before` is the macro table before the first undecided arm, which every
   later arm starts from, and `touched` names each macro the group's arms
   changed. A group opened inside a hidden arm is `inert`: all its arms are
   hidden. */
module typedef struct CppGroup {
  int id, arm, taken, doubtful, inert;
  Symbol state;
  Map before, touched;
} CppGroup;

/* One token of a macro use while it is expanded: a token, the names of the
   macros whose expansion produced it, which do not expand it again, and
   whether blanks preceded it. An `<empty>` token stands for an empty
   argument beside `##`. */
module typedef struct CppToken {
  struct Token token;
  List hide;
  int space;
} CppToken;

// states

/** Returns a state with the macro table `macros`, which it takes, and no
    open conditional group.
*/
Cpp Cpp.new(Map macros) {
  Cpp cpp = xcalloc(1, sizeof(struct Cpp));
  cpp.macros = macros;
  cpp.groups = Block.new(sizeof(CppGroup));
  return cpp;
}

/** Returns a state like `Cpp.new` whose `#include` directives apply no
    macros. A reading before collection uses one, because which included
    files have been collected then depends on earlier units.
*/
Cpp Cpp.isolated(Map macros) {
  Cpp cpp = Cpp.new(macros);
  cpp.isolated = 1;
  return cpp;
}

/** Returns an independent copy of `cpp`. */
Cpp Cpp.copy(Cpp cpp) {
  Cpp copy = Cpp.new(cpp.macros.copy());
  copy.serial = cpp.serial;
  copy.isolated = cpp.isolated;
  CppGroup *groups = cpp.groups.bytes;
  for (size_t i = 0; i < cpp.groups.len(); i++) {
    CppGroup group = groups[i];
    if (group.touched) group.touched = group.touched.copy();
    copy.groups.push(&group);
  }
  return copy;
}

/** Reports whether C never takes the arm at this point. */
int Cpp.hidden(Cpp cpp) {
  size_t depth = cpp.groups.len();
  return depth && ((CppGroup *) cpp.groups.bytes)[depth - 1].state == <hidden>;
}

/** Returns the `(name value)` rows of every macro whose value differs from
    its value in `initial`, sorted by name: what a file exports to the
    files that include it.
*/
List Cpp.changes(Cpp cpp, Map initial) {
  Array rows = [];
  foreach ((String name, Var value) in cpp.macros) {
    Var before = initial[name];
    if (before is void || !Var.equal(before, value)) rows.push($(name, value));
  }
  rows.sort();
  return rows.list_free();
}

/** Returns a macro table holding the `(name value)` rows `rows`. */
Map Cpp.table(List rows) {
  Map macros = {};
  foreach (List row in rows) macros[row.car()] = row.cadr();
  return macros;
}

// tokens

/** Reports whether `t` is an identifier or a keyword, which a macro can name.
*/
int Token.is_word(Token t) =>
  t.type == <ident> || (t.text && scan_keyword_type(t.text, t.text.len()));

/** Returns the text that the tokens from `first` through `last` of one
    stream spell, with the blanks and comments between them as written. A
    space separates two tokens that an expansion placed side by side when
    their texts would otherwise run together.
*/
String Token.spelling(Token first, Token last) {
  Array parts = [];
  for (Token token = first; token <= last; token++) {
    if (token > first && _runs_together(token - 1, token)) parts.push(" ");
    parts.push(token.text);
  }
  return "".join(parts.list_free());
}

static int _runs_together(Token left, Token right) =>
  left.text.len() && right.text.len() &&
  _word_char(left.text[left.text.len() - 1]) && _word_char(right.text[0]);

static int _word_char(char ch) => isalnum((unsigned char) ch) || ch == '_';

module {
  "macros.x",
  "conditions.x",
  "expand.x",
}
