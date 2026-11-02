#include "x2c.x"
#include "args.x"
#include "encoding.x"
#include "typed-array.x"
#include "typed-map.x"
#include "url.x"

// Each runtime producer returns fresh storage of the region that called it.
Block decoded(String text) {
  auto {
    Block b = text.base64_decode_bytes();
    return b;
  }
  return NULL;
}

void boxed(Array out, ArrayInt values) {
  auto {
    out.push(values.array());
  }
}

MapIntInt created(void) {
  auto {
    MapIntInt m = MapIntInt.new();
    return m;
  }
  return NULL;
}

ArrayInt copied(ArrayInt values) {
  auto {
    ArrayInt a = values.copy();
    return a;
  }
  return NULL;
}

Map query(String text) {
  auto {
    Map m = Url.parse_query(text);
    return m;
  }
  return NULL;
}

Map options(List args, List spec) {
  auto {
    Map m = Args.parse(args, spec);
    return m;
  }
  return NULL;
}

Block encoded(Array symbols) {
  auto {
    Block b = SymbolSet.encode(symbols);
    return b;
  }
  return NULL;
}

// A typed Map moved to the caller's Scope outlives the region.
MapIntInt kept_map(Scope *keep) {
  auto {
    MapIntInt m = MapIntInt.new();
    m.move_to(keep);
    return m;
  }
  return NULL;
}
