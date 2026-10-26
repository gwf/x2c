/*  context.x -- bounded runtime state and value export

    Copyright (c) 2026 Gary William Flake

    Context owns one bounded unit of runtime work: a `Scope` lifetime with its
    `Error` and `Match` state and, when isolated, a nested canonical-value
    pool. Export carries a value out before close reclaims the rest: it moves
    built-in storage the source `Scope` owns and recanonicalizes immutable
    values only when the source's private pool owns them.
*/

#pragma once

#include "error-macros.x"

#include "common.x"

protocol Cleanup(Context);

#include "array/array.x"
#include "atom.x"
#include "block.x"
#include "buffer.x"
#include "dispatch.x"
#include "error/error.x"
#include "exception.x"
#include "list/list.x"
#include "map/map.x"
#include "match/match.x"
#include "pool/pool.x"
#include "scope/scope.x"
#include "string/string.x"
#include "var/var.x"

#include <stdlib.h>

/* The Context record itself belongs to the parent's active Scope. Its nested
   Scope and optional canonical pool own work performed inside the Context;
   the destination Scope slot and pool are borrowed from the state captured
   before that work is installed. */
static struct Context {
  Context parent, Scope scope, *destination_scope, Pool pool;
  Pool destination_pool, void *error_state, *match_state;
  Map exported;
};

static threaded Context current_context;

// export

/** Exports `value` into the parent of the current `Context`.
    Values may belong to a retained region of that `Context`; export them
    while live, before releasing their `Scope` or closing the `Context`.
    Built-in movable families preserve identity. A custom exact-descriptor
    exporter defines its returned value, including identity. Private canonical
    immutable built-ins may change, so callers must use the returned value;
    inherited or borrowed built-ins are unchanged. `void` exports as `void`
    because it owns no storage.

    Built-in `Array` and `Map` export restores the container's source ownership
    if recursive export fails, but nested exports already completed are not
    rolled back.

    Raises: `<bad-state>` unless `context` is current, `<bad-types>` for an
    unsupported value without a registered exporter, or a cause from nested
    allocation, hashing, equality, or custom export.
*/
meta native Var Context.export(Context context, Var value) {
  if (!context || current_context != context)
    raise %(bad-state (operation "Context.export"));
  return _export_root(context, value);
}

/** Exports a sealed worker result `Scope` into the current `Scope` and pool.
    Built-in movable families preserve identity. A custom exact-descriptor
    exporter defines its returned value, including identity. Private canonical
    built-ins may change, so callers must use the returned value; inherited or
    borrowed built-ins are unchanged. The source `Scope` and pool remain
    caller-owned through the call.

    Built-in `Array` and `Map` export restores the container's source ownership
    if recursive export fails, but nested exports already completed are not
    rolled back.

    Raises: `<bad-types>` for an unsupported value without a registered
    exporter, or a cause from nested allocation, hashing, equality, or custom
    export.
*/
Var Context.export_scope(Scope source_scope, Pool pool, Var value) {
  struct Context source = {
    .scope = source_scope,
    .pool = pool,
    .destination_scope = Scope.top(),
    .destination_pool = Pool.current()
  };
  return _export_root(&source, value);
}

static Var _export_root(Context c, Var value) {
  if (c.exported != NULL) return _export_value(c, value);
  defer {
    if (c.exported != NULL) c.exported.cleanup();
    c.exported = NULL;
  }
  Var result = _export_value(c, value);
  _commit_export(c);
  return result;
}

/* Moving a whole ownership subtree cannot mark only the visited container:
   its adopted descendants still need recursive canonical-value export. */
static int _visited(Context c, Var value) {
  _export_memo(c);
  if (c.exported.contains(value)) return 1;
  c.exported.set(value, 1);
  return 0;
}

static Map _export_memo(Context c) {
  if (c.exported == NULL) c.exported = Map.new();
  return c.exported;
}

/* Scope keys mark complete storage moves. Container keys mark visits; raw
   storage keys and wide-box bit identities record primitive move actions. */
static int _scheduled_owner(Context c, Scope scope) {
  for (; scope; scope = scope.parent())
    if (c.exported.contains(scope)) return 1;
  return 0;
}

static void _commit_export(Context c) {
  if (c.exported == NULL) return;
  Scope *destination = c.destination_scope;
  if (!*destination) *destination = Scope.new();
  foreach (Var (key, value) in c.exported) {
    if (value.is_wide()) {
      if (!_scheduled_owner(c, value.wide_owner()))
        value.move_wide_to(destination);
    }
    else if (key is <block> || key is <buffer> || key is <p48>) {
      void *allocation = key.pointer();
      if (_scheduled_owner(c, Scope.owner(allocation))) continue;
      if (key is <block>) ((Block) allocation).move_to(destination);
      else if (key is <buffer>) ((Buffer) allocation).move_to(destination);
      else Scope.move(allocation, destination);
    }
  }
  foreach (Var key in c.exported.keys()) {
    if (key is not <scope>) continue;
    Scope storage = key;
    if (!_scheduled_owner(c, storage.parent()))
      storage.transfer(*destination);
  }
}

static Var _export_value(Context c, Var v) {
  if (v is void || v.is_null() || v.is_nil() || v is <symbol>) return v;
  if (v.is_wide()) return _export_wide(c, v);
  if (v.is_integer() || v.is_floating()) return v;
  if (v is <string>) return _export_string(c, v);
  if (v is <lsym>) return _export_atom(c, v);
  if (v is <list>) return _export_list(c, v);
  if (v is <array>) return _export_array(c, v);
  if (v is <map>) return _export_map(c, v);
  if (v is <block> || v is <bytes> || v is <buffer>)
    return _export_storage(c, v);
  Var custom;
  if (v.try_export_context(c, custom)) return custom;
  Symbol tag = v.tag();
  raise %(bad-types (operation "Context.export") (tag $tag));
}

static Var _export_wide(Context c, Var v) {
  if (!_owns_scope(c, v.wide_owner())) return v;
  Map memo = _export_memo(c);
  Scope scratch = memo;
  /* Numeric Map equality compares values, so use the encoded box identity
     as the key and keep its temporary key box under the memo's own scope. */
  auto (&scratch) memo.set(Var.box_ulong(v.u64), v);
  return v;
}

static Var _export_string(Context c, Var value) {
  if (!c.pool || !c.pool.owns(value)) return value;
  String string = value;
  return String.new_in(c.destination_pool, string, string.len());
}

static Var _export_atom(Context c, Var value) {
  String spelling = value.str();
  if (!c.pool || !c.pool.owns(spelling)) return value;
  String result = String.new_in(c.destination_pool, spelling, spelling.len());
  return Var.new(<lsym>, result);
}

static List _export_list(Context c, List list) {
  if (!list || (c.pool && !c.pool.owns(list))) return list;
  Block heads = auto Block.new(sizeof(Var));
  List tail = list;
  while (tail && (!c.pool || c.pool.owns(tail))) {
    Var head = _export_value(c, tail.car);
    heads.push(&head);
    tail = tail.cdr;
  }
  Var *items = heads.bytes;
  for (size_t i = heads.length; i; i--)
    tail = c.pool ? List.cons_in(c.destination_pool, items[i - 1], tail)
                  : List.cons(items[i - 1], tail);
  return tail;
}

/* Visit each container once. Root export commits only outermost scheduled
   scopes, preserving adoption regardless of reference traversal order. */
static Var _export_array(Context c, Var value) {
  Array array = value;
  if (!c.owns(array) || _visited(c, value)) return value;
  c.move_block(array);
  Var *items = array.bytes;
  for (size_t i = 0; i < array.length; i++)
    items[i] = _export_value(c, items[i]);
  return value;
}

static Var _export_map(Context c, Var value) {
  Map map = value;
  if (!c.owns(map) || _visited(c, value)) return value;
  map.export_to(c, _export_callback, c.destination_scope);
  c.move_allocation(map);
  c.move_block(map.hashes);
  c.move_block(map.entries);
  c.move_scope(map.scope);
  return value;
}

/* `Map.export_to` takes the value-first C signature of a custom exporter. */
static Var _export_callback(Var value, Context c) =>
  _export_value(c, value);

/* Block, Bytes, and Buffer storage moves and keeps its identity. */
static Var _export_storage(Context c, Var v) {
  void *allocation = v is <bytes> ? v.bytes().block() : v.pointer();
  if (!c.owns(allocation)) return v;
  if (v is <buffer>) _export_memo(c).set(v, 1);
  else c.move_block((Block) allocation);
  return v;
}

/* custom exporters

   A registered exporter for a custom class recurses through
   `Context.export_nested` and moves its own storage. */

/** Recursively exports one nested value through an active or sealed `Context`.
    Registered custom exporters call this; other callers export their
    complete result with `Context.export`. Call only during an enclosing
    `Context.export` or `Context.export_scope`: its root commits pending
    storage moves after traversal. Built-in movable families preserve
    identity. A custom exact-descriptor exporter defines its returned value,
    including identity. For built-ins, private canonical pointers may change,
    so callers must use the result; inherited or borrowed values are unchanged.

    Built-in `Array` and `Map` export restores the container's source ownership
    if recursive export fails, but nested exports already completed are not
    rolled back.

    Raises: `<bad-types>` for an unsupported value without a registered
    exporter, or a cause from nested allocation, hashing, equality, or custom
    export.
*/
Var Context.export_nested(Context c, Var value) => _export_value(c, value);

/** Reports whether a managed allocation still needs export from `context`.
    The nonnull pointer must come from a `Scope` allocator. Registered custom
    exporters call this before moving their own storage. An individual
    allocation scheduled by `Context.move_allocation` answers zero, although
    physical ownership changes only when the enclosing root export commits.
    Scheduling a complete scope does not hide its unvisited descendants.
*/
int Context.owns(Context context, void *allocation) =>
  allocation && context &&
  !(context.exported != NULL && context.exported.contains(allocation)) &&
  _owns_scope(context, Scope.owner(allocation));

static int _owns_scope(Context context, Scope owner) {
  if (!context || !owner) return 0;
  for (Scope scope = context.scope; scope; scope = scope.down)
    if (scope.contains(owner)) return 1;
  return 0;
}

/** Returns the borrowed `Scope` slot that receives exports from `c`.
    The slot remains valid only while the `Context`'s destination state lives;
    a null `Context` returns NULL.
*/
Scope *Context.export_destination(Context c) => c ? c.destination_scope : NULL;

/** Schedules one allocation during a registered custom export callback.
    A null allocation or one outside `c`'s `Scope` chain is unchanged.
    It immediately answers zero to `Context.owns`, preserving custom cycle
    guards. Root export keeps it beneath any scheduled owning scope, or
    relinks it individually after traversal when no such owner is exported.
    Application code exports its value with `Context.export` instead.
    Raises: allocation and table-growth causes while recording the move.
*/
void Context.move_allocation(Context c, void *allocation) {
  if (c.owns(allocation)) _export_memo(c).set(allocation, 1);
}

/** Schedules custom-exporter storage while preserving explicit adoption.
    Root export reparents outermost requested scopes after recursive export.
    Exporters call this for grouped storage, never from channel transport.
    Raises: allocation and table-growth causes while recording the move.
*/
void Context.move_scope(Context c, Scope storage) {
  if (_owns_scope(c, storage)) _export_memo(c).set(storage, 1);
}

/** Schedules Block storage and nullable owned contents for an exporter.
    Root export keeps allocations covered by a scheduled storage scope under
    that owner. Uncovered storage moves with `Block.move_to`.
    Raises: allocation and table-growth causes while recording the move.
*/
void Context.move_block(Context c, Block block) {
  if (!c.owns(block)) return;
  _export_memo(c).set(block, 1);
  c.move_scope(block.lifetime);
}

// lifecycle

/** Opens and makes current a `Context` using the active canonical-value pool.
    Close it before its parent; its `Scope` owns subsequent mutable
    allocations.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state.
*/
meta native Context Context.open(void) => _open(NULL, 0);

/** Opens and makes current a named `Context` that inherits immutable values.
    The diagnostic name is copied, and the `Context` must close before its
    parent.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state.
*/
Context Context.open_named(const char *name) => _open(name, 0);

/** Opens and makes current a `Context` with a private canonical-value pool.
    Export surviving immutable values before closing the `Context`.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state.
*/
Context Context.open_isolated(void) => _open(NULL, 1);

/** Opens and makes current a named `Context` with a private canonical pool.
    The diagnostic name is copied; export survivors before closing the
    `Context`.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state.
*/
Context Context.open_isolated_named(const char *name) => _open(name, 1);

static Context _open(const char *name, int isolated) {
  Context.initialize();
  Context context = xcalloc(1, sizeof(struct Context));
  alias context {
    _.parent = current_context;
    _.destination_scope = Scope.top();
    int pushed = 0, installed = 0;
    /* Publish the Context only after its Scope, optional pool, Error state,
       and Match state are ready. A failed open closes those dependencies in
       reverse order while the parent's destination state is still live. */
    defer if (!installed) {
      if (_.match_state) MatchCache.context_close(_.match_state);
      if (_.error_state)
        Error.context_close(_.error_state, x2c_exception_unwinding());
      if (_.pool)     Pool.close();
      if (pushed)     Scope.pop();
      if (_.scope)    Scope.destroy(_.scope);
      xfree(_);
    }
    _.scope = name ? Scope.new_named(name) : Scope.new();
    Scope.push(&_.scope);
    pushed = 1;
    if (isolated) {
      _.pool = Pool.open_named(name);
      _.destination_pool = _.pool.up;
    }
    _.error_state = Error.context_open();
    _.match_state = MatchCache.context_open();
    current_context = _;
    installed = 1;
    return _;
  }
}

/** Returns the `Context` currently active on this thread, or NULL. */
meta native Context Context.current(void) => current_context;

/** Closes the current `Context`, reclaims unexported state, and restores
    parent.
    The `Context` must be current; all pointers into its remaining `Scope` or
    private canonical pool become invalid.

    Raises: `<bad-state>` for a null or noncurrent `Context`, or while its
    `Match` cache has an active lease. The failure leaves the `Context` active.
*/
meta native void Context.close(Context c) {
  if (!c || current_context != c)
    raise %(bad-state (operation "Context.close"));

  /* Match and Error teardown can still use Context-owned values. Release the
     private canonical pool before its Scope, restore the destination Scope
     before destroying the child, and publish the parent only after teardown
     can no longer observe this Context. */
  MatchCache.context_close(c.match_state);
  Error.context_close(c.error_state, x2c_exception_unwinding());
  if (c.pool) Pool.close();

  Scope scope = c.scope, Context parent = c.parent;
  /* Drop any slot the body pushed and never popped, as an `exit()` from
     inside the `Context` leaves. Popping one of those instead would leave
     this `Context`'s own slot active, and destroying it would raise. */
  while (Scope.top() != &c.scope) Scope.pop();
  Scope.pop();
  scope.destroy();
  current_context = parent;
  xfree(c);
}

/** Ends the owned lifetime when a managed local leaves its block. */
meta native void Context.cleanup(Context value) { value.close(); }

/** Registers `Context` cleanup before workers can start. */
void Context.initialize(void) {
  if (pthread_once(&context_shutdown_once, _register_shutdown)) {
    fprintf(stderr, "Context: could not register shutdown\n");
    abort();
  }
}

static pthread_once_t context_shutdown_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

static void _shutdown(void) {
  while (current_context) current_context.close();
}

static void _register_shutdown(void) {
  Scope.shutdown_hook(_shutdown);
}
