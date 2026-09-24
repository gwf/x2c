#include "x2c.x"

typedef Array Items;
typedef Map Entries;
typedef Var Box;
typedef List Values;
typedef String Text;
typedef Symbol Key;

meta static Items meta_items(void) {
  return [(unsigned char) 255, "ready", <key>, %(3 4)];
}
meta static Entries meta_entries(void) {
  Map values = {};
  values[<name>] = "ready";
  values["number"] = (short) -7;
  values[%(1 2)] = 42;
  return values;
}
meta static Array meta_empty_array(void) { return []; }
meta static Map meta_empty_map(void) { return {}; }
meta static Box meta_boxed(void) { return [9]; }
meta static Array meta_keep(Array value) { return value; }

meta static Map meta_nested(void) {
  Map values = {};
  values["rows"] = [[1, 2], [(unsigned char) 3, 2.5]];
  values["index"] = {even: [0, 2], odd: [1]};
  values["scalars"] = [0.25f, (short) -7, %(x [9])];
  values["blank"] = (Map) {};
  return values;
}
meta static Map meta_null_entry(void) {
  Map values = {};
  values["k"] = {};
  return values;
}

meta static Values meta_values(void) { return %(6 7); }
meta static Text meta_text(void) { return "ready"; }
meta static Key meta_key(void) { return <key>; }

static Array items(void) { return $meta_items(); }
static Map entries(void) { return $meta_entries(); }

int main(void) {
  Array a = items(), b = items(), alias = a;
  printf("array %d %d %d %s %s %d\n",
    (void *) a != (void *) b, (void *) alias == (void *) a,
    (int) a[0], (String) a[1], ((Symbol) a[2]).str(),
    ((List) a[3]).len());
  printf("tags %s %s\n", a[0].tag().str(), a[3].tag().str());
  a[0] = 7;
  printf("mutation %d %d %d\n", (int) alias[0], (int) b[0],
    (void *) meta_keep(a) == (void *) a);
  Map m = entries(), n = entries(), same = m;
  printf("map %d %d %s %d %d %s\n",
    (void *) m != (void *) n, (void *) same == (void *) m,
    (String) m[<name>], (int) m["number"], (int) m[%(1 2)],
    m["number"].tag().str());
  m["number"] = 8;
  printf("map-mutation %d %d\n", (int) same["number"],
    (int) n["number"]);
  Array e = $meta_empty_array(), f = $meta_empty_array();
  Map x = $meta_empty_map(), y = $meta_empty_map();
  e.push(1); x[<x>] = 1;
  printf("empty %d %d %d %d\n", e != f, x != y,
    (int) f.len(), (int) y.len());
  Var boxed = $meta_boxed();
  Array boxed_array = boxed;
  printf("boxed %s %d\n", boxed.tag().str(), (int) boxed_array[0]);
  Array lisp = $(meta_empty_array);
  printf("lisp %d\n", (int) lisp.len());
  Map t = $meta_nested(), u = $meta_nested();
  printf("nested %s %s %d\n", t["rows"].repr(),
    t["index"][<even>].repr(), ((List) t["scalars"][2]).len());
  Array row = t["rows"][0], odd = t["index"][<odd>];
  row.push(3); odd.push(3);
  Map blank = t["blank"];
  blank[<x>] = 1;
  printf("fresh %s %s %s %s\n", u["rows"][0].repr(),
    u["index"][<odd>].repr(), u["blank"].repr(), t["rows"][0].repr());
  printf("scalar-tags %s %s %s %s\n", t["scalars"][0].tag().str(),
    t["scalars"][1].tag().str(), t["rows"][1][0].tag().str(),
    t["rows"][1][1].tag().str());
  Map native_null = meta_null_entry(), meta_null = $meta_null_entry();
  printf("null %s %s\n", native_null.repr(), meta_null.repr());
  Values values = $meta_values(); Text text = $meta_text();
  Key key = $meta_key();
  printf("aliases %d %s %d %s\n", values.len(), text,
    text.len(), key.str());
  return 0;
}
