/*  file.x -- `File` I/O operations and stream handling

    Copyright (c) 2025 Gary William Flake

    Wraps native FILE streams while preserving stream-handle identity for hash,
    equality, and ordering. Raw read and copy operations report status
    separately from bytes written. `String` adapters canonicalize through the
    active pool chain. A returned identity may already belong to an ancestor
    and lives until its actual owning pool is released; NULL is the empty
    `String`. Other return values, stream position, buffering, and error
    indicators follow stdio unless an operation documents different status
    behavior. Stdin, Stdout, and Stderr are initialized as borrowed process
    streams.
 */
#pragma once

#include <sys/stat.h>
#include <stdio.h>
#include "common.x"

$(import "error-macros.xmacro")

/** Names a native stdio stream handle.
    A successful open returns an owned stream. `Stdin`, `Stdout`, and `Stderr`
    are borrowed. An alias does not retain a stream, and closing one
    invalidates every alias.
*/
typedef FILE *File;

protocol FILE *(T) {
  int   T.close(T)                                   = fclose;
  int   T.pclose(T)                                  = pclose;
  int   T.eof(T)                                     = feof;
  int   T.error(T)                                   = ferror;
  int   T.flush(T)                                   = fflush;
  int   T.purge(T)                                   = fflush;
  int   T.getc(T)                                    = fgetc;
  int   T.fileno(T)                                  = fileno;
  int   T.getpos(T, fpos_t *)                        = fgetpos;
  int   T.setpos(T, const fpos_t *)                  = fsetpos;
  int   T.seek(T, long, int)                         = fseek;
  int   T.seeko(T, off_t, int)                       = fseeko;
  int   T.setvbuf(T, char *, int, size_t)            = setvbuf;
  int   T.va_printf(T, const char *, va_list)        = vfprintf;
  int   T.va_scanf(T, const char *, va_list)         = vfscanf;
  long  T.tell(T)                                    = ftell;
  off_t T.tello(T)                                   = ftello;
  void  T.clearerr(T)                                = clearerr;
  void  T.rewind(T)                                  = rewind;
  void  T.setbuf(T, char *)                          = setbuf;
}

/*  The adoption row sits beside the declaration. The native alias #defines
    then emit into this unit's header. */
protocol FILE *(File);

extern File Stdin, Stdout, Stderr;

/** Reports whether a raw `File` read produced bytes, reached clean EOF, or
    rejected its arguments. Host read failures transfer `<io-fail>` instead of
    returning `FILE_READ_ERROR`.
*/
typedef enum FileReadStatus {
  FILE_READ_ERROR = -1,
  FILE_READ_EOF = 0,
  FILE_READ_DATA = 1
} FileReadStatus;

#pragma private

#include "string.x"
#include "block.x"
#include "buffer.x"
#include "exception.x"
#include "var.x"
#include "iter.x"

#include <unistd.h>
#include <stdarg.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void _open_error(Symbol operation, const char *path, int error) {
  if (!path) raise %(io-fail (operation $operation) (errno $error));
  String resource = path;
  if (error == ENOENT)
    raise %(not-found (operation $operation) (path $resource)
            (errno $error));
  raise %(io-fail (operation $operation) (path $resource) (errno $error));
}

static void _io_error(Symbol operation, int error) {
  raise %(io-fail (operation $operation) (errno $error));
}

static void _check_read(File file) {
  if (!ferror(file)) return;
  int error = errno;
  _io_error(<read>, error);
}

static File _open_path(const char *path, const char *mode, Symbol op) {
  if (!path || !mode) raise %(bad-arg (operation $op));
  File file = fopen(path, mode);
  if (file) return file;
  int error = errno;
  _open_error(op, path, error);
}

static int _string_allocation(size_t length) {
  if (length >= INT_MAX) raise %(size-limit (size $length));
  return (int) length + 1;
}

static void _validate_text(const void *bytes, size_t length) {
  if (!length) return;
  if (!bytes) raise %(bad-arg (owner "File.text") (why "null bytes"));
  if (memchr(bytes, '\0', length))
    raise %(bad-arg (owner "File.text") (why "embedded NUL"));
}

/* Every text adapter ends here. Byte input then cannot produce a String
   whose visible length differs from the consumed length. `intern_free`
   consumes the temporary allocation and returns the canonical String. */
static String _finish_text(String result, size_t length) {
  _validate_text(result, length);
  char *out = result;
  out[length] = '\0';
  return result.intern_free();
}

static String _text(const void *bytes, size_t length) {
  if (!length) return NULL;
  if (!bytes) raise %(bad-arg (owner "File.text") (why "null bytes"));
  int allocation = _string_allocation(length);
  String result = String.malloc(allocation);
  memcpy(result, bytes, length);
  return _finish_text(result, length);
}

static inline void _block_putc(Block block, unsigned char value) {
  if (block.length == SIZE_MAX) raise %(size-limit);
  size_t expected = block.length + 1;
  if (block.length == block.cap) block.reserve(expected);
  ((unsigned char *) block.bytes)[block.length] = value;
  block.length = expected;
}

/* Writes every byte or raises. `written` accumulates the accepted bytes, so
   a catch still sees the partial count a failed write left behind. */
static void _write_bytes(
  File file, const void *ptr, size_t size, size_t *written) {
  const unsigned char *bytes = ptr, size_t offset = 0;
  defer if (written) *written += offset;
  while (offset < size) {
    size_t count = fwrite(bytes + offset, 1, size - offset, file);
    if (!count) {
      int error = errno;
      _io_error(<write>, error);
    }
    offset += count;
  }
}

static void _append_text(Block content, const void *bytes, size_t count) {
  if (count >= INT_MAX - content.length) {
    size_t size = content.length + count;
    raise %(size-limit (size $size));
  }
  _validate_text(bytes, count);
  content.append(bytes, count);
}

/* A regular file's observed extent is a sizing hint. After reading that many
   bytes, probe once for concurrent growth before accepting EOF. */
static String _regular_text(File file, size_t requested) {
  int allocation = _string_allocation(requested);
  String first = String.malloc(allocation), Block content = NULL;
  defer {
    if ((void *) first != NULL) first.free();
    if ((void *) content != NULL) content.free();
  }
  size_t count = fread(first, 1, requested, file);
  _check_read(file);
  if (count < requested) {
    String result = _finish_text(first, count);
    first = NULL;
    return result;
  }
  int next = fgetc(file);
  if (next == EOF) {
    _check_read(file);
    String result = _finish_text(first, count);
    first = NULL;
    return result;
  }
  content = Block.new(sizeof(char));
  if (count >= INT_MAX - 1) raise %(size-limit (size $count));
  _append_text(content, first, count);
  char *head = first;
  head[count] = '\0';
  first.free();
  first = NULL;
  _block_putc(content, (unsigned char) next);
  unsigned char bytes[BUFSIZ];
  while ((count = fread(bytes, 1, sizeof(bytes), file)) > 0)
    _append_text(content, bytes, count);
  _check_read(file);
  String result = _text(content.bytes, content.length);
  content.free();
  content = NULL;
  return result;
}

/** Reads the remaining text, then closes `file` on return or transfer.
    The close result is discarded, so a close failure is not reported. The
    stream and all of its aliases are invalid afterward.
    Raises: the same causes as `File.string`.
*/
String File.string_close(File file) {
  defer file.close();
  return file.string();
}

/** Opens the filesystem path named by `fname`.
    The caller owns a successful stream and must close it. A missing path
    raises `<not-found>`; another host failure raises `<io-fail>`; and a null
    path or mode raises `<bad-arg>`. Host failures carry the path, operation,
    and captured errno.
*/
File String.open(String fname, const char *mode) =>
  _open_path(fname, mode, <open>);

/** Wraps an open file descriptor in a `File` stream.
    On success the returned stream owns `fildes`, which must be closed through
    the stream. On failure the caller still owns the descriptor. A host failure
    raises `<io-fail>` with the operation and captured errno; a null mode
    raises `<bad-arg>`.
*/
File File.fdopen(int fildes, const char *mode) {
  if (!mode) {
    Symbol operation = <fdopen>;
    raise %(bad-arg (operation $operation));
  }
  File file = fdopen(fildes, mode);
  if (file) return file;
  int error = errno;
  _open_error(<fdopen>, NULL, error);
}

/** Opens `path` with the requested stdio mode.
    The caller owns a successful stream and must close it. A missing path
    raises `<not-found>`; another host failure raises `<io-fail>`; and a null
    path or mode raises `<bad-arg>`. Host failures carry the path, operation,
    and captured errno.
*/
File File.open(const char *path, const char *mode) =>
  _open_path(path, mode, <open>);

/** Opens a process pipe with the requested mode.
    The caller owns a successful stream and must finish it with `File.pclose`
    to close the pipe and collect the child status. A host failure raises
    `<not-found>` for `ENOENT` or `<io-fail>` otherwise, with the command as
    `path`, operation, and captured errno; a null command or mode raises
    `<bad-arg>`.
*/
File File.popen(const char *cmd, const char *mode) {
  if (!cmd || !mode) raise %(bad-arg (operation popen));
  File file = popen(cmd, mode);
  if (file) return file;
  int error = errno;
  _open_error(<popen>, cmd, error);
}

/** Reuses `file` for a newly opened path and mode.
    This consumes the original stream even when the native reopen fails; after
    a transfer the caller must not close or reuse the old handle. A missing
    path raises `<not-found>`; another host failure raises `<io-fail>`; and a
    null stream, path, or mode raises `<bad-arg>`. Host failures carry the
    path, operation, and captured errno.
*/
Self File.reopen(Self file, const char *path, const char *mode) {
  if (!file || !path || !mode) raise %(bad-arg (operation reopen));
  File opened = freopen(path, mode, file);
  if (opened) return opened;
  int error = errno;
  _open_error(<reopen>, path, error);
}

/** Reads a native line into `str` and returns `str`, or NULL at EOF or error.
    At most `size - 1` bytes are stored followed by NUL, and a newline is kept
    when it fits.
*/
inline char *File.gets(File file, char *str, int size) =>
  fgets(str, size, file);

/** Writes one byte and returns it as an unsigned char, or EOF on failure. */
inline int File.putc(File file, int c) => fputc(c, file);

/** Writes a NUL-terminated C string.
    Returns a nonnegative value on success or EOF on failure.
*/
inline int File.puts(File file, const char *s) => fputs(s, file);

/** Writes one native `int` and returns `w`, or EOF on a short write. */
inline int File.putw(File file, int w) =>
  fwrite(&w, sizeof(w), 1, file) == 1 ? w : EOF;

/** Reads and returns one native `int`, or EOF when a full word is unavailable.
    A stored value equal to EOF is indistinguishable from the sentinel without
    inspecting the stream indicators.
*/
inline int File.getw(File file) {
  int word;
  return fread(&word, sizeof(word), 1, file) == 1 ? word : EOF;
}

/** Requests line buffering for `file` and returns zero.
    The underlying `setvbuf` result is intentionally not exposed.
*/
inline int File.setlinebuf(File file) {
  setvbuf(file, NULL, _IOLBF, 0);
  return 0;
}

/** Pushes one byte back and returns it, or EOF when it cannot be pushed. */
inline int File.ungetc(File file, int c) => ungetc(c, file);
/** Reads up to `nitems` elements and returns the number read. */
inline size_t File.read(File file, void *ptr, size_t size, size_t nitems) =>
  fread(ptr, size, nitems, file);

/** Writes up to `nitems` elements and returns the number written. */
inline size_t File.write(
  File file, const void *ptr, size_t size, size_t nitems) =>
    fwrite(ptr, size, nitems, file);

/** Installs caller-supplied buffering, or disables buffering for a null `buf`.
    A nonnull buffer is borrowed until the stream closes or buffering changes.
*/
inline void File.setbuffer(File file, char *buf, int size) {
  setbuffer(file, buf, size);
}

/** Writes metadata for `file` into `buf`.
    Returns zero on success or -1 on a native error.
*/
inline int File.stat(File file, struct stat *buf) => fstat(file.fileno(), buf);

/** Formats values into `file`.
    Returns the character count or a negative value on failure.
*/
int File.printf(File file, const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  int result = file.va_printf(format, ap);
  va_end(ap);
  return result;
}

/** Scans values from `file`, returning the assignment count or EOF. */
int File.scanf(File file, const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  int result = file.va_scanf(format, ap);
  va_end(ap);
  return result;
}

/** Reads up to `size` bytes into a canonical `String`.
    Reading starts at the current stream position and returns NULL when no
    bytes are read. Prefer `File.read_into` for raw bytes and explicit status.
    Raises: `<bad-arg>` for a negative `size`, `<size-limit>` when the
    requested `String` cannot be represented, `<bad-arg>` when the bytes
    contain
    an embedded NUL, `<io-fail>` on a stream read error, or `<alloc-fail>`
    while constructing the result.
*/
String File.readblock(File file, long size) {
  if (size < 0) raise %(bad-arg (owner "File.readblock") (size $size));
  size_t requested = (size_t) size;
  int allocation = _string_allocation(requested);
  String result = String.malloc(allocation), owned = result;
  defer if ((void *) owned != NULL) owned.free();
  size_t count = file.read(result, 1, requested);
  _check_read(file);
  String output = _finish_text(result, count);
  owned = NULL;
  return output;
}

/** Reads one raw line into caller-owned byte storage.
    Valid inputs clear `dest`, then include the newline when one is read.
    `Null`
    inputs or a `Block` width other than one report ERROR without raising and
    leave a nonnull `dest` unchanged; a read failure transfers instead, leaving
    its partial bytes in `dest`.
    Raises: `<io-fail>` on a stream read error, or `<size-limit>` or
    `<alloc-fail>` when the destination cannot grow.
*/
FileReadStatus File.readline_into(File file, Block dest) {
  if (!file || (void *) dest == NULL || dest.width != sizeof(char))
    return FILE_READ_ERROR;
  dest.clear();
  int failed, error;
  {
    /* One logical line is one locked operation. The defer also unlocks before
       a read or allocation cause transfers out of this function. */
    flockfile(file);
    defer funlockfile(file);
    int c;
    while ((c = getc_unlocked(file)) != EOF) {
      _block_putc(dest, (unsigned char) c);
      if (c == '\n') break;
    }
    failed = ferror(file);
    error = failed ? errno : 0;
  }
  if (failed) _io_error(<read>, error);
  return dest.length ? FILE_READ_DATA : FILE_READ_EOF;
}

/** Reads the remaining stream bytes into caller-owned storage.
    Valid inputs clear `dest` first. `Null` inputs or a `Block` width other
    than
    one report ERROR without raising and leave a nonnull `dest` unchanged; a
    read failure transfers instead, leaving its partial bytes in `dest`.
    Raises: `<io-fail>` on a stream read error, or the cause reported by
    `Block.append` when the destination cannot grow.
*/
FileReadStatus File.read_into(File file, Block dest) {
  if (!file || (void *) dest == NULL || dest.width != sizeof(char))
    return FILE_READ_ERROR;
  dest.clear();
  unsigned char bytes[BUFSIZ], size_t count;
  while ((count = fread(bytes, 1, sizeof(bytes), file)) > 0)
    dest.append(bytes, count);
  _check_read(file);
  return dest.length ? FILE_READ_DATA : FILE_READ_EOF;
}

/** Writes every requested byte unless the stream reports failure.
    A null stream or a null pointer with nonzero size returns zero without
    raising; every other outcome returns nonzero or transfers. A transfer may
    leave a prefix already written.
    Raises: `<io-fail>` on a short or failed write, which does not return
    here.
*/
int File.write_all(File file, const void *ptr, size_t size) {
  if (!file || (!ptr && size)) return 0;
  _write_bytes(file, ptr, size, NULL);
  return 1;
}

/** Copies the remaining bytes from `source` to `output`.
    A null stream returns zero without raising; every other outcome returns
    nonzero or transfers. When `copied` is nonnull it receives the number of
    bytes written, including the partial count a catch observes after a
    failure.
    Raises: `<io-fail>` on a source read or destination write failure.
*/
int File.copy_to(File source, File output, size_t *copied) {
  if (copied) *copied = 0;
  if (!source || !output) return 0;
  unsigned char bytes[BUFSIZ], size_t count;
  while ((count = fread(bytes, 1, sizeof(bytes), source)) > 0)
    _write_bytes(output, bytes, count, copied);
  _check_read(source);
  return 1;
}

/** Reads one raw line into a canonical `String`.
    Includes the newline when present. Clean EOF and `FILE_READ_ERROR` both map
    to NULL. Prefer `File.readline_into` or `File.iter` when raw status and
    bytes should remain separate.
    Raises: `<io-fail>` on a stream read error, `<bad-arg>` when returned bytes
    are not valid `String` text, `<size-limit>` when the line cannot be
    represented, or `<alloc-fail>` while constructing the result.
*/
String File.readline(File file) {
  Block line = Block.new(sizeof(char));
  defer line.free();
  line.reserve(BUFSIZ);
  FileReadStatus status = file.readline_into(line);
  String result = status == FILE_READ_DATA
    ? _text(line.bytes, line.length) : NULL;
  return result;
}

/** Reads the remaining stream into one canonical `String`.
    Starts at the current position, advances through EOF, and returns NULL when
    no bytes remain.
    Raises: `<io-fail>` on a stream read error, `<bad-arg>` when returned bytes
    contain an embedded NUL, `<size-limit>` when the `String` cannot be
    represented, or `<alloc-fail>` while constructing the result.
*/
String File.string(File file) {
  struct stat statbuf = {0};
  off_t position = file.tello();
  if (position >= 0 && file.stat(&statbuf) == 0 && S_ISREG(statbuf.st_mode) &&
      statbuf.st_size > position) {
    uintmax_t remaining = (uintmax_t) (statbuf.st_size - position);
    _string_allocation(remaining);
    return _regular_text(file, (size_t) remaining);
  }
  Block content = Block.new(sizeof(char));
  defer content.free();
  unsigned char bytes[BUFSIZ], size_t count;
  while ((count = fread(bytes, 1, sizeof(bytes), file)) > 0)
    _append_text(content, bytes, count);
  _check_read(file);
  return _text(content.bytes, content.length);
}

static int _next(Iter iter, Var *out) {
  File file = iter.obj;
  if (!file) return 0;
  Block line = iter.state;
  if ((void *) line == NULL) return 0;
  int keep = 0;
  defer if (!keep) {
    line.free();
    iter.state = void;
  }
  FileReadStatus status = file.readline_into(line);
  if (status != FILE_READ_DATA) return 0;
  String text = _text(line.bytes, line.length);
  *out = text;
  keep = 1;
  return 1;
}

/** Returns an iterator over `File`.
    The caller supplies `dest`; each pull yields one `String` under the
    canonical
    pool-chain lifetime described above, including its newline when present.
    The iterator borrows `file`, which must remain open through every pull.
    Clean EOF exhausts the iterator and releases its line storage. Abandoning
    it before exhaustion leaves that `Scope`-owned `Block` until its `Scope` is
    cleaned up. A null `dest` returns NULL; a null `file` initializes `dest` as
    exhausted.
    Raises: `<alloc-fail>` while initializing. Pulling may raise the same
    causes as `File.readline`; none return to the pull, and a transfer releases
    the iterator's line storage.
*/
Iter File.iter(File file, Iter dest) {
  if ((void *) dest == NULL) return NULL;
  if (!file) return dest.init((Var) {0}, NULL, (Var) { .u64 = 0 });
  Block line = Block.new(sizeof(char)), int keep = 0;
  defer if (!keep) line.free();
  line.reserve(BUFSIZ);
  dest.init(file, _next, line);
  keep = 1;
  return dest;
}

/** Returns a handle-identity hash consistent with `File.equal`. */
unsigned File.hash(File file) => Var.new(<p48>, file).hash();

/** Reports whether `x` and `y` are the same native stream handle. */
int File.equal(File x, File y) => (void *) x == (void *) y;

/** Returns a readable handle and descriptor representation without reading. */
String File.repr(File file) {
  if (!file) return Var.pointer_string(file);
  return %"<File:%p, fd:%d>".printf(file, file.fileno());
}

/** Returns the display `String` for `file`.
    A nonnull file follows `File.string`. It advances through EOF, returns a
    canonical result under the pool-chain lifetime described above or NULL
    when empty, and transfers the same causes. A null handle returns its
    pointer representation without reading.
*/
String File.str(File file) => file ? file.string() : Var.pointer_string(file);

/** Appends the readable pointer representation of `file` to `out`. */
Buffer File.write_repr(File file, Buffer out) {
  if (!file) return Var.write_pointer_repr(file, out);
  return out.printf("<File:%p, fd:%d>", file, file.fileno());
}

/** Publishes the process's borrowed standard streams as `File` globals.
    The globals do not take ownership or arrange cleanup of the native streams.
*/
void File.initialize(void) {
  Stdin = stdin;
  Stdout = stdout;
  Stderr = stderr;
}
