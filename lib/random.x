/*  random.x -- pseudorandom numbers, system entropy, and UUIDs

    Copyright (c) 2026 Gary William Flake

    `Random` is a seedable generator whose sequence its seed fixes; it is
    fast and unsuitable for secrets. `Random.secure_fill` reads the
    operating system's cryptographic generator, `arc4random_buf` on macOS
    and `getrandom` on Linux, and version 4 UUIDs take their bits from it.
*/

#pragma once
#include "x2c.x"

#include <stdint.h>

/** A xoshiro256** pseudorandom generator, from Blackman and Vigna,
    "Scrambled Linear Pseudorandom Number Generators" (2018). The value
    holds the whole generator state, so a copy continues the same sequence
    independently. Construct one with `Random.new` or
    `Random.from_entropy`.
*/
typedef struct Random { uint64_t state[4]; } Random;

/** The receiverless owner of `Uuid.v4` and the other UUID operations. */
typedef Symbol Uuid;

#include <errno.h>
#ifdef __APPLE__
#include <stdlib.h>
#else
#include <sys/random.h>
#endif

// generators

/** Returns a generator whose sequence `seed` fixes: equal seeds yield equal
    sequences. SplitMix64 expands the seed into the state.
*/
Random Random.new(uint64_t seed) {
  Random r;
  for (int i = 0; i < 4; i++) r.state[i] = _splitmix(seed);
  return r;
}

/** Returns a generator seeded from `Random.secure_fill`, so each call
    starts a different sequence.
    Raises: `<io-fail>` when the system generator fails.
*/
Random Random.from_entropy(void) {
  uint64_t seed;
  Random.secure_fill(&seed, sizeof seed);
  return Random.new(seed);
}

/** Returns the next 64 random bits and advances `r`. */
uint64_t Random.next(Random &r) {
  uint64_t *s = r.state, result = _rotate(s[1] * 5, 7) * 9, t = s[1] << 17;
  s[2] ^= s[0];
  s[3] ^= s[1];
  s[1] ^= s[2];
  s[0] ^= s[3];
  s[2] ^= t;
  s[3] = _rotate(s[3], 45);
  return result;
}

/** Returns an integer drawn uniformly from 0 through `bound - 1`. Draws
    that would favor small results are rejected, so every result is equally
    likely.
    Raises: `<bad-arg>` when `bound` is not positive.
*/
long Random.below(Random &r, long bound) {
  if (bound <= 0) raise %(bad-arg (operation "Random.below") (bound $bound));
  uint64_t limit = bound, threshold = -limit % limit;
  for (;;) {
    uint64_t bits = r.next();
    if (bits >= threshold) return (long) (bits % limit);
  }
}

/** Returns a double drawn uniformly from [0, 1), with 53 random bits. */
double Random.double(Random &r) => (r.next() >> 11) / 9007199254740992.0;

/** Puts the elements of `items` in a uniformly random order, in place,
    with the Fisher-Yates shuffle.
*/
void Random.shuffle(Random &r, Array items) {
  for (long i = (long) items.len() - 1; i > 0; i--) {
    long j = r.below(i + 1);
    Var held = items[i];
    items[i] = items[j];
    items[j] = held;
  }
}

/** Returns an element of `items` chosen uniformly.
    Raises: `<bad-arg>` when `items` is empty.
*/
Var Random.choice(Random &r, Array items) {
  if (!items)
    raise %(bad-arg (operation "Random.choice") (reason "empty Array"));
  return items[r.below(items.len())];
}

// system entropy

/** Fills `count` bytes at `bytes` from the operating system's
    cryptographic generator, suitable for keys, tokens, and nonces.
    Raises: `<io-fail>` with `errno` when the system generator fails.
*/
void Random.secure_fill(void *bytes, size_t count) {
#ifdef __APPLE__
  arc4random_buf(bytes, count);
#else
  for (size_t done = 0; done < count;) {
    ssize_t got = getrandom((char *) bytes + done, count - done, 0);
    if (got >= 0) done += got;
    else if (errno != EINTR) {
      int error = errno;
      raise %(io-fail (operation "Random.secure_fill") (errno $error));
    }
  }
#endif
}

// UUIDs

/** Returns a new random version 4 UUID in its canonical form: 36
    lowercase characters such as `9f6e2c1a-0b7d-4e3f-a2c5-6d8e9f0a1b2c`.
    Its 122 random bits come from `Random.secure_fill`.
    Raises: `<io-fail>` when the system generator fails.
*/
String Uuid.v4(void) {
  unsigned char bytes[16];
  Random.secure_fill(bytes, sizeof bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return _canonical(bytes);
}

/** Returns the UUID `text` spells in its canonical lowercase form. `text`
    must be 32 hexadecimal digits of either case, grouped 8-4-4-4-12 by
    hyphens; any version and variant is accepted.
    Raises: `<malformed>` with `reason` and byte `offset` when it is not.
*/
String Uuid.parse(String text) {
  unsigned char bytes[16];
  int offset = _decode(text, bytes);
  if (offset >= 0)
    raise %(malformed (operation "Uuid.parse") (reason $(_reason(offset)))
            (offset $offset));
  return _canonical(bytes);
}

/** Reports whether `text` is a UUID that `Uuid.parse` accepts. */
int Uuid.is_valid(String text) {
  unsigned char bytes[16];
  return _decode(text, bytes) < 0;
}

// generator steps

/* SplitMix64, from Steele, Lea, and Flood, "Fast Splittable Pseudorandom
   Number Generators" (2014); it advances `seed` and returns its mix. */
static uint64_t _splitmix(uint64_t &seed) {
  uint64_t z = seed += 0x9e3779b97f4a7c15;
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
  z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
  return z ^ (z >> 31);
}

static inline uint64_t _rotate(uint64_t x, int n) =>
  (x << n) | (x >> (64 - n));

// UUID text

static String _canonical(const unsigned char *bytes) {
  char text[36];
  for (int i = 0, at = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) text[at++] = '-';
    text[at++] = "0123456789abcdef"[bytes[i] >> 4];
    text[at++] = "0123456789abcdef"[bytes[i] & 15];
  }
  return String.new_len(text, 36);
}

/* Decodes the 16 bytes `text` spells and returns -1, or returns the offset
   of the first byte that does not belong. */
static int _decode(String text, unsigned char *bytes) {
  const char *at = text ? text : "";
  for (int i = 0, digits = 0; i < 36; i++) {
    if (_hyphen_at(i)) {
      if (at[i] != '-') return i;
      continue;
    }
    int digit = scan_ascii_hex_value(at[i]);
    if (digit < 0) return i;
    bytes[digits / 2] = digits % 2 ? bytes[digits / 2] | digit : digit << 4;
    digits++;
  }
  return at[36] ? 36 : -1;
}

static String _reason(int offset) {
  if (offset == 36) return "unexpected text after the UUID";
  return _hyphen_at(offset) ? "expected '-'" : "expected a hexadecimal digit";
}

static int _hyphen_at(int i) => i == 8 || i == 13 || i == 18 || i == 23;
