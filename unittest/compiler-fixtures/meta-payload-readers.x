/* Raw payload readers return zero for the other numeric family. */
#include "x2c.x"

meta int payload_readers(int unused) {
  (void) unused;
  Var integer = 7, floating = 3.5, text = "x";
  return integer.integer() == 7 && floating.floating() == 3.5
    && floating.integer() == 0 && integer.floating() == 0.0
    && text.integer() == 0 && text.floating() == 0.0;
}
int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $payload_readers(0), payload_readers(argc - 1));
  return 0;
}
