/*  dependencies.x -- place declarations and delayed function bodies */

/* forward declarations

   Each node follows the declarations it needs: the static declarations it
   references and prototypes of the global functions nothing declares. */

/* `declared` holds every key and forwarded declaration a reader at the
   current position can already see, `statics` each static declaration by
   binding and spelling, and `out` the ordered source. */
static typedef struct Forward {
  Compiler c, Map declared, statics, Array out;
} Forward;

// prototypes and bodies

/* A source starts with only its own header guarded and can use the complete
   includes it emits. A header can be entered through a cycle with any
   enclosing header guarded, so its inline bodies still need forwards. */
module List _forward_declarations(
  Compiler c, List source, int source_includes) {
  Forward f = {
    .c = c, .declared = {}, .statics = {}, .out = []};
  if (c.runtime_inc && source_includes)
    c.runtime_function_declarations(f.declared);
  _source_declarations(source, f.statics);
  foreach (List node in source) {
    node = _inline_prototype(c, node);
    if (node.car() == <typedef> && node in f.declared) continue;
    if (source_includes && node ~= %(preproc ?(String text))) {
      int angle = 0;
      String target = Compiler.preproc_include_target(text, angle);
      if (target)
        c.include_function_declarations(target, angle, f.declared);
    }
    _collect_declared(node, f.declared);
    _dependencies(f, node);
    f.out.push(node);
  }
  return f.out.list_free();
}

/* Native directives and initializer inputs keep their source order.
   Public inline definitions keep their macro state at their positions.
   Ordinary function bodies follow the file's declarations and directives,
   preserving their existing access to later private includes and macros,
   but precede a later `#undef` and any conditional group containing one,
   as C requires of a body that uses the macro. Source initializer helpers
   stay at their capture positions. */
module List _move_bodies(List source, Map inline_bodies) {
  Array out = [], bodies = auto [];
  Map undefs = auto _undef_positions(source), List arms = NULL;
  int position = 0;
  foreach (List node in source) {
    if (position in undefs) _place_bodies(out, bodies, arms);
    position++;
    match (node)
      case %(function ?type (!set ?signature (bind ?binding *)) ?): {
        if (binding in inline_bodies) {
          out.push(node);
          continue;
        }
        bodies.push($(node, @arms));
        if (type.list().type().is_static())
          out.push(_prototype(type, signature));
        continue;
      }
    if (node ~= %(preproc ?content))
      arms = Compiler.preproc_track_arms(arms, content);
    out.push(node);
  }
  _place_bodies(out, bodies, NULL);
  return out.list_free();
}

/* The positions in `source` of each `#undef` and of the directive opening
   each conditional group that contains one. */
static Map _undef_positions(List source) {
  Map positions = {};
  Array open = auto [], int position = 0;
  foreach (List node in source) {
    if (node ~= %(preproc ?(String content))) {
      Symbol kind = Compiler.preproc_conditional_kind(content);
      if (kind == <open>) open.push(position);
      else if (kind == <close> && open.len()) open.take_last();
      else if (Compiler.preproc_directive(content).startswith("undef")) {
        positions[position] = 1;
        foreach (int group in open) positions[group] = 1;
      }
    }
    position++;
  }
  return positions;
}

/* Moves to `out` each pending body written under the open `arms`,
   reopening the groups it was written in beyond those. A body from another
   arm stays pending. */
static void _place_bodies(Array out, Array bodies, List arms) {
  size_t kept = 0, unsigned open = arms.len();
  foreach (List pending in bodies) {
    List written = pending.cdr();
    if (written.tail(open) != arms) {
      bodies[kept++] = pending;
      continue;
    }
    List reopened = written.head(written.len() - open);
    List statement = $(pending.car());
    foreach (List item in Compiler.preproc_within_arms(reopened, statement))
      out.push(item);
  }
  bodies.resize(kept);
}

// declared names

/* Records source declarations by binding: every defined function's
   prototype, also under its native spelling, static objects without their
   initializers, and typedefs, also under their spellings. */
static void _source_declarations(Var value, Map statics) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function ?type (!set ?signature (bind ?binding ?)) ?):
      _set_function(statics, binding, _prototype(type, signature));
    case %(declare ?base (bindings *declarators)):
      if (base.list().type().is_static())
        foreach (List declarator in declarators)
          _set_static(statics, base, declarator);
    case %(typedef ? (bindings *declarators)):
      foreach (List declarator in declarators)
        _set_typedef(statics, _declaration_binding(declarator), node);
    default: foreach (Var child in node) _source_declarations(child, statics);
  }
}

static void _set_static(Map statics, List base, List declarator) {
  List binding = _declaration_binding(declarator);
  if (!binding) return;
  if (declarator ~= %(op = ?target ?)) declarator = target;
  statics[binding] = %(declare $base (bindings $declarator));
}

/* Pending sibling suffixes stay off the C stack. Only declaration
   dependencies recurse; ordinary expressions share the same worklist.
   Inputs are source Lists or declarations produced for statics. */
static void _dependencies(Forward &f, List value) {
  if (!value) return;
  Array resume = auto [];
  for (List node = value; node; node = _next(node, resume)) _visit(f, node);
}

static void _visit(Forward &f, List node) {
  match (node) {
    case %(!set ?binding (binding ? ?)): _binding(f, binding);
    case %(call ?(String name) *): _declaration(f, %(native $name));
    case %((!or expr declare typedef function cast param) ?type *):
      if (type is <list>) _types(f, type);
  }
}

/* A binding needs its static declaration, found by binding or by native
   spelling, or else the prototype of the global function it names. */
static void _binding(Forward &f, List binding) {
  String spelling = Ast.binding_spelling(binding);
  List native = %(native $spelling);
  if (binding in f.statics) _declaration(f, binding);
  else if (native in f.statics) _declaration(f, native);
  else _global(f, binding, spelling);
}

/* A helper group omits its provider's runtime header, so forward the
   ordinary adapters its typed bodies call. Native aliases still come from
   their defining headers; a host function-like macro cannot be prototyped. */
static void _global(Forward &f, List binding, String spelling) {
  Compiler c = f.c, Type type = NULL;
  List global = spelling ? c.sym.resolve_global($(spelling), type) : NULL;
  if (!global || !global.equal(binding) || !type.is_function()) return;
  if (global in f.declared || %(native $spelling) in f.declared) return;
  if (c.sym.get($("generated-protocol", spelling)) &&
      (!c.meta_build || c.native_protocol_alias(spelling))) return;
  f.declared[global] = 1;
  _types(f, type);
  List declaration = Ast.prototype_declarator(type.declaration_ast(global));
  f.out.push(_inline_prototype(c, declaration));
}

/* Emits prerequisites before forwarding the symbol under `key` once. */
static void _declaration(Forward &f, Var key) {
  Var declaration;
  if (key in f.declared || !f.statics.try_get(key, declaration)) return;
  f.declared[declaration] = 1;
  _collect_declared(declaration, f.declared);
  _dependencies(f, declaration);
  f.out.push(declaration);
}

/* Source parameters and fields are visited as declarations. Only semantic
   function modifiers nest Types; tags and array bounds are not type names. */
static void _types(Forward &f, Type type) {
  Type base = type.base_type();
  if (base.is_bare_typedef_name()) _declaration(f, base.car());
  foreach (Var modifier in type)
    if (modifier ~= %(func (*parameters)))
      foreach (Type parameter in parameters) _types(f, parameter);
}

/* Every public inline definition has C internal linkage, including the
   authored prototypes in a file that reaches its defining source. */
static List _inline_prototype(Compiler c, List node) {
  match (node) {
    case %(declare ?type (!set ?declarator
             (bind ?binding ((fnmod *) *)))):
      if (!type.type().is_static() && _inline_binding(c, binding))
        return %(declare (static @type) $declarator);
    case %(declare ?type (bindings *declarators))
      if (!type.type().is_static()): {
      Array rows = [], int changed = 0;
      foreach (List declarator in declarators) {
        List base = type;
        if (declarator ~= %(bind ?binding ((fnmod *) *)) &&
            _inline_binding(c, binding)) {
          base = %(static @type);
          changed = 1;
        }
        rows.push(%(declare $base (bindings $declarator)));
      }
      if (changed) return rows.list_free();
      rows.free();
    }
  }
  return node;
}

static int _inline_binding(Compiler c, List binding) =>
  c.sym.get($("function-inline", Ast.binding_spelling(binding))) != NULL;



/* Adds to `declared` each binding `value` declares, with each function's
   native spelling and each typedef's spelling. */
static void _collect_declared(Var value, Map declared) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    case %(function ? (!set ?declarator (bind (binding ? ?) ?)) ?):
      _set_function(declared, _declaration_binding(declarator), 1);
    case %(declare ? (!set ?declarator (bind (binding ? ?) ?))):
      if (node.type_from_ast().is_function())
        _set_function(declared, _declaration_binding(declarator), 1);
    case %(declare (*) (bindings *declarators)):
      foreach (List declarator in declarators) {
        List binding = _declaration_binding(declarator);
        if (binding) declared[binding] = 1;
      }
    case %(typedef (*) (bindings *declarators)):
      foreach (List declarator in declarators)
        _set_typedef(declared, _declaration_binding(declarator), 1);
    default: foreach (Var child in node) _collect_declared(child, declared);
  }
}

/* A function is found by its binding and by its native spelling. */
static void _set_function(Map names, List binding, Var value) {
  names[binding] = value;
  names[%(native $(Ast.binding_spelling(binding)))] = value;
}

/* A typedef is found by its binding and by its spelling. */
static void _set_typedef(Map names, List binding, Var value) {
  if (!binding) return;
  names[binding] = value;
  names[Ast.binding_spelling(binding)] = value;
}

module List _declaration_binding(List declarator) {
  match (declarator)
    case $Ast.declarator_pattern(%((!set ?binding (binding ? ?)) ?)):
      return binding;
  return NULL;
}

/* The next nonempty List after `node` in a preorder walk, or NULL at the
   end. `resume` holds the sibling suffixes still to visit. */
static List _next(List node, Array resume) {
  List rest = node;
  for (;;) {
    while (!rest) {
      if (!resume.len()) return NULL;
      rest = resume.take_last();
    }
    Var child = rest.car();
    rest = rest.cdr();
    if (child is <list> && !child.is_nil()) {
      if (rest) resume.push(rest);
      return child;
    }
  }
}
