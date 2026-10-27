static void name(String *out) {
  *out = "x";
}

static void forward(String text) {
  name(text);
}

int main(void) {
  forward("a");
  return 0;
}
