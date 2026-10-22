/* Benchmark-only multi-file entry point; reuse V0's counting implementation. */
#define main words_v0_single_file_main
#include "words-v0.c"
#undef main

int main(int argc, char **argv) {
  Counts counts = {0};
  char *line = NULL;
  size_t capacity = 0;
  int status = EXIT_SUCCESS;
  for (int i = 1; i < argc; ++i) {
    FILE *input = fopen(argv[i], "r");
    if (!input) {
      perror(argv[i]);
      status = EXIT_FAILURE;
      break;
    }
    while (getline(&line, &capacity, input) != -1) count_line(&counts, line);
    int finished = feof(input);
    fclose(input);
    if (!finished) {
      fprintf(stderr, "Could not finish reading %s\n", argv[i]);
      status = EXIT_FAILURE;
      break;
    }
  }
  free(line);
  if (status == EXIT_SUCCESS) print_top_ten(&counts);
  free_counts(&counts);
  return status;
}
