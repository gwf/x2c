/*  context.x -- bounded runtime state and value export

    Copyright (c) 2026 Gary William Flake

    Context owns one bounded unit of runtime work: a `Scope` lifetime with its
    `Error` and `Match` state and, when isolated, a nested canonical-value
    pool. Export carries a value out before close reclaims the rest: it moves
    built-in storage the source `Scope` owns and recanonicalizes immutable
    values only when the source's private pool owns them.
*/

#pragma once

$(import "error-macros.xmacro")

#include "common.x"

protocol Cleanup(Context);

#pragma private

#include "array.x"
#include "atom.x"
#include "block.x"
#include "buffer.x"
#include "dispatch.x"
#include "error.x"
#include "exception.x"
#include "list.x"
#include "map.x"
#include "match-cache.x"
#include "pool.x"
#include "scope.x"
#include "string.x"
#include "var.x"

#include <stdlib.h>

/* The Context record itself belongs to the parent's active Scope. Its nested
   Scope and optional canonical pool own work performed inside the Context;
   the destination Scope slot and pool are borrowed from the state captured
   before that work is installed. */
struct Context {
  Context parent, Scope scope, *destination_scope, Pool pool;
  Pool destination_pool, void *error_state, *match_state;
};

typedef struct ContextThreadState {
  Context current;
} *ContextThreadState;

static threaded struct ContextThreadState context_thread;

static ContextThreadState _thread(void) => &context_thread;

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
    allocation, hashing, equality, or custom export. */
meta native Var Context.export(Context context, Var value) {
  if (!context || _thread().current != context)
    raise %(bad-state (owner "Context.export"));
  return context._export_value(value);
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
  return Context._export_value(&source, value);
}

static Var Context._export_value(Context c, Var v) {
  if (v is void || v.is_null() || v.is_nil() || v is <symbol>) return v;
  if (v.is_wide()) return c._export_wide(v);
  if (v.is_integer() || v.is_floating()) return v;
  if (v is <string>) return c._export_string(v);
  if (v is <lsym>) return c._export_atom(v);
  if (v is <list>) return c._export_list(v);
  if (v is <array>) return c._export_array(v);
  if (v is <map>) return c._export_map(v);
  if (v is <block> || v is <bytes> || v is <buffer>)
    return c._export_storage(v);
  Var custom;
  if (v.try_export_context(c, custom)) return custom;
  Symbol tag = v.tag();
  raise %(bad-types (owner "Context.export") (tag $tag));
}

static Var Context._export_wide(Context c, Var v) {
  if (!c._owns_scope(v.wide_owner())) return v;
  return v.move_wide_to(c.destination_scope);
}

static Var Context._export_string(Context c, Var value) {
  if (!c.pool || !c.pool.owns(value)) return value;
  String string = value;
  return String.new_in(c.destination_pool, string, string.len());
}

static Var Context._export_atom(Context c, Var value) {
  String spelling = value.str();
  if (!c.pool || !c.pool.owns(spelling)) return value;
  String result = String.new_in(c.destination_pool, spelling, spelling.len());
  return Var.new(<lsym>, result);
}

static List Context._export_list(Context c, List list) {
  if (!list || (c.pool && !c.pool.owns(list))) return list;
  Block heads = $auto(Block.new(sizeof(Var)));
  List tail = list;
  while (tail && (!c.pool || c.pool.owns(tail))) {
    Var head = c._export_value(tail.car);
    heads.push(&head);
    tail = tail.cdr;
  }
  Var *items = heads.bytes;
  for (size_t i = heads.length; i; i--)
    tail = c.pool ? List.cons_in(c.destination_pool, items[i - 1], tail)
                  : List.cons(items[i - 1], tail);
  return tail;
}

/* Move an Array or Map identity before recursively exporting its contents.
   A cyclic revisit then sees an object outside the source and terminates.
   Failure restores this container's original owner, but nested exports that
   already completed are not rolled back; backing storage moves only after
   the recursive work succeeds. */
static Var Context._export_array(Context c, Var value) {
  Array array = value;
  if (!c.owns(array)) return value;
  Scope owner = Scope.owner(array);
  Scope.move(array, c.destination_scope);
  int exported = 0;
  defer if (!exported) Scope.move(array, &owner);
  Var *items = array.bytes;
  for (size_t i = 0; i < array.length; i++)
    items[i] = c._export_value(items[i]);
  array.move_to(c.destination_scope);
  exported = 1;
  return value;
}

static Var Context._export_map(Context c, Var value) {
  Map map = value;
  if (!c.owns(map)) return value;
  Scope owner = Scope.owner(map);
  Scope.move(map, c.destination_scope);
  int exported = 0;
  defer if (!exported) Scope.move(map, &owner);
  map.export_to(c, _export_callback, c.destination_scope);
  exported = 1;
  return value;
}

/* `Map.export_to` takes the value-first C signature of a custom exporter. */
static Var _export_callback(Var value, Context c) =>
  c._export_value(value);

/* Block, Bytes, and Buffer storage moves and keeps its identity. */
static Var Context._export_storage(Context c, Var v) {
  void *allocation = v is <bytes> ? v.bytes().block() : v.pointer();
  if (!c.owns(allocation)) return v;
  if (v is <buffer>) ((Buffer) allocation).move_to(c.destination_scope);
  else ((Block) allocation).move_to(c.destination_scope);
  return v;
}

/* custom exporters

   A registered exporter for a custom class recurses through
   `Context.export_nested` and moves its own storage. */

/** Recursively exports one nested value through an active or sealed `Context`.
    Registered custom exporters call this; other callers export their
    complete result with `Context.export`. Built-in movable families preserve
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
Var Context.export_nested(Context c, Var value) => c._export_value(value);

/** Reports whether `allocation` belongs to `context`'s `Scope` chain.
    The nonnull pointer must come from a `Scope` allocator. Registered custom
    exporters call this before moving their own storage.
*/
int Context.owns(Context context, void *allocation) =>
  allocation && context._owns_scope(Scope.owner(allocation));

static int Context._owns_scope(Context context, Scope owner) {
  if (!context || !owner) return 0;
  for (Scope scope = context.scope; scope; scope = scope.down)
    if (scope == owner) return 1;
  return 0;
}

/** Returns the borrowed `Scope` slot that receives exports from `c`.
    The slot remains valid only while the `Context`'s destination state lives;
    a null `Context` returns NULL.
*/
Scope *Context.export_destination(Context c) => c ? c.destination_scope : NULL;

/** Moves one custom-exporter-owned allocation to the destination `Context`.
    A null allocation or one outside `c`'s `Scope` chain is unchanged.
    Application code exports its value with `Context.export` instead.
*/
void Context.move_allocation(Context c, void *allocation) {
  if (c.owns(allocation)) Scope.move(allocation, c.export_destination());
}

// lifecycle

/** Opens and makes current a `Context` using the active canonical-value pool.
    Close it before its parent; its `Scope` owns subsequent mutable
    allocations.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state. */
meta native Context Context.open(void) => _open(NULL, 0);

/** Opens and makes current a named `Context` that inherits immutable values.
    The diagnostic name is copied, and the `Context` must close before its
    parent.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state. */
Context Context.open_named(const char *name) => _open(name, 0);

/** Opens and makes current a `Context` with a private canonical-value pool.
    Export surviving immutable values before closing the `Context`.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state. */
Context Context.open_isolated(void) => _open(NULL, 1);

/** Opens and makes current a named `Context` with a private canonical pool.
    The diagnostic name is copied; export survivors before closing the
    `Context`.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state. */
Context Context.open_isolated_named(const char *name) => _open(name, 1);

static Context _open(const char *name, int isolated) {
  Context.initialize();
  Context context = Scope.calloc(1, sizeof(struct Context));
  with context {
    _.parent = _thread().current;
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
      Scope.free(_);
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
    _thread().current = _;
    installed = 1;
    return _;
  }
}

/** Returns the `Context` currently active on this thread, or NULL. */
meta native Context Context.current(void) => _thread().current;

/** Closes the current `Context`, reclaims unexported state, and restores
    parent.
    The `Context` must be current; all pointers into its remaining `Scope` or
    private canonical pool become invalid.

    Raises: `<bad-state>` for a null or noncurrent `Context`, or while its
    `Match`
    cache has an active lease. The failure leaves the `Context` active. */
meta native void Context.close(Context c) {
  if (!c || _thread().current != c) raise %(bad-state (owner "Context.close"));

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
  _thread().current = parent;
  Scope.free(c);
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
  while (_thread().current) _thread().current.close();
}

static void _register_shutdown(void) {
  Scope.shutdown_hook(_shutdown);
}
