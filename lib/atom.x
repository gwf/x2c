/*  atom.x -- canonical exact names

    Copyright (c) 2026 Gary William Flake

    An `Atom` preserves its spelling exactly. Compact spellings use immediate
    `Symbol`s when `Symbol` encoding round-trips every byte; all other
    spellings
    use the private `<lsym>` representation with a direct pointer to the
    canonical `String`. `String` canonicalization makes equal long `Atom`s
    bit-identical. Compact `Atom`s have value lifetime. A long `Atom` borrows
    its
    canonical spelling, which may belong to any pool in the active chain and
    lives until its owning pool is released.
*/

#pragma once

#include "common.x"

/** Promotes a long `Atom` spelling into its parent `String` pool.
    Returns `atom` unchanged. Compact `Atom`s and long spellings
    not owned by the
    innermost pool are unchanged. A promoted spelling keeps the same pointer.
    Raises: `<alloc-fail>` when promotion metadata cannot be allocated.
*/
Self Atom.promote(Self atom) {
  if (atom is <lsym>) String.promote(atom.str());
  return atom;
}

/* True when a spelling can be written bare and read back identically
   by the Lisp reader: the first byte is printable and not a delimiter, the
   spelling has no numeric prefix, and both reader scanners consume it whole.
   The snapshot writer delegates its bare-symbol decision here. */
/** Reports whether a spelling can round-trip as a bare Lisp `Atom`. */
int Atom.bare_spelling(String spelling) {
  if (!spelling || !*spelling || _numeric_prefix(spelling)) return 0;
  unsigned char first = (unsigned char) spelling[0];
  if (first < 33 || first > 126) return 0;
  if (strchr("()'`,\"#@$[]{}<\\", first)) return 0;
  int length = spelling.len();
  return scan_atom(spelling) == length;
}

/** Appends the exact spelling of `atom` to `out`.
    Neither representation allocates a `String`. An `<lsym>` `Atom` already
    owns
    its bytes, and a compact `<symbol>` decodes straight into `out`. An invalid
    `Atom` appends nothing.
    Raises: `<size-limit>` or `<alloc-fail>` when `out` cannot grow.
*/
Buffer Atom.write_str(Atom atom, Buffer out) {
  if (atom is <symbol>) return Symbol.write_str(atom, out);
  if (atom is <lsym>) return out.write((String) atom.pointer());
  return out;
}

/** Writes the escaped readable spelling of `atom` to `out`.
    The escaping makes the result readable as the same exact `Atom`. An invalid
    `Atom` appends nothing.
    Raises: `<alloc-fail>` while decoding a compact `Atom`, or
    `<size-limit>` or
    `<alloc-fail>` when `out` cannot grow.
*/
Buffer Atom.write_repr(Atom value, Buffer out) {
  static const char hex[] = "0123456789ABCDEF", String spelling = value.str();
  for (int i = 0, n = spelling.len(); i < n; i++) {
    unsigned char ch = (unsigned char) spelling[i];
    if (!_escape_byte(spelling, i)) {
      out.write_char((char) ch);
      continue;
    }
    char escaped[4] = {
      '\\', 'x', hex[(ch >> 4) & 0xf], hex[ch & 0xf]
    };
    out.write_len(escaped, sizeof escaped);
  }
  return out;
}

#pragma private

#include "buffer.x"
#include "dispatch.x"
#include "scan.x"
#include "string.x"
#include "symbol.x"

#include <stdlib.h>

/** Reports whether `value` is an exact-spelling `Atom`. */
int Var.is_atom(Var value) => value is <symbol> || value is <lsym>;

/** Returns the exact spelling of `atom` as a `String`.
    A compact `Atom` is decoded and canonicalized through the active pool
    chain.
    A long `Atom` returns its borrowed canonical spelling under the module
    lifetime rule above. An invalid `Atom` returns NULL.
    Raises: `<alloc-fail>` while canonicalizing a compact spelling.
*/
String Atom.str(Atom atom) {
  if (atom is <symbol>) return atom.symbol();
  if (atom is <lsym>) return (String) atom.pointer();
  return NULL;
}

/** Returns the first byte of `atom`'s exact spelling, or NUL when invalid.
    Raises: the same causes as `Atom.str`.
*/
char Atom.first(Atom atom) {
  String spelling = atom.str();
  return spelling ? spelling[0] : '\0';
}

static int _numeric_prefix(String spelling) {
  int length = spelling.len();
  unsigned char first = (unsigned char) spelling[0];
  if (first >= '0' && first <= '9') return 1;
  if (length > 1 && (first == '+' || first == '-' || first == '.') &&
      spelling[1] >= '0' && spelling[1] <= '9')
    return 1;
  return 0;
}

static int _escape_byte(String spelling, int index) {
  int length = spelling.len();
  unsigned char ch = (unsigned char) spelling[index];
  if (index == 0 && _numeric_prefix(spelling)) return 1;
  if (ch < 33 || ch > 126) return 1;
  if (strchr("()'`,\"$@[]{}#\\", ch)) return 1;
  if (index == 0 && ch == '<' && strchr(spelling + 1, '>')) return 1;
  if (ch == '/' && index + 1 < length &&
      (spelling[index + 1] == '/' || spelling[index + 1] == '*'))
    return 1;
  return 0;
}

static String _repr(Var value) {
  Buffer out = Buffer.new(0);
  Atom.write_repr(value, out);
  String result = out.str_free();
  return result;
}

static unsigned _hash(Var value) => ((String) value.pointer()).hash();

static int _equal(Var left, Var right) {
  (void) left;  (void) right;
  /* Atom.intern makes equal spellings bit-identical, so reaching descriptor
     equality after the raw-Var fast path proves the values are unequal. */
  return 0;
}

static int _compare(Var left, Var right) =>
  ((String) left.pointer()).compare((String) right.pointer());

static int _truth(Var value) => value.pointer() != NULL;

/** Initializes the process-wide `Atom` runtime owner.
    Repeated calls after successful registration have no effect.
    Raises: `<bad-state>` after descriptor registration is frozen,
    `<alloc-fail>` while lower-casing the descriptor name, or `<init-fail>`
    when registration returns zero.
*/
void Atom.initialize(void) {
  static int initialized = 0;
  if (initialized) return;
  VarMethods methods = {
    .str = (VarStrFn) Atom.str,
    .repr = _repr,
    .hash = _hash,
    .equal = _equal,
    .compare = _compare,
    .truth = _truth,
    .write_str = Atom.write_str,
    .write_repr = Atom.write_repr
  };
  if (!x2c_try_register_descriptor("lsym", methods))
    raise %(init-fail (owner "Atom"));
  initialized = 1;
}

static Symbol _exact_7bit(String spelling) {
  int length = spelling.len();
  if (length > SYMBOL_MAX_7BIT) return 0;
  Symbol result = 0;
  foreach (int byte, spelling) {
    unsigned char ch = byte;
    if (ch > 0x7f) return 0;
    result = (result << 7) | ch;
  }
  return (result << 1) | 1;
}

/* True when `compact` decodes to `canonical`. Comparing the decoded bytes
   keeps the encoding check off the String pool; a round trip through
   Symbol.str would probe the pool once per candidate. */
static int _decodes_to(Symbol compact, String canonical, int length) {
  if (!compact) return 0;
  char text[SYMBOL_MAX_5BIT + 1];
  compact.decode(text);
  return (int) strlen(text) == length && !memcmp(text, canonical, length);
}

/** Returns the canonical `Atom` with the supplied exact spelling.
    Repeated interning of equal bytes returns a bit-identical `Atom`. A
    spelling
    that round-trips through either compact encoding becomes an immediate
    `Symbol`; every other spelling borrows its canonical `String` under the
    module
    lifetime rule above. Use `Atom.promote` before a long `Atom` escapes its
    innermost owning pool.
    Raises: `<bad-arg>` when `spelling` is null or empty, `<alloc-fail>` when
    its canonical `String` cannot be allocated, or `<bad-enc>` if the
    long-`Atom`
    pointer cannot be boxed.
*/
Atom Atom.intern(String spelling) {
  if (!spelling || !*spelling) raise %(bad-arg (owner "Atom.intern"));
  String canonical = String.new(spelling), int length = canonical.len();
  Symbol compact = Symbol.new_len(canonical, length);
  if (_decodes_to(compact, canonical, length))
    return compact;
  compact = _exact_7bit(canonical);
  if (_decodes_to(compact, canonical, length))
    return compact;
  return Var.new(<lsym>, canonical);
}
