/*  lisp.x -- Lisp sessions, imports and shared libraries */

/* compile-time Lisp

   Each Compiler initializes one Lisp session lazily, as a child of the
   shared library session when one is published. A `$(...)` form at file
   scope evaluates there, or imports a file; in an expression its value
   lifts into syntax. */

/** Opens the unit's compile-time Lisp session when it has none. An
    Each use records the library files as dependencies,
    and a session loads them once. */
void Compiler.ensure_macro_lisp(Compiler c) {
  int loaded = c.macro_lisp != NULL;
  int shared = library_session != NULL, ready = loaded || shared;
  if (!loaded) {
    c.macro_lisp = Lisp.kernel();
    c.macro_lisp.adopt(library_session);
  }
  if (!ready) _install_builtins(c.macro_lisp);
  foreach (String (path, message) in _library_files())
    _eval_library(c, ready, path, message);
  if (!ready) _install_native_operations(c);
}

module Var _eval_string(Compiler c, String source, Token invocation) {
  Var result;
  MetaContext *context = MetaContext.current();
  $let(context.site, invocation)
  $let(context.evaluator, c) {
    /* A compiler operation called from Lisp has already reported its
       failure; wrapping the transfer would report it a second time. */
    try result = c.macro_lisp.eval_string(source);
    catch %(malformed (category ?category)):
      raise %(malformed (category $category));
    catch %(?code *detail):
      c.report_lisp_failure(invocation, cons(code, detail), source);
  }
  return result;
}

module String _lisp_form(Compiler c) {
  Token start = c.token, close = start.group_close();
  if (close.type == <eof>)
    $fail.macros_lisp_unclosed(c, start);
  c.token = close.after_group();
  int begin = start.pos + start.len;
  return %"(${String.new_len(c.text + begin, close.pos - begin)})";
}

/** Evaluates one source Lisp form or imports an .xlisp dependency. */
List Compiler.parse_macro_lisp_top_level(Compiler c) {
  Token invocation = c.token;
  String import_path = NULL;
  int is_import = _import_path(c, import_path);
  String form = _lisp_form(c);
  if (is_import) return _import(c, import_path, invocation);
  /* The shared session evaluated this file's forms once for the target and
     every unit inherits them, so evaluating this one again would only try to
     replace a name an ancestor binds. */
  if (c.inherited_lisp) return NULL;
  c.evaluate_declaration_effect(form, invocation);
  return NULL;
}

/** Loads import dependencies and queues source Lisp effects.
    Declaration projection forces preceding effects exactly once; otherwise
    full parsing keeps the ordinary source-order evaluation. */
void Compiler.parse_macro_lisp_shallow(Compiler c) {
  String requested = NULL;
  if (_import_path(c, requested)) {
    if (!c.source_private) {
      String path =
        Compiler.portable_path(_canonical_path(c, requested, c.token));
      _record_compile_time_effect(
        c, %(compile-time import $path ${_effect_source(c, c.token)}),
        c.token);
    }
    c.parse_macro_lisp_top_level();
    return;
  }
  Token first = c.token;
  String form = _lisp_form(c);
  /* As in full parsing, the shared session already holds an inherited
     import's forms, and running one again would rebind an ancestor's name. */
  if (c.inherited_lisp) return;
  if (!c.source_private)
    _record_compile_time_effect(
      c, %(compile-time lisp $form ${_effect_source(c, first)}), first);
  c.queue_declaration_effect(form, first, c.token);
}

/* An including unit replays a recorded effect in the own text of the file
   that holds its site, which for a module member is the member's file, so
   the site is recorded at its place in that file. */
static List _effect_source(Compiler c, Token site) {
  String file = NULL;
  Token placed = c.source_token(site, file);
  return %(source ${Compiler.portable_path(Path.absolute(file))}
    ${c.freeze_declaration_syntax(placed)});
}

/** Evaluates a queued source Lisp form with its original diagnostic site. */
void Compiler.evaluate_declaration_effect(
  Compiler c, String form, Token invocation) {
  List key = %(${Compiler.portable_path(Path.absolute(c.filename))}
               ${invocation.pos} $form);
  if (key in c.evaluated_effects ||
      (!library_filling && library_imports && key in library_imports)) return;
  $let(c.collect_protocols, 1) {
    c.ensure_macro_lisp();
    _eval_string(c, form, invocation);
  }
  c.evaluated_effects[key] = 1;
  if (library_filling) {
    key.try_own();
    auto(&library_scope) library_imports[key] = 1;
  }
}

/** Parses a compile-time Lisp form in an expression position.
    Macro-definition parsing records a deferred slot; ordinary parsing
    evaluates the form in the translation unit's Lisp session and lifts it.
*/
List Compiler.parse_macro_lisp_expression(Compiler c) {
  Token invocation = c.token;
  String form = _lisp_form(c);
  if (c.macro_holes) return %(expr (<macro-expr>) (macro-slot 0 $form));
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  Var value = _eval_string(c, form, invocation);
  return c.lift_macro_lisp_expression(value, invocation);
}

/** Converts a compile-time Lisp value into a bound expression AST.
    Scalars, immutable values, representable Array/Map roots, compiler-issued
    identifiers, and nonempty code `List`s are accepted; `invocation` locates
    an unsupported result.
*/
List Compiler.lift_macro_lisp_expression(
  Compiler c, Var value, Token invocation) {
  List literal = c.meta_value_expression(NULL, value, invocation);
  if (literal) return literal;
  Var identifier = _sdk_identifier_result(value);
  if (identifier is not void)
    return c.resolve_expression(%(expr () (ident $identifier)), invocation);
  if (value is <list> && !value.is_nil())
    return c.bind_syntax(_helper_result(c, value), <expression>, NULL);
  $fail.macros_lisp_expr(c, invocation, value);
}

/** Binds a compile-time Lisp code `value` returned to a statement at
    `context`. */
List Compiler.bind_macro_lisp_statement(
  Compiler c, List value, Symbol context) {
  value = _helper_result(c, value);
  return _statement_expression(c, value)
    ? %(stmnt ${c.lift_macro_lisp_expression(value, c.token)})
    : c.bind_syntax(value, context, c.return_type);
}

/* The root inside a carrier determines whether the statement discards an
   expression or binds a statement. Ordinary binding consumes the carrier. */
static int _statement_expression(Compiler c, List value) {
  loop match (value) {
    case %((!or "x2c.quoted" src at) ? ?root): value = root;
    case %("x2c.at" ?root): value = root;
    case %(code-value ? ?root ?): value = root;
    case %(macro-invoke ?stored ? ?site):
      return _result_kind(
        _stored_definition(
          c, stored, c.macro_invocation_site(site))) == <expression>;
    case %(expr *): return 1;
    default: return _sdk_identifier_result(value) is not void;
  }
}

static Var _sdk_identifier_result(Var value) {
  match (value)
    case %("x2c.ident" (!is ?spelling type string)): return spelling;
  return value is <list> &&
         Ast.try_binding(value, NULL, NULL) ? value : void;
}

static Var _lisp_import_hook(String path) {
  MetaContext *context = MetaContext.current();
  Compiler c = context.evaluator;
  if (!c) raise %(bad-state (operation "compile-time import"));
  _import(c, path, context.site);
  return %();
}

/* Lisp files use the translation session and ordinary dependency tracking.
   Source declarations travel through #include and the selected interface. */

module List _import(Compiler c, String requested, Token invocation) {
  c.ensure_macro_lisp();
  String path = _canonical_path(c, requested, invocation);
  c.add_translation_dependency(path);
  if (library_filling) library_imports[path] = 1;
  Var dependencies;
  if (c.imports.try_get(path, dependencies)) {
    c.merge_translation_dependencies(dependencies);
    return NULL;
  }
  if (path in c.import_stack)
    $fail.macros_import_cycle(c, invocation, path);
  if (!path.endswith(".xlisp"))
    $fail.macros_import_extension(c, invocation, _path_note(c, path));
  Map before = c.deps.copy();
  String text = _read_source(
    c, path, "cannot open compile-time Lisp import", invocation);
  /* Collection queues the import itself, so only evaluation fills imports.
     A nested import runs while its importing effect is on import_stack. */
  if (c.shallow && !c.import_stack.len() && !library_filling) {
    c.queue_declaration_effect(%"(import ${path.repr()})", invocation, NULL);
    return NULL;
  }
  if (!Compiler.inherits_import(path)) {
    c.import_stack.push(path);
    defer c.import_stack.take_last();
    if (c.collect_protocols) c.evaluate_declaration_effect(text, invocation);
    else c.queue_declaration_effect(text, invocation, invocation);
  }
  Map added = {};
  foreach ((String key, Var value) in c.deps)
    if (before[key] != value) added[key] = value;
  c.imports[path] = added;
  return NULL;
}

static int _import_path(Compiler c, String &?path) {
  Token token = Token.skip_trivia(c.token + 1);
  /* The checked-in bootstrap still tokenizes `import` as an identifier, so
     both spellings of the same word open a compile-time import. */
  if ((token.type != <ident> && token.type != <import>) ||
      token.text != "import")
    return 0;
  token = Token.skip_trivia(token + 1);
  if (token.type != <lit-char*>) return 0;
  if (path) path = String.new_len(token.text + 1, token.len - 2).unescape();
  token = Token.skip_trivia(token + 1);
  return token.type == <)>;
}

/* Cached templates retain global references across symbol-table resets.
   Bind those names in the current global scope without replaying imports. */
module Var _rebind_imported(Compiler c, Var stored) {
  if (stored is not <list>) return stored;
  List definition = stored;
  if (definition.car() != <macrodef>) return definition;
  return _rebind_globals(c, definition);
}

/* Binds each identifier of cached syntax in the current global scope. */
module List _rebind_globals(Compiler c, List syntax) {
  Map replacements = {};
  _reference_bindings(c, syntax, replacements);
  return replacements.len() ? _replace_bindings(syntax, replacements) : syntax;
}

static void _reference_bindings(
  Compiler c, List syntax, Map replacements) {
  match (syntax)
    case %(expr ? ${$source_identifier_content(%(?binding))}): {
      String spelling = NULL;
      if (Ast.try_binding(binding, NULL, spelling))
        replacements[binding] = c.sym.reference_global(%($spelling));
      return;
    }
  foreach (Var child in syntax)
    if (child is <list>) _reference_bindings(c, child, replacements);
}

// source files

/* A relative import names a file beside the source that writes it at
   `site`, or else one under the home's `lib/`. */
static String _canonical_path(Compiler c, String path, Token site) {
  if (!path || path[0] == '/') return c.canonical_path(path);
  String local = %"${_source_dir(c, site)}/$path";
  String system = %"${c.root_dir}/lib/$path";
  int use_system = !c.sources.exists(local) && c.sources.exists(system);
  return c.canonical_path(use_system ? system : local);
}

/* The importing macro file, or the file whose lines hold `site`. */
static String _source_dir(Compiler c, Token site) {
  String filename = c.import_stack.len()
                  ? c.import_stack[-1]
                  : c.token_source(site ? site : c.token, NULL);
  return filename ? Path.dirname(filename) : ".";
}

/** Returns the canonical path of the source `file`. A relative name that
    is not a file resolves against the home. */
String Compiler.source_path(Compiler c, String file) {
  if (!file || file.startswith("<")) return file;
  String rooted = %"${c.root_dir}/$file";
  if (file[0] != '/' && !c.sources.exists(file) && c.sources.exists(rooted))
    file = rooted;
  return c.canonical_path(file);
}

/* An absolute path; the definition keeps the home-portable spelling. */
module String _definition_file(List definition) {
  String file = definition.assoc(<file>);
  return !file || file.startswith("<")
    ? file : Compiler.absolute_home_path(file);
}

/* Reads a compile-time source and records its content hash as a
   dependency. */
static String _read_source(
  Compiler c, String path, String message, Token token) {
  String text = _source_text(c, path, message, token, _path_note(c, path));
  c.deps.merge_translation_dependency(path, "%08x".printf(text.hash()));
  return text;
}

/* An unreadable compile-time source is a located diagnostic. */
static String _source_text(
  Compiler c, String path, String message, Token token, List notes) {
  String text = NULL;
  if (!c.read_source(path, text))
    c.report_error(<macro>, message, token, notes);
  return text;
}

/* the shared library session

   A build target fills one Lisp session with the home's compile-time
   libraries and native operations, freezes it, and makes it the parent of
   every unit's session. */

/* The paths whose top-level Lisp the shared session evaluated while it was
   being filled. A unit that reaches one of these registers the file's macro
   definitions as usual and leaves its Lisp alone: the shared session already
   holds those definitions, and a session cannot replace a name an ancestor
   binds. The key is the path the loader resolved, which is the identity the
   import cache itself uses, so a file that shadows a library name through
   another include path is a different key and evaluates normally. */
static Map library_imports = NULL, static int library_filling = 0;

static Map library_definitions = NULL;

/* The shared session's compile-time-only definitions, which have no
   runtime form in any unit that reads them. */
static Map library_comptime = NULL;

static Lisp library_session = NULL, static Scope library_scope = NULL;

static int library_hooked = 0;

/** Builds the shared compile-time session, leaving it open for the caller to
    fill and then publish. Returns the session, or null when this home cannot
    preload, in which case every unit falls back to its own load, which
    reports against the unit that needed it.

    The session is not published until `Compiler.publish_macro_library`, so a
    unit opened in between still builds its own.
*/
Lisp Compiler.open_macro_library(Compiler c) {
  if (library_session != NULL) return NULL;
  auto(&library_scope) {
    if (!library_hooked) {
      Scope.shutdown_hook(_library_shutdown);
      library_hooked = 1;
    }
    Lisp shared = Lisp.kernel();
    library_imports = {};
    library_definitions = {};
    library_comptime = {};
    $let(c.macro_lisp, shared)
      return _fill_library(c, shared);
  }
}

/* A failure while filling leaves no session, so each unit loads its own. */
static Lisp _fill_library(Compiler c, Lisp shared) {
  library_filling = 1;
  try {
    _install_builtins(shared);
    foreach (String (path, message) in _library_files())
      _eval_library(c, 0, path, message);
    _install_native_operations(c);
  }
  catch %(? *): {
    library_filling = 0;
    return NULL;
  }
  return shared;
}

/* The three libraries' paths in the home and the message each failure
   reports, in the order a session needs them. Every use of a session
   records them, so the paths are joined once per process. */
static List library_files = NULL;

static List _library_files(void) {
  if (library_files) return library_files;
  Array rows = [];
  foreach (String (relative, message) in %(
      ("etc/init.xlisp" "cannot open the compile-time Lisp environment")
      ("etc/lisp-values.xlisp" "cannot open the compile-time value operations")
      ("etc/compiler-sdk.xlisp" "cannot open the compile-time Lisp SDK")))
    rows.push(%(${%"${x2c_get_root()}/$relative"} $message));
  List files = rows.list_free();
  _require_owned(files.try_own());
  return library_files = files;
}

/** Records the compile-time Lisp libraries as dependencies of `c`, as each
    use of its session does. */
void Compiler.add_library_dependencies(Compiler c) {
  foreach (List library in _library_files())
    c.add_translation_dependency(library.car());
}

/* A home Lisp library is evaluated once, when `loaded` is zero, but every use
   records it, so a file's dependencies do not depend on whether an earlier
   file loaded it. */
static void _eval_library(
  Compiler c, int loaded, String path, String message) {
  c.add_translation_dependency(path);
  if (library_filling) library_imports[path] = 1;
  if (loaded || Compiler.inherits_import(path)) return;
  String text = _source_text(c, path, message, c.token, %("path:" $path));
  _eval_string(c, text, c.token);
}

/** Prepares and freezes the shared session and makes it every unit's parent.
    `shared` must be the session `Compiler.open_macro_library` returned.
*/
void Compiler.publish_macro_library(Compiler c, Lisp shared) {
  (void) c;
  library_filling = 0;
  /* A second preload for the same target finds the session published. */
  if (library_session) return;
  if (!shared) {
    library_imports = NULL;
    library_definitions = NULL;
    library_comptime = NULL;
    return;
  }
  shared.freeze();
  library_session = shared;
}

/** Whether the shared session evaluated the file at `path`. A unit that is
    that file, as when a library is linted, inherits its Lisp forms.
*/
int Compiler.inherits_import(String path) {
  /* An empty `Map` is false, so the test is for the allocation. */
  return !library_filling && library_imports != NULL &&
         path in library_imports;
}

/** Records that `name` is compile-time only in `c`, and in the shared
    session when it is being filled. */
void Compiler.record_comptime(Compiler c, String name) {
  c.meta_comptime[name] = 1;
  if (!library_filling || !(void *) library_comptime) return;
  auto(&library_scope) library_comptime[name] = 1;
  name.try_own();
}

/** Marks the shared session's compile-time-only definitions in a fresh
    compiler pass, which reads them without defining them. */
void Compiler.inherit_library_comptime(Compiler c) {
  if (library_filling || library_comptime == NULL) return;
  foreach (String name in library_comptime.keys()) c.meta_comptime[name] = 1;
}

/** Answers whether the shared compile-time session is still being filled,
    before `lib/meta.x` has defined the syntax builders. */
int Compiler.library_filling(void) => library_filling;

/** Returns the published definition keys, or null before publication.
    The borrowed map is the shared session's source identity table.
*/
Map Compiler.shared_definitions(Compiler c) {
  (void) c;
  return library_session ? library_definitions : NULL;
}

/** Answers whether the published shared session already holds the
    definition of `name` from this file, which a unit reading the file again
    leaves alone. */
int Compiler.shares_meta_definition(Compiler c, String name) {
  if (library_filling || library_definitions == NULL || !c.filename) return 0;
  String key = %"${Path.absolute(c.filename)}#$name";
  return key in library_definitions;
}

/* built-in macros

   The compiler carries two macro sources in its own image: the built-in
   macros, and the Lisp binding macros that a `lisp.` name installs on
   first use. A unit parses each source once and keeps its aliases under a
   marker. */

static macro Expression $_embed_lisp_binding_macros() =>
  $(x2c.literal.string (x2c.embed.text "../../etc/lisp-bindings.x"));

static macro Expression $_embed_builtin_macros() =>
  $(x2c.literal.string (x2c.embed.text "../../etc/builtin-macros.x"));

static String lisp_binding_macros = $_embed_lisp_binding_macros();

static String lisp_bindings_marker = NULL;

static String builtin_macros = $_embed_builtin_macros();

static String builtin_macros_marker = NULL;

/** Installs the compiler-shipped source macros into `c` once. */
void Compiler.install_builtin_macros(Compiler c) {
  if (!builtin_macros_marker) builtin_macros_marker = "_x2c.builtin.macros";
  _install_source(
    c, builtin_macros, "<builtin:macros>", builtin_macros_marker, 1);
}

static void _install_source(
  Compiler c, String text, String filename, String marker,
  int builtin) {
  (void) marker.try_own();
  Var installed;
  if (c.macros.try_get(marker, installed)) {
    c.kw_aliases.merge(installed);
    return;
  }
  Compiler child = Compiler.new_shared(c);
  defer c.close_child(child);
  child.filename = filename;
  child.sym = c.sym;
  child.fn_defs = c.fn_defs;
  child.macros = c.macros;
  child.kw_aliases = c.kw_aliases;
  child.builtin_defs = builtin;
  child.tokenize(text);
  Map aliases = _read_definitions(child);
  c.macros[marker] = aliases;
}

/* A shipped source holds only definitions and keyword aliases. */
static Map _read_definitions(Compiler c) {
  Map aliases = {};
  while (c.peek(0) != <eof>) {
    if (c.keyword_form_is_definition()) _record_alias(c, aliases);
    else if (c.macro_form_is_definition()) c.parse_macro_definition();
    else
      $fail.macros_builtin_form(c, c.token);
  }
  return aliases;
}

/* Every `lisp.` lookup records the bindings file, which is installed only
   when `install` is nonzero and the bindings are not yet installed. */
module void _use_lisp_bindings(Compiler c, int install) {
  if (!lisp_bindings_marker) lisp_bindings_marker = "_x2c.lisp.bindings";
  int loaded =
    !install || lisp_bindings_marker in c.macros;
  if (!loaded) c.ensure_macro_lisp();
  _eval_library(
    c, loaded, %"${c.root_dir}/etc/lisp-bindings.xlisp",
    "cannot open the native Lisp macro support");
  if (loaded) return;
  // Binding groups start with the macro state that installs their macros.
  c.binding_rows = c.binding_sealed = NULL;
  _install_source(
    c,
    lisp_binding_macros, "<builtin:lisp-bindings>", lisp_bindings_marker, 0);
}

/* native operations

   Native operations read the active expansion's context, not the session
   that owns their callable, so the shared parent owns them once. */

static void _install_native_operations(Compiler c) {
  _bind_primitives(c.macro_lisp);
  foreach ((String name, Func function) in Compiler.compiler_targets()) {
    c.macro_lisp.set_global(name, function);
    Compiler.bind_meta_operation(c.macro_lisp, name, function);
  }
}

/* The internal primitives, which carry the `_x2c.` prefix, come before the
   meta surface is parsed. */
static void _bind_primitives(Lisp lisp) {
  $lisp.bind(lisp, "_x2c.import-hook", _lisp_import_hook);
  Compiler.bind_sdk_primitives(lisp);
}

/* Binds the built-in macro algorithms into `lisp` under the names its
   compile-time Lisp calls. */
static void _install_builtins(Lisp lisp) {
  foreach ((String name, Func function) in Compiler.builtin_targets())
    lisp.set_global(name, function);
}

/** Binds `function`, the operation `lib/meta.x` declares as `name`, under
    its Lisp name in `lisp`. A definition the compile-time libraries
    already give that name wins, because it adapts the arguments.
*/
void Compiler.bind_meta_operation(Lisp lisp, String name, Var function) {
  String dotted = _meta_lisp_name(name);
  Var bound;
  if (!lisp.try_get(dotted, bound)) lisp.set_global(dotted, function);
}

/* The Lisp name of the operation `lib/meta.x` declares as `name`: a method
   `Owner_member` is `Owner.member`, as the Lisp value operations spell
   theirs, and in an `x2c_` helper each `_` becomes `.`. */
static String _meta_lisp_name(String name) =>
  name.startswith("x2c_") ? name.replace("_", ".")
                          : %"${name[:4]}.${name[5:]}";

// lifecycle

static void _library_shutdown(void) {
  Lisp.destroy(library_session);
  library_session = NULL;
  library_imports = NULL;
  library_definitions = NULL;
  library_comptime = NULL;
  library_scope.destroy();
  library_scope = NULL;
}

/** Ends the shared compile-time library before its build-target Context is
    reclaimed. A later target creates a fresh session in its own Context. */
void Compiler.reset_macro_library(void) {
  _library_shutdown();
  library_filling = 0;
}
