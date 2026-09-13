static Var double_value(Var value) {
  return value * 2;
}

static int is_even(Var value) {
  return value % 2 == 0;
}

static Var add_pair(Var left, Var right) {
  return left + right;
}

int main(void) {
  Scope.retain();

  List fluent = range(1, 4, 1)
    .map(double_value).filter(is_even).list();
  Var paired = range(1, 3, 1)
    .map2(range(10, 12, 1), add_pair).sum();

  int nested = 0;
  foreach(int left, range(1, 2, 1).map(double_value))
    foreach(int right, range(10, 11, 1).head(1))
      nested += left + right;

  struct Iter mixed_source_storage;
  List mixed = range(1, 3, 1, &mixed_source_storage)
    .map(double_value).list();

  struct Iter source_storage, map_storage, filter_storage;
  Iter source = range(1, 4, 1, &source_storage);
  Iter mapped = source.map(double_value, &map_storage);
  Iter filtered = mapped.filter(is_even, &filter_storage);
  List explicit = filtered.list();

  printf("%d %d %d %d %d\n", fluent.len(), paired.int(), nested,
         mixed.len(), explicit.len());
  Scope.release();
  return 0;
}
