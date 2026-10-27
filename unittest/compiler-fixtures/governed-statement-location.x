static void take(int *out) {
  *out = 1;
}

static void forward(int &?count) {
  if (count)
    take(count);
}

int main(void) {
  int count = 0;
  forward(count);
  return count;
}
