/*  functions.x -- native meta functions

    Copyright (c) 2026 Gary William Flake.
*/

/* meta functions

   A bodied `meta` function runs at compile time through a stub in the
   unit's session. The stub calls the function's compiled copy in the
   project's helper, or in the REPL the group's native code. */

/** Installs a bodied `meta` function. The project meta build compiled it
    into the project's helper, so the session holds a stub that calls it
    there; the REPL's stub stages the session's group at the first call
    instead, and the project meta build's own parse only groups it. A
    function whose body reaches a compiler operation, a template, or a
    compile-time-only function has no runtime form. A body that lets its
    own storage outlive a call is rejected where the storage leaves.
*/
void Compiler.install_meta_function(Compiler c, List fn, Token marker) {
  c.ensure_macro_lisp();
  c.check_meta_regions(fn);
  match (fn)
    case %(function ? (bind (binding ? ?(String name)) *) ?): {
      c.native_meta.del(name);
      c.meta_group_bound.del(%"<unbound $name>");
      if (c.meta_reaches_compile_time(fn)) c.record_comptime(name);
      if (c.macro_holes) return;
      c.group_meta_function(fn);
      if (c.meta_calls_wait()) return;
      if (!Compiler.library_filling() && !c.shares_meta_definition(name))
        _install_stub(c, name, ((List) c.meta_group[-1]).last(), NULL, marker);
    }
}

/** Installs the stub of the bodied `meta` definition `declaration` whose
    body collection skips, so a file-scope constant after it can call it in
    the project's helper. The full parse installs it again. The
    compiler's linked copy answers while its source hashes agree; otherwise
    the definition replaces an earlier binding with a helper stub. A group
    that stages in process waits for the full parse. */
void Compiler.install_collected_meta_function(
  Compiler c, List declaration, Token marker) {
  if (c.signature_only || c.macro_holes) return;
  if (c.source_private < 0 && _install_included_meta(c, declaration, marker))
    return;
  /* The definition depends on the compile-time libraries even while the
     shared session that will answer it is being filled. */
  if (Compiler.library_filling()) {
    c.add_library_dependencies();
    return;
  }
  String name = _native_meta_name(c, declaration, marker);
  if (c.shares_meta_definition(name)) return;
  c.ensure_macro_lisp();
  Map linked = _linked_module();
  if (c.groups_meta() && !(name in linked)) return;
  _install_stub(
    c, name, declaration.type_from_ast().canonicalize(), NULL, marker);
}

/* Host-preprocessed text holds each included file's definitions where the
   include was. A public one binds as that include advertises it, with its
   file as the provider whose helper table runs it, and reports that it did.
   The unit's own and a static one bind as their file's collection binds
   them, since a call runs in the table of the file that wrote it. */
static int _install_included_meta(
  Compiler c, List declaration, Token marker) {
  Type type = declaration.type_from_ast().canonicalize();
  String file = c.canonical_path(c.token_source(marker, NULL));
  if (type.is_static() || file == c.canonical_path(c.filename)) return 0;
  String name = _native_meta_name(c, declaration, marker);
  c.install_project_meta_effect(
    %(project-meta $name ${c.func_signature(type)}
      ${Compiler.portable_path(file)}));
  return 1;
}

/* A host binding remains in this session; installation failures report at
   the declaration marker. */
static void _install_stub(
  Compiler c, String name, Type type, String provider, Token marker) {
  String context = %"$name\n${provider ? provider : ""}";
  try c.macro_lisp.bind(
    name,
    Func.new_context(
      _meta_stub, c.func_signature(type),
      (char *) context, context.len() + 1));
  catch %(?code *detail): {
    List cause = cons(code, detail);
    $fail.meta_native_function_install(c, marker, cause);
  }
}

/* Adapts a call of a bodied `meta` function's session binding, whose
   context holds the function's name, to a call in the project's helper,
   or in the REPL to a call of the group's native code, which the first
   call stages and binds under the name. */
static Var _meta_stub(Func function, const FuncArg *argv) {
  Array values = _stub_arguments(function, argv);
  String context = String.new((const char *) Func.context(function));
  int split = context.find("\n");
  String name = context[:split], provider = context[split + 1:];
  Compiler c = Compiler.expanding();
  if (!c) $fail.meta_native_outside_compilation(name);
  Token site = MetaContext.current().site;
  if (!site) site = c.token;
  if (!provider.len()) {
    Map linked = _linked_module();
    if (name in linked) {
      if (c.shallow && !_linked_copy(c, name, linked))
        c.complete_meta_hashes();
      if (_linked_copy(c, name, linked))
        return c.macro_lisp.apply(linked[name], values.list_free());
    }
  }
  if (c.meta_calls_wait()) raise %(meta-later (name $name));
  List rows = _subject_rows(c, values);
  Var previous = Macro.subject();
  Macro.use_subject(rows);
  defer Macro.use_subject(previous);
  if (c.meta_helper || !c.groups_meta())
    return c.meta_helper_call(name, site, values.list_free(), provider);
  c.bind_meta_group(name, site);
  Var bound;
  c.macro_lisp.try_get(name, bound);
  return c.macro_lisp.apply(bound, values.list_free());
}

static Array _stub_arguments(Func function, const FuncArg *argv) {
  List parameters = Func.signature(function).car().list().cadr();
  if (parameters == %((void))) parameters = NULL;
  Array values = [];
  int count = parameters.len();
  for (int i = 0; i < count; i++) values.push(argv[i].data.value);
  return values;
}

/** Tests a registered macro with the candidate's global and source
    bindings. A pattern derived without them reads none. */
int Compiler.matches_macro(Compiler c, MacroMatcher &matcher, List code) {
  if (matcher.pattern) return matcher.matches(code);
  Var previous = Macro.subject();
  Array arguments = auto [code];
  Macro.use_subject(_subject_rows(c, arguments));
  defer Macro.use_subject(previous);
  return matcher.matches(code);
}

/* The caller's global bindings and source-name projections for bindings in
   the arguments, carried through the existing helper subject context. */
static List _subject_rows(Compiler c, Array values) {
  Map globals = {}, source_names = {};
  foreach (Var value in values)
    _subject_globals(c, value, globals, source_names);
  Array rows = [];
  foreach ((String spelling, List binding) in globals)
    rows.push(%($spelling $binding));
  foreach ((List binding, String spelling) in source_names)
    rows.push(%(source-spelling $binding $spelling));
  return rows.list_free();
}

/* Records global identities and source spellings from argument syntax. */
static void _subject_globals(
  Compiler c, Var value, Map globals, Map source_names) {
  List node;
  $ast.walk(value, node) {
    String spelling = NULL;
    if (Ast.try_binding(node, NULL, spelling)) {
      Var source;
      if (c.semantic_binding_facts().try_get(%(source-spelling $node), source))
        source_names[node] = source;
      List global = c.sym.resolve_global(%($spelling), NULL);
      if (global && List.compare(global, node) == 0) globals[spelling] = node;
      continue;
    }
  }
}

/** Applies a contextual `meta` marker to one initialized file-static value.
    The unit's staged `meta` group holds the compile-time instance, which
    its module initializes for each unit. */
void Compiler.install_meta_declaration(
  Compiler c, List declaration, Token marker) {
  match (declaration) {
    case %(declare ?spec
           (bindings
             (op = (bind (binding ? ?(String name)) *) ?))): {
      if (!spec.type().is_static())
        $fail.meta_native_meta_storage(c, marker, name);
      if (c.groups_meta()) c.meta_group.push(%(static $declaration));
      return;
    }
  }
  $fail.meta_native_meta_decl(c, marker);
}

/** Records the provider of a public bodied meta function in its interface.
    The provider owns both its native body and its compile-time state. */
void Compiler.record_project_meta_effect(
  Compiler c, List declaration, Token marker) {
  if (c.source_private < 0) return;
  Type type = declaration.type_from_ast().canonicalize();
  if (type.is_static()) return;
  String path = Compiler.portable_path(Path.resolved_absolute(c.filename));
  String name = _native_meta_name(c, declaration, marker);
  if (%(function $name) in c.sym.file_statics()) return;
  c.sym.set(
    %("source-node" (declaration $path ${marker.pos})),
    %(project-meta $name ${c.func_signature(type)} $path));
}

/** Installs an included meta function's evaluator advertisement. */
void Compiler.install_project_meta_effect(Compiler c, List row) {
  match (row) case %(project-meta ?name ?signature ?provider): {
    c.project_meta[name] = %($signature $provider);
    c.native_meta.del(name);
    c.meta_group_bound.del(%"<unbound $name>");
    if (!c.meta_calls_wait()) {
      c.ensure_macro_lisp();
      _bind_advertised_meta(c, name, 1);
    }
  }
}

/* Binds an advertised meta function and reports whether it was found.
   Its provider supplies the helper table and private helpers. */
module int _bind_project_meta(Compiler c, String name) {
  if (!c.project_meta.len())
    c.install_native_meta_effects(c.sym.unit_symbols());
  return _bind_advertised_meta(c, name, 0);
}

/* An include installs its provider at that position. Later lookups keep
   any Lisp definition the unit installs after the include. */
static int _bind_advertised_meta(Compiler c, String name, int install) {
  Var target;
  if (!c.project_meta.try_get(name, target)) return 0;
  if (c.meta_calls_wait()) return 0;
  Var bound;
  if (!install && c.macro_lisp.try_get(name, bound)) return 1;
  Var (signature, provider) = target;
  Var function = _linked_target(c, name, signature, provider);
  if (function is not <func>)
    _install_stub(c, name, signature, provider, NULL);
  else if (!c.macro_lisp.try_get(name, bound) || !bound.equal(function))
    c.macro_lisp.set_global(name, function);
  return 1;
}
