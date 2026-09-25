static int read(unsigned &?count) {
  unsigned value = count;
  return (int) value;
}

int main(void) {
  unsigned count = 3;
  return read(count);
}
