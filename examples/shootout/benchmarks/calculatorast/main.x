/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/calculatorast-idiomatic main.x
 *   /tmp/calculatorast-idiomatic 1000000
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static SymbolSet _names = %<<a b>>;

static long _eval(List ast, long *variables) {
  match (ast) {
    case %(number ?value): return value.long();
    case %(variable ?name): return variables[_names.index(name)];
    case %(assign ?name ?expression):
      return variables[_names.index(name)] =
        _eval(expression, variables);
    case %(binary ?op ?left ?right): {
      long a = _eval(left, variables);
      long b = _eval(right, variables);
      switch (op.symbol()) {
        case <+>: return a + b;
        case <->: return a - b;
        case <*>: return a * b;
        default:  return a / b;
      }
    }
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  int runs = atoi(argv[1]);
  List program = %(
    (assign a (number 7))
    (assign b (binary * (variable a) (number 6)))
    (binary + (variable b)
      (binary / (number 100) (number 5))));
  uint64_t checksum = 0;
  for (int run = 0; run < runs; run++) {
    long variables[2] = {0};
    foreach(List expression, program) checksum += _eval(expression, variables);
  }
  printf("%llu\n", (unsigned long long) checksum);
  return 0;
}
