int main(void) {
  int x2c_exception_push = 7;
  try { if (x2c_exception_push != 7) return 1; }
  finally {}
  return 0;
}
