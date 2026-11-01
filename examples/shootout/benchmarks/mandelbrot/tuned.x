/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * Adapted from the contributions recorded in ../../benchmarks.json.
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <stdlib.h>
#include "typed-array.x"

class Rows { int size, first, last; ArrayChar bytes; Thread worker; } *;

int main(int argc, char **argv) {
  int size = atoi(argv[1]);
  printf("P4\n%d %d\n", size, size);
  for (int first = 0; first < size; first += 96) auto {
    Array batches = [];
    for (int row = first; row < size && row < first + 96; row += 16)
      batches.push(Rows.new(size, row, row + 16 < size ? row + 16 : size));
    foreach (Rows rows in batches) {
      if (rows.worker) {
        rows.worker.join();
        rows.worker.free();
      }
      fwrite(rows.bytes.bytes, 1, rows.bytes.len(), stdout);
    }
  }
  return 0;
}

static void Rows.init(Rows rows, int size, int first, int last) {
  rows.size = size;
  rows.first = first;
  rows.last = last;
  rows.bytes = ArrayChar.new();
  int length = (last - first) * ((size + 7) / 8);
  for (int i = 0; i < length; i++) rows.bytes.push(0);
  if (size >= 256) rows.worker = Thread.start(_render, rows);
  else _render(rows);
}

static Var _render(Var input) {
  Rows rows = input;
  int offset = 0, size = rows.size;
  for (int y = rows.first; y < rows.last; y++) {
    for (int x = 0; x < size; x += 8) {
      int bits = size - x < 8 ? size - x : 8;
      unsigned byte = 0;
      for (int b = 0; b < bits; b++)
        byte = (byte << 1) | _inside(x + b, y, size);
      rows.bytes[offset++] = byte << (8 - bits);
    }
  }
  return void;
}

static unsigned _inside(int x, int y, int size) {
  double zr = 0.0, zi = 0.0, tr = 0.0, ti = 0.0;
  double cr = 2.0 * x / size - 1.5, ci = 2.0 * y / size - 1.0;
  for (int i = 0; i < 50 && tr + ti <= 4.0; i++) {
    zi = 2.0 * zr * zi + ci;
    zr = tr - ti + cr;
    tr = zr * zr;
    ti = zi * zi;
  }
  return tr + ti <= 4.0;
}
