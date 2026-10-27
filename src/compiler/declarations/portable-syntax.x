/*  portable-syntax.x -- portable compile-time syntax

    Public macro definitions and effects cross Context and interface
    boundaries. Freezing turns tokens and origin indices into portable rows;
    thawing rebuilds them in the importing unit. Local recipes stay live.
*/

/** Retains exported syntax across translation units and cached interfaces.
    Tokens and origin indices become portable source data; marker-shaped user
    Lists are escaped so thawing preserves their values.
*/
Var Compiler.freeze_declaration_syntax(Compiler c, Var syntax) {
  if (syntax is not <list> || syntax.is_nil()) return _freeze_leaf(syntax);
  String physical = NULL;
  Var source = void;
  if (Ast.try_binding(syntax, NULL, physical) &&
      c.semantic_binding_facts().try_get(%(source-spelling $syntax), source) &&
      source != physical)
    return %(declaration-binding $syntax $source);
  match (syntax) {
    case %(cache ?(int id)):
      return %(declaration-cache $(_freeze_cache_key(c, c.id_keys[id])));
    case %(macrodef *rows): return _declaration_macro(c, rows, 0);
    case %(src (source ?path ?begin ?end) ?node):
      return %(src (source $(_declaration_path(path, 0)) $begin $end)
        $(c.freeze_declaration_syntax(node)));
    case %(at ?(int origin) ?node): return _freeze_origin(c, origin, node);
  }
  return _freeze_rows(c, syntax);
}

/** Restores exported syntax in the importing unit's parsing lifetime. */
Var Compiler.thaw_declaration_syntax(Compiler c, Var syntax) {
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  match (syntax) {
    /* A quotation's hole holds a live value, which was never frozen. */
    case %("x2c.hole" *): return syntax;
    case %(declaration-binding ?binding ?source): {
      c.set_fact(%(source-spelling $binding), source);
      return binding;
    }
    case %(declaration-cache ?key):
      return c.cache(_thaw_cache_key(c, key));
    case %(declaration-list *rows): return _thaw_rows(c, rows);
    case %(macrodef *rows): return _declaration_macro(c, rows, 1);
    case %(src (source ?path ?begin ?end) ?node):
      return %(src (source $(_declaration_path(path, 1)) $begin $end)
        $(c.thaw_declaration_syntax(node)));
    case %(declaration-void): return void;
    case %(declaration-empty-symbol): return (Symbol) 0;
    case %(declaration-atom ?spelling): return Atom.intern(spelling);
    case %(declaration-token ?type ?text ?line ?column ?length ?position):
      return _thaw_token(type, text, line, column, length, position);
    case %(declaration-origin ?location ?node):
      return _thaw_origin(c, location, node);
  }
  return _thaw_rows(c, syntax);
}

// portable compile-time syntax

// An origin index freezes as the location it names in this parse.
static List _freeze_origin(Compiler c, int origin, Var node) {
  List location = c.origin_location(origin);
  if (!location) return %(at m-origin $(c.freeze_declaration_syntax(node)));
  return %(declaration-origin $(_declaration_location(location, 0))
            $(c.freeze_declaration_syntax(node)));
}

// A List whose head is a marker is escaped, so thawing keeps its value.
static List _freeze_rows(Compiler c, List syntax) {
  Array rows = [];
  foreach (Var row in syntax) rows.push(c.freeze_declaration_syntax(row));
  match (syntax)
    case %((!or declaration-void declaration-empty-symbol declaration-atom
                declaration-token declaration-origin declaration-list
                declaration-cache declaration-cache-binding
                declaration-binding) *):
      return %(declaration-list @(rows.list_free()));
  return rows.list_free();
}

/* Literal conversion calls refer to the consumer's global bindings. */
static Var _freeze_cache_key(Compiler c, Var key) {
  String name = NULL;
  if (Ast.try_binding(key, NULL, name))
    return %(declaration-cache-binding $name);
  if (key is not <list>) return _freeze_leaf(key);
  if (key ~= %(cache ?)) return c.freeze_declaration_syntax(key);
  Array out = [];
  foreach (Var child in key.list()) out.push(_freeze_cache_key(c, child));
  return out.list_free();
}

static Var _thaw_cache_key(Compiler c, Var key) {
  if (key is not <list>) return key;
  match (key) {
    case %(declaration-cache-binding ?name):
      return c.sym.reference_global($(name));
    case %(declaration-cache ?): return c.thaw_declaration_syntax(key);
    case %((!or declaration-void declaration-empty-symbol declaration-atom
                declaration-token declaration-origin declaration-list) *):
      return c.thaw_declaration_syntax(key);
  }
  Array out = [];
  foreach (Var child in key.list()) out.push(_thaw_cache_key(c, child));
  return out.list_free();
}

static List _thaw_rows(Compiler c, List rows) {
  Array values = [];
  foreach (Var row in rows) values.push(c.thaw_declaration_syntax(row));
  return values.list_free();
}

// A frozen location becomes a new row of this parse's origin table.
static List _thaw_origin(Compiler c, List location, Var node) {
  if (location ~= %((file ?file) (line ?line) (column ?column)
                    (length ?length) (position ?position)))
    c.origins.push(%(source $file $line $column $length $position));
  int occurrence = c.origins.len();
  return %(at $occurrence $(c.thaw_declaration_syntax(node)));
}

static List _declaration_macro(Compiler c, List rows, int thaw) {
  Array out = [];
  foreach (List row in rows) out.push(_macro_row(c, row, thaw));
  return %(macrodef @(out.list_free()));
}

static List _macro_row(Compiler c, List row, int thaw) {
  match (row) {
    case %(origin ?location):
      return %(origin $(_declaration_location(location, 0)));
    case %(file ?path): return %(file $(Compiler.portable_path(path)));
  }
  return thaw ? c.thaw_declaration_syntax(row)
              : c.freeze_declaration_syntax(row);
}

// A leaf that a List cannot carry as itself becomes a marker row.
static Var _freeze_leaf(Var syntax) {
  if (syntax is void) return %(declaration-void);
  if (syntax is <symbol> && !syntax.symbol())
    return %(declaration-empty-symbol);
  if (syntax.is_atom() && !Atom.bare_spelling(syntax.str()))
    return %(declaration-atom $(syntax.str()));
  if (syntax is not <token>) return syntax;
  Token token = syntax;
  return %(declaration-token $(token.type.str()) $(token.text)
            $(token.line) $(token.col) $(token.len) $(token.pos));
}

static Token _thaw_token(
  Var type, Var text, Var line, Var column, Var length, Var position) {
  Token token = xcalloc(1, sizeof(struct Token));
  *token = (struct Token) {
    .text = text, .type = Symbol.new(type.string()), .line = line,
    .col = column, .len = length, .pos = position};
  return token;
}

static List _declaration_location(List location, int thaw) {
  Array rows = [];
  foreach (List row in location) {
    if (row ~= %(file ?path))
      row = %(file $(_declaration_path(path, thaw)));
    rows.push(row);
  }
  return rows.list_free();
}

module String _declaration_path(String path, int thaw) {
  if (!path || path.startswith("<")) return path;
  return thaw ? Compiler.absolute_home_path(path)
              : Compiler.portable_path(path);
}
