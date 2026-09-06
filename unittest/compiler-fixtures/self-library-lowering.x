#include "x2c.x"
#include "typed-array.x"

typedef Bytes Packet;
typedef Array Scores;
typedef ArrayInt Measurements;
typedef Buffer TextBuffer;
typedef Map Headers;
typedef String Text;
typedef Atom Name;
typedef Var Dynamic;
typedef Iter Cursor;
typedef File LogFile;

int Packet.done(Packet value) { return value != NULL; }
int Scores.done(Scores value) { return value != NULL; }
int Measurements.done(Measurements value) { return value != NULL; }
int TextBuffer.done(TextBuffer value) { return value != NULL; }
int Headers.done(Headers value) { return value != NULL; }
int Text.done(Text value) { return value != NULL; }
int Name.done(Name value) { return value is not void; }
int Dynamic.done(Dynamic value) { return value is not void; }
int Cursor.done(Cursor value) { return value != NULL; }
int LogFile.done(LogFile value) { return value != NULL; }

int bytes_chain(Packet value, const void *source) {
  return value.reserve(8).append(source, 1).append_fill(source, 1)
    .push(source).done();
}

int array_chain(Scores value, Scores other) {
  return value.update_n(0).copy().getslice(0, 0, 1)
    .setslice(0, 0, other).remslice(0, 0).splice(0, 0, other)
    .concat(other).reverse().sort().done();
}

int packed_array_chain(Measurements value, Measurements other) {
  return value.copy().getslice(0, 0, 1).setslice(0, 0, other)
    .remslice(0, 0).splice(0, 0, other).concat(other).reverse().done();
}

int buffer_chain(TextBuffer value) {
  return value.reserve(32).clear().write_len("", 0).write("")
    .printf("%s", "").write_char('x').write_repeat('y', 1).unwrite(1)
    .pad().newline().indent().newline_indent().push().pop().done();
}

int map_chain(Headers value, Headers other) {
  return value.update_n(0).copy().merge(other).done();
}

int string_chain(Text value) {
  return value.promote().intern().done();
}

int string_owned_chain(Text value) {
  return value.intern_free().done();
}

int atom_chain(Name value) { return value.promote().done(); }

int var_chain(Dynamic value, Scope *scope) {
  return value.move_wide_to(scope).done();
}

int iter_chain(Cursor value, Var object, IterNextFn next, Cursor dest) {
  (void) dest;
  return value.init(object, next, 0).done();
}

int file_chain(LogFile value, const char *path, const char *mode) {
  return value.reopen(path, mode).done();
}
