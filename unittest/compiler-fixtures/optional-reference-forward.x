static void increment(int &value) {
  value += 1;
}

static void increment_if_present(int &?value) {
  increment(value);
}

int main(void) {
  increment_if_present(NULL);
  return 0;
}
