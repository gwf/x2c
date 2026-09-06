
int main(int argc, char **argv) {
  List lst = %(1 2 3);
  foreach(int i, lst) {
    printf("v = %d\n", i);
  }
  return 0;
}
