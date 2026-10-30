/*  preprocess.x -- C preprocessor directives in x2c source

    Copyright (c) 2025 Gary William Flake.

    Preprocessor lines stay in the token stream and become `preproc` nodes,
    so generated C keeps them where they were written. Optional CPP expansion
    decides conditional groups for C compatibility; ordinary source retains
    narrow handling of literal false and impossible host arms. This module
    hides those arms, marks layout attributes, and records what preceding
    directives say about the unit's `#define` names.
*/
#pragma once
#include "compiler/compiler.x"
#include "ast.x"
#include <ctype.h>

/* conditional arms

   An arm C never takes holds no syntax x2c needs to parse. Its tokens
   become comments; the directives around it stay in place, so emission is
   unchanged. */

/* One scan of a unit's tokens. `open` holds the conditional
   groups open at the scan, as `(id arm state)` rows. `layout` maps each
   macro whose body can change a struct's layout to 1, or to 2 when the
   body packs. */
static typedef struct ArmScan {
  Compiler c, List open, Map layout, Array stack;
  int hidden, serial;
} ArmScan;

/* directive lines

   Each operation classifies one directive line. The conditional scan,
   collection, and generation read directives through them. */

/** Returns the file named by the `#include` line `text`, or `NULL` for any
    other line. `angle` is 1 for a `<...>` name and 0 otherwise. Text after
    the name, such as a comment, is ignored.
*/
String Compiler.preproc_include_target(String text, int &angle) {
  angle = 0;
  String body = Compiler.preproc_directive(text);
  if (!body.startswith("include")) return NULL;
  body = body.remove_prefix("include").lstrip(" \t");
  if (!body.len() || (body[0] != '"' && body[0] != '<')) return NULL;
  angle = body[0] == '<';
  String rest = body[1:], int close = rest.find(angle ? ">" : "\"");
  return close > 0 ? rest[:close] : NULL;
}

/** Returns the file that the host preprocessor's line marker `text`,
    `# N "file" flags`, names and sets `line` to N, or returns `NULL` for
    any other line.
*/
String Compiler.preproc_marker_file(String text, int &line) {
  String body = Compiler.preproc_directive(text);
  size_t digits = 0;
  while (digits < body.len() && isdigit(body[digits])) digits++;
  String rest = body[digits:].lstrip(" \t");
  if (!digits || !rest.startswith("\"")) return NULL;
  int close = rest[1:].find("\"");
  if (close < 0) return NULL;
  line = atoi(body);
  return rest[1:close + 1].unescape();
}

/** Hides literal false and impossible host arms in ordinary source, or the
    arms decided by optional CPP expansion. Records conditional groups and
    marks layout attributes without expanding ordinary source macros.
*/
void Compiler.scan_conditionals(Compiler c) {
  Map layout = auto {};
  Array stack = auto (c.arm_stacks == NULL ? Array.new() : NULL);
  ArmScan scan = {.c = c, .layout = layout, .stack = stack};
  if (stack != NULL) c.arm_stacks = {};
  c.layout_marks = [];
  c.packed_marks = [];
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.type == <eof>) break;
    if (token.type == <preproc>) _directive(scan, token, i);
    else i = _code(scan, token, i);
  }
}

/** Returns the name token of the `#define` or `#undef` directive
    `content`, or NULL for any other directive, and sets `undefined` for
    `#undef`. The text after `define` or `undef` is scanned by
    `Compiler.scan_directive`, so the tokens after the name are the rest of
    the directive.
*/
Token Compiler.macro_directive(String content, int &undefined) {
  String directive = Compiler.preproc_directive(content);
  undefined = directive.startswith("undef");
  if (!undefined && !directive.startswith("define")) return NULL;
  Token token = Token.skip_trivia(
    Compiler.scan_directive(
      directive.remove_prefix(undefined ? "undef" : "define")));
  return token.is_word() ? token : NULL;
}

/** Returns the first token of `text` scanned as x2c tokens after its
    continuation lines are joined, as a directive's text is read. The
    tokens end in `eof` and belong to the current Scope.
*/
Token Compiler.scan_directive(String text) {
  Tokenizer scanned = Tokenizer.new(
    text.replace("\\\r\n", "").replace("\\\n", ""), <x2c>);
  scanned.scan();
  return scanned.tokens;
}

/* leading directives

   Directives before a form record the unit's `#define` names, which literals
   and declaration prefixes read. */

/** Returns source-ordered preprocessor nodes in the preceding trivia.

    Spaces and comments remain trivia rather than becoming AST nodes.
*/
List Compiler.leading_preproc(Compiler c) => _leading_preproc(c, 0);

/** Returns preceding directives with source-mapped include locations.
    Analysis callers use `leading_preproc` for unwrapped directive nodes.
    Source includes reuse the ordinary `at` origin through C emission.
*/
List Compiler.located_preproc(Compiler c) =>
  _leading_preproc(c, c.source_map);

/** Records object-like `#define` names and removes names after `#undef`.
    Source storage determines visibility independently of directives.
*/
void Compiler.note_preprocessor_macros(Compiler c, List directives) {
  foreach (List directive in directives)
    c.note_object_macro(Ast.without_origin(directive).cadr());
}

/** Records the name of the `#define` line `content` so a bare atom spelled
    the same way inside a literal can be flagged and a declaration prefix
    can be read. The directive after `#define` is scanned as x2c tokens. An
    `#undef` drops the name, so later source reads it as an ordinary
    identifier.
*/
void Compiler.note_object_macro(Compiler c, String content) {
  int undefined;
  Token token = Compiler.macro_directive(content, undefined);
  if (!token || token.type != <ident>) return;
  String name = token.text;
  Token body = token + 1;
  if (undefined) c.object_macros.del(name);
  // A parameter list touching the name makes the macro function-like.
  else if (body.type == <(>) _note_function_macro(c, name, body);
  else _note_prefix_macro(c, name, body.skip_trivia());
}

/* conditional groups around placed items

   Generation and emission place some items away from the directives that
   guard them. They record the groups open at each item and reopen them
   around it. */

/** Follows the conditional groups open after the preprocessor line `text`.
    `arms` holds one entry per open group, innermost first, listing the
    `preproc` nodes that select that group's current arm.
*/
List Compiler.preproc_track_arms(List arms, String text) {
  Symbol kind = Compiler.preproc_conditional_kind(text);
  if (kind == <open>) return cons(%((preproc $text)), arms);
  if (!arms) return arms;
  if (kind == <branch>)
    return cons(%(@(arms.car()) (preproc $text)), arms.cdr());
  return kind == <close> ? arms.cdr() : arms;
}

/** Classifies the preprocessor line `text` as a conditional directive:
    `<open>` for `#if`, `#ifdef`, and `#ifndef`, `<branch>` for `#elif`
    and `#else` forms, `<close>` for `#endif`, or 0 for any other line.
*/
Symbol Compiler.preproc_conditional_kind(String text) {
  String directive = Compiler.preproc_directive(text);
  if (directive.startswith("if")) return <open>;
  if (directive.startswith("el")) return <branch>;
  if (directive.startswith("endif")) return <close>;
  return 0;
}

/** Returns the preprocessor line `text` without its `#` and the blanks
    around the directive.
*/
String Compiler.preproc_directive(String text) =>
  text.strip(" \t").remove_prefix("#").strip(" \t");

/** Returns `items` inside the conditional arms `arms` tracked by
    `Compiler.preproc_track_arms`: the directives that reopen each group,
    outermost first, then `items`, then one `#endif` per group.
*/
List Compiler.preproc_within_arms(List arms, List items) {
  Array out = [];
  foreach (List group in arms.reverse())
    foreach (List directive in group) out.push(directive);
  foreach (List item in items) out.push(item);
  for (unsigned i = arms.len(); i; i--) out.push(%(preproc "#endif"));
  return out.list_free();
}

static List _leading_preproc(Compiler c, int located) {
  List noncode = %();
  Token base = c.tokenizer.tokens, token = c.token;
  while (--token >= base) {
    if (token.type == <preproc>) {
      List directive = %(preproc $(token.text));
      int angle = 0;
      if (located && Compiler.preproc_include_target(token.text, angle))
        directive = c.anchor_origin(directive, token);
      noncode = cons(directive, noncode);
    }
    else if (token.type != <space> && token.type != <comment>) break;
  }
  return noncode;
}

// conditional branch tracking

static void _directive(ArmScan &s, Token token, size_t i) {
  if (s.stack != NULL) {
    _plain_directive(s, token, i);
    return;
  }
  Var open;
  if (s.c.arm_stacks.try_get((long) i, open)) {
    s.open = open;
    s.hidden = _hidden_group(s.open);
  }
  else if (!s.hidden) _note_layout_macro(s, token.text);
}

/* Ordinary source only hides literal false and impossible host arms. It does
   not evaluate macro definitions or acquire included macro tables. */
static void _plain_directive(ArmScan &s, Token token, size_t i) {
  Symbol kind = Compiler.preproc_conditional_kind(token.text);
  int conditional = kind == <open> || (kind && s.stack.len());
  if (kind == <open>)
    s.stack.push($(++s.serial, 0, _plain_open_state(token.text)));
  else if (kind == <branch> && s.stack.len()) {
    Var (id, arm, state) = s.stack[-1];
    s.stack[-1] = $(id, arm.integer() + 1,
      state == 1 || state == 3 ? 3 : 0);
  }
  else if (kind == <close> && s.stack.len()) s.stack.take_last();
  else if (!s.hidden) _note_layout_macro(s, token.text);
  if (!conditional) return;
  s.open = s.stack;
  s.c.arm_stacks[(long) i] = s.open;
  s.hidden = _hidden_group(s.open);
}

/* State 2 hides the opening arm; state 1 selects it, and state 3 keeps
   every following alternative hidden after a selected arm. */
static int _plain_open_state(String text) {
  String line = _plain_directive_line(Compiler.preproc_directive(text));
  line = line.replace("defined ( <never> )", "defined <never>");
  if (line == "ifdef <never>" || line == "if 0" || line == "if ( 0 )" ||
      line == "if defined <never>" ||
      (line.startswith("if defined <never> && ") && !(" || " in line)))
    return 2;
  return line == "ifndef <never>" || line == "if ! defined <never>";
}

static String _plain_directive_line(String directive) {
  Token token = Token.skip_trivia(Compiler.scan_directive(directive));
  Array words = [];
  for (; token.type != <eof>; token = Token.skip_trivia(token + 1))
    words.push(_never_defined(token.text) ? "<never>" : token.text);
  return " ".join(words.list_free());
}

static int _never_defined(String name) {
  if (name == "__cplusplus" || name == "_MSC_VER") return 1;
#if defined(_WIN32) || defined(__CYGWIN__)
  return 0;
#else
  return name == "_WIN32" || name == "_WIN64" || name == "__CYGWIN__";
#endif
}

static int _hidden_group(List open) {
  foreach (List group in open)
    if (group.caddr() == <hidden> || group.caddr() == 2 ||
        group.caddr() == 3) return 1;
  return 0;
}

/* Hides a token of an arm C never takes and marks layout attributes, and
   returns the index of the token's last part. A lexical failure ends the
   token stream, so the rest of the unit is missing whichever arm holds it;
   the `<error>` token stays visible, and the parser reports it. */
static size_t _code(ArmScan &s, Token token, size_t i) {
  if (s.hidden && token.type != <space> && token.type != <error>)
    token.type = <comment>;
  else if (token.type == <ident> && token.text == "__attribute__")
    return _note_attribute(s, i);
  else if (token.type == <ident> && token.text in s.layout)
    _mark_layout(s, i, s.layout[token.text] == 2);
  return i;
}

/* Records a pair of layout marks at the `__attribute__ ((...))` starting at
   token `index` when it can change a struct's layout. Returns the index of
   the attribute's last token. */
static size_t _note_attribute(ArmScan &s, size_t index) {
  Token base = s.c.tokenizer.tokens;
  Token open = Token.skip_trivia(base + index + 1);
  if (open.type != <(>) return index;
  Token last = open.group_close();
  if (last.type == <eof>) return index;
  int level = _attribute_layout(base + index);
  if (level) _mark_layout(s, index, level == 2);
  return last - base;
}

/* A layout mark pair brackets the token at `index`, and a packing
   attribute adds a packed pair. */
static void _mark_layout(ArmScan &s, size_t index, int packed) {
  Compiler c = s.c;
  c.layout_marks.push((long) index);
  c.layout_marks.push((long) index + 1);
  if (!packed) return;
  c.packed_marks.push((long) index);
  c.packed_marks.push((long) index + 1);
}

/* Tracks in `layout` the macros whose body holds an attribute that can
   change a struct's layout, written out or through another such macro. A
   use of one is marked as the attribute it expands to would be. As with
   layout, a macro that any arm defines with such an attribute stays in
   `layout`; only an `#undef` or definition outside every conditional group
   removes it. */
static void _note_layout_macro(ArmScan &s, String content) {
  int undefined;
  Token name = Compiler.macro_directive(content, undefined);
  if (!name || name.type != <ident>) return;
  Map layout = s.layout;
  if (!s.open) layout.del(name.text);
  if (undefined) return;
  Token token = name + 1;
  if (token.type == <(>) token = token.after_group();
  int value = 0;
  for (; token.type != <eof>; token = Token.skip_trivia(token + 1)) {
    if (token.type != <ident>) continue;
    int level = 0;
    if (token.text == "__attribute__") level = _attribute_layout(token);
    else if (token.text in layout) level = layout[token.text];
    if (level > value) value = level;
  }
  if (value && (!(name.text in layout) || layout[name.text] < value))
    layout[name.text] = value;
}

/* 2 for a packing `__attribute__` at `token`, 1 for another attribute that
   can change a struct's layout, and 0 otherwise. */
static int _attribute_layout(Token token) {
  Token open = Token.skip_trivia(token + 1);
  Token inner = open.type == <(> ? Token.skip_trivia(open + 1) : open;
  if (inner.type != <(>) return 0;
  Token close = inner.group_close();
  int depth = 0, layout = 0, packed = 0;
  // Only depth-one names are attributes; their arguments are not.
  for (Token t = inner; t < close; t++) {
    depth += t.type.group_step();
    if (depth != 1 || t.type != <ident>) continue;
    String word = t.text.strip("_");
    if (word == "packed") {
      layout = 1;
      packed = 1;
    }
    else if (word == "aligned" || word == "mode" ||
             word == "vector_size") layout = 1;
  }
  if (!layout) return 0;
  return packed ? 2 : 1;
}

/* A function-like macro whose body is empty or an attribute is an
   `<annotation>`, and one that wraps its parameter is a `<wrapper>`; any
   other function-like macro is skipped. */
static void _note_function_macro(Compiler c, String name, Token params) {
  Token after = params.after_group(), String param = NULL;
  Token first = Token.skip_trivia(params + 1);
  if (first.type == <ident> && Token.skip_trivia(first + 1).type == <)>)
    param = first.text;
  Var kind = _macro_prefix(c, after, param);
  if (kind == %()) c.object_macros[name] = <annotation>;
  else if (kind == <wrapper>) c.object_macros[name] = <wrapper>;
}

/* An object-like body is classified by `_macro_prefix`. A name another arm
   defines to anything but a string literal is no string literal:
   `Var v = SEP;` must not make a String of the other arm's number. */
static void _note_prefix_macro(Compiler c, String name, Token body) {
  Var definition = _macro_prefix(c, body, NULL), existing;
  if (!c.object_macros.try_get(name, existing) ||
      _prefix_rank(definition) > _prefix_rank(existing) ||
      (existing == <string> && definition != <string>))
    c.object_macros[name] = definition;
}

/* Classifies a macro body, scanned as x2c tokens, by the declaration prefix
   it contributes: the `List` of its specifier words, which are storage
   classes, `inline`, qualifiers, builtin types, and the words of other
   prefix macros, amid attributes that contribute nothing; `<wrapper>` when
   a function-like body is its parameter `param` amid prefixes; `<string>`
   for a string literal; and 1 for any other text. */
static Var _macro_prefix(Compiler c, Token token, String param) {
  if (token.type == <lit-char*>) return <string>;
  Array words = [], int wrapped = 0;
  while (token.type != <eof>) {
    Symbol type = token.type, String word = token.text;
    Var definition;
    Token next = Token.skip_trivia(token + 1);
    if (_is_specifier(type)) words.push(type);
    else if (type == <lit-char*>);   // the linkage name in `extern "C"`
    else if (type != <ident>) return 1;
    else if (_is_annotation(c, word)) {
      if (next.type != <(>) return 1;
      next = next.after_group();
    }
    else if (param && word == param && !wrapped) wrapped = 1;
    else if (!c.object_macros.try_get(word, definition) ||
             definition is not <list>)
      return 1;
    else foreach (Symbol item in definition) words.push(item);
    token = next;
  }
  return wrapped ? <wrapper> : words.list_free();
}

static int _is_specifier(Symbol type) =>
  type.is_storage_class() || type.is_inline() || type.is_type_qualifier() ||
  type.is_builtin_type();

static int _is_annotation(Compiler c, String word) {
  Var definition;
  return word == "__attribute__" || word == "__declspec" ||
         (c.object_macros.try_get(word, definition) &&
          definition == <annotation>);
}

/* Ranks prefix classifications so a name defined differently in two
   conditional arms keeps the reading that emits correct C: `static` hides
   a definition from the header, so it wins; a qualifier that another arm
   omits, as zlib's `z_const` is `const` or nothing, rejects writes that C
   accepts in that arm, so it loses to any other prefix; other text loses to
   any prefix. */
static int _prefix_rank(Var v) {
  if (v is not <list>) return 0;
  List words = v;
  if (<static> in words) return 4;
  foreach (Symbol word in words) if (word.is_type_qualifier()) return 1;
  return words ? 3 : 2;
}
