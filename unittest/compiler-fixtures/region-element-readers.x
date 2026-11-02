#include "x2c.x"
#include "substring-map.x"

Array indexed(void) {
  auto {
    Array holder = [], inner = [];
    holder.push(inner);
    return holder[0];
  }
  return NULL;
}
Array getter(void) {
  auto {
    Array holder = [], inner = [];
    holder.push(inner);
    return holder.getindex(0);
  }
  return NULL;
}
Array shifted(void) {
  auto {
    Array holder = [], inner = [];
    holder.push(inner);
    return holder.shift();
  }
  return NULL;
}
Array taken(void) {
  auto {
    Array holder = [], inner = [];
    holder.push(inner);
    return holder.take_last();
  }
  return NULL;
}
Array removed(void) {
  auto {
    Array holder = [], inner = [];
    holder.push(inner);
    return holder.remove(0);
  }
  return NULL;
}
Array mapped(void) {
  auto {
    Map holder = {};
    Array inner = [];
    holder["key"] = inner;
    return holder["key"];
  }
  return NULL;
}
Array map_getter(void) {
  auto {
    Map holder = {};
    Array inner = [];
    holder["key"] = inner;
    return holder.get("key");
  }
  return NULL;
}
Array deleted(void) {
  auto {
    Map holder = {};
    Array inner = [];
    holder["key"] = inner;
    return holder.del("key");
  }
  return NULL;
}
MapSubInt substring_map(void) {
  auto { return MapSubInt.new(); }
  return NULL;
}
Map substring_strings(void) {
  auto { MapSubInt map = MapSubInt.new(); return map.strings(); }
  return NULL;
}

// Freeing a temporary container does not free its borrowed elements.
Var copied_element(Array outer) {
  Array copy = auto outer.copy();
  return copy[0];
}
Var listed_element(List outer) {
  Array copy = auto outer;
  return copy[0];
}

Var mutable_copy_element(Array outer) {
  auto Array copy = outer.copy();
  return copy[0];
}
Var mutable_list_element(List outer) {
  auto Array copy = outer;
  return copy[0];
}
Array owned_auto_element(void) {
  auto {
    auto Array holder = [];
    Array inner = [];
    holder.push(inner);
    return holder[0];
  }
  return NULL;
}
void pooled_into_outer(Array outer) {
  {
    Pool.open();
    outer.push(String.printf("%d", 7));
    Pool.close();
  }
}

Var read_element(Array holder) => holder[0];
void store_element(Array holder, Array target) { target.push(holder[0]); }
Var borrowed_helper_return(Array outer) {
  auto Array copy = outer.copy();
  return read_element(copy);
}
void borrowed_helper_store(Array outer, Array target) {
  auto Array copy = outer.copy();
  store_element(copy, target);
}
Array escaped_helper_return(void) {
  auto {
    Array holder = [], inner = [];
    holder.push(inner);
    return read_element(holder);
  }
  return NULL;
}
