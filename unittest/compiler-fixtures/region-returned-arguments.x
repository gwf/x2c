#include "x2c.x"
#include "typed-array.x"

// Each operation returns the storage it was given.
Array reversed(void) {
  auto {
    Array a = [1, 2, 3];
    return a.reverse();
  }
  return NULL;
}

Array sorted(void) {
  auto {
    Array a = [3, 1, 2];
    return a.sort();
  }
  return NULL;
}

Array sorted_with(Func compare) {
  auto {
    Array a = [3, 1, 2];
    return a.sort_with(compare);
  }
  return NULL;
}

Array sorted_by(Func key) {
  auto {
    Array a = [3, 1, 2];
    return a.sort_by(key);
  }
  return NULL;
}

Array replaced(void) {
  auto {
    Array a = [1, 2, 3];
    return a.setslice(0, 1, [9]);
  }
  return NULL;
}

Map merged(void) {
  auto {
    Map m = {"a": 1};
    return m.merge({"b": 2});
  }
  return NULL;
}

Buffer printed(void) {
  auto {
    Buffer b = Buffer.new(0);
    return b.printf("%d", 1);
  }
  return NULL;
}

ArrayInt reversed_typed(void) {
  auto {
    ArrayInt a = %[1, 2];
    return a.reverse();
  }
  return NULL;
}

// The caller's own Array outlives the region.
Array reversed_parameter(Array a) {
  auto {
    return a.reverse();
  }
  return NULL;
}

Array updated_array(void) {
  auto {
    Array a = [];
    return a.update_n(0);
  }
  return NULL;
}

Map updated_map(void) {
  auto {
    Map m = {};
    return m.update_n(0);
  }
  return NULL;
}

Map merged_with(Map other) {
  auto {
    Map m = {};
    return m.merge_with(other, NULL);
  }
  return NULL;
}

Map merged_with_null(Map other) {
  auto {
    Map m = NULL;
    return m.merge_with(other, NULL);
  }
  return NULL;
}

Array updated_parameter(Array a) {
  auto {
    return a.update_n(0);
  }
  return NULL;
}
