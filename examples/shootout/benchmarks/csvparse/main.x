/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/csvparse-idiomatic main.x
 *   /tmp/csvparse-idiomatic 50000 10
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <stdlib.h>

static String _make_csv(int rows) {
  Buffer text = Buffer.new(0).reserve((size_t) rows * 96);
  for (int i = 0; i < rows; i++)
    text.printf(
      "\"point %d, sample\",%.6f,,%.6f,\"tag %d\",%.6f\n",
      i, (double) (i % 101) / 7.0, (double) (i % 97) / 11.0,
      i % 13, (double) (i % 89) / 5.0);
  return text.str_free();
}

static Array _fields(String line) {
  Array fields = %[];
  const char *text = line;
  int start = 0, quoted = 0, len = line.len();
  for (int i = 0; i <= len; i++) {
    if (i < len && text[i] == '"') quoted = !quoted;
    if (i == len || (text[i] == ',' && !quoted)) {
      fields.push(line[start:i]);
      start = i + 1;
    }
  }
  return fields;
}

static double _number(String text) {
  double value;
  if (!text.try_double(&value)) exit(3);
  return value;
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  String csv = _make_csv(atoi(argv[1]));
  double checksum = 0;
  int runs = atoi(argv[2]);
  for (int run = 0; run < runs; run++) {
    Scope.retain();
    foreach(String line, csv.lines()) {
      Array fields = _fields(line);
      checksum += _number(fields[1]) +
                  _number(fields[3]) +
                  _number(fields[5]);
    }
    Scope.release();
  }
  printf("%.6f\n", checksum);
  return 0;
}
