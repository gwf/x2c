/*  source-locations.x -- source locations

   An origin row locates a parsed node for later diagnostics. With source
   facts on, as for the editor adapter, declarations and references also
   record their source ranges. */

/** Wraps a parsed node in the source location of its opening token.

    A null node remains null. Macro construction uses its active `m-origin`
    marker; otherwise a node without a token remains unwrapped.
*/
List Compiler.anchor_origin(Compiler c, List node, Token token) {
  if (!node) return node;
  if (c.macro_holes) return %(at m-origin $node);
  int occurrence = c.record_origin(token);
  if (!occurrence) return node;
  return %(at $occurrence $node);
}

/** Records a token's location and returns its one-based occurrence.

    A null token returns zero. Callers pass the token that opened a construct,
    so an `(at N node)` wrapper retains its start for transform diagnostics
    after `c.token` has reached end of file.
*/
int Compiler.record_origin(Compiler c, Token token) {
  if (!token) return 0;
  int line = token.line;
  String file = c.line_markers ? c.token_source(token, line) : c.filename;
  if (!file) file = "<stdin>";
  if (!c.source_map) file = c.display_path(file);
  c.origins.push(
    %(source $file $line $(c.token_column(token)) $(token.len) $(token.pos)));
  return c.origins.len();
}

/** Records a physical declaration using the binding's actual scope and key.
    Occurrence rows retain their five-field prefix and append `<decl>`
    so references can omit earlier declarations that a later one replaced.
*/
void Compiler.record_source_declaration(
  Compiler c, List binding, Token first, Token after, int external) {
  if (!c.source_facts || c.macro_holes) return;
  Var value;
  if (!c.semantic_binding_facts().try_get(%(src-key $binding), value)) return;
  List source_key = value, range = _source_range(c, first, after);
  if (!range) return;
  Map symbols = source_key.car();
  List key = source_key.cadr();
  Type type = symbols[key];
  List method = c.fact(%(method $binding));
  List declaration = $(@range, type, method);
  if (external)
    declaration = %(@declaration () $(c.emitted_binding_name(binding)));
  c.sym.put(c.source_declarations, source_key, declaration);
  if (c.source_primary && !c.shallow) {
    c.materialize_source_declaration(binding, declaration);
    c.source_occurrences.push($(@range, binding, type, <decl>));
  }
}

/** A foreign alias emits a macro, not an external C symbol of its own. */
void Compiler.clear_source_external(Compiler c, List binding) {
  if (!c.source_facts) return;
  List key = c.fact(%(src-key $binding));
  Var value;
  if (key && c.source_declarations.try_get(key, value)) {
    List declaration = value;
    if (declaration[6] is <string>)
      c.sym.put(c.source_declarations, key, declaration[:6]);
  }
  if (c.source_definitions.try_get(binding, value)) {
    List declaration = value;
    if (declaration[6] is <string>)
      c.source_definitions[binding] = declaration[:6];
  }
}

/** Records a resolved reference without inventing spans for constructed
    ASTs.
*/
void Compiler.record_source_reference(
  Compiler c, List binding, Type type, Token first, Token after) {
  if (!c.source_facts || c.macro_holes ||
      !Ast.try_binding(binding, NULL, NULL)) return;
  if (!c.source_primary || c.shallow) {
    if (c.source_capture == NULL) return;
    List range = _source_range(c, first, after);
    if (range)
      c.source_capture.push($(@range, binding, type,
        c.fact(%(src-key $binding))));
    return;
  }
  List range = _source_range(c, first, after);
  if (range) c.source_occurrences.push($(@range, binding, type));
}

/** Attaches a completed named-type capture to its existing declaration row. */
void Compiler.attach_source_references(Compiler c, List binding, Array capture) {
  List key = c.fact(%(src-key $binding));
  List declaration = c.source_declarations[key];
  declaration = %(@(declaration[:5]) $capture @(declaration[6:]));
  c.sym.put(c.source_declarations, key, declaration);
  if (c.source_primary && !c.shallow)
    c.materialize_source_declaration(binding, declaration);
}

/** Materializes one producer-owned source row and its captured references.
    Row fields are file, start, end, Type, method, optional capture, and
    optional external emitted name. Only ordinary declarations supply linkage.
    Installing the row before replay marks self and mutually recursive rows.
*/
void Compiler.materialize_source_declaration(
  Compiler c, List binding, List declaration) {
  if (c.source_definitions[binding] === declaration) return;
  c.source_definitions[binding] = declaration;
  List method = declaration[4];
  if (method) c.set_fact(%(method $binding), method);
  Array capture = declaration[5];
  foreach (List entry in capture) {
    (String file, int start, int end, List target,
     Type type, List key) = entry;
    Var source;
    if (key && c.source_declarations.try_get(key, source)) {
      c.set_fact(%(src-key $target), key);
      c.materialize_source_declaration(target, source);
    }
    c.source_occurrences.push($(file, start, end, target, type));
  }
}

/** Carries declaration metadata beside a completed symbol-map merge. */
void Compiler.merge_source_declarations(Compiler c, Map target, Map source) {
  if (!c.source_facts) return;
  foreach (Var key in source.keys())
    if (key is <list>) c.copy_source_declaration(target, source, key);
}

/** Carries declaration metadata with one actual symbol contribution. */
void Compiler.copy_source_declaration(
  Compiler c, Map target, Map source, List key) {
  if (!c.source_facts) return;
  Var declaration;
  List target_key = $(target, key);
  if (c.source_declarations.try_get($(source, key), declaration))
    c.sym.put(c.source_declarations, target_key, declaration);
  else c.sym.drop(c.source_declarations, target_key);
}

static List _source_range(Compiler c, Token first, Token after) {
  if (!first || !after || first >= after || c.macro_holes) return NULL;
  Token last = after - 1;
  while (last > first &&
         (last.type == <space> || last.type == <comment> ||
          last.type == <preproc>)) last--;
  // A module member's range counts from the start of the member.
  int start = first.pos;
  String path = Path.resolved_absolute(c.text_source(first.pos, start));
  if (!c.line_markers && !(path in c.source_texts))
    c.source_texts[path] = c.text;
  return $(path, start, start + last.pos + last.len - first.pos);
}
