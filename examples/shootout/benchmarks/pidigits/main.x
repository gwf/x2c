/* The Computer Language Benchmarks Game: pidigits.
   GMP supplies arbitrary precision. The spigot performs both extract(3) and
   extract(4), as required, through ordinary mutable Integer values. */

#include <gmp.h>
#include "cleanup.x"
#include <stdio.h>
#include <stdlib.h>

typedef struct Integer { mpz_t value; } Integer;
typedef struct Spigot {
  Integer numerator, accumulator, denominator, term, digit;
} Spigot;

$cleanup.by(Spigot, drop);

int main(int argc, char **argv) {
  int count = argc > 1 ? atoi(argv[1]) : 30, emitted = 0;
  auto Spigot spigot = Spigot.new();
  for (ulong k = 1; emitted < count; k++) {
    spigot.advance(k);
    if (spigot.numerator.greater(spigot.accumulator)) continue;
    ulong digit = spigot.extract(3);
    if (digit != spigot.extract(4)) continue;
    putchar('0' + digit);
    if (++emitted % 10 == 0) printf("\t:%d\n", emitted);
    spigot.eliminate(digit);
  }
  if (emitted % 10) {
    for (int i = emitted % 10; i < 10; i++) putchar(' ');
    printf("\t:%d\n", emitted);
  }
  return 0;
}

static Integer Integer.new(ulong initial) {
  Integer number;
  mpz_init_set_ui(number.value, initial);
  return number;
}

static void Integer.drop(Integer &number) => mpz_clear(number.value);

static void Integer.product(Integer &out, Integer &input, ulong scale) =>
  mpz_mul_ui(out.value, input.value, scale);

static void Integer.add(Integer &out, Integer &other) =>
  mpz_add(out.value, out.value, other.value);

static void Integer.subtract(Integer &out, Integer &other) =>
  mpz_sub(out.value, out.value, other.value);

static void Integer.quotient(Integer &out, Integer &a, Integer &b) =>
  mpz_tdiv_q(out.value, a.value, b.value);

static int Integer.greater(Integer &a, Integer &b) =>
  mpz_cmp(a.value, b.value) > 0;

static ulong Integer.number(Integer &value) => mpz_get_ui(value.value);

static Spigot Spigot.new(void) {
  Spigot state;
  state.numerator = Integer.new(1);
  state.accumulator = Integer.new(0);
  state.denominator = Integer.new(1);
  state.term = Integer.new(0);
  state.digit = Integer.new(0);
  return state;
}

static void Spigot.drop(Spigot &state) {
  state.numerator.drop();
  state.accumulator.drop();
  state.denominator.drop();
  state.term.drop();
  state.digit.drop();
}

static void Spigot.advance(Spigot &state, ulong k) {
  state.term.product(state.numerator, 2);
  state.accumulator.add(state.term);
  state.accumulator.product(state.accumulator, 2 * k + 1);
  state.denominator.product(state.denominator, 2 * k + 1);
  state.numerator.product(state.numerator, k);
}

static ulong Spigot.extract(Spigot &state, ulong nth) {
  state.term.product(state.numerator, nth);
  state.term.add(state.accumulator);
  state.digit.quotient(state.term, state.denominator);
  return state.digit.number();
}

static void Spigot.eliminate(Spigot &state, ulong digit) {
  state.term.product(state.denominator, digit);
  state.accumulator.subtract(state.term);
  state.accumulator.product(state.accumulator, 10);
  state.numerator.product(state.numerator, 10);
}
