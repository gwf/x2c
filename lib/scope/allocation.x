/*  allocation.x -- scope allocation */

// block layout

/* Native allocation alignment leaves the low pointer bit clear. At a list
   head, `prev` stores the owning Scope with that bit set; every other `prev`
   is the untagged preceding ScopeAlloc. Free, move, realloc, and owner lookup
   all rely on relinking without losing this one in-band ownership marker. */
static macro Expression $scope.ptr_alloc(Expr $p) =>
  ((ScopeAlloc) ((char *) ($p) - sizeof(struct ScopeAlloc)));
static macro Expression $scope.alloc_ptr(Expr $a) =>
  ((void *) ((char *) ($a) + sizeof(struct ScopeAlloc)));
static macro Expression $scope.tag_pointer(Expr $p) =>
  ((void *) ((uintptr_t) ($p) | (uintptr_t) 1));
static macro Expression $scope.untag_pointer(Expr $p) =>
  ((void *) ((uintptr_t) ($p) & ~((uintptr_t) 1)));
static macro Expression $scope.is_tagged(Expr $p) =>
  ((uintptr_t) ($p) & (uintptr_t) 1);

/* Every allocation keeps its requested payload size and optional destructor
   before the public header. ScopeAlloc remains immediately before the payload
   and the combined prefix preserves native allocation alignment. */
static typedef struct ScopeMetadata {
  size_t requested_size;
  void (*drop)(void *);
} ScopeMetadata;

_Static_assert(
  (sizeof(ScopeMetadata) + sizeof(struct ScopeAlloc)) %
    _Alignof(max_align_t) == 0,
  "Scope allocation prefix must preserve payload alignment");

static macro Expression $scope.alloc_meta(Expr $a) =>
  (((ScopeMetadata *) ($a)) - 1);

// allocation

/** Allocates `size` uninitialized bytes in the active scope.
    The result is managed memory. `Scope.realloc` resizes it, `Scope.free`
    ends its life early, `Scope.move` reassigns its owner, and
    `Scope.release` or `Scope.destroy` reclaims whatever is left. The active
    scope at the time of allocation owns the result; a later retain or push
    does not move it.
    Raises: `<size-limit>` when the size would overflow the allocation header,
    or `<alloc-fail>` when the underlying allocation fails. Before `Error`
    initialization they terminate at the error floor.
*/
meta native void *Scope.malloc(size_t size) {
  _require_running();
  return _malloc_in(_thread().active, size, NULL);
}

/** Allocates `size` uninitialized bytes in the active scope with a finalizer.
    `drop` runs exactly once with the block's pointer when the block is
    reclaimed: by `Scope.free`, by `Scope.realloc` to size zero, by the
    release or destruction of its scope, or by thread and process shutdown.
    The finalizer follows the block through `Scope.move` and survives
    `Scope.realloc`, which passes `drop` the resized pointer. Blocks are
    reclaimed most recent first, so a finalizer sees older blocks still live.

    A wrapper for a native handle allocates its record this way and releases
    the handle from `drop`; an explicit early release that clears the field
    leaves nothing for the finalizer to do. `drop` runs on the thread that
    reclaims the block, with the block already unlinked, so it must not free
    or move the block itself. It must not raise. It may allocate into other
    scopes, and into the dying scope only for scratch the same destruction
    reclaims.
    Raises: `<bad-arg>` when `drop` is NULL, `<size-limit>` when the size
    would overflow the allocation header, or `<alloc-fail>` when the
    underlying allocation fails. Before `Error` initialization they
    terminate at the error floor.
*/
void *Scope.malloc_finalized(size_t size, void (*drop)(void *)) {
  _require_running();
  if (!drop) raise %(bad-arg);
  return _malloc_in(_thread().active, size, drop);
}

/** Allocates `size` uninitialized bytes in the scope held by `slot`.
    `slot` is the address of a `Scope` variable; if it holds NULL, a fresh
    unnamed scope is created and stored there. Targeting a slot does not
    touch the active-scope stack, so an intervening `Scope.retain` or
    `Scope.push` cannot redirect the allocation. Pass `Scope.top()` to name
    the active slot explicitly.
    Raises: `<bad-arg>` when `slot` is NULL, `<size-limit>` when the size
    overflows, or `<alloc-fail>` when allocation fails. Before `Error`
    initialization they terminate at the error floor.
*/
void *Scope.malloc_in(Scope *slot, size_t size) {
  _require_running();
  return _malloc_in(slot, size, NULL);
}

/** Allocates `size` bytes with finalizer `drop` in the scope held by `s`.
    The slot-targeted form of `Scope.malloc_finalized`, with the same lazy
    scope creation as `Scope.malloc_in`; the active scope is left alone.
    Raises: `<bad-arg>` when `s` or `drop` is NULL, `<size-limit>` when
    the size overflows, or `<alloc-fail>` when allocation fails. Before
    `Error` initialization they terminate at the error floor.
*/
void *Scope.malloc_finalized_in(Scope *s, size_t size, void (*drop)(void *)) {
  _require_running();
  if (!drop) raise %(bad-arg);
  return _malloc_in(s, size, drop);
}

// zeroed and copied allocation

/** Allocates `count` objects of `size` bytes each, zeroed, in the active
    scope. The product is checked for overflow before anything is allocated,
    and the bytes are set to zero; in every other respect this behaves like
    `Scope.malloc`. A request that multiplies out to zero still returns a
    distinct pointer the scope owns, so it is not a failure signal.
    Raises: `<size-limit>` when the object count overflows, or `<alloc-fail>`
    when allocation fails. Before `Error` initialization they terminate at the
    error floor.
*/
meta native void *Scope.calloc(size_t count, size_t size) {
  _require_running();
  return _calloc_in(_thread().active, count, size);
}

/** Allocates `count` zeroed objects of `size` bytes in the scope in `slot`.
    The slot-targeted form of `Scope.calloc`, with the same overflow check and
    the same lazy scope creation as `Scope.malloc_in`; the active scope is left
    alone.
    Raises: `<bad-arg>` when `slot` is NULL, `<size-limit>` when the object
    count overflows, or `<alloc-fail>` when allocation fails. Before `Error`
    initialization they terminate at the error floor.
*/
void *Scope.calloc_in(Scope *slot, size_t count, size_t size) {
  _require_running();
  return _calloc_in(slot, count, size);
}

/** Copies `size` bytes from `ptr` into a new allocation in the active scope.
    The copy is ordinary scope-owned memory, freed by `Scope.free` or by the
    release that ends the region. Nothing about the source is remembered, so
    duplicating a C string means copying its terminator too:
    `xmemdup(text, strlen(text) + 1)`.

    A NULL `ptr` or a zero `size` returns NULL and allocates nothing, so a
    duplicate of nothing is indistinguishable from failure; check the
    arguments when that distinction matters.
    Raises: `<size-limit>` or `<alloc-fail>` from the underlying allocation.
    A NULL `ptr` or zero `size` returns NULL without raising.
*/
meta native void *Scope.memdup(const void *ptr, size_t size) {
  _require_running();
  return _memdup_in(_thread().active, ptr, size);
}

/** Copies `size` bytes from `ptr` into the scope held by `slot`.
    The slot-targeted form of `Scope.memdup`, with the same NULL-for-nothing
    rule and the same lazy scope creation as `Scope.malloc_in`. It is the
    usual way to hand a snapshot of caller data to a scope that outlives the
    current region.
    Raises: `<bad-arg>` when `slot` is NULL, or `<size-limit>` or
    `<alloc-fail>` from the underlying allocation. A NULL `ptr` or zero
    `size` returns NULL without raising.
*/
void *Scope.memdup_in(Scope *slot, const void *ptr, size_t size) {
  _require_running();
  return _memdup_in(slot, ptr, size);
}

// freeing, moving, and resizing

/** Frees one scope-owned allocation before its scope ends.
    `ptr` must be a pointer returned by `Scope.malloc`, `Scope.calloc`,
    `Scope.memdup`, one of their `_in` forms, or `Scope.realloc`. It is
    unlinked from whichever scope owns it now, which after a `Scope.move` may
    not be the active one.

    Shortening a lifetime this way is normal. Freeing anything else, such as a
    stack address, an interned `String`, or a plain `malloc` result, is
    undefined, as is freeing the same pointer twice. Nothing diagnoses
    either.

    A NULL `ptr` does nothing.
*/
meta native void Scope.free(void *ptr) {
  _require_running();
  if (!ptr) return;
  _free($scope.ptr_alloc(ptr));
}

/** Returns the `Scope` that currently owns `ptr`.
    `ptr` must be a live pointer returned by a `Scope` allocator. `Context`
    uses this to leave ancestor-owned objects where they are while moving
    results out of its own `Scope` chain. Passing any other nonnull pointer is
    undefined behavior, matching `Scope.free` and `Scope.move`.
*/
Scope Scope.owner(void *ptr) {
  _require_running();
  if (!ptr) return NULL;
  ScopeAlloc alloc = $scope.ptr_alloc(ptr);
  while (alloc && !$scope.is_tagged(alloc.prev)) alloc = alloc.prev;
  return alloc ? $scope.untag_pointer(alloc.prev) : NULL;
}

/** Relinks one allocation onto the scope held by `slot`.
    The bytes are not copied and the pointer does not change; only ownership
    moves, so a temporary region can compute one result that outlives it. If
    `slot` holds NULL a fresh unnamed scope is created there, as the `_in`
    allocators do.

    ```x2c
    ~int main(void) {
    Scope keep = Scope.new_named("results");
    Scope.retain();
    char *text = xmemdup("survivor", 9);
    Scope.move(text, &keep);
    Scope.release();
    puts(text);
    Scope.destroy(keep);
    ~  return 0;
    ~}
    ```

    You do not need this for a `String`, a `List`, or a `Symbol`. Canonical
    values already outlive the scope that was active when they were built.
    Raises: `<bad-arg>` when `slot` is NULL, or `<alloc-fail>` when a new
    destination scope cannot be allocated. These failures leave ownership
    unchanged. A NULL `ptr` does nothing. Before `Error` initialization they
    terminate at the error floor.
*/
meta native void Scope.move(void *ptr, Scope *slot) {
  _require_running();
  if (!ptr) return;
  if (!slot) raise %(bad-arg);
  if (!*slot) *slot = _new_scope(NULL);
  ScopeAlloc alloc = $scope.ptr_alloc(ptr);
  _detach(alloc);
  _attach((*slot), alloc);
}

/** Moves one allocation immediately before another in its owner's list.
    Both pointers must name distinct live Scope allocations under exclusive
    access. This internal storage-replacement operation preserves payloads
    and finalizers without allocation, owner lookup, or scope creation.
*/
void Scope.move_before(void *ptr, void *anchor) {
  ScopeAlloc alloc = $scope.ptr_alloc(ptr);
  ScopeAlloc before = $scope.ptr_alloc(anchor);
  _detach(alloc);
  _relink(alloc, before.prev, before);
}

/** Resizes one scope-owned allocation and returns the new pointer.
    Ownership does not change: the allocation stays with the scope that
    already held it, even if that is not the active one. Two edge cases follow
    C's `realloc`: a NULL `ptr` allocates `size` bytes in the active scope, and
    a `size` of zero frees the allocation and returns NULL. A NULL result is
    not by itself a failure.

    As with C, the old pointer must be treated as dead once a resize succeeds.
    Raises: `<size-limit>` when the size overflows, or `<alloc-fail>` when
    allocation fails. Before `Error` initialization these failures terminate at
    the error floor.
*/
meta native void *Scope.realloc(void *ptr, size_t size) {
  _require_running();
  if (!ptr) return _malloc_in(_thread().active, size, NULL);
  if (!size) {
    _free($scope.ptr_alloc(ptr));
    return NULL;
  }
  ScopeAlloc old = $scope.ptr_alloc(ptr), next = old.next, prev = old.prev;
  ScopeMetadata *old_meta = $scope.alloc_meta(old);
  size_t old_size = old_meta.requested_size;
  if (size > SIZE_MAX - sizeof(ScopeMetadata) - sizeof(struct ScopeAlloc))
    raise %(size-limit);
  ScopeMetadata *meta = _data_realloc(
    old_meta, sizeof(ScopeMetadata) + sizeof(struct ScopeAlloc) + size);
  meta.requested_size = size;
  ScopeAlloc replacement = (ScopeAlloc) (meta + 1);
  _relink(replacement, prev, next);
  _record_resize(old_size, size);
  return $scope.alloc_ptr(replacement);
}

static void *_malloc_in(Scope *slot, size_t size, void (*drop)(void *)) {
  if (!slot) raise %(bad-arg);
  if (size > SIZE_MAX - sizeof(ScopeMetadata) - sizeof(struct ScopeAlloc)) {
    if (x2c_error_runtime_ready) raise %(size-limit);
    _raw_fatal("allocation size overflow");
  }
  if (!*slot) *slot = _new_scope(NULL);
  ScopeMetadata *meta = _data_malloc(
    sizeof(ScopeMetadata) + sizeof(struct ScopeAlloc) + size);
  meta.requested_size = size;
  meta.drop = drop;
  ScopeAlloc alloc = (ScopeAlloc) (meta + 1);
  _attach((*slot), alloc);
  _record_allocation(size);
  return $scope.alloc_ptr(alloc);
}

/* New blocks go first, so destruction reclaims the newest block first. */
static void _attach(Scope scope, ScopeAlloc alloc) {
  alloc.next = scope.first;
  alloc.prev = $scope.tag_pointer(scope);
  if (scope.first) scope.first.prev = alloc;
  scope.first = alloc;
}

module void *_data_malloc(size_t size) {
  void *ptr = malloc(size);
  if (!ptr) raise %(alloc-fail);
  return ptr;
}

static void *_calloc_in(Scope *slot, size_t count, size_t size) {
  if (count && size > SIZE_MAX / count) {
    if (x2c_error_runtime_ready) raise %(size-limit);
    _raw_fatal("calloc size overflow");
  }
  size_t total = count * size, void *ptr = _malloc_in(slot, total, NULL);
  if (total) memset(ptr, 0, total);
  return ptr;
}

static void *_memdup_in(Scope *slot, const void *ptr, size_t size) {
  if (!ptr || !size) return NULL;
  void *copy = _malloc_in(slot, size, NULL);
  memcpy(copy, ptr, size);
  return copy;
}

static void _free(ScopeAlloc alloc) {
  _detach(alloc);
  _release(alloc);
}

module void _detach(ScopeAlloc alloc) {
  ScopeAlloc next = alloc.next, prev = alloc.prev;
  _point_to(prev, next);
  if (next) next.prev = prev;
}

/* The link before a block is its owner's head when `prev` is the tagged
   owner, and the preceding block's `next` otherwise. */
static void _point_to(ScopeAlloc prev, ScopeAlloc alloc) {
  if ($scope.is_tagged(prev)) {
    Scope scope = $scope.untag_pointer(prev);
    scope.first = alloc;
  }
  else prev.next = alloc;
}

/* The block is already unlinked, so a drop that allocates or frees other
   storage sees a consistent list. */
module void _release(ScopeAlloc alloc) {
  ScopeMetadata *meta = $scope.alloc_meta(alloc);
  void (*drop)(void *) = meta.drop;
  _record_free(meta.requested_size);
  if (drop) drop($scope.alloc_ptr(alloc));
  free(meta);
}

/* Puts `alloc` where a block between `prev` and `next` was. */
static void _relink(
  ScopeAlloc alloc, ScopeAlloc prev, ScopeAlloc next) {
  alloc.next = next;
  alloc.prev = prev;
  if (next) next.prev = alloc;
  _point_to(prev, alloc);
}

static void *_data_realloc(void *ptr, size_t size) {
  void *result = realloc(ptr, size);
  if (!result) raise %(alloc-fail);
  return result;
}
