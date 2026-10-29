/*  macros.x -- the macro table

    `#define`, `#undef`, and `#include` change a state's table in source
    order. The table of a file x2c includes comes from that file's
    collection entry, so a replayed interface supplies what a cold walk
    does. */

// directives

/* Applies the `#define`, `#undef`, or `#include` directive `token` of the
   file `path` to `cpp`. Any other directive stays for the C compiler. */
module void _command(Compiler c, Cpp cpp, Token token, String path) {
  int undefined = 0, angle = 0;
  Token name = Compiler.macro_directive(token.text, undefined);
  if (name && undefined) _set(cpp, name.text, <undef>);
  else if (name) _define(cpp, name, _site(c, token, path));
  else {
    String target = Compiler.preproc_include_target(token.text, angle);
    String dir = path ? Path.dirname(path) : ".";
    if (target && !cpp.isolated)
      _merge(cpp, c.included_macros(target, angle, dir));
  }
}

/* Records the definition whose name `name` begins. A body x2c cannot scan
   leaves the name to the C compiler, and so does a malformed parameter
   list, which C reports. */
module void _define(Cpp cpp, Token name, List site) {
  Token after = name + 1;
  if (_unreadable(after)) _set(cpp, name.text, <cond>);
  else if (after.type != <(>)
    _set(cpp, name.text, %(object $(name.text) $(_body(after)) $site));
  else {
    Array params = [];
    int variadic = 0;
    Token close = _parameters(after, params, variadic);
    List list = params.list_free();
    String body = close ? _body(close + 1) : NULL;
    if (!close) _set(cpp, name.text, <cond>);
    else
      _set(
        cpp, name.text,
        %(function $(name.text) $list $variadic $body $site));
  }
}

/* Sets one macro's value, which the innermost open group then counts among
   the names it changed. */
module void _set(Cpp cpp, String name, Var value) {
  cpp.macros[name] = value;
  _touch(cpp, name);
}

/* Applies the `(name value)` rows a file exports, as its `#include`
   does. */
static void _merge(Cpp cpp, List rows) {
  foreach (List row in rows) _set(cpp, row.car(), row.cadr());
}

module void _touch(Cpp cpp, String name) {
  size_t depth = cpp.groups.len();
  if (!depth) return;
  CppGroup *group = &((CppGroup *) cpp.groups.bytes)[depth - 1];
  if (!group.touched) group.touched = {};
  group.touched[name] = 1;
}

/* The parameter names after the `(` at `open`, with `__VA_ARGS__` or a
   named variadic parameter last. Returns the closing `)`, or NULL when the
   list is malformed. */
static Token _parameters(Token open, Array params, int &variadic) {
  Token token = Token.skip_trivia(open + 1);
  if (token.type == <)>) return token;
  for (;;) {
    if (token.type == <"...">) {
      params.push("__VA_ARGS__");
      variadic = 1;
    }
    else if (!token.is_word()) return NULL;
    else {
      params.push(token.text);
      Token next = Token.skip_trivia(token + 1);
      if (next.type == <"...">) {
        variadic = 1;
        token = next;
      }
    }
    token = Token.skip_trivia(token + 1);
    if (token.type == <)>) return token;
    if (variadic || token.type != <,>) return NULL;
    token = Token.skip_trivia(token + 1);
  }
}

/* The replacement list from `first` to the end of the directive, as
   written, without surrounding blanks. */
static String _body(Token first) {
  Array parts = [];
  for (Token token = first; token.type != <eof>; token++)
    parts.push(token.text);
  return "".join(parts.list_free()).strip(" \t");
}

static int _unreadable(Token token) {
  for (; token.type != <eof>; token++)
    if (token.type == <error>) return 1;
  return 0;
}

/* Locates a definition through the current source markers. */
static List _site(Compiler c, Token token, String path) {
  int line = token.line;
  String file = c.line_markers ? c.token_source(token, line) : path;
  return $(file ? c.display_path(file) : "<stdin>", line);
}

// the command line

/** Returns the `(name value)` rows that the `-D` and `-U` options among
    the command-line arguments `args` define, sorted by name. `-D NAME`
    defines `NAME` as `1` and `-D NAME=VALUE` as `VALUE`; a later option
    for the same name wins.
*/
List Compiler.command_macros(List args) {
  Cpp cpp = Cpp.new({});
  for (List at = args; at; at = at.cdr()) {
    String arg = at.car(), option = arg[:2], value = arg[2:];
    if (option != "-D" && option != "-U") continue;
    if (!value.len() && at.cdr()) {
      at = at.cdr();
      value = at.car();
    }
    if (option == "-U") _set(cpp, value, <undef>);
    else _command_define(cpp, value);
  }
  return cpp.changes({});
}

static void _command_define(Cpp cpp, String value) {
  int equals = value.find("="), undefined = 0;
  String line = equals < 0
              ? value + " 1" : value[:equals] + " " + value[equals + 1:];
  Token name = Compiler.macro_directive("#define " + line, undefined);
  if (name) _define(cpp, name, %("<command line>" 0));
}
