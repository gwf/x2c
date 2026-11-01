/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 * Algorithm and constants from Paul Hsieh's contributed C program.
 */

#include <stdlib.h>
#include <string.h>
#include "typed-array.x"

static int seed = 42;
static String alu =
  "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGG"
  "GAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGA"
  "CCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAAT"
  "ACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCA"
  "GCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGG"
  "AGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCC"
  "AGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 1000;
  puts(">ONE Homo sapiens alu");
  _repeat(2 * n);
  puts(">TWO IUB ambiguity codes");
  _random("acgtBDHKMNRSVWY", _probabilities([
    0.27, 0.12, 0.12, 0.27, 0.02, 0.02, 0.02, 0.02,
    0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02]), 3 * n);
  puts(">THREE Homo sapiens frequency");
  _random("acgt", _probabilities([
    0.3029549426680, 0.1979883004921,
    0.1975473066391, 0.3015094502008]), 5 * n);
  return 0;
}

static void _repeat(int count) {
  char output[61 * 256];
  size_t used = 0, position = 0, length = alu.len();
  while (count > 0) {
    int line = count < 60 ? count : 60, remaining = line;
    while (remaining > 0) {
      size_t span = length - position;
      if (span > remaining) span = remaining;
      memcpy(output + used, (const char *) alu + position, span);
      used += span;
      remaining -= span;
      position += span;
      if (position == length) position = 0;
    }
    output[used++] = '\n';
    count -= line;
    if (used == sizeof(output)) {
      Stdout.write_all(output, used);
      used = 0;
    }
  }
  if (used) Stdout.write_all(output, used);
}

static void _random(String letters, ArrayDbl probabilities, int count) {
  double total = 0;
  int choices = probabilities.len();
  for (int i = 0; i < choices; i++) {
    total += probabilities[i];
    probabilities[i] = total;
  }
  char output[61 * 256];
  size_t used = 0;
  while (count > 0) {
    int line = count < 60 ? count : 60;
    for (int i = 0; i < line; i++) {
      seed = (seed * 3877 + 29573) % 139968;
      double random = (double) seed / 139968;
      int choice = 0;
      for (int j = 0; j < choices - 1; j++)
        choice += random >= probabilities[j];
      output[used++] = letters[choice];
    }
    output[used++] = '\n';
    count -= line;
    if (used == sizeof(output)) {
      Stdout.write_all(output, used);
      used = 0;
    }
  }
  if (used) Stdout.write_all(output, used);
}

static ArrayDbl _probabilities(Array values) {
  ArrayDbl result = ArrayDbl.new();
  foreach (double probability in values) result.push(probability);
  return result;
}
