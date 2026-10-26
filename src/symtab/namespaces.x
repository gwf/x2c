/*  namespaces.x -- symbol namespaces */

// privacy boundaries

/** Records the visibility of one parsed top-level declaration.
    Lexical privacy and static storage mark bindings in `Sym`; typedef rows are
    retained for placing generated protocol declarations at the same boundary.
*/
void Compiler.record_declaration_visibility(Compiler c, List declaration) {
  int private = c.source_private > 0;
  match (declaration) {
    case %(seq *rows):
      foreach (List row in rows) c.record_declaration_visibility(row);
    case %(function ?type (bind ?identity *) *): {
      if (!private && !type.type().is_static()) return;
      String name = Ast.binding_spelling(identity);
      if (name) c.sym.mark_static($(name));
    }
    case %(
      (!or ?kind typedef declare) ?type (bindings *rows)
    ): {
      int mark = private || type.type().is_static();
      if (mark) {
        Type base = type.type().base_type();
        match (base)
          case %((!or ?tag struct union enum) ?name *body):
            if (name && (body || !rows || rows === %((bind () ()))))
              c.sym.mark_static($(tag, name));
      }
      _record_rows_visibility(c, declaration, kind, private, mark, rows);
      if (kind == <declare> && !mark)
        _record_native_objects(c, type, rows);
    }
  }
}

/* A public object definition belongs to this source, including a tentative
   definition. An extern declaration only names its native supplier. */
static void _record_native_objects(
  Compiler c, Type spec, List rows) {
  if (!c.shallow || c.source_private < 0 ||
      !Path.is_x2c_source(c.filename)) return;
  String path = Compiler.portable_path(c.canonical_path(c.filename));
  foreach (List row in rows) {
    List declarator = row;
    match (row) case %(op = ?bound ?): declarator = bound;
    if (spec.is_extern() && declarator == row) continue;
    match (declarator) case %(bind ?binding ?): {
      List declaration = %(declare $spec (bindings $declarator));
      if (declaration.type_from_ast().is_function()) continue;
      String name = Ast.binding_spelling(binding);
      if (!name || !name.len()) continue;
      c.sym.set(
        %("source-node" (native-object $path $(c.token.pos) $name)),
        %(native-object $name));
    }
  }
}

static void _record_rows_visibility(
  Compiler c, List declaration, Symbol kind, int private, int mark,
  List rows) {
  foreach (List row in rows)
    match (row) case $source_declarator_row(%(?identity *)):
      _record_binding_visibility(
        c, declaration, kind, private, mark, identity);
}

static void _record_binding_visibility(
  Compiler c, List declaration, Symbol kind, int private, int mark,
  List identity) {
  String name = Ast.binding_spelling(identity);
  if (kind == <typedef> && name) {
    c.record_source_typedef(name, declaration, mark);
    if (mark) c.sym.mark_static(%(typedef $name));
  }
  if (mark && name) c.sym.mark_static($(name));
}

// module and package names

/** Returns the prefix that a file-scope declaration of `type` takes in the
    current module file, or NULL. A static takes it, and so does each
    declaration of a `static typedef` or `static class`; a `module`
    declaration and every declaration outside a module unit do not. */
String Compiler.private_prefix(Compiler c, Type type) {
  if (c.module_declaration ||
      !(c.source_private > 0 || (type && type.is_static())))
    return NULL;
  return c.file_prefix();
}

/** Returns `name` spelled in a declaration's scope: with `prefix`, a file
    prefix, or else in the current package. A name the compiler derived
    from a spelling this unit already prefixed, such as `second__Node_new`
    or `Var_second__node` for a private class `second__Node`, stays
    unchanged; it is unique in the unit, so code generated outside the file
    still reaches it. Ordinary source spellings always take their file's
    prefix, even when they resemble another generated spelling. */
String Compiler.scoped_spelling(Compiler c, String prefix, String name) {
  if (!prefix) return c.package_spelling(name);
  if (!name || (c.macro_stack && _derived_spelling(c.sym, name)))
    return name;
  return %"$prefix$name";
}

/** Returns `name` as `scoped_spelling` does for a declaration, recording
    a spelling that took `prefix` so the names the compiler derives from
    it are known to hold their prefix already. A replayed collected
    declaration was spelled when it was collected, so its names are final
    and are recorded as they are. */
String Compiler.declared_spelling(Compiler c, String prefix, String name) {
  String spelled =
    c.replaying_declaration ? name : c.scoped_spelling(prefix, name);
  if (!prefix || (spelled == name && !c.replaying_declaration))
    return spelled;
  String bare = spelled.startswith(prefix) ? spelled[prefix.len():] : name;
  c.sym.put(c.sym.prefixed, spelled, bare);
  c.sym.put(c.sym.prefixed, spelled.lower(), bare.lower());
  return spelled;
}

/* `name` is a recorded prefixed spelling, one followed by `_` and more,
   or `Var_` and one in lower case. */
static int _derived_spelling(Sym s, String name) {
  if (!s.prefixed.len()) return 0;
  if (name in s.prefixed) return 1;
  if (name.startswith("Var_") && name[4:] in s.prefixed) return 1;
  for (int at = 1; at < name.len() - 1; at++)
    if (name[at] == '_' && name[:at] in s.prefixed) return 1;
  return 0;
}

/** Returns the static prefix of each file of the module unit. */
List Compiler.file_prefixes(Compiler c) {
  Array prefixes = [];
  if (c.line_markers)
    foreach (List row in c.line_markers)
      match (row) case %(? ? ? ? ? ? ?(String prefix)):
        if (!(prefix in prefixes)) prefixes.push(prefix);
  return prefixes.list_free();
}

/** Returns the source name of a spelling this unit gave a file prefix, or
    `name`. Var tags and descriptor names use that short name. */
String Compiler.unprefixed(Compiler c, String name) {
  Var bare;
  return c.sym.prefixed.try_get(name, bare) ? bare : name;
}

/** Returns a name in the current package namespace, preserving prefixes.

    Idempotence lets parsing and declaration rewrites share this operation.
*/
String Compiler.package_spelling(Compiler c, String name) {
  if (!c.package || !name) return name;
  String prefix = %"$(c.package)__";
  return name.startswith(prefix) ? name : %"$prefix$name";
}

/** Registers one local package alias.

    Shallow collection and full parsing both see an import, so repeating the
    same package and alias is a no-op. Another binding of the local spelling
    is a parse error.
*/
void Compiler.register_package_alias(
  Compiler c, String name, String alias, Token token) {
  Var bound = c.package_aliases[alias];
  if (bound is not void && bound == name) return;
  _check_package_binding(c, "alias", alias, token);
  c.package_aliases[alias] = name;
}

/** Registers one package member under a bare local spelling.

    The package member must already exist in the symbol table. Repeating the
    same binding is a no-op; any conflicting local binding is an error.
*/
void Compiler.register_package_member(
  Compiler c, String name, String member, String local,
  Token member_token, Token local_token) {
  /* Keep the source spellings so a later conflict says `geo.Vec` rather
     than naming the package-prefixed C symbol. */
  List binding = $(name, member);
  Var bound = c.package_members[local];
  if (bound is not void && bound.list() === binding) return;
  String spelling = %"$(name)__$member";
  if (!c.sym.get_exact($(spelling)))
    $fail.parse_package_member(c, member_token, name, member);
  _check_package_binding(c, "name", local, local_token);
  c.package_members[local] = binding;
}

/* An alias and a `with` name each claim one local spelling. Rebinding that
   spelling, or taking one a declaration already uses, is the same conflict.
   Both messages name what the developer wrote. */
static void _check_package_binding(
  Compiler c, String kind, String local, Token token) {
  Var alias = c.package_aliases[local];
  Var member = c.package_members[local];
  String bound = alias is void ? NULL : alias;
  if (!bound && member is not void) {
    List pair = member;
    (String package, String member_name) = pair;
    bound = %"$package.$member_name";
  }
  if (bound)
    $fail.symbols_package_bound(c, token, kind, local, bound);
  if (c.sym.get_exact($(local)))
    $fail.symbols_package_collision(c, token, kind, local);
}

/** Returns a visible `with` name's package-prefixed spelling, or `NULL`.

    An ordinary declaration of the local spelling shadows the `with` name.
*/
String Compiler.package_member_spelling(Compiler c, String name) {
  if (!c.package_members.len()) return NULL;
  Var bound = c.package_members[name];
  if (bound is void || c.sym.get_exact($(name))) return NULL;
  List pair = bound;
  (String package, String member_name) = pair;
  return %"$(package)__$member_name";
}

/** Returns sorted imported packages that publish `name`.

    Package-owned methods use `<package>__<Type>_<member>` internally while
    consumers retain the spelling from the package header. Sorting keeps
    ambiguity diagnostics deterministic.
*/
List Compiler.imported_providers(Compiler c, String name) {
  if (!name || !c.package_roots.len()) return NULL;
  List packages = %();
  foreach (String (package, root) in c.package_roots) {
    if (c.sym.get_exact(%("$(package)__$name")))
      packages = cons(package, packages);
  }
  return packages.sort();
}

/** Returns an unambiguous imported spelling for `name`, or `NULL`. */
String Compiler.imported_spelling(Compiler c, String name) {
  List packages = c.imported_providers(name);
  if (!packages || packages.cdr()) return NULL;
  return %"$(packages.car())__$name";
}
