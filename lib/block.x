/*  block.x -- checked dynamic storage for fixed-width elements

    Copyright (c) 2025 Gary William Flake

    `Block` maintains the length and capacity invariants for contiguous
    fixed-width storage. `Bytes` exposes the same allocation through its data
    pointer and a hidden back-pointer. Capacity growth raises where the
    failure is detected, leaves storage unchanged, and does not return to the
    call.

    A self-source may name any initialized range inside reserved capacity.
    Growth rebases that range after reallocating the owning block.

    The declared `Block` protocol supplies `Bytes`'s generated `truth`, `pop`,
    `free`, and `truncate` members through the `Bytes.block` storage view.
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

static int _allocation_size(size_t width, size_t cap, size_t *out) {
  if (!width || cap > (SIZE_MAX - sizeof(Block)) / width) return 0;
  *out = sizeof(Block) + width * cap;
  return 1;
}

/** Allocates an empty `Block` for elements of `width` bytes.
    Raises: `<bad-arg>` when `width` is zero, `<size-limit>` when the initial
    allocation size cannot be represented, or `<alloc-fail>` when allocation
    fails.
*/
Block Block.new(size_t width) {
  if (!width) raise %(bad-arg);
  Block block = Scope.malloc(sizeof(struct Block));
  block.width = width;
  block.length = 0;
  block.cap = 1;
  size_t size;
  if (!_allocation_size(width, block.cap, &size))
    raise %(size-limit (width $width));
  unsigned char *allocation = Scope.malloc(size);
  *((Block *) allocation) = block;
  block.bytes = allocation + sizeof(Block);
  return block;
}

/** Allocates empty byte storage for elements of `width` bytes.
    The result is the base view of a `Scope`-owned `Block`. Methods that may
    grow it return the current `Bytes` pointer, which callers must keep.
    Raises: the same causes as `Block.new`.
*/
Bytes Bytes.new(size_t width) => Block.new(width).bytes;

/** Returns the stable `Block` that owns the live `bytes` base pointer.
    An interior or stale pointer is invalid; NULL returns NULL.
*/
inline Block Bytes.block(Bytes bytes) {
  if ((void *) bytes == NULL) return NULL;
  unsigned char *data = bytes;
  return *((Block *) (data - sizeof(Block)));
}

/** Ensures `block` can hold at least `minimum` elements.
    The `Block` handle and contents remain stable, but growth may replace
    `block.bytes` and invalidate saved `Bytes` or element pointers.
    Raises: `<bad-arg>` when `block` is null, `<size-limit>` when the requested
    capacity cannot be represented, or `<alloc-fail>` when growth fails.
    These failures leave the `Block` unchanged.
*/
void Block.reserve(Block block, size_t minimum) {
  if ((void *) block == NULL) raise %(bad-arg);

  if (minimum <= block.cap) return;
  size_t cap = block.cap ? block.cap : 1;
  while (cap < minimum) {
    if (cap > SIZE_MAX / 2) {
      cap = minimum;
      break;
    }
    cap *= 2;
  }
  size_t size;
  if (!_allocation_size(block.width, cap, &size)) {
    size_t width = block.width;
    raise %(size-limit (width $width) (cap $cap));
  }
  unsigned char *allocation = (unsigned char *) block.bytes - sizeof(Block);
  allocation = Scope.realloc(allocation, size);
  *((Block *) allocation) = block;
  block.bytes = allocation + sizeof(Block);
  block.cap = cap;
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

/** Shortens `block` to at most `length` elements. */
inline void Block.truncate(Block block, size_t length) {
  if ((void *) block != NULL && length < block.length) block.length = length;
}

/** Removes every element from `block` without releasing capacity. */
inline void Block.clear(Block block) {
  if ((void *) block != NULL) block.length = 0;
}

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
  if ((void *) b == NULL) raise %(bad-arg);

  if (!count) return;
  if (count <= b.cap - b.length) {
    size_t copy_size = count * b.width;
    unsigned char *destination =
      (unsigned char *) b.bytes + b.length * b.width;
    if (!source) memset(destination, 0, copy_size);
    else memmove(destination, source, copy_size);
    b.length += count;
    return;
  }
  if (count > SIZE_MAX - b.length || count > SIZE_MAX / b.width) {
    size_t width = b.width;
    raise %(size-limit (width $width) (count $count));
  }

  size_t copy_size = count * b.width, source_offset = 0, int internal = 0;
  if (source) {
    /* realloc preserves the entire allocation, not only logical content. */
    size_t offset = (uintptr_t) source - (uintptr_t) b.bytes;
    size_t capacity_size = b.cap * b.width;
    if (offset < capacity_size) {
      source_offset = offset;
      if (copy_size > capacity_size - source_offset)
        raise %(bad-arg (count $count));

      internal = 1;
    }
  }

  size_t old_length = b.length, new_length = old_length + count;
  b.reserve(new_length);
  unsigned char *destination =
    (unsigned char *) b.bytes + old_length * b.width;
  if (!source) memset(destination, 0, copy_size);
  else if (internal)
    memmove(
      destination, (unsigned char *) b.bytes + source_offset, copy_size);
  else memcpy(destination, source, copy_size);
  b.length = new_length;
}

/** Appends `count` elements to `bytes` and returns its current base pointer.
    Callers must use the return because growth may relocate storage. Raises:
    the same causes as `Block.append`; failure leaves the original view live
   .
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
    self-source
    element on a nonzero append; `<size-limit>` when the new extent cannot be
    represented; or `<alloc-fail>` when growth fails. These failures leave the
    `Block` unchanged.
*/
void Block.append_fill(Block b, const void *element, size_t count) {
  if ((void *) b == NULL) raise %(bad-arg);

  if (!count) return;
  if (!element) raise %(bad-arg);

  if (count > SIZE_MAX - b.length) raise %(size-limit (count $count));
  size_t old_length = b.length, new_length = old_length + count;
  size_t element_offset = 0, int internal = 0;
  uintptr_t start = (uintptr_t) b.bytes, pointer = (uintptr_t) element;
  size_t capacity_size = b.cap * b.width;
  if (pointer >= start && pointer - start < capacity_size) {
    size_t logical_size = old_length * b.width;
    element_offset = pointer - start;
    if (element_offset > logical_size ||
        b.width > logical_size - element_offset) {
      raise %(bad-arg);
    }
    internal = 1;
  }
  b.reserve(new_length);
  if (internal) element = (unsigned char *) b.bytes + element_offset;
  unsigned char *destination =
    (unsigned char *) b.bytes + old_length * b.width;
  if (b.width == 1)
    memset(destination, *((const unsigned char *) element), count);
  else
    for (size_t i = 0; i < count; i++)
      memmove(destination + i * b.width, element, b.width);
  b.length = new_length;
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

/** Removes the final element of `block`, copying it to `out` when present.
    Returns zero for a null or empty `Block` and leaves `out` unchanged. A null
    `out` still removes a present element.
*/
inline int Block.try_pop(Block block, void *out) {
  if ((void *) block == NULL || !block.length) return 0;
  size_t index = block.length - 1;
  if (out)
    memmove(
      out, (unsigned char *) block.bytes + index * block.width, block.width);
  block.length = index;
  return 1;
}

/** Removes the final element through `bytes` as `Block.try_pop` does. */
inline int Bytes.try_pop(Bytes bytes, void *out) => bytes.block().try_pop(out);

/** Appends one copied element; storage and failures follow `Block.append`. */
inline void Block.push(Block block, const void *source) {
  block.append(source, 1);
}

/** Appends one element and returns the possibly relocated `Bytes` base. */
inline Self Bytes.push(Self bytes, const void *source) =>
  bytes.append(source, 1);

/** Removes the final element of `block` when present. */
inline void Block.pop(Block block) {
  block.try_pop(NULL);
}

/** Releases the `Block` and its backing storage, invalidating every alias. */
void Block.free(Block block) {
  if ((void *) block == NULL) return;
  if ((void *) block.bytes != NULL)
    Scope.free((unsigned char *) block.bytes - sizeof(Block));
  Scope.free(block);
}

/** Moves `block` and its backing allocation into `scope`.
    This preserves the `Block` and `Bytes` pointers and contents while changing
    which `Scope` ends their lifetime. `Context` export calls this method
    instead
    of assuming a `Block` is one allocation.
    For a nonnull `Block`, raises `<bad-arg>` for a null destination slot, or
    `<alloc-fail>` when an empty slot cannot acquire a `Scope`. Failure leaves
    ownership unchanged.
*/
void Block.move_to(Block block, Scope *scope) {
  if ((void *) block == NULL) return;
  if ((void *) block.bytes != NULL)
    Scope.move((unsigned char *) block.bytes - sizeof(Block), scope);
  Scope.move(block, scope);
}

/** Returns the number of elements stored in `block`. */
inline size_t Block.len(Block block) =>
  (void *) block != NULL ? block.length : 0;

/** Returns nonzero when `block` contains at least one element. */
int Block.truth(Block block) => (void *) block != NULL && block.length != 0;

/** Returns how many elements `block` can hold without growing. */
inline size_t Block.capacity(Block block) =>
  (void *) block != NULL ? block.cap : 0;

/** Ends the owned lifetime when a managed local leaves its block. */
void Block.cleanup(Block value) { value.free(); }

/** Releases the Block backing a managed Bytes view. */
void Bytes.cleanup(Bytes value) { value.free(); }
