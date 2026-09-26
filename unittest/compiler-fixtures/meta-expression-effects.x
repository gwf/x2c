#include "x2c.x"

meta int discarded(int n) { (void) (n = n + 2); return n; }
meta int branch(int n) { (void) (n ? (n += 2) : (n += 3)); return n; }
meta int short_circuit(int n) { (void) (n && (n += 2)); return n; }
meta int assign_return(int n) { return (n = n + 2); }

int main(int argc, char **argv) {
  (void) argv;
  int one = argc, zero = one - 1;
  printf("discarded %d %d %d\n", $discarded(1), discarded(1), discarded(one));
  printf("branch-yes %d %d %d\n", $branch(1), branch(1), branch(one));
  printf("branch-no %d %d %d\n", $branch(0), branch(0), branch(zero));
  printf("short-yes %d %d %d\n",
    $short_circuit(1), short_circuit(1), short_circuit(one));
  printf("short-no %d %d %d\n",
    $short_circuit(0), short_circuit(0), short_circuit(zero));
  printf("return %d %d %d\n",
    $assign_return(1), assign_return(1), assign_return(one));
  return 0;
}
