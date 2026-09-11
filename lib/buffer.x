/*  buffer.x -- growable text buffer with indentation support

    Copyright (c) 2025 Gary William Flake

    `Buffer` is a text-only builder over `Block` storage. It tracks the byte
    position and leading indentation of the current line, supports nested
    tabstops, and provides bulk character writes for formatting hot paths.
    Embedded NUL is rejected because `Buffer` materializes canonical `String`s.
*/

#pragma once
$(import "error-macros.xmacro")
#include "common.x"
#include "block.x"

#include <stddef.h>

/** Holds mutable text plus an indentation stack in two `Block`s.
    The `Buffer` and both `Block`s belong to the `Scope` active at construction
    unless `Buffer.move_to` transfers them. `content.bytes` is a borrowed,
    non-NUL-terminated view that any growing write may invalidate. `pos` and
    `_indent` describe the current final line; `Buffer.free` invalidates the
    `Buffer` and both backing `Block`s.
*/
typedef struct Buffer {
  Block content, indents, size_t padding, pos, _indent;
} *Buffer;

protocol Cleanup(Buffer);

#pragma private

#include "exception.x"
#include "scope.x"
#include "string.x"

#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void _recompute_line_state(Buffer buf) {
  size_t length = buf.content.length;
  if (!length) {
    buf.pos = 0;
    buf._indent = 0;
    return;
  }
  const char *text = buf.content.bytes, size_t start = length;
  while (start && text[start - 1] != '\n') start--;
  buf.pos = length - start;
  buf._indent = 0;
  while (buf._indent < buf.pos && text[start + buf._indent] == ' ')
    buf._indent++;
}

/** Allocates an empty `Buffer` whose `pad` method writes `padding` spaces.
    Raises: `<alloc-fail>` or `<size-limit>` while allocating its fixed-width
    backing `Block`s.
*/
Buffer Buffer.new(size_t padding) {
  Buffer buf = Scope.malloc(sizeof(struct Buffer));
  buf.content = Block.new(sizeof(char));
  /* Eager allocation keeps the indent Block in the Buffer's owning scope
     rather than the scope active at the first push. */
  buf.indents = Block.new(sizeof(size_t));
  buf.padding = padding;
  buf.pos = 0;
  buf._indent = 0;
  return buf;
}

/** Releases `buf` and both backing `Block`s, invalidating every alias. */
void Buffer.free(Buffer buf) {
  if ((void *) buf == NULL) return;
  if ((void *) buf.content != NULL) buf.content.free();
  if ((void *) buf.indents != NULL) buf.indents.free();
  Scope.free(buf);
}

/** Moves `buf` and both owned `Block`s into `scope`, keeping their identities.
    Their lifetime then ends with the destination `Scope` unless freed earlier.
    For a nonnull `Buffer`, raises `<bad-arg>` for a null destination slot, or
    `<alloc-fail>` when an empty slot cannot acquire a `Scope`. Failure leaves
    ownership unchanged.
*/
void Buffer.move_to(Buffer buf, Scope *scope) {
  if ((void *) buf == NULL) return;
  buf.content.move_to(scope);
  buf.indents.move_to(scope);
  Scope.move(buf, scope);
}

/** Reserves room for at least `minimum` output bytes in `buf`.
    Growth may invalidate a borrowed `content.bytes` pointer but does not
    change the `Buffer` or content `Block` identity.
    Raises: `<size-limit>` or `<alloc-fail>` when the requested capacity
    cannot be provided.
*/
Self Buffer.reserve(Self buf, size_t minimum) {
  buf.content.reserve(minimum);
  return buf;
}

/** Empties `buf` and its indentation stack without releasing capacity. */
Self Buffer.clear(Self buf) {
  buf.content.clear();
  if (buf.indents) buf.indents.clear();
  buf.pos = 0;
  buf._indent = 0;
  return buf;
}

/** Appends `length` bytes from `text` to `buf`.
    `text` may be a live range inside `buf.content`, including across growth.
    A zero length accepts a null source. Raises: `<bad-arg>` for a null
    nonempty source or embedded NUL, or `<size-limit>` or `<alloc-fail>` when
    the `Buffer` cannot grow. Argument, allocation, and size failures leave the
    text and line state unchanged.
*/
Self Buffer.write_len(Self buf, const char *text, size_t length) {
  if (!length) return buf;
  if (!text) raise %(bad-arg);
  if (length == 1) {
    char value = *text;
    if (!value) raise %(bad-arg (value 0));
    buf.content.append(&value, 1);
    if (value == '\n') {
      buf.pos = 0;
      buf._indent = 0;
    }
    else {
      if (value == ' ' && buf.pos == buf._indent) buf._indent++;
      buf.pos++;
    }
    return buf;
  }
  if (memchr(text, '\0', length)) raise %(bad-arg (value 0));
  const char *newline = memchr(text, '\n', length);
  size_t line_start = SIZE_MAX;
  while (newline) {
    line_start = (size_t) (newline - text) + 1;
    size_t remaining = length - line_start;
    newline = memchr(text + line_start, '\n', remaining);
  }
  size_t next_pos, next_indent;
  if (line_start != SIZE_MAX) {
    next_pos = length - line_start;
    next_indent = 0;
    while (next_indent < next_pos && text[line_start + next_indent] == ' ')
      next_indent++;
  }
  else {
    next_pos = buf.pos + length;
    next_indent = buf._indent;
    if (buf.pos == buf._indent) {
      size_t leading = 0;
      while (leading < length && text[leading] == ' ') leading++;
      next_indent += leading;
    }
  }
  buf.content.append(text, length);
  buf.pos = next_pos;
  buf._indent = next_indent;
  return buf;
}

/** Appends NUL-terminated `text` to `buf`.
    Raises: the same causes as `Buffer.write_len`.
*/
Self Buffer.write(Self buf, const char *text) {
  if (!text) raise %(bad-arg);
  return buf.write_len(text, strlen(text));
}

/** Appends formatted text to `buffer`.
    Raises: `<format>` when formatting fails, `<alloc-fail>` when staging
    storage cannot be allocated, or a cause from `Buffer.write_len`. Existing
    text is preserved and this call appends nothing on failure.
*/
Self Buffer.printf(Self buf, const char *format, ...) {
  /* Stage the common short case on the stack. Longer output is measured and
     allocated before writing, so formatting never truncates. */
  char stack[160], va_list args;
  va_start(args, format);
  int length = vsnprintf(stack, sizeof stack, format, args);
  va_end(args);
  if (length < 0) raise %(format);
  if ((size_t) length < sizeof stack) return buf.write_len(stack, length);
  char *bytes = Scope.malloc((size_t) length + 1);
  defer Scope.free(bytes);
  va_start(args, format);
  int written = vsnprintf(bytes, (size_t) length + 1, format, args);
  va_end(args);
  if (written < 0) raise %(format);
  buf = buf.write_len(bytes, length);
  return buf;
}

/** Appends the non-NUL byte `value` to `buf`.
    Raises: `<bad-arg>` when `value` is NUL, or `<size-limit>` or
    `<alloc-fail>` when the `Buffer` cannot grow. These failures leave text and
    line state unchanged.
*/
Self Buffer.write_char(Self buf, char value) {
  if (!value) raise %(bad-arg (value 0));
  buf.content.append(&value, 1);
  if (value == '\n') {
    buf.pos = 0;
    buf._indent = 0;
  }
  else {
    if (value == ' ' && buf.pos == buf._indent) buf._indent++;
    buf.pos++;
  }
  return buf;
}

/** Appends `count` copies of the non-NUL byte `value` to `buf`.
    A zero count accepts any value. Raises: `<bad-arg>` when a nonzero write
    uses NUL, or `<size-limit>` or `<alloc-fail>` when the `Buffer` cannot
    grow.
    These failures leave text and line state unchanged.
*/
Self Buffer.write_repeat(Self buf, char value, size_t count) {
  if (!count) return buf;
  if (!value) raise %(bad-arg (value 0));
  buf.content.append_fill(&value, count);
  if (value == '\n') {
    buf.pos = 0;
    buf._indent = 0;
  }
  else {
    if (value == ' ' && buf.pos == buf._indent) buf._indent += count;
    buf.pos += count;
  }
  return buf;
}

/** Removes the final `count` bytes from `buf`. */
Self Buffer.unwrite(Self buf, size_t count) {
  if (count > buf.content.length) count = buf.content.length;
  buf.content.truncate(buf.content.length - count);
  _recompute_line_state(buf);
  return buf;
}

/** Appends the configured number of padding spaces. */
Self Buffer.pad(Self buf) => buf.write_repeat(' ', buf.padding);

/** Appends a newline to `buf`. */
Self Buffer.newline(Self buf) => buf.write_char('\n');

/** Appends spaces through `buf`'s current indentation depth. */
Self Buffer.indent(Self buf) => buf.write_repeat(' ', buf.tabstop());

/** Appends a newline followed by current indentation. */
Self Buffer.newline_indent(Self buf) => buf.newline().indent();

/** Pushes the current column as a later indentation depth.
    Raises: `<size-limit>` or `<alloc-fail>` if the stack cannot grow. Failure
    leaves the stack unchanged.
*/
Self Buffer.push(Self buf) {
  buf.indents.append(&buf.pos, 1);
  return buf;
}

/** Pops one indentation depth from `buf`'s stack when present. */
Self Buffer.pop(Self buf) {
  if (buf.indents) buf.indents.try_pop(NULL);
  return buf;
}

/** Returns the most recently pushed indentation depth. */
size_t Buffer.tabstop(Buffer buf) {
  if (!buf.indents || !buf.indents.length) return 0;
  size_t *indents = buf.indents.bytes;
  return indents[buf.indents.length - 1];
}

/** Writes the byte at normalized `index` to `out` when it exists.
    Negative indexes count from the end. Returns zero for a null `Buffer`, null
    output, or missing byte and leaves `out` unchanged.
*/
int Buffer.try_get(Buffer buf, ptrdiff_t index, char *out) {
  if (!buf || !out) return 0;
  size_t normalized;
  if (index < 0) {
    size_t distance = (size_t) (-(index + 1)) + 1;
    if (distance > buf.content.length) return 0;
    normalized = buf.content.length - distance;
  }
  else {
    normalized = index;
    if (normalized >= buf.content.length) return 0;
  }
  *out = ((char *) buf.content.bytes)[normalized];
  return 1;
}

/** Returns the byte at `index`, or NUL when `index` is out of range.
    Prefer `Buffer.try_get` to distinguish an out-of-range index from a NUL
    byte.
*/
char Buffer.get(Buffer buf, ptrdiff_t index) {
  char out;
  return buf.try_get(index, &out) ? out : '\0';
}

/** Returns the number of bytes currently stored in `buf`. */
size_t Buffer.len(Buffer buf) => buf ? buf.content.length : 0;

/** Returns a canonical copy of `buf`'s text without consuming the `Buffer`.
    A null or empty `Buffer` returns the null `String`. A nonempty result
    remains
    live until its owning `String` pool is released.
    Raises: `<size-limit>` when the text exceeds `String`'s representation, or
    `<alloc-fail>` while canonicalizing it.
*/
String Buffer.str(Buffer buf) {
  if (!buf || !buf.content.length) return NULL;
  if (buf.content.length > INT_MAX) {
    size_t length = buf.content.length, int limit = INT_MAX;
    raise %(size-limit (size $length) (limit $limit));
  }
  return String.new_len(buf.content.bytes, (int) buf.content.length);
}

/** Returns `buf.str()` and frees `buf`.
    `Buffer.str` performs the conversion, so the result is a canonical `String`
    copied out of the `Buffer`. Its storage is not adopted. `buf` is released
    on success and when the conversion transfers an `Error`.
    Raises: the same causes as `Buffer.str`.
*/
String Buffer.str_free(Buffer buf) {
  defer buf.free();
  return buf;
}

/** Returns the readable representation of `Buffer`.
    Raises: the same causes as `Buffer.str` or `String` rendering.
*/
String Buffer.repr(Buffer buf) {
  if (!buf || !buf.content.length) return String.repr(NULL);
  String str = buf;
  return str.repr();
}

/** Returns nonzero when `buffer` contains at least one byte. */
int Buffer.truth(Buffer buffer) =>
  (void *) buffer != NULL && buffer.content.length != 0;

/** Ends the owned lifetime when a managed local leaves its block. */
void Buffer.cleanup(Buffer value) { value.free(); }
