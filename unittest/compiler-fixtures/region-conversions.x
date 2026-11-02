#include "x2c.x"
#include "typed-array.x"
#include "typed-map.x"

// A destination of another family converts its value into fresh storage.
Array from_list(List items) {
  auto {
    Array a = items;
    return a;
  }
  return NULL;
}

Array from_iter(Iter values) {
  auto {
    Array a = values;
    return a;
  }
  return NULL;
}

Array from_typed(ArrayInt values) {
  auto {
    Array a = values;
    return a;
  }
  return NULL;
}

ArrayInt to_typed(Array values) {
  auto {
    ArrayInt a = values;
    return a;
  }
  return NULL;
}

MapIntInt to_typed_map(Map entries) {
  auto {
    MapIntInt m = entries;
    return m;
  }
  return NULL;
}

Map from_typed_map(MapIntInt entries) {
  auto {
    Map m = entries;
    return m;
  }
  return NULL;
}

// A returned value converts as an assigned one does.
Array returned_list(List items) {
  auto {
    return items;
  }
  return NULL;
}

Array assigned_list(List items) {
  Array a = NULL;
  auto {
    a = items;
  }
  return a;
}

// An argument converts for the parameter that receives it.
static void keep(Map entries, Array values) {
  entries["values"] = values;
}

void passed(Map entries, List items) {
  auto {
    keep(entries, items);
  }
}

// A view of the same storage converts nothing.
Block viewed(Array values) {
  auto {
    Block b = values;
    return b;
  }
  return NULL;
}
