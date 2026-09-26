#include "x2c.x"

$(import "meta-iterators.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%s\n%d %d %d %d %d\n%d %d %d\n%d %d\n", mapped(10).str(),
    keys_valid(), independent(), lazy(), live_map(), x2c_truth(), folds(),
    void_consumers(), found(), $sequences(0), sequences(argc - 1));
  printf("%d %d\n", $split_walks(0), split_walks(argc - 1));
  return 0;
}
