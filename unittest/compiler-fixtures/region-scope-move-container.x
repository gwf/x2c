#include "x2c.x"

// Scope.move relinks only the record; the buffers stay in the region.
Array moved_array(Scope *keep) {
  auto {
    Array values = [1, 2, 3];
    Scope.move(values, keep);
    return values;
  }
  return NULL;
}

Map moved_map(Scope *keep) {
  auto {
    Map names = {"a": 1};
    Scope.move(names, keep);
    return names;
  }
  return NULL;
}

Buffer moved_buffer(Scope *keep) {
  auto {
    Buffer text = Buffer.new(0);
    Scope.move(text, keep);
    return text;
  }
  return NULL;
}

// A record with no buffers of its own moves whole.
typedef struct Entry { int id; } *Entry;

Entry moved_record(Scope *keep) {
  auto {
    Entry entry = xcalloc(1, sizeof(struct Entry));
    Scope.move(entry, keep);
    return entry;
  }
  return NULL;
}
