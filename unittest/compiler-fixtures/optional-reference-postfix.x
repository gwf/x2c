static void bump(int &?value) {
  value++;
}

int main(void) {
  int value = 1;
  bump(value);
  return 0;
}
