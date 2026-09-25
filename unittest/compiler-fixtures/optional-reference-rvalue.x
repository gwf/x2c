static void set(int &?value) {
  if (!value) return;
  value = 5;
}

int main(void) {
  set(5);
  return 0;
}
