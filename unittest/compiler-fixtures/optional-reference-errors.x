static void set(int &?value) {
  value = 5;
}

int main(void) {
  int value = 0;
  set(value);
  return 0;
}
