/*  digest.x -- SHA-256 digests of Strings and streams

    Copyright (c) 2026 Gary William Flake

    A digest is the 64-character lowercase hexadecimal `String` that
    `shasum -a 256` prints. A stream digest reads raw bytes, so a file that
    holds NUL bytes, which a `String` cannot, hashes like any other.
*/

#pragma once
#include "x2c.x"

#pragma private

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* FIPS 180-4 section 4.2.2: the first 32 bits of the fractional parts of the
   cube roots of the first 64 primes. */
static const uint32_t _ROUND[64] = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

/* `block` holds the `used` bytes not yet compressed; `length` counts every
   byte absorbed. */
typedef struct _Sha256 {
  uint32_t state[8];
  uint64_t length;
  unsigned char block[64];
  size_t used;
} _Sha256;

/* Section 5.3.3: the first 32 bits of the fractional parts of the square
   roots of the first 8 primes. */
static const _Sha256 _INITIAL = {{
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
}};

static inline uint32_t _rotate(uint32_t x, int n) =>
  (x >> n) | (x << (32 - n));

static void _compress(_Sha256 *sha, const unsigned char *block) {
  uint32_t w[64], s[8];
  for (int i = 0; i < 16; i++)
    w[i] = (uint32_t) block[4 * i] << 24 | (uint32_t) block[4 * i + 1] << 16 |
           (uint32_t) block[4 * i + 2] << 8 | (uint32_t) block[4 * i + 3];
  for (int i = 16; i < 64; i++)
    w[i] = w[i - 16] + w[i - 7] +
           (_rotate(w[i - 15], 7) ^ _rotate(w[i - 15], 18) ^
            w[i - 15] >> 3) +
           (_rotate(w[i - 2], 17) ^ _rotate(w[i - 2], 19) ^ w[i - 2] >> 10);
  memcpy(s, sha->state, sizeof(s));
  for (int i = 0; i < 64; i++) {
    uint32_t e = s[4], a = s[0];
    uint32_t t1 = s[7] + (_rotate(e, 6) ^ _rotate(e, 11) ^ _rotate(e, 25)) +
                  ((e & s[5]) ^ (~e & s[6])) + _ROUND[i] + w[i];
    uint32_t t2 = (_rotate(a, 2) ^ _rotate(a, 13) ^ _rotate(a, 22)) +
                  ((a & s[1]) ^ (a & s[2]) ^ (s[1] & s[2]));
    memmove(s + 1, s, 7 * sizeof(uint32_t));
    s[4] += t1;
    s[0] = t1 + t2;
  }
  for (int i = 0; i < 8; i++) sha->state[i] += s[i];
}

static void _absorb(_Sha256 *sha, const unsigned char *bytes, size_t count) {
  sha->length += count;
  while (count) {
    size_t take = 64 - sha->used;
    if (take > count) take = count;
    memcpy(sha->block + sha->used, bytes, take);
    sha->used += take;
    bytes += take;
    count -= take;
    if (sha->used == 64) {
      _compress(sha, sha->block);
      sha->used = 0;
    }
  }
}

static String _finish(_Sha256 *sha) {
  uint64_t bits = sha->length * 8;
  unsigned char tail[72] = {0x80};
  size_t pad = (sha->used < 56 ? 56 : 120) - sha->used;
  for (int i = 0; i < 8; i++)
    tail[pad + i] = (unsigned char) (bits >> (56 - 8 * i));
  _absorb(sha, tail, pad + 8);
  char hex[65];
  for (int i = 0; i < 64; i++)
    hex[i] = "0123456789abcdef"[sha->state[i / 8] >> (28 - 4 * (i % 8)) & 15];
  hex[64] = '\0';
  return String.new(hex);
}

/** Returns the SHA-256 digest of the bytes of `text`; NULL is empty text. */
String String.sha256(String text) {
  _Sha256 sha = _INITIAL;
  _absorb(&sha, (const unsigned char *) text, text.len());
  return _finish(&sha);
}

/** Returns the SHA-256 digest of the bytes from the current position of
    `file` to its end, leaving the stream at end of file and open.
    Raises: `<io-fail>` on a stream read error.
*/
String File.sha256(File file) {
  _Sha256 sha = _INITIAL;
  unsigned char bytes[BUFSIZ], size_t count;
  while ((count = fread(bytes, 1, sizeof(bytes), file)) > 0)
    _absorb(&sha, bytes, count);
  if (ferror(file)) {
    int error = errno;
    raise %(io-fail (operation <read>) (errno $error));
  }
  return _finish(&sha);
}
