meta static int hidden(int n) => n + 10;
macro Expression $kept() using hidden => $hidden(3);
int main(void) {
  int hidden = 99;
  printf("%d %d\n", $kept(), hidden);
  return 0;
}
