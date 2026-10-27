/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/csvparse-idiomatic main.x
 *   /tmp/csvparse-idiomatic 50000 10
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  String csv = _make_csv(atoi(argv[1]));
  double checksum = 0;
  int runs = atoi(argv[2]);
  double fields[6];
  for (int run = 0; run < runs; run++) {
    const char *text = csv;
    int length = csv.len(), start = 0;
    while (start < length) {
      int end = start;
      while (end < length && text[end] != '\n' && text[end] != '\r') end++;
      _fields(text + start, end - start, fields);
      checksum += fields[1] + fields[3] + fields[5];
      start = end;
      if (start < length && text[start] == '\r') start++;
      if (start < length && text[start] == '\n') start++;
    }
  }
  printf("%.6f\n", checksum);
  return 0;
}

static String _make_csv(int rows) {
  Buffer text = Buffer.new(0).reserve((size_t) rows * 96);
  for (int i = 0; i < rows; i++)
    text.printf(
      "\"point %d, sample\",%.6f,,%.6f,\"tag %d\",%.6f\n",
      i, (double) (i % 101) / 7.0, (double) (i % 97) / 11.0,
      i % 13, (double) (i % 89) / 5.0);
  return text.str_free();
}

static void _fields(const char *text, int len, double *fields) {
  int start = 0, quoted = 0, count = 0;
  for (int i = 0; i <= len; i++) {
    if (i < len && text[i] == '"') quoted = !quoted;
    if (i == len || (text[i] == ',' && !quoted)) {
      /* Keep strtod from skipping a line ending into the next row. */
      const char *first = text + start;
      while (first < text + i && isspace((unsigned char) *first)) first++;
      char *stop = (char *) first;
      errno = 0;
      double value = first < text + i ? strtod(first, &stop) : 0.0;
      while (stop < text + i && isspace((unsigned char) *stop)) stop++;
      fields[count++] = stop == text + i && errno != ERANGE ? value : 0.0;
      start = i + 1;
    }
  }
}
