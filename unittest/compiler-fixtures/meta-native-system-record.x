#include <time.h>

meta int timespec_get(struct timespec *, int);

meta int native_record_probe(int offset) {
  struct timespec value = {0};
  int status = timespec_get(&value, 1);
  return offset == 0 && status == 1 && value.tv_sec > 0 &&
         value.tv_nsec >= 0 && value.tv_nsec < 1000000000;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $native_record_probe(0),
         native_record_probe(argc - 1));
  return 0;
}
