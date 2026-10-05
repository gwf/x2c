#include "datum.x"

meta static Array null_items(void) => [Var.null()];

meta static Map null_entries(void) {
  Map data = {};
  data[Var.null()] = 7;
  data["missing"] = Var.null();
  return data;
}

meta static List null_list(void) {
  return List.cons(Var.null(), NULL);
}

int main(void) {
  Array native = null_items(), inserted = $null_items();
  Map entries = $null_entries();
  List list = $null_list();
  printf("%d %d %ld %d %d\n", native[0].is_null(), inserted[0].is_null(),
         entries[Var.null()].integer(), entries["missing"].is_null(),
         list.car().is_null());
  Buffer frame = Buffer.new(0);
  Array data = [Var.null(), %(), %(x2c.null)];
  datum_frame(frame, data);
  size_t used = 0;
  Var decoded = void;
  datum_unframe(frame.str(), used, decoded);
  Array values = decoded;
  printf("%d %d %d %d\n", values[0].is_null(), values[1].is_nil(),
         values[2].list() === %(x2c.null), used == frame.len());
  int pointed = 7;
  printf("pointer %d\n", datum_frame(frame, Var.new(<u32*>, &pointed)));
  frame.free();
  return 0;
}
