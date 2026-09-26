#include "x2c.x"

$(import "meta-call-effects.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  int initial = argc - 1;
  printf("ordered %d %d\n", $(ordered 0), ordered(initial));
  printf("repeated %d %d\n", $(repeated 0), repeated(initial));
  printf("discarded %d %d\n", $(discarded 0), discarded(initial));
  printf("snapshot %d %d\n", $(snapshot 0), snapshot(initial));
  printf("identity %d %d\n", $(identity 0), identity(initial));
  printf("subject %d %d\n", $(subject 0), subject(initial));
  printf("destructured %d %d\n", $(destructured 0), destructured(initial));
  printf("loop %d %d\n", $(loop 0), loop(initial));
  return 0;
}
