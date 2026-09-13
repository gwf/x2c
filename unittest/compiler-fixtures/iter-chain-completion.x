int main(void) {
  Scope.retain();

  List fluent = range(1, 4, 1).list();

  List source = %(1 2 3 4 5);
  Array collected = source.iter().array();

  int nested = 0;
  foreach(int left, range(1, 2, 1))
    foreach(int right, range(10, 11, 1))
      nested += left + right;

  struct Iter explicit_storage;
  List explicit = range(1, 3, 1, &explicit_storage).list();

  printf("%d %d %d %d\n", fluent.len(), collected.len(), nested,
         explicit.len());
  Scope.release();
  return 0;
}
