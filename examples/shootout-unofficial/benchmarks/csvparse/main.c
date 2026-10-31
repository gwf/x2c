/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *make_csv(int rows) {
  size_t capacity = (size_t)rows * 96 + 1, used = 0;
  char *text = malloc(capacity);
  for (int i = 0; i < rows; i++)
    used += snprintf(text + used, capacity - used,
      "\"point %d, sample\",%.6f,,%.6f,\"tag %d\",%.6f\n",
      i, (i % 101) / 7.0, (i % 97) / 11.0, i % 13, (i % 89) / 5.0);
  return text;
}

static int parse(char *line, double *sum) {
  char *fields[6], *start = line;
  int count = 0, quoted = 0;
  for (char *p = line; ; p++) {
    if (*p == '"') quoted = !quoted;
    if ((!*p || (*p == ',' && !quoted)) && count < 6) {
      fields[count++] = start;
      if (!*p) break;
      *p = 0; start = p + 1;
    }
  }
  if (count != 6) return 0;
  *sum += strtod(fields[1], 0) + strtod(fields[3], 0) + strtod(fields[5], 0);
  return 1;
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int rows = atoi(argv[1]), runs = atoi(argv[2]);
  char *csv = make_csv(rows);
  double checksum = 0;
  for (int run = 0; run < runs; run++) {
    char *copy = strdup(csv), *line = copy;
    while (line && *line) {
      char *end = strchr(line, '\n');
      if (end) *end = 0;
      parse(line, &checksum);
      line = end ? end + 1 : 0;
    }
    free(copy);
  }
  printf("%.6f\n", checksum);
  free(csv);
  return 0;
}
