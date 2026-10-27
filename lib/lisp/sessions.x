/*  sessions.x -- Lisp sessions

    Copyright (c) 2026 Gary William Flake.
*/

static pthread_once_t lisp_initialize_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;
static int lisp_initialize_success;

module unsigned _canonical_count(void) =>
  sizeof(lisp_canonical_names) / sizeof(lisp_canonical_names[0]);

static void _initialize_once(void) {
  Var values[sizeof(lisp_canonical_names) / sizeof(lisp_canonical_names[0])];
  for (unsigned i = 0; i < _canonical_count(); i++)
    values[i] = Atom.intern(lisp_canonical_names[i].spelling);
  for (unsigned i = 0; i < _canonical_count(); i++)
    if (values[i] is <lsym> && !values[i].str().try_own()) return;
  for (unsigned i = 0; i < _canonical_count(); i++)
    *lisp_canonical_names[i].value = values[i];
  lisp_initialize_success = 1;
}

static int _initialize(void) {
  if (pthread_once(&lisp_initialize_once, _initialize_once)) {
    fprintf(stderr, "Lisp: could not initialize canonical names\n");
    abort();
  }
  return lisp_initialize_success;
}

module int _global_lookup(Lisp lisp, Var name, Var &out) {
  for (Lisp s = lisp; s; s = s.parent)
    if (_binding_get(s.globals, name, out)) return 1;
  return 0;
}

/* A reserved special form, from this session or the nearest parent. A child
   that inherits its parent's specials also inherits their identity, which is
   what `_special_id` compares. */
module int _reserved_lookup(Lisp lisp, Var name, Var &out) {
  for (Lisp s = lisp; s; s = s.parent)
    if (s.reserved.try_get(name, out)) return 1;
  return 0;
}

/* A child may define new names but cannot replace inherited definitions. */
module int _inherited(Lisp lisp, Var name) {
  for (Lisp s = lisp.parent; s; s = s.parent)
    if (name in s.globals || name in s.reserved) return 1;
  return 0;
}

module int _binding_get(Map bindings, Var name, Var &out) {
  Var slot;
  if (!bindings || !bindings.try_get(name, slot)) return 0;
  out = _cell_load(slot);
  return 1;
}

module void _binding_set(Scope *owner, Map bindings, Var name, Var value) {
  Var slot;
  if (bindings.try_get(name, slot)) _cell_store(slot, value);
  else bindings[name] = _cell(owner, value);
}

/* Bindings use separately allocated cells because a Map excludes void from
   its value domain. */
static Var _cell(Scope *owner, Var value) {
  Var *slot = Scope.malloc_in(owner, sizeof(Var));
  *slot = value;
  return Var.new(<var*>, slot);
}

static Var _cell_load(Var cell) => *((Var *) cell.pointer());

static void _cell_store(Var cell, Var value) {
  *((Var *) cell.pointer()) = value;
}

/* sessions

   A kernel session holds only the evaluator's special forms, and a new
   session also evaluates the standard environment from `etc/init.xlisp`. */

static String lisp_standard_source = $lisp._standard.source();

/** Creates an isolated embedded `Lisp` session with only evaluator primitives.
    The caller owns a successful session and must pass it to `Lisp.destroy`.
    Returns NULL if a long shared name cannot be owned by the active pool
    chain. Failure of native once initialization writes a diagnostic and
    aborts the process.
    Raises: `<alloc-fail>` or `<size-limit>` while creating session storage, or
    `<bad-enc>` while interning shared or special-form names.
*/
Lisp Lisp.kernel(void) {
  Scope session = Scope.new_named("Lisp session"), Lisp result = NULL;
  defer if (!result) Scope.destroy(session);
  Lisp lisp = Scope.calloc_in(&session, 1, sizeof(struct Lisp));
  defer if (!result) Scope.destroy(lisp.user);
  if (!_initialize()) return NULL;
  lisp.scope = session;
  lisp.user = Scope.new_named("Lisp user");
  lisp.call_step_max = LISP_CALL_STEP_MAX;
  auto (&lisp.scope) {
    lisp.globals = {};
    lisp.reserved = {};
    _install_specials(lisp);
  }
  return result = lisp;
}

/* A special form's reserved value is a distinct stub Func, which the
   evaluator recognizes by identity. */
static void _install_specials(Lisp lisp) {
  for (unsigned i = 0; i < _canonical_count(); i++) {
    const LispCanonicalName *info = &lisp_canonical_names[i];
    if (!info.special) continue;
    lisp.specials[i] = Func.new(_special_stub, $!Type{ Var (void) });
    Atom name = Atom.intern(info.spelling);
    lisp.reserved[name] = lisp.specials[i];
  }
}

static Var _special_stub(void) => Var.null();

/** Creates an isolated session with the standard Lisp environment loaded.
    The caller owns the result and must pass it to `Lisp.destroy`.
    If standard-source evaluation transfers, no handle is returned and the
    constructed session remains allocated.
    Raises any cause from `Lisp.kernel` or `Lisp.eval_string`.
*/
Lisp Lisp.new(void) {
  Lisp lisp = Lisp.kernel();
  lisp.eval_string(lisp_standard_source);
  return lisp;
}

/** Releases a `Lisp` session and invalidates all session-owned state.
    This includes its global and reserved `Map`s, Lambdas, and transferred
    `Func`s. Borrowed values are not released. A null session does nothing;
    no evaluation may remain active.
    Destroying its still-active `Scope` raises `<bad-state>`.
*/
void Lisp.destroy(Lisp lisp) {
  if (!lisp) return;
  Scope.destroy(lisp.user);
  Scope.destroy(lisp.scope);
}

/** Makes `lisp` read `parent`'s definitions for names it does not bind.

    Lisp definitions cannot replace names supplied by an ancestor.
    `Lisp.set_global` may shadow them in the child. Child writes never
    reach the parent or another child. The child also takes the parent's
    special forms in place of its own, because
    the evaluator recognizes a special form by the identity of the `Func` a
    name resolves to, and the child resolves reserved names in the parent.

    The caller keeps `parent` alive for as long as any child names it, and
    freezes it with `Lisp.freeze` before the first child runs: a child's
    values belong to a narrower `Context` than the parent's, so nothing a
    child produces may become reachable from the parent.
*/
void Lisp.adopt(Lisp lisp, Lisp parent) {
  if (!lisp || !parent) return;
  lisp.parent = parent;
  auto (&lisp.scope) lisp.reserved = {};
  for (unsigned i = 0; i < _canonical_count(); i++)
    lisp.specials[i] = parent.specials[i];
}

/** Marks `lisp` complete, so nothing produced later may reach it.

    A frozen session rejects `def` and `Lisp.set_global`: a value produced
    while a narrower `Context` is current would leave the session holding
    values that die with that `Context`.
*/
void Lisp.freeze(Lisp lisp) { if (lisp) lisp.frozen = 1; }

// globals

/** Writes the global binding for `name` to `out` when present.
    Returns 1 only after writing the borrowed value. A null session, name, or
    output, or an absent name returns 0 and leaves `out` unchanged. Raises
    `<alloc-fail>` or `<bad-enc>` when a nonempty lookup name cannot be
    canonicalized.
*/
int Lisp.try_get(Lisp lisp, String name, Var &?out) {
  if (!out) return 0;
  return lisp && name && _global_lookup(lisp, Atom.intern(name), out);
}

/** Binds `name` to `value` in the embedded Lisp global environment.
    The session stores the value in a raw slot, so `void` remains distinct
    from Lisp `nil`. The binding does not take ownership of value referents;
    their canonical graphs or other owners must outlive the binding or
    session. A host binding may shadow an inherited name in this session;
    it does not change the ancestor. Lisp `def` still rejects inherited
    names, including a name the host has shadowed locally.
    Binding an `x2c.` name protects that namespace from later Lisp
    `def` forms, but direct calls to this function may replace such a
    binding.
    Raises: `<bad-arg>` for a null session or name, or `<alloc-fail>`,
    `<size-limit>`, or `<bad-enc>` while canonicalizing or storing the binding.
*/
void Lisp.set_global(Lisp lisp, String name, Var value) {
  if (!lisp || !name) $error.global.args();
  if (lisp.frozen)
    $error.global.frozen("Lisp.set_global");
  auto (&lisp.scope) {
    Var interned = Atom.intern(name);
    _binding_set(&lisp.scope, lisp.globals, interned, value);
    if (name.startswith("x2c.")) lisp.protect_x2c = 1;
  }
}

/** Removes this session's global binding for `name`, if present. An
    ancestor's binding of the same name becomes visible again. Code that
    already resolved the binding keeps its value; value referents keep their
    owners.
    Raises: `<bad-arg>` for a null session or name, `<bad-state>` for a
    frozen session, or `<alloc-fail>` or `<bad-enc>` while canonicalizing
    the name.
*/
void Lisp.remove_global(Lisp lisp, String name) {
  if (!lisp || !name) $error.entry.null("Lisp.remove_global");
  if (lisp.frozen)
    $error.global.frozen("Lisp.remove_global");
  lisp.globals.del(Atom.intern(name));
}

/** Installs `function` as `name` and transfers its storage to `lisp`.
    Invalid arguments raise `<bad-arg>` without transferring ownership. Once
    validation succeeds, the `Func` moves before the global insertion. The
    caller relinquishes ownership even if name canonicalization or `Map`
    growth then raises `<alloc-fail>`, `<size-limit>`, or `<bad-enc>`, but
    may borrow the pointer while the session lives. A direct function or
    noncapturing lambda converts to a shared handle that lives for the
    program; the session only borrows it. Values inside the `Func`,
    including its signature graph, retain their existing owners.
*/
void Lisp.bind(Lisp lisp, String name, Func function) {
  if (!lisp || !name || !function) $error.bind.args();
  function.move(&lisp.scope);
  lisp.set_global(name, function);
}

// session storage

/** Borrows the session executing the current native Lisp callback. */
Lisp Lisp.active(void) => lisp_active;
/** Borrows the storage owner for callback state retained by this session. */
Scope *Lisp.storage(Lisp lisp) => &lisp.scope;
/** Borrows the current lowered source activation's automatic storage. */
Scope *Lisp.automatic_storage(Lisp lisp) =>
  lisp.automatic_owner ? lisp.automatic_owner : &lisp.scope;
/** Borrows the caller's storage for a lowered record result. */
Scope *Lisp.result_storage(Lisp lisp) =>
  lisp.result_owner ? lisp.result_owner : &lisp.scope;
