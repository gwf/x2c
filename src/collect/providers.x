/*  providers.x -- source collection providers

    Copyright (c) 2026 Gary William Flake.
*/

/** Reports whether a linked provider and the files it read are unchanged.
    The linked inventory retains the ordinary collector's dependency proof. */
int Compiler.linked_meta_provider_current(Compiler c, String path) {
  String canonical = _canonical_path(path);
  _process_cache();
  Var current;
  if (linked_providers.try_get(canonical, current)) return current;
  Map seen = {};
  int valid = _linked_provider_current(c, canonical, seen);
  if (valid)
    foreach (String dependency in seen.keys()) {
      _retain(dependency);
      linked_providers[dependency] = 1;
    }
  else {
    _retain(canonical);
    linked_providers[canonical] = 0;
  }
  return valid;
}

static int _linked_provider_current(
  Compiler c, String path, Map seen) {
  Var current;
  if (linked_providers.try_get(path, current)) return current;
  if (path in seen) return 1;
  seen[path] = 1;
  List source =
    Compiler.linked_meta_provider_source(Compiler.portable_path(path));
  match (source)
    case %(source ?hash ?(List dependencies) *): {
      if (!_hash_matches(c, path, hash)) return 0;
      Map found = _read_dependencies(c, dependencies);
      if (found == NULL) return 0;
      // Member content was hashed above; only included units own proofs.
      foreach ((String dependency, Var expected) in found)
        if (Path.is_x2c_source(dependency) && expected is <string> &&
            !String.startswith(expected, "search:") &&
            Compiler.linked_meta_provider_source(
              Compiler.portable_path(dependency)) &&
            !_linked_provider_current(c, dependency, seen)) return 0;
      return 1;
    }
  return 0;
}

/** Reports whether a provider's linked definition hashes still match.
    Changes outside definitions do not require a project helper. */
int Compiler.linked_meta_definitions_current(Compiler c, String path) {
  if (c.linked_meta_provider_current(path)) return 1;
  String canonical = _canonical_path(path);
  String provider = Compiler.portable_path(canonical);
  List source = Compiler.linked_meta_provider_source(provider);
  match (source) case %(source ?hash *):
    if (_hash_matches(c, canonical, hash)) return 1;
  match (source) case %(source ? ? ?(String definitions)): {
    List entry = _meta_provider_entry(c, canonical);
    if (!entry) return 0;
    foreach (Var part in entry.car()) {
      if (part is not <map>) continue;
      Var value;
      if (!part.map().try_get(
        %("source-node" (meta-hashes $provider 0)), value)) continue;
      Map hashes = value.list().caddr();
      return _content_hash(_stored_meta_hashes(hashes)) == definitions;
    }
  }
  return 0;
}

/* Metadata lookahead reads declarations and hashes without source effects. */
static List _meta_provider_entry(Compiler c, String canonical) {
  List entry = _entry(c, canonical);
  if (!entry) {
    DiagnosticsHold hold = c.diagnostics.hold();
    with (c.meta_build = 1,
          c.signature_only = 1,
          c.recovery_depth = c.recovery_depth + 1) {
      try entry = _walk_cold(c, canonical, canonical, {}, {});
      catch %(malformed *): entry = NULL;
    }
    c.diagnostics.release(hold, 0);
  }
  return entry;
}

/** Completes a linked function's own source hashes before a shallow call.
    A lookahead entry never replaces the file's ordinary contribution. */
void Compiler.complete_meta_hashes(Compiler c) {
  List entry = _meta_provider_entry(c, _canonical_path(c.filename));
  if (entry)
    foreach (Var part in entry.car()) {
      if (part is not <map>) continue;
      foreach (Var value in part.map())
        match (value) case %(meta-hashes ? ?(Map hashes)):
          c.meta_hashes.merge(hashes);
    }
  Compiler.forget_provisional_entries();
}

/** Returns the shared function hashes of an advertised meta provider. */
Map Compiler.meta_provider_hashes(Compiler c, String provider) =>
  c.sym.get_exact(%("source-node" (meta-hashes $provider 0))).caddr();

/** Retains source proofs and one definition hash per linked provider. */
void Compiler.add_linked_meta_provider_hashes(Compiler c, Map rows) {
  foreach (String path in c.deps.keys()) {
    if (!Path.is_x2c_source(path)) continue;
    List entry = _entry(c, _canonical_path(path));
    if (!entry) continue;
    String provider = Compiler.portable_path(_canonical_path(path));
    List proof = NULL;
    Map hashes = NULL;
    foreach (Var part in entry.car()) {
      if (part is not <map>) continue;
      Var value;
      if (part.map().try_get(
        %("source-node" (provider-source $provider 0)), value))
        proof = value;
      if (part.map().try_get(
        %("source-node" (meta-hashes $provider 0)), value))
        hashes = value.list().caddr();
    }
    foreach (String name in hashes.keys()) {
      if (!(name in c.project_meta) && !(name in c.meta_calls)) continue;
      proof = proof.append(
        %(${_content_hash(_stored_meta_hashes(hashes))}));
      break;
    }
    rows[provider] = proof;
  }
}

/** Selects helper C spellings for public definitions owned by `path`.
    Bindings, rather than source tokens, keep unrelated private names and
    fields unchanged. Native supplier declarations retain their C names. */
void Compiler.name_meta_provider_bindings(
  Compiler c, String path, int index) {
  List entry = _entry(c, _canonical_path(path));
  if (!entry) return;
  foreach (String name in entry.caddr()) _name_meta_provider(c, name, index);
  foreach (Var part in entry.car()) {
    if (part is not <map>) continue;
    foreach (Var value in part.map())
      match (value) case %(native-object ?(String name)):
        _name_meta_provider(c, name, index);
  }
}

/** Returns this source's native definitions with their canonical declarations
    and the public type rows needed to check other units' declarations. */
List Compiler.loaded_provider(Compiler c) {
  List entry = _entry(c, _canonical_path(c.filename));
  Array names = [];
  foreach (String name in entry.caddr())
    if (name != "main" || c.load_source) names.push(name);
  foreach (Var part in entry.car())
    if (part is <map>)
      foreach (Var value in part.map())
        match (value) case %(native-object ?(String name)):
          names.push(name);
  List owned = names.list_free();
  Map symbols = c.callable_symbols(owned), declarations = {};
  foreach (String name in owned)
    declarations[name] = _loaded_declaration(c, symbols[%($name)]);
  return %($declarations $symbols);
}

/** Returns the native calling type of a loaded function. Array parameters
    decay to pointers, and a parameter's outer qualifiers affect only its
    local copy. Keep the declared type for inspection and reload checks. */
Type Compiler.loaded_call_type(Compiler c, Type type) {
  List parameters = NULL;
  Type result = NULL;
  type.function_parts(parameters, result);
  Array adjusted = [];
  foreach (Type parameter in parameters) {
    Type shape = c.sym.normalize_declared_type(parameter);
    if (shape.is_array()) parameter = shape.dereference().reference();
    while (parameter.car() is <symbol> &&
           parameter.car().symbol().is_type_qualifier())
      parameter = parameter.cdr();
    adjusted.push(parameter);
  }
  return %((func ${adjusted.list_free()}) @result);
}

static Type _loaded_declaration(Compiler c, Type type) {
  type = c.sym.normalize_declared_type(type);
  if (!type.is_function()) return type;
  List parameters = NULL;
  Type result = NULL;
  type.function_parts(parameters, result);
  Array declared = [];
  foreach (Type parameter in parameters)
    declared.push(c.sym.normalize_declared_type(parameter));
  List args = parameters ? declared.list_free() : %((void));
  return c.loaded_call_type(
    %((func $args) @{c.sym.normalize_declared_type(result)}));
}

/** Names declared bindings through one loaded provider. Its own source
    declarations remain authoritative; private bindings never link out. */
void Compiler.name_loaded_provider(
  Compiler c, String path, int index, List provider) {
  (Map declarations, Map symbols) = provider;
  Map visible = auto c.sym.unit_symbols();
  foreach ((String name, Type expected) in declarations) {
    if (%($name) in c.sym.file_statics() ||
        %(function $name) in c.sym.file_statics()) continue;
    Type type = NULL;
    List binding = c.sym.resolve_global(%($name), type);
    if (!binding) continue;
    if (!_loaded_types_equal(_loaded_declaration(c, type), expected) ||
        !_loaded_type_rows(type, visible, symbols))
      $report.collect_loaded_declaration(c, c.token, name, path);
    _name_meta_provider(c, name, index);
    // C headers keep their source spellings; declare the linked spelling too.
    type = type.declared();
    c.add_early(c.rebuild_statement($!{ extern $type $binding; }).cadr());
  }
}

static int _loaded_types_equal(Type declared, Type defined) {
  if (declared.equal(defined)) return 1;
  return declared.is_array() && defined.is_array() &&
    declared.car().list().len() == 1 && declared.cdr().equal(defined.cdr());
}

/* Compare complete type families actually named by the declaration. A
   forward declaration can remain incomplete in the calling source. */
static int _loaded_type_rows(Type type, Map visible, Map provider) {
  auto Map needed = {}, checked = {};
  _needed_types(type, visible, needed);
  int changed = 1;
  while (changed) {
    changed = 0;
    foreach (Var (key, value) in visible) {
      List family = _type_family(key);
      if (!family || !(family in needed) || key in checked) continue;
      Var expected;
      if (provider.try_get(key, expected) && !value.equal(expected)) return 0;
      checked[key] = 1;
      if (value is <list>) _needed_types(value, visible, needed);
      changed = 1;
    }
  }
  return 1;
}

static void _name_meta_provider(
  Compiler c, String name, int index) {
  if (%($name) in c.sym.file_statics()) return;
  if (name in c.native_meta && c.bind_native_meta(name)) return;
  List binding = c.sym.lookup(%($name), NULL);
  if (binding)
    c.set_fact(%(emitted $binding), %"_x2c_gensym_meta_group_${index}_$name");
}
