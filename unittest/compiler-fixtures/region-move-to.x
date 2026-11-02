#include "x2c.x"

// `move_to` moves a container's record and buffers to the caller's Scope.
static Array kept_array(Scope *keep) {
  auto {
    Array values = [1, 2, 3];
    values.move_to(keep);
    return values;
  }
  return NULL;
}

static Map kept_map(Scope *keep) {
  auto {
    Map names = {"a": 1};
    names.move_to(keep);
    return names;
  }
  return NULL;
}

static Buffer kept_buffer(Scope *keep) {
  auto {
    Buffer text = Buffer.new(0);
    text.write("text");
    text.move_to(keep);
    return text;
  }
  return NULL;
}

static Block kept_block(Scope *keep) {
  auto {
    Block ids = Block.new(sizeof(int));
    int id = 7;
    ids.push(&id);
    ids.move_to(keep);
    return ids;
  }
  return NULL;
}

// `move_wide_to` moves a wide number's box.
static Var kept_box(Scope *keep, long big) {
  auto {
    Var v = big;
    v.move_wide_to(keep);
    return v;
  }
  return 0;
}

int main(void) {
  Scope keep = NULL;
  Array values = kept_array(&keep);
  Map names = kept_map(&keep);
  Buffer text = kept_buffer(&keep);
  Block ids = kept_block(&keep);
  Var big = kept_box(&keep, 1L << 60);
  // Storage the regions freed would be reused here.
  Array scratch = [9, 9, 9, 9, 9, 9, 9, 9];
  int *first = ids.bytes;
  printf(
    "%s %s %s %d %s %zu\n", values.repr(), names.repr(), text.str(),
    first[0], big.repr(), scratch.len());
  Scope.destroy(keep);
  return 0;
}
