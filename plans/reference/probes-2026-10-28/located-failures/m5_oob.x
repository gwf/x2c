int main(void) {
  Array a = [1, 2, 3];
  printf("read: %s\n", a[7].repr());
  int v = a[7];
  printf("converted: %d\n", v);
  a[7] = 9;
  printf("after write: %s\n", a.repr());
  return 0;
}
