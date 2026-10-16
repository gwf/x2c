#include "x2c.x"

/* `Args` is a free name where the template is written. Where it lands,
   `Args` names a type, so `Args.from_argv` calls `Args_from_argv`. */
macro Unit $define_count(Name $count) {
  static int $count(int argc, char **argv) {
    List args = Args.from_argv(argc, argv);
    return (int) args.len();
  }
}

#include "args.x"

$define_count(count);

int main(void) {
  char *argv[] = {"program", "one", "two"};
  printf("%d\n", count(3, argv));
  return 0;
}
