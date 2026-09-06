#include <stdint.h>
#include <stdio.h>

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  FILE *input = fopen(argv[1], "rb");
  if (!input) return 1;
  uint64_t hash = UINT64_C(1469598103934665603);
  unsigned char bytes[16384];
  size_t count;
  while ((count = fread(bytes, 1, sizeof(bytes), input)))
    for (size_t i = 0; i < count; i++) {
      hash ^= bytes[i];
      hash *= UINT64_C(1099511628211);
    }
  int failed = ferror(input);
  fclose(input);
  if (failed) return 1;
  printf("%016llx\n", (unsigned long long) hash);
  return 0;
}
