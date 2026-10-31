/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * Adapted from the contributions recorded in ../../benchmarks.json.
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <stdlib.h>

class Chunk {
  int n, maximum, checksum;
  long first, last;
  Thread worker;
} *;

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 7;
  printf("Pfannkuchen(%d) = %d\n", n, _fannkuch(n));
  return 0;
}

static int _fannkuch(int n) {
  long total = 1;
  for (int i = 2; i <= n; i++) total *= i;
  int workers = n < 9 ? 1 : 6, maximum = 0, checksum = 0;
  auto {
    Array chunks = [];
    for (int worker = 0; worker < workers; worker++) {
      Chunk chunk = Chunk.new(n,
        total * worker / workers, total * (worker + 1) / workers);
      if (workers == 1) _run_chunk(chunk);
      else chunk.worker = Thread.start(_run_chunk, chunk);
      chunks.push(chunk);
    }
    foreach (Chunk chunk in chunks) {
      if (workers > 1) {
        chunk.worker.join();
        chunk.worker.free();
      }
      if (chunk.maximum > maximum) maximum = chunk.maximum;
      checksum += chunk.checksum;
    }
  }
  printf("%d\n", checksum);
  return maximum;
}

static void Chunk.init(Chunk chunk, int n, long first, long last) {
  chunk.n = n;
  chunk.first = first;
  chunk.last = last;
}

static Var _run_chunk(Var input) {
  Chunk chunk = input;
  Array permutation = [], working = [], counts = [];
  for (int i = 0; i < chunk.n; i++) {
    permutation.push(i);
    working.push(i);
    counts.push(i + 1);
  }
  if (chunk.first) _seek(permutation, counts, chunk.n, chunk.first);
  int maximum = 0, checksum = 0;
  for (long index = chunk.first; index < chunk.last; index++) {
    working.setslice(0, chunk.n, permutation);
    int flips = 0;
    for (int k = working[0].int(); k; k = working[0].int()) {
      for (int i = 0, j = k; i < j; i++, j--) {
        Var value = working[i];
        working[i] = working[j];
        working[j] = value;
      }
      flips++;
    }
    if (flips > maximum) maximum = flips;
    checksum += index % 2 ? -flips : flips;
    _advance(permutation, counts, chunk.n);
  }
  chunk.maximum = maximum;
  chunk.checksum = checksum;
  return void;
}

static void _seek(Array permutation, Array counts, int n, long index) {
  long factor = 1;
  for (int i = 2; i < n; i++) factor *= i;
  for (int r = n - 1; r > 0; r--) {
    int rotations = index / factor;
    index %= factor;
    counts[r] = r + 1 - rotations;
    for (int i = 0; i < rotations; i++) _rotate(permutation, r);
    factor /= r;
  }
}

static void _rotate(Array permutation, int last) {
  Var first = permutation[0];
  for (int i = 0; i < last; i++) permutation[i] = permutation[i + 1];
  permutation[last] = first;
}

static int _advance(Array permutation, Array counts, int n) {
  for (int r = 1; r < n; r++) {
    _rotate(permutation, r);
    int remaining = counts[r].int() - 1;
    counts[r] = remaining;
    if (remaining) return 1;
    counts[r] = r + 1;
  }
  return 0;
}
