/*  context.x -- bounded runtime state and value export

    Copyright (c) 2026 Gary William Flake

    `Context` combines one `Scope` lifetime with `Error` and `Match` state. An
    isolated `Context` also owns a nested canonical-value pool. Export moves
    built-in movable storage owned by the source `Scope`. For built-in
    immutable
    values, it recanonicalizes only those owned by the source's private pool;
    inherited or borrowed values are returned unchanged. Closing reclaims
    everything else.
*/

#pragma once

$(import "error-macros.xmacro")

#include "common.x"

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
#include "match.x"
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

static pthread_once_t context_shutdown_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

static void _shutdown(void) {
  while (_thread().current) _thread().current.close();
}

static void _register_shutdown(void) {
  Scope.shutdown_hook(_shutdown);
}

/** Registers `Context` cleanup before workers can start. */
void Context.initialize(void) {
  if (pthread_once(&context_shutdown_once, _register_shutdown)) {
    fprintf(stderr, "Context: could not register shutdown\n");
    abort();
  }
}

static int _owns_scope(Context context, Scope owner) {
  if (!context || !owner) return 0;
  for (Scope scope = context.scope; scope; scope = scope.down)
    if (scope == owner) return 1;
  return 0;
}

/** Reports whether `allocation` belongs to `context`'s `Scope` chain.
    The nonnull pointer must come from a `Scope` allocator. Registered custom
    exporters call this before moving their own storage.
*/
int Context.owns(Context context, void *allocation) => allocation &&
         _owns_scope(context, Scope.owner(allocation));

/** Returns the borrowed `Scope` slot that receives exports from `context`.
    The slot remains valid only while the `Context`'s destination state lives;
    a null `Context` returns NULL.
*/
Scope *Context.export_destination(Context context) =>
  context ? context.destination_scope : NULL;

/** Moves one custom-exporter-owned allocation to the destination `Context`.
    A null allocation or one outside `context`'s `Scope` chain is unchanged.
    Application code exports its value with `Context.export` instead.
*/
void Context.move_allocation(Context context, void *allocation) {
  if (context.owns(allocation))
    Scope.move(allocation, context.export_destination());
}

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
      if (_.pool)     String.pool_release();
      if (pushed)     Scope.pop();
      if (_.scope)    Scope.destroy(_.scope);
      Scope.free(_);
    }
    _.scope = name ? Scope.new_named(name) : Scope.new();
    Scope.push(&_.scope);
    pushed = 1;
    if (isolated) {
      _.pool = String.pool_retain_named(name);
      _.destination_pool = _.pool.up;
    }
    _.error_state = Error.context_open();
    _.match_state = MatchCache.context_open();
    _thread().current = _;
    installed = 1;
    return _;
  }
}

/** Opens and makes current a `Context` using the active canonical-value pool.
    Close it before its parent; its `Scope` owns subsequent mutable
    allocations.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing nested state.
    Failed construction restores the parent's `Scope`, canonical pool, `Error`,
    `Match`, and current `Context` state. */
Context Context.open(void) => _open(NULL, 0);

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

/** Returns the `Context` currently active on this thread, or NULL. */
Context Context.current(void) => _thread().current;

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
Var Context.export_nested(Context context, Var value) =>
  _export_value(value, context);

static Var _export_string(Var value, Context source) {
  if (!source.pool || !source.pool.owns(value)) return value;
  String string = value;
  String result = String.new_in(source.destination_pool, string, string.len());
  return result;
}

static Var _export_atom(Var value, Context source) {
  String spelling = value.str();
  if (!source.pool || !source.pool.owns(spelling)) return value;
  String result = String.new_in(
    source.destination_pool, spelling, spelling.len());
  return Var.new(<lsym>, result);
}

static List _export_list(List list, Context source) {
  if (!list || (source.pool && !source.pool.owns(list))) return list;
  Block heads = Block.new(sizeof(Var));
  defer heads.free();
  List tail = list;
  while (tail && (!source.pool || source.pool.owns(tail))) {
    Var head = _export_value(tail.car, source);
    heads.push(&head);
    tail = tail.cdr;
  }
  Var *items = heads.bytes;
  for (size_t i = heads.length; i; i--)
    tail = source.pool
         ? List.cons_in(source.destination_pool, items[i - 1], tail)
         : List.cons(items[i - 1], tail);
  return tail;
}

/* Move an Array or Map identity before recursively exporting its contents.
   A cyclic revisit then sees an object outside the source and terminates.
   Failure restores this container's original owner, but nested exports that
   already completed are not rolled back; backing storage moves only after
   the recursive work succeeds. */
static Var _export_array(Var value, Context source) {
  Array array = value;
  if (!source.owns(array)) return value;
  Scope owner = Scope.owner(array);
  Scope.move(array, source.destination_scope);
  int exported = 0;
  defer if (!exported) Scope.move(array, &owner);
  Var *items = array.bytes;
  for (size_t i = 0; i < array.length; i++)
    items[i] = _export_value(items[i], source);
  array.move_to(source.destination_scope);
  exported = 1;
  return value;
}

static Var _export_map(Var value, Context source) {
  Map map = value;
  if (!source.owns(map)) return value;
  Scope owner = Scope.owner(map);
  Scope.move(map, source.destination_scope);
  int exported = 0;
  defer if (!exported) Scope.move(map, &owner);
  map.export_to(source, _export_value, source.destination_scope);
  exported = 1;
  return value;
}

static Var _export_value(Var v, Context source) {
  if (v is void || v.is_null() || v.is_nil() ||
      v is <symbol>) return v;
  if (v.is_wide()) {
    if (_owns_scope(source, v.wide_owner()))
      return v.move_wide_to(source.destination_scope);
    return v;
  }
  if (v.is_integer() || v.is_floating()) return v;
  if (v is <string>) return _export_string(v, source);
  if (v is <lsym>) return _export_atom(v, source);
  if (v is <list>) return _export_list(v, source);
  if (v is <array>) return _export_array(v, source);
  if (v is <map>) return _export_map(v, source);
  if (v is <block>) {
    Block block = v;
    if (source.owns(block)) block.move_to(source.destination_scope);
    return v;
  }
  if (v is <bytes>) {
    Bytes bytes = v, Block block = bytes;
    if (source.owns(block)) block.move_to(source.destination_scope);
    return v;
  }
  if (v is <buffer>) {
    Buffer buffer = v;
    if (source.owns(buffer)) buffer.move_to(source.destination_scope);
    return v;
  }
  Var custom;
  if (v.try_export_context(source, &custom)) return custom;
  Symbol tag = v.tag();
  raise %(bad-types (owner "Context.export") (tag $tag));
}

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
Var Context.export(Context context, Var value) {
  if (!context || _thread().current != context)
    raise %(bad-state (owner "Context.export"));
  return _export_value(value, context);
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
    .destination_pool = String.pool_current()
  };
  return _export_value(value, &source);
}

/** Closes the current `Context`, reclaims unexported state, and restores
    parent.
    The `Context` must be current; all pointers into its remaining `Scope` or
    private canonical pool become invalid.

    Raises: `<bad-state>` for a null or noncurrent `Context`, or while its
    `Match`
    cache has an active lease. The failure leaves the `Context` active. */
void Context.close(Context context) {
  if (!context || _thread().current != context)
    raise %(bad-state (owner "Context.close"));

  /* Match and Error teardown can still use Context-owned values. Release the
     private canonical pool before its Scope, restore the destination Scope
     before destroying the child, and publish the parent only after teardown
     can no longer observe this Context. */
  MatchCache.context_close(context.match_state);
  Error.context_close(context.error_state, x2c_exception_unwinding());
  if (context.pool) String.pool_release();

  Scope scope = context.scope, Context parent = context.parent;
  Scope.pop();
  Scope.destroy(scope);
  _thread().current = parent;
  Scope.free(context);
}
