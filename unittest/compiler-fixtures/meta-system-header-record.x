#include <time.h>

meta int header_record_probe(int offset) {
  struct timespec value = { .tv_sec = 7 + offset, .tv_nsec = 9 };
  return value.tv_sec + value.tv_nsec;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $header_record_probe(0),
         header_record_probe(argc - 1));
  return 0;
}
