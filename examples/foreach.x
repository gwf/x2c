/*  foreach.x -- iterate over a List */

int main(void) {
  List numbers = %(1 2 3);
  foreach (int i in numbers) {
    printf("v = %d\n", i);
  }
  return 0;
}
