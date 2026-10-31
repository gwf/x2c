static int _export_string(int c, Var v) { return c + 1; }
static int _export_list(int c, Var v) { return c + 2; }
static int _export_array(int c, Var v) { return c + 3; }
static int _export_map(int c, Var v) { return c + 4; }

static int export(int c, Var v) {
  expand %(
    (string "_export_string")
    (list   "_export_list")
    (array  "_export_array")
    (map    "_export_map")
  )
  macro Stmt(Expr $tag, Name $export) {
    if (v is $tag) return $export(c, v);
  }
  return 0;
}

int main(void) {
  Array array = [];
  Map map = {};
  printf("%d %d %d %d\n", export(10, "s"), export(10, %()),
    export(10, array), export(10, map));
  return 0;
}
