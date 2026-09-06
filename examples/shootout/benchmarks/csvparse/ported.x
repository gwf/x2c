/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/csvparse-ported ported.x
 *   /tmp/csvparse-ported 50000 10
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static String _make_csv(int rows) {
  Buffer text = Buffer.new(0).reserve((size_t) rows * 96);
  for (int i = 0; i < rows; i++)
    text.printf("\"point %d, sample\",%.6f,,%.6f,\"tag %d\",%.6f\n",
      i, (i % 101) / 7.0, (i % 97) / 11.0, i % 13, (i % 89) / 5.0);
  return text.str_free();
}

static int _parse(char *line, double *sum) {
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
  String csv = _make_csv(rows);
  double checksum = 0;
  for (int run = 0; run < runs; run++) {
    Scope.retain();
    char *copy = Scope.malloc(csv.len() + 1), *line = copy;
    memcpy(copy, csv, csv.len() + 1);
    while (line && *line) {
      char *end = strchr(line, '\n');
      if (end) *end = 0;
      _parse(line, &checksum);
      line = end ? end + 1 : 0;
    }
    Scope.release();
  }
  printf("%.6f\n", checksum);
  return 0;
}
