/*  block.x -- checked dynamic storage for fixed-width elements

    Copyright (c) 2025 Gary William Flake

    `Block` maintains the length and capacity invariants for contiguous
    fixed-width storage. `Bytes` exposes the same allocation through its data
    pointer and a hidden back-pointer. Capacity growth raises where the
    failure is detected, leaves storage unchanged, and does not return to the
    call.

    A self-source may name any initialized range inside reserved capacity.
    Growth rebases that range after reallocating the owning block.

    `Bytes` receives the `Block` protocol's generated members through the
    `Bytes.block` storage view.
*/

#pragma once
$(import "error-macros.xmacro")
#include "common.x"

#include <stdint.h>
#include <string.h>

/** Holds resizable contiguous storage for fixed-width elements.
    The object and backing allocation belong to the `Scope` active at
    construction unless `Block.move_to` transfers them. The `Block` handle
    remains stable, but `bytes` is a borrowed base pointer that growth may
    replace. Valid `Block`s have nonzero `width` and `length <= cap`;
    `Block.free` invalidates the handle and every `Bytes` view.
*/
typedef struct Block {
  Bytes bytes, size_t width, length, cap;
} *Block;

protocol Cleanup(Block);
protocol Cleanup(Bytes);

#pragma private

#include "exception.x"
#include "scope.x"

/* storage layout

   One allocation holds a back-pointer to the owning `Block` and then the
   elements; `bytes` points just past the back-pointer. */

/* The size of an allocation for `cap` elements, or zero when it cannot be
   represented. */
static size_t _allocation_size(size_t width, size_t cap) {
  if (!width || cap > (SIZE_MAX - sizeof(Block)) / width) return 0;
  return sizeof(Block) + width * cap;
}

static void *_allocation(Block b) => (unsigned char *) b.bytes - sizeof(Block);

static void _attach(Block b, unsigned char *allocation) {
  *((Block *) allocation) = b;
  b.bytes = allocation + sizeof(Block);
}

static unsigned char *_end(Block b) =>
  (unsigned char *) b.bytes + b.length * b.width;

/** Returns the stable `Block` that owns the live `bytes` base pointer.
    An interior or stale pointer is invalid; NULL returns NULL.
*/
inline Block Bytes.block(Bytes bytes) {
  if (bytes == NULL) return NULL;
  unsigned char *data = bytes;
  return *((Block *) (data - sizeof(Block)));
}

// appending

/** Appends `count` elements copied from `source` to `block`.
    The source may be NULL for zero-filled elements; otherwise it must name
    `count` readable elements. When growth is required, an initialized range
    inside this `Block`'s reserved storage keeps its offset across relocation.
    Success may invalidate saved `Bytes` and element pointers.
    Raises: `<bad-arg>` for a null `Block`, or for an internal source crossing
    reserved storage when growth is required; `<size-limit>` when the new
    extent cannot be represented; or `<alloc-fail>` when growth fails. These
    failures leave the `Block` unchanged.
*/
void Block.append(Block b, const void *source, size_t count) {
  if (b == NULL) raise %(bad-arg);
  if (!count) return;
  if (count <= b.cap - b.length) _append_in_place(b, source, count);
  else _append_growing(b, source, count);
}

/* Without growth no source moves, and memmove covers one that overlaps the
   end. */
static void _append_in_place(Block b, const void *source, size_t count) {
  unsigned char *end = _end(b);
  if (!source) memset(end, 0, count * b.width);
  else memmove(end, source, count * b.width);
  b.length += count;
}

/* A source inside the reserved storage is copied from its offset after the
   relocation. */
static void _append_growing(Block b, const void *source, size_t count) {
  if (count > SIZE_MAX - b.length || count > SIZE_MAX / b.width) {
    size_t width = b.width;
    raise %(size-limit (width $width) (count $count));
  }
  size_t size = count * b.width, offset = _reserved_offset(b, source);
  if (offset != SIZE_MAX && size > b.cap * b.width - offset)
    raise %(bad-arg (count $count));
  size_t length = b.length;
  b.reserve(length + count);
  unsigned char *end = _end(b);
  if (!source) memset(end, 0, size);
  else if (offset != SIZE_MAX)
    memmove(end, (unsigned char *) b.bytes + offset, size);
  else memcpy(end, source, size);
  b.length = length + count;
}

/* The offset of `p` inside `b`'s reserved storage, or SIZE_MAX outside it.
   The offset survives growth because realloc preserves the entire
   allocation, not only logical content. */
static size_t _reserved_offset(Block b, const void *p) {
  uintptr_t start = (uintptr_t) b.bytes, at = (uintptr_t) p;
  if (at < start || at - start >= b.cap * b.width) return SIZE_MAX;
  return at - start;
}

/** Appends `count` elements to `bytes` and returns its current base pointer.
    Callers must use the return because growth may relocate storage. Raises:
    the same causes as `Block.append`; failure leaves the original view live.
*/
inline Self Bytes.append(Self bytes, const void *source, size_t count) {
  Block block = bytes;
  block.append(source, count);
  return block.bytes;
}

/** Appends repeated fixed-width elements to `block`.
    A zero count is a no-op and accepts a null `element`. Otherwise `element`
    must point to one complete element.
    `element` may point at one complete logical element in `block`; its offset
    is preserved if growth relocates storage. Success may invalidate saved
    `Bytes` and element pointers.
    Raises: `<bad-arg>` for a null `Block`, or for a null or invalid
    self-source element on a nonzero append; `<size-limit>` when the new
    extent cannot be represented; or `<alloc-fail>` when growth fails. These
    failures leave the `Block` unchanged.
*/
void Block.append_fill(Block b, const void *element, size_t count) {
  if (b == NULL) raise %(bad-arg);
  if (!count) return;
  if (!element) raise %(bad-arg);
  if (count > SIZE_MAX - b.length) raise %(size-limit (count $count));
  size_t length = b.length, used = length * b.width;
  size_t offset = _reserved_offset(b, element);
  if (offset != SIZE_MAX && (offset > used || b.width > used - offset))
    raise %(bad-arg);
  b.reserve(length + count);
  if (offset != SIZE_MAX) element = (unsigned char *) b.bytes + offset;
  _fill(b, element, count);
  b.length = length + count;
}

/* Writes `count` copies of `element` past the end of `b`'s elements. */
static void _fill(Block b, const void *element, size_t count) {
  unsigned char *end = _end(b);
  if (b.width == 1) memset(end, *((const unsigned char *) element), count);
  else
    for (size_t i = 0; i < count; i++)
      memmove(end + i * b.width, element, b.width);
}

/** Appends repeated elements to `bytes` and returns its current base pointer.
    Callers must use the return because growth may relocate storage. Raises:
    the same causes as `Block.append_fill`; failure leaves the original view
    live.
*/
inline Self Bytes.append_fill(Self bytes, const void *element, size_t count) {
  Block block = bytes;
  block.append_fill(element, count);
  return block.bytes;
}

/** Appends one copied element; storage and failures follow `Block.append`. */
inline void Block.push(Block block, const void *source) {
  block.append(source, 1);
}

/** Appends one element and returns the possibly relocated `Bytes` base. */
inline Self Bytes.push(Self bytes, const void *source) =>
  bytes.append(source, 1);

// capacity

/** Ensures `block` can hold at least `minimum` elements.
    The `Block` handle and contents remain stable, but growth may replace
    `block.bytes` and invalidate saved `Bytes` or element pointers.
    Raises: `<bad-arg>` when `block` is null, `<size-limit>` when the requested
    capacity cannot be represented, or `<alloc-fail>` when growth fails.
    These failures leave the `Block` unchanged.
*/
void Block.reserve(Block block, size_t minimum) {
  if (block == NULL) raise %(bad-arg);
  if (minimum <= block.cap) return;
  size_t cap = _grown_capacity(block.cap, minimum);
  size_t size = _allocation_size(block.width, cap);
  if (!size) {
    size_t width = block.width;
    raise %(size-limit (width $width) (cap $cap));
  }
  _attach(block, Scope.realloc(_allocation(block), size));
  block.cap = cap;
}

/* Doubles `cap` until `minimum` fits, or returns `minimum` when doubling
   would overflow. */
static size_t _grown_capacity(size_t cap, size_t minimum) {
  if (!cap) cap = 1;
  while (cap < minimum) {
    if (cap > SIZE_MAX / 2) return minimum;
    cap *= 2;
  }
  return cap;
}

/** Ensures `bytes` can hold at least `minimum` elements and returns its base.
    Growth may relocate storage, so callers must use the returned `Bytes` and
    discard earlier views. Raises: the same causes as `Block.reserve`; failure
    leaves the original view live.
*/
inline Self Bytes.reserve(Self bytes, size_t minimum) {
  Block block = bytes;
  block.reserve(minimum);
  return block.bytes;
}

/** Returns the number of elements stored in `b`. */
inline size_t Block.len(Block b) => b != NULL ? b.length : 0;

/** Returns how many elements `b` can hold without growing. */
inline size_t Block.capacity(Block b) => b != NULL ? b.cap : 0;

/** Returns nonzero when `block` contains at least one element. */
int Block.truth(Block block) => block != NULL && block.length != 0;

// removal

/** Shortens `block` to at most `length` elements. */
inline void Block.truncate(Block block, size_t length) {
  if (block != NULL && length < block.length) block.length = length;
}

/** Removes every element from `block` without releasing capacity. */
inline void Block.clear(Block block) {
  if (block != NULL) block.length = 0;
}

/** Removes the final element of `b`, copying it to `out` when present.
    Returns zero for a null or empty `Block` and leaves `out` unchanged. A null
    `out` still removes a present element.
*/
inline int Block.try_pop(Block b, void *out) {
  if (b == NULL || !b.length) return 0;
  size_t index = b.length - 1;
  if (out) memmove(out, (unsigned char *) b.bytes + index * b.width, b.width);
  b.length = index;
  return 1;
}

/** Removes the final element through `bytes` as `Block.try_pop` does. */
inline int Bytes.try_pop(Bytes bytes, void *out) => bytes.block().try_pop(out);

/** Removes the final element of `block` when present. */
inline void Block.pop(Block block) {
  block.try_pop(NULL);
}

// lifecycle

/** Allocates an empty `Block` for elements of `width` bytes.
    Raises: `<bad-arg>` when `width` is zero, `<size-limit>` when the initial
    allocation size cannot be represented, or `<alloc-fail>` when allocation
    fails.
*/
Block Block.new(size_t width) {
  if (!width) raise %(bad-arg);
  Block block = Scope.malloc(sizeof(struct Block));
  *block = (struct Block) {.width = width, .length = 0, .cap = 1};
  size_t size = _allocation_size(width, block.cap);
  if (!size) raise %(size-limit (width $width));
  _attach(block, Scope.malloc(size));
  return block;
}

/** Allocates empty byte storage for elements of `width` bytes.
    The result is the base view of a `Scope`-owned `Block`. Methods that may
    grow it return the current `Bytes` pointer, which callers must keep.
    Raises: the same causes as `Block.new`.
*/
Bytes Bytes.new(size_t width) => Block.new(width).bytes;

/** Releases the `Block` and its backing storage, invalidating every alias. */
void Block.free(Block b) {
  if (b == NULL) return;
  if (b.bytes != NULL) Scope.free(_allocation(b));
  Scope.free(b);
}

/** Moves `block` and its backing allocation into `scope`.
    This preserves the `Block` and `Bytes` pointers and contents while changing
    which `Scope` ends their lifetime. `Context` export calls this method
    instead of assuming a `Block` is one allocation.
    For a nonnull `Block`, raises `<bad-arg>` for a null destination slot, or
    `<alloc-fail>` when an empty slot cannot acquire a `Scope`. Failure leaves
    ownership unchanged.
*/
void Block.move_to(Block block, Scope *scope) {
  if (block == NULL) return;
  if (block.bytes != NULL) Scope.move(_allocation(block), scope);
  Scope.move(block, scope);
}

/** Ends the owned lifetime when a managed local leaves its block. */
void Block.cleanup(Block value) { value.free(); }

/** Releases the Block backing a managed Bytes view. */
void Bytes.cleanup(Bytes value) { value.free(); }
