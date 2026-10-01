/*  preprocess.x -- C preprocessor directives in x2c source

    Copyright (c) 2025 Gary William Flake.

    Preprocessor lines stay in the token stream and become `preproc` nodes,
    so generated C keeps them where they were written. This module reads
    them: it classifies one directive line, hides the conditional arms C
    never takes and marks layout attributes when a unit is tokenized,
    applies the directives before a form to source visibility and the
    unit's `#define` names, and reopens conditional groups around the items
    that generation and emission place elsewhere.
*/
#pragma once
#include "compiler.x"
#pragma private

/* directive lines

   Each operation classifies one directive line. The conditional scan,
   collection, and generation read directives through them. */

/** Returns the preprocessor line `text` without its `#` and the blanks
    around the directive. */
String preproc_directive(String text) =>
  text.strip(" \t").remove_prefix("#").strip(" \t");

/** Classifies the preprocessor line `text` as a conditional directive:
    `<open>` for `#if`, `#ifdef`, and `#ifndef`, `<branch>` for `#elif`
    and `#else` forms, `<close>` for `#endif`, or 0 for any other line.
*/
Symbol preproc_conditional_kind(String text) {
  String directive = preproc_directive(text);
  if (directive.startswith("if")) return <open>;
  if (directive.startswith("el")) return <branch>;
  if (directive.startswith("endif")) return <close>;
  return 0;
}

/** Classifies an opening conditional directive by which of its arms C can
    never reach: `<first>` when the condition requires a never-defined name
    or is `0`, `<rest>` when it is exactly `!defined(NAME)`, else 0. Each
    never-defined name reads as `<never>`, which no C token spells. */
Symbol preproc_never_active_arm(String s) {
  Tokenizer scanned = Tokenizer.new(preproc_directive(s), <x2c>);
  scanned.scan();
  Array words = [];
  for (Token t = Token.skip_trivia(scanned.tokens); t.type != <eof>;
       t = Token.skip_trivia(t + 1))
    words.push(_never_defined(t.text) ? "<never>" : t.text);
  String line = " ".join(words.list_free()).replace(
    "defined ( <never> )", "defined <never>");
  // A `||` gives the condition another way to hold, so the arm can be taken.
  if (line == "ifdef <never>" || line == "if 0" || line == "if ( 0 )" ||
      line == "if defined <never>" ||
      (line.startswith("if defined <never> && ") && !line.contains(" || ")))
    return <first>;
  return line == "ifndef <never>" || line == "if ! defined <never>"
    ? <rest> : 0;
}

/* x2c output is compiled as C by a GNU-style compiler, so `__cplusplus` and
   `_MSC_VER` are never defined, and a compiler built for a host other than
   Windows never targets it. */
static int _never_defined(String name) {
  if (name == "__cplusplus" || name == "_MSC_VER") return 1;
#if defined(_WIN32) || defined(__CYGWIN__)
  return 0;
#else
  return name == "_WIN32" || name == "_WIN64" || name == "__CYGWIN__";
#endif
}

/** Returns the hidden-arm state of the conditional group that `text` opens:
    2 when C never takes its first arm, 1 when C never takes the arms after
    its first `#else`, and 0 otherwise. */
int preproc_open_state(String text) {
  Symbol never = preproc_never_active_arm(text);
  return never == <first> ? 2 : never == <rest>;
}

/** Returns a group's hidden-arm state after its `#elif` or `#else`: 2 when
    the group's state was 1, and 0 otherwise. */
int preproc_branch_state(int state) => state == 1 ? 2 : 0;

/** Returns 1 when the preprocessor line `text` is `#pragma private`, 0 when
    it is `#pragma public`, and -1 otherwise. A comment in the line reads as
    a blank, as it does in C. */
int preproc_visibility(String text) {
  String directive = preproc_directive(text);
  if (!directive.startswith("pragma")) return -1;
  Tokenizer scanned = Tokenizer.new(directive, <x2c>);
  scanned.scan();
  Array words = [];
  for (Token t = Token.skip_trivia(scanned.tokens); t.type != <eof>;
       t = Token.skip_trivia(t + 1))
    words.push(t.text);
  String line = " ".join(words.list_free());
  if (line == "pragma private") return 1;
  return line == "pragma public" ? 0 : -1;
}

/** Returns the file named by the `#include` line `text`, or `NULL` for any
    other line. `angle` is 1 for a `<...>` name and 0 otherwise. Text after
    the name, such as a comment, is ignored.
*/
String preproc_include_target(String text, int &angle) {
  angle = 0;
  String body = preproc_directive(text);
  if (!body.startswith("include")) return NULL;
  body = body.remove_prefix("include").lstrip(" \t");
  if (!body.len() || (body[0] != '"' && body[0] != '<')) return NULL;
  angle = body[0] == '<';
  String rest = body[1:], int close = rest.find(angle ? ">" : "\"");
  return close > 0 ? rest[:close] : NULL;
}

/* Returns the name token of the `#define` or `#undef` directive `content`,
   or NULL for any other directive, and sets `*undefined` for `#undef`. The
   directive is scanned as x2c tokens. */
static Token _macro_directive(String content, int &undefined) {
  String directive = preproc_directive(content);
  undefined = directive.startswith("undef");
  if (!undefined && !directive.startswith("define")) return NULL;
  Tokenizer scanned = Tokenizer.new(
    directive.remove_prefix(undefined ? "undef" : "define"), <x2c>);
  scanned.scan();
  Token token = Token.skip_trivia(scanned.tokens);
  return token.type == <ident> ? token : NULL;
}

/* conditional arms

   x2c output is always compiled as C by a GNU-style compiler, so an arm
   that only C++, MSVC, or `#if 0` reaches holds no syntax x2c needs to
   parse. Its tokens become comments; the directives around it stay in
   place, so emission is unchanged. */

/* One scan of a unit's tokens. `stack` holds the open conditional groups
   as `(id arm state)` entries; a group's state is 2 while its arm is
   hidden, 1 when the arms after its first `#else` will be, and 0
   otherwise. `layout` maps each macro whose body can change a struct's
   layout to 1, or to 2 when the body packs. */
typedef struct ArmScan {
  Compiler c, Array stack, Map layout;
  int hidden, serial;
} ArmScan;

/** Records the open groups after each conditional directive of the
    tokenized unit, and marks layout attributes where written or where a
    macro expands to one.
*/
void Compiler.scan_conditionals(Compiler c) {
  Array stack = $auto([]);
  Map layout = $auto({});
  ArmScan scan = {.c = c, .stack = stack, .layout = layout};
  c.arm_stacks = {};
  c.layout_marks = [];
  c.packed_marks = [];
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.type == <eof>) break;
    if (token.type == <preproc>) scan.directive(token, i);
    else i = scan.code(token, i);
  }
}

static void ArmScan.directive(ArmScan *s, Token token, size_t i) {
  Symbol kind = preproc_conditional_kind(token.text);
  int conditional = kind == <open> || (kind && s.stack.len());
  if (kind == <open>)
    s.stack.push(%(${++s.serial} 0 ${preproc_open_state(token.text)}));
  else if (kind == <branch> && s.stack.len()) {
    Var (id, arm, state) = s.stack[-1];
    s.stack[-1] = %($id ${arm.integer() + 1} ${preproc_branch_state(state)});
  }
  else if (kind == <close> && s.stack.len()) s.stack.take_last();
  else if (!s.hidden) _note_layout_macro(token.text, s.layout, s.stack.len());
  if (!conditional) return;
  s.c.arm_stacks[(long) i] = s.stack.list();
  s.hidden = _hidden_group(s.stack);
}

static int _hidden_group(Array stack) {
  foreach (List group, stack) if (group.caddr() == 2) return 1;
  return 0;
}

/* Hides a token of an arm C never takes and marks layout attributes, and
   returns the index of the token's last part. A lexical failure ends the
   token stream, so the rest of the unit is missing whichever arm holds it;
   the `<error>` token stays visible, and the parser reports it. */
static size_t ArmScan.code(ArmScan *s, Token token, size_t i) {
  if (s.hidden && token.type != <space> && token.type != <error>)
    token.type = <comment>;
  else if (token.type == <ident> && token.text == "__attribute__")
    return _note_attribute(s.c, i);
  else if (token.type == <ident> && token.text in s.layout)
    _mark_layout(s.c, i, s.layout[token.text] == 2);
  return i;
}

/* Records a pair of layout marks at the `__attribute__ ((...))` starting at
   token `index` when it can change a struct's layout. Returns the index of
   the attribute's last token. */
static size_t _note_attribute(Compiler c, size_t index) {
  Token base = c.tokenizer.tokens;
  Token open = Token.skip_trivia(base + index + 1);
  if (open.type != <(>) return index;
  Token inner = Token.skip_trivia(open + 1), last = open.group_close();
  if (last.type == <eof>) return index;
  int packed = 0;
  if (inner.type == <(> && _layout_attribute(inner, packed))
    _mark_layout(c, index, packed);
  return last - base;
}

/* A layout mark pair brackets the token at `index`, and a packing
   attribute adds a packed pair. */
static void _mark_layout(Compiler c, size_t index, int packed) {
  c.layout_marks.push((long) index);
  c.layout_marks.push((long) index + 1);
  if (!packed) return;
  c.packed_marks.push((long) index);
  c.packed_marks.push((long) index + 1);
}

/* Reports whether the attribute list the group `open` holds names an
   attribute that can change a struct's layout, spelled with or without its
   surrounding underscores. Identifiers inside an attribute's own arguments
   are not names. */
static int _layout_attribute(Token open, int &packed) {
  Token close = open.group_close();
  int depth = 0, layout = 0;
  for (Token t = open; t < close; t++) {
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
  return layout;
}

/* Tracks in `layout` the macros whose body holds an attribute that can
   change a struct's layout, written out or through another such macro. A
   use of one is marked as the attribute it expands to would be. As with
   layout, a macro that any arm defines with such an attribute stays in
   `layout`; only an `#undef` or definition outside every conditional group,
   `conditional` false, removes it. */
static void _note_layout_macro(String content, Map layout, int conditional) {
  int undefined;
  Token name = _macro_directive(content, undefined);
  if (!name) return;
  if (!conditional) layout.del(name.text);
  if (undefined) return;
  Token token = name + 1;
  if (token.type == <(>) token = token.after_group();
  int value = 0;
  for (; token.type != <eof>; token = Token.skip_trivia(token + 1)) {
    if (token.type != <ident>) continue;
    int level = _word_layout(token, layout);
    if (level > value) value = level;
  }
  if (value && (!layout.contains(name.text) || layout[name.text] < value))
    layout[name.text] = value;
}

/* The layout level one word of a macro body contributes: an attribute's
   own level, or the level of the layout macro it names. */
static int _word_layout(Token token, Map layout) {
  if (token.text == "__attribute__") return _attribute_layout(token);
  if (token.text in layout) return layout[token.text];
  return 0;
}

/* 2 for a packing `__attribute__` at `token`, 1 for another attribute that
   can change a struct's layout, and 0 otherwise. */
static int _attribute_layout(Token token) {
  Token open = Token.skip_trivia(token + 1);
  Token inner = open.type == <(> ? Token.skip_trivia(open + 1) : open;
  int packed = 0;
  if (inner.type != <(> || !_layout_attribute(inner, packed)) return 0;
  return packed ? 2 : 1;
}

/* leading directives

   The directives before a form set source visibility and record the unit's
   `#define` names, which literals and declaration prefixes read. */

/** Returns source-ordered preprocessor nodes in the preceding trivia.

    Spaces and comments remain trivia rather than becoming AST nodes.
*/
List Compiler.leading_preproc(Compiler c) {
  List noncode = %();
  Token base = c.tokenizer.tokens, token = c.token;
  if (token == base) return NULL;
  while (--token >= base) {
    if (token.type == <preproc>)
      noncode = cons(%( preproc ${token.text} ), noncode);
    else if (token.type != <space> && token.type != <comment>) break;
  }
  return noncode;
}

/** Applies public and private pragma directives to source visibility state
    and records each object-like `#define` name, less those `#undef` drops,
    for the literal warning.

    A negative visibility state disables pragma tracking for this token
    stream; macro names are recorded regardless.
*/
void Compiler.update_source_visibility(Compiler c, List directives) {
  foreach (List directive, directives) c.note_object_macro(directive.cadr());
  if (c.source_private < 0) return;
  foreach (List directive, directives) {
    int visibility = preproc_visibility(directive.cadr());
    if (visibility >= 0) c.source_private = visibility;
  }
}

/** Records the name of the `#define` line `content` so a bare atom spelled
    the same way inside a literal can be flagged and a declaration prefix
    can be read. The directive after `#define` is scanned as x2c tokens. An
    `#undef` drops the name, so later source reads it as an ordinary
    identifier.
*/
void Compiler.note_object_macro(Compiler c, String content) {
  int undefined;
  Token token = _macro_directive(content, undefined);
  if (!token) return;
  String name = token.text;
  Token body = token + 1;
  if (undefined) c.object_macros.del(name);
  // A parameter list touching the name makes the macro function-like.
  else if (body.type == <(>) _note_function_macro(c, name, body);
  else _note_prefix_macro(c, name, body.skip_trivia());
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
  if (kind.equal(%())) c.object_macros[name] = <annotation>;
  else if (kind.equal(<wrapper>)) c.object_macros[name] = <wrapper>;
}

/* An object-like body is classified by `_macro_prefix`. A name another arm
   defines to anything but a string literal is no string literal:
   `Var v = SEP;` must not make a String of the other arm's number. */
static void _note_prefix_macro(Compiler c, String name, Token body) {
  Var definition = _macro_prefix(c, body, NULL), existing;
  if (!c.object_macros.try_get(name, existing) ||
      _prefix_rank(definition) > _prefix_rank(existing) ||
      (existing.equal(<string>) && !definition.equal(<string>)))
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
    else foreach (Var item, definition) words.push(item);
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
          definition.equal(<annotation>));
}

/* Ranks prefix classifications so a name defined differently in two
   conditional arms keeps the reading that emits correct C: `static` hides
   a definition from the header, so it wins; a qualifier that another arm
   omits, as zlib's `z_const` is `const` or nothing, rejects writes that C
   accepts in that arm, so it loses to any other prefix; other text loses to
   any prefix. */
static int _prefix_rank(Var v) {
  if (v is not <list>) return 0;
  if (List.match(v, %(* static *))) return 4;
  foreach (Symbol word, v) if (word.is_type_qualifier()) return 1;
  return v.list() ? 3 : 2;
}

/* conditional groups around placed items

   Generation and emission place some items away from the directives that
   guard them. They record the groups open at each item and reopen them
   around it. */

/** Follows the conditional groups open after the preprocessor line `text`.
    `arms` holds one entry per open group, innermost first, listing the
    `preproc` nodes that select that group's current arm.
*/
List preproc_track_arms(List arms, String text) {
  Symbol kind = preproc_conditional_kind(text);
  if (kind == <open>) return cons(%((preproc $text)), arms);
  if (!arms) return arms;
  if (kind == <branch>)
    return cons(%(@{arms.car()} (preproc $text)), arms.cdr());
  return kind == <close> ? arms.cdr() : arms;
}

/** Returns `items` inside the conditional arms `arms` tracked by
    `preproc_track_arms`: the directives that reopen each group, outermost
    first, then `items`, then one `#endif` per group.
*/
List preproc_within_arms(List arms, List items) {
  Array out = [];
  foreach (List group, arms.reverse())
    foreach (List directive, group) out.push(directive);
  foreach (Var item, items) out.push(item);
  for (unsigned i = arms.len(); i; i--) out.push(%(preproc "#endif"));
  return out.list_free();
}
