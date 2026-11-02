/*  providers.x -- source collection providers

    Copyright (c) 2026 Gary William Flake.
*/

/** Reports whether a provider's linked definition hashes still match.
    Changes outside definitions do not require a project helper.
*/
int Compiler.linked_meta_definitions_current(Compiler c, String path) {
  if (c.linked_meta_provider_current(path)) return 1;
  String canonical = _canonical_path(path);
  String provider = Compiler.portable_path(canonical);
  List source = Compiler.linked_meta_provider_source(provider);
  if (source ~= %(source ?hash *) && _hash_matches(c, canonical, hash))
    return 1;
  if (source ~= %(source ? ? ?(String definitions))) {
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

/** Reports whether a linked provider and the files it read are unchanged.
    The linked inventory retains the ordinary collector's dependency proof.
*/
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

/** Completes a linked function's own source hashes before a shallow call.
    A lookahead entry never replaces the file's ordinary contribution.
*/
void Compiler.complete_meta_hashes(Compiler c) {
  List entry = _meta_provider_entry(c, _canonical_path(c.filename));
  if (entry)
    foreach (Var part in entry.car()) {
      if (part is not <map>) continue;
      foreach (Var value in part.map())
        if (value ~= %(meta-hashes ? ?(Map hashes)))
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
    /* The proof and hash key name the same provider identity. */
    String canonical = _canonical_path(path);
    List entry = _entry(c, canonical);
    if (!entry) continue;
    String provider = Compiler.portable_path(canonical);
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
        $(_content_hash(_stored_meta_hashes(hashes))));
      break;
    }
    rows[provider] = proof;
  }
}

/** Selects helper C spellings for public definitions owned by `path`.
    Bindings, rather than source tokens, keep unrelated private names and
    fields unchanged. Native supplier declarations retain their C names.
*/
void Compiler.name_meta_provider_bindings(
  Compiler c, String path, int index) {
  List entry = _entry(c, _canonical_path(path));
  if (!entry) return;
  foreach (String name in entry.caddr()) _name_meta_provider(c, name, index);
  foreach (Var part in entry.car()) {
    if (part is not <map>) continue;
    foreach (Var value in part.map())
      if (value ~= %(native-object ?(String name)))
        _name_meta_provider(c, name, index);
  }
}

// source collection providers

static int _linked_provider_current(
  Compiler c, String path, Map seen) {
  Var current;
  if (linked_providers.try_get(path, current)) return current;
  if (path in seen) return 1;
  seen[path] = 1;
  List source =
    Compiler.linked_meta_provider_source(Compiler.portable_path(path));
  if (source ~= %(source ?hash ?(List dependencies) *)) {
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

static void _name_meta_provider(
  Compiler c, String name, int index) {
  if ($(name) in c.sym.file_statics()) return;
  if (name in c.native_meta && c.bind_native_meta(name)) return;
  List binding = c.sym.lookup($(name), NULL);
  if (binding)
    c.set_fact(%(emitted $binding), %"_x2c_gensym_meta_group_$(index)_$name");
}
