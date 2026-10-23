/* Lambda captures store non-reference values as Var, so traversal callbacks
   that carry the compiler need this raw pointer crossing. The pointee and its
   lifetime stay with the caller. */
/** Boxes the compiler's pointer; the caller keeps the compiler. */
Var Compiler.var(Compiler c) => (Var) { .p64 = c };

/** Recovers the compiler pointer boxed by `Compiler.var`. */
Compiler Var.compiler(Var value) => value.p64;

/* diagnostics routing

   A child compiler either shares its owner's diagnostic store or keeps its
   own, whose reports the owner takes when the child closes. */

/** Routes this compiler's diagnostic store through its own printer.

    Compilers that share a store call this when taking the diagnostic stream
    back from another compiler.
*/
void Compiler.own_diagnostics(Compiler c) {
  c.diagnostics.printer = c;
}

/** Retains a child's final diagnostics and closes its owned Lisp session. */
void Compiler.close_child(Compiler c, Compiler child) {
  c.take_diagnostics(child);
  if (!child.public_bodies) child.free_lisp();
}

// related compilers

/** Shares `owner`'s pending `meta` group and the definitions it reads, which
    belong with the Lisp session that holds the group's stubs. */
void Compiler.share_meta_group(Compiler c, Compiler owner) {
  $copy_fields(c, owner, meta_group, meta_group_bound);
}

/** Takes over `owner`'s macro, object-like `#define`, include, keyword,
    literal cache, and Lisp state for one segment of a collected file.
    Segments are one translation unit, so retained macro bodies index the
    unit's literal cache and use its Lisp environment.
*/
void Compiler.take_unit_state(Compiler c, Compiler owner) {
  $copy_fields(c, owner, id_keys, key_ids);
  $segment_state(c, owner);
  c.borrowed_lisp = c.macro_lisp != NULL;
  c.share_meta_group(owner);
}

/** Returns that state to `owner`, so the next segment starts where this one
    finished and any Lisp environment this segment created stays alive after
    the shadow is released.
*/
void Compiler.return_unit_state(Compiler c, Compiler owner) {
  $segment_state(owner, c);
  owner.declaration_produced |= c.declaration_produced;
  c.borrowed_lisp = c.macro_lisp != NULL;
}

// translation state and lifecycle

/** Creates a compiler with independent package and generated-name state. */
Compiler Compiler.new(void) => _new(NULL);

/** Creates a compiler sharing its owner's package and generated-name state. */
Compiler Compiler.new_shared(Compiler owner) {
  /* Shallow collection compilers must declare into the same package space,
     and share the owner's package maps so an import seen in one segment is
     registered and collected exactly once for the whole unit. */
  return _new(owner);
}

// Zero finalizer-visible state before any fallible initialization.
static Compiler _new(Compiler owner) {
  Compiler c =
    Scope.malloc_finalized(sizeof(struct Compiler), _drop_compiler);
  memset(c, 0, sizeof(struct Compiler));
  _init_tables(c);
  if (owner) _share_unit(c, owner);
  else _own_unit(c);
  c.sym = Sym.new(c);
  c.pending.reset();
  c.collect_protocols = 1;
  c.diagnostics = Diagnostics.new(
    owner && owner.diagnostics.printer ? c : NULL,
    owner ? owner.diagnostics.limit : 1);
  $set_fields(
    c, [], braces, line_starts, import_stack, meta_group, placements);
  c.ancestors = Block.new(sizeof(Ancestor));
  c.origins = owner ? owner.origins : [];
  c.root_dir = x2c_get_root();
  return c;
}

static void _init_tables(Compiler c) {
  c.id_keys = [];
  $set_fields(c, {}, key_ids, deps, macros, kw_aliases,
              object_macros, proto_cache, imports, init_tokens,
              static_init_deps, fn_defs, meta_comptime, meta_regions,
              meta_hashes, meta_calls, native_meta, project_meta,
              evaluated_effects, meta_group_bound);
}

/* A child compiler owns its tokens, symbols, and diagnostics. Package
   registries and generated-name state belong to the whole translation
   unit, so every child must mutate the owner's exact objects. */
static void _share_unit(Compiler c, Compiler owner) {
  $copy_fields(c, owner, package, package_dirs, package_source_dirs,
               package_roots, package_aliases, package_members,
               package_effects, names,
               source_map, recovery_depth, sources, declaration_produced,
               source_facts, source_occurrences, source_definitions,
               source_declarations, source_texts, unit_script, include_dirs,
               meta_build, meta_helper, evaluated_effects, pending_inline_bodies,
               collection_native_files);
}

/* The first compiler of a unit creates the state its children share and
   starts from the shared session's compile-time-only definitions. */
static void _own_unit(Compiler c) {
  c.pending_inline_bodies = [];
  c.collection_native_files = {};
  c.inherit_library_comptime();
  $set_fields(c, {}, package_roots, package_aliases, package_members,
              package_effects);
  c.names = xcalloc(1, sizeof(struct GenNames));
  $set_fields(c.names, {}, counters, adapters, file_scope_owners);
}

/** Destroys a compiler's owned `Lisp` session, if any.

    A borrowed session is left alive. Owned sessions not freed here are
    destroyed when the compiler's Scope ends. This is final compiler cleanup:
    it clears the diagnostic store and the compiler must not be reused.
    At process exit, root Scope cleanup follows shutdown hooks and canonical
    pool cleanup. Close explicitly while any native session dependencies live.
*/
void Compiler.free_lisp(Compiler c) {
  if (!c) return;
  if (c.macro_lisp && !c.borrowed_lisp) {
    c.macro_lisp.destroy();
    c.macro_lisp = NULL;
  }
  c.diagnostics = NULL;
}

// Lisp calls must have returned before the compiler's Scope is reclaimed.
static void _drop_compiler(void *ptr) {
  Compiler c = ptr;
  c.free_lisp();
}
