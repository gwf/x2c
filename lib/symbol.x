/*  symbol.x -- immediate encoded names

    Copyright (c) 2025 Gary William Flake

    `Symbol` stores closed-vocabulary names directly in an integer. Restricted
    spellings use ten 5-bit characters; other spellings use seven 7-bit
    bytes. The restricted form folds ASCII case and aliases underscore with
    hyphen; the general form retains only the low seven bits. Construction
    truncates beyond the selected capacity. Use `Atom` when every input byte
    must round-trip.
*/

#pragma once

#include "common.x"

#define SYMBOL_MAX_5BIT 10
#define SYMBOL_MAX_7BIT 7

#pragma private

#include <stdint.h>
#include <string.h>

#include "buffer.x"
#include "string.x"

static const char _symbol_alphabet[] =
    "\0abcdefghijklmnopqrstuvwxyz*+?!-";

/* Maximum-capacity encodings within the 64-bit Symbol value:

   ----------------------------------------------------------------
   6666555555555544444444443333333333222222222211111111110000000000
   3210987654321098765432109876543210987654321098765432109876543210
   ----------------------------------------------------------------
   XXXXXXXXXXXXX[555][555][555][555][555][555][555][555][555][555]0
   XXXXXXXXXXXXX0[77777][77777][77777][77777][77777][77777][77777]1
   ----------------------------------------------------------------

   X marks an unused bit, [555] a 5-bit character, and [77777] a
   7-bit character. The low bit selects 5- or 7-bit encoding. Shorter
   spellings use fewer leading character groups.

   Var admits Symbol payloads below 2^51. The 5-bit form fixes bit 0 at
   zero; the 7-bit form uses bit 0 as one and fixes bit 50 at zero.

   The restricted alphabet folds case and aliases '_' with '-'. A zero from
   _char_to_5bit means that the byte requires 7-bit encoding.
*/
static int _char_to_5bit(int c) {
  if (c >= 'a' && c <= 'z') return c - 'a' + 1;
  if (c >= 'A' && c <= 'Z') return c - 'A' + 1;
  switch (c) {
    case '*': return 27;
    case '+': return 28;
    case '?': return 29;
    case '!': return 30;
    case '_': case '-': return 31;
    default: return 0;
  }
}

static int _bytes_fit_5bit(const char *str, int len) {
  if (!str) return 0;
  for (int i = 0; i < len; i++) if (!_char_to_5bit(str[i])) return 0;
  return 1;
}

/** Encodes at most `len` bytes of `str` as a compact `Symbol`.
    A null `str` or nonpositive `len` returns zero. All `len` readable bytes
    select the encoding before the result is truncated to ten restricted or
    seven general bytes. The restricted encoding folds ASCII case and treats
    underscore as hyphen; the general encoding retains each low seven bits,
    including embedded NUL. `String` and `Buffer` conversions stop at the first
    decoded NUL.
*/
Symbol Symbol.new_len(const char *str, int len) {
  if (!str || len <= 0) return 0;

  int is_5bit = _bytes_fit_5bit(str, len);
  int max_len = is_5bit ? SYMBOL_MAX_5BIT : SYMBOL_MAX_7BIT;
  if (len > max_len) len = max_len;

  uint64_t result = 0;
  if (is_5bit) {
    for (int i = 0; i < len; i++) {
      result <<= 5;
      result |= (uint64_t) (0x1F & _char_to_5bit(str[i]));
    }
    return result << 1;
  }

  for (int i = 0; i < len; i++) {
    result <<= 7;
    result |= (uint64_t) (0x7F & (unsigned char) str[i]);
  }
  return (result << 1) | 1;
}

/** Encodes the nonnull NUL-terminated spelling `str` as a compact `Symbol`.
    Encoding and truncation follow `Symbol.new_len`.
*/
Symbol Symbol.new(const char *str) => Symbol.new_len(str, strlen(str));

/** Encodes `spelling` only when the `Symbol` preserves every byte.
    Returns 1 and writes `out` on success; returns 0 and leaves `out`
    untouched when case folding, `_`/`-` folding, or truncation would change
    the spelling. The null `String` is the empty `Symbol`.
    Raises: `<alloc-fail>` while checking the decoded spelling.
*/
int Symbol.try_new(String spelling, Symbol *out) {
  if (!out) return 0;
  Symbol symbol = spelling ? Symbol.new(spelling) : 0;
  if (!String.equal(spelling, symbol.str())) return 0;
  *out = symbol;
  return 1;
}

/** Returns the number of decoded bytes in `symbol`. */
int Symbol.len(Symbol symbol) {
  int len = 0, bits = (symbol & 1) ? 7 : 5;
  for (symbol >>= 1; symbol; symbol >>= bits) len++;
  return len;
}

/** Decodes `symbol` into caller-owned byte storage.
    `dest` must hold at least `SYMBOL_MAX_5BIT + 1` bytes. A nonzero `Symbol`
    is
    NUL-terminated there. A null destination or zero `Symbol` leaves storage
    unchanged.
*/
void Symbol.decode(Symbol symbol, char *dest) {
  if (!dest || !symbol) return;
  int len = symbol.len();
  memset(dest, 0, SYMBOL_MAX_5BIT + 1);
  if (symbol & 1) {
    symbol >>= 1;
    for (int i = 0; i < len; i++) {
      dest[len - i - 1] = symbol & 0x7F;
      symbol >>= 7;
    }
  }
  else {
    symbol >>= 1;
    for (int i = 0; i < len; i++) {
      dest[len - i - 1] = _symbol_alphabet[symbol & 0x1F];
      symbol >>= 5;
    }
  }
  dest[len] = '\0';
}

/** Returns the decoded spelling as a canonical `String`.
    Conversion stops at the first decoded NUL.
    The result follows the canonical pool chain: it may already belong to an
    ancestor and lives until its actual owning pool is released. A zero
    `Symbol`
    returns NULL, the empty `String`.
    Raises: `<alloc-fail>` while canonicalizing the spelling.
*/
String Symbol.str(Symbol symbol) {
  char text[SYMBOL_MAX_5BIT + 1];
  if (!symbol) return NULL;
  symbol.decode(text);
  return String.new_len(text, strlen(text));
}

/** Compares decoded `Symbol` spellings bytewise.
    Zero sorts before nonzero values. Equal decoded lengths and bytes are
    ordered by the encoded value, so distinct encodings still have a total
    order. The result is -1, 0, or 1.
*/
int Symbol.compare(Symbol a, Symbol b) {
  if (a == b) return 0;
  if (!a) return b ? -1 : 0;
  if (!b) return 1;
  char a_text[SYMBOL_MAX_5BIT + 1], b_text[SYMBOL_MAX_5BIT + 1];
  a.decode(a_text);
  b.decode(b_text);
  int a_len = a.len(), b_len = b.len(), len = a_len < b_len ? a_len : b_len;
  int comparison = memcmp(a_text, b_text, len);
  if (comparison) return comparison < 0 ? -1 : 1;
  if (a_len != b_len) return a_len < b_len ? -1 : 1;
  return a < b ? -1 : 1;
}

/** Returns the canonical readable representation of `symbol`.
    Zero becomes `<>`; other values use the form emitted by
    `Symbol.write_repr`. The result follows the canonical pool-chain lifetime
    described by `Symbol.str`.
    Raises: `<alloc-fail>` while constructing the result.
*/
String Symbol.repr(Symbol symbol) {
  Buffer out = Buffer.new(0);
  symbol.write_repr(out);
  String result = out.str_free();
  return result;
}

/** Appends the decoded spelling of `symbol` to `out`.
    The bytes go straight into `out`, allocating no `String`. A zero `Symbol`
    appends nothing.
    Raises: `<size-limit>` or `<alloc-fail>` when `out` cannot grow.
*/
Buffer Symbol.write_str(Symbol symbol, Buffer out) {
  if (!symbol) return out;
  char text[SYMBOL_MAX_5BIT + 1] = { 0 };
  symbol.decode(text);
  return out.write(text);
}

/** Appends the readable representation of `symbol` to `out`.
    Zero writes `<>`; restricted values use a bare angled spelling and general
    values use a quoted angled spelling, escaping backslash and double quote.
    Raises: `<size-limit>` or `<alloc-fail>` when `out` cannot grow.
*/
Buffer Symbol.write_repr(Symbol symbol, Buffer out) {
  if (!symbol) return out.write("<>");
  char text[SYMBOL_MAX_5BIT + 1] = { 0 };
  symbol.decode(text);
  out.write_char('<');
  if (!(symbol & 1)) out.write(text);
  else {
    out.write("\\\"");
    for (const char *src = text; *src; src++) {
      if (*src == '\\' || *src == '"') out.write_char('\\');
      out.write_char(*src);
    }
    out.write("\\\"");
  }
  return out.write_char('>');
}

/** Returns the first decoded byte of `symbol`, or NUL for zero. */
char Symbol.first(Symbol symbol) {
  if (!symbol) return '\0';
  int bits = (symbol & 1) ? 7 : 5, uint64_t value = symbol >> 1;
  int len = symbol.len();
  if (len == 0) return '\0';
  value >>= bits * (len - 1);
  if (bits == 5) return _symbol_alphabet[value & 0x1F];
  return value & 0x7F;
}

/** Returns the final decoded byte of `symbol`, or NUL for zero. */
char Symbol.last(Symbol symbol) {
  if (!symbol) return '\0';
  int bits = (symbol & 1) ? 7 : 5, uint64_t value = symbol >> 1;
  if (bits == 5) return _symbol_alphabet[value & 0x1F];
  return value & 0x7F;
}

/** Parses the first compact `Symbol` spelling from `text`.
    The parser accepts an angled literal or a bare `Atom` prefix and ignores
    trailing text. Quoted angled literals use `String` escape rules. The parsed
    bytes then take `Symbol.new_len` folding and truncation. `Null`, empty, or
    malformed input returns zero. Zero is also the empty `Symbol`.
    Raises: `<alloc-fail>` while unescaping a quoted literal.
*/
Symbol Symbol.parse(char *text) {
  int scan_symbol_literal(char *s);
  int scan_atom(char *s);
  if (!text || !*text) return 0;
  int len = scan_symbol_literal(text);
  if (len <= 0) {
    len = scan_atom(text);
    if (len <= 0) return 0;
    return Symbol.new_len(text, len);
  }

  /* A quoted symbol uses String's escape rules. An empty intermediate is
     NULL by convention, so an empty result here means the empty symbol. */
  if (len >= 3 && text[1] == '"') {
    String inner = String.new_len(text + 2, len - 4);
    if (!inner) return 0;
    String unquoted = inner.unescape();
    if (!unquoted) return 0;
    return Symbol.new(unquoted);
  }
  return Symbol.new_len(text + 1, len - 2);
}
