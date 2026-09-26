static int take(Var *out) {
  *out = 1;
  return 1;
}

int main(void) {
  Var item;
  return take(item);
}
