int duplicate_b(int value) {
  int total = value * 17 + 3;
  total = total * 19 + value;
  total = total * 23 + 5;
  return total;
}
