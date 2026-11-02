#include "x2c.x"

// Each copy is fresh storage of the region that made it.
Array copied(Array src) {
  auto {
    Array a = src.copy();
    return a;
  }
  return NULL;
}

Array concatenated(Array src) {
  auto {
    Array a = src.concat(src);
    return a;
  }
  return NULL;
}

Array sliced(Array src) {
  auto {
    Array a = src[1:];
    return a;
  }
  return NULL;
}

Array removed(Array src) {
  auto {
    Array a = src.remslice(0, 1);
    return a;
  }
  return NULL;
}

Array spliced(Array src) {
  auto {
    Array a = src.splice(0, 1, NULL);
    return a;
  }
  return NULL;
}

Array mapped(Array src, Func f) {
  auto {
    Array a = src.map(f);
    return a;
  }
  return NULL;
}

Array mapped_pairs(Array src, Func f) {
  auto {
    Array a = src.map2(src, f);
    return a;
  }
  return NULL;
}

Map copied_map(Map src) {
  auto {
    Map m = src.copy();
    return m;
  }
  return NULL;
}

Map sized_map(void) {
  auto {
    Map m = Map.new_capacity(8);
    return m;
  }
  return NULL;
}

// A conversion or a box is fresh storage too.
void converted(Array out, List items, ulong n, long double x) {
  auto {
    out.push(items.array());
    out.push(ulong.var(n));
    out.push(Var.box_ulong(n));
    out.push(Var.box_long_long(n));
    out.push(Var.box_ulong_long(n));
    out.push(Var.box_long_double(x));
    out.push(Var.clone_wide(out[0]));
  }
}

// A named pool bracket is a region.
List pooled(void) {
  Pool.open_named("scratch");
  List items = $(1, 2);
  Pool.close();
  return items;
}
