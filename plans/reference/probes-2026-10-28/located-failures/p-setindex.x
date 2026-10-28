int main(void) {
  Array a = [1, 2, 3];
  a[7] = 9;
  printf("after write: %s\n", a.repr().str());
  Map m = {"k": 1};
  String s = m["zz"];
  return 0;
}
