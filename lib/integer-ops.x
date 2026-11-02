/*  integer-ops.x -- shared native arithmetic templates

    Copyright (c) 2026 Gary William Flake

    `Var` operators and the compound updates of typed Arrays and typed Maps
    share these templates. The statement templates expand inline, so a
    public inline element update uses them without a call. The update
    templates end the enclosing function: each returns the stored value or
    raises before changing the element, with the causes `Var.update` raises.
*/

#pragma once
#include "var/var.x"

/*  Stores in `$raw` the low `$bits` bits of integer `$operator` applied to
    `$a` and `$b`, which contain only their low bits, with 0 < bits <= 64.
    Callers validate shift counts and own promotion, diagnostics for those
    counts, and result storage or boxing.
*/
macro Stmt $integer.step(
  Name $raw, Expr $operator, Expr $a, Expr $b, Expr $bits,
  Expr $unsigned_value
) {
  Symbol op = $operator;
  unsigned long long a = $a, b = $b;
  int bits = $bits, unsigned_value = $unsigned_value;
  // not `Var.width_mask`, which would be a call in an inline update
  unsigned long long mask = bits < 64 ? (1ull << bits) - 1 : ~0ull;
  switch (op) {
    case <+>: $raw = a + b; break;
    case <->: $raw = a - b; break;
    case <*>: $raw = a * b; break;
    case <&>: $raw = a & b; break;
    case <|>: $raw = a | b; break;
    case <^>: $raw = a ^ b; break;
    case </>: case <%>:
      if (!b) raise %(div-zero (op $op));
      if (unsigned_value) $raw = op == </> ? a / b : a % b;
      else {
        long long signed_a = Var.signed_from_bits(a, bits);
        long long signed_b = Var.signed_from_bits(b, bits);
        unsigned long long minimum = 1ull << (bits - 1);
        if (a == minimum && b == mask) $raw = op == </> ? minimum : 0;
        else $raw = op == </> ? (unsigned long long) (signed_a / signed_b)
                              : (unsigned long long) (signed_a % signed_b);
      }
      break;
    case <"<<">: $raw = a << b; break;
    case <">>">:
      $raw = a >> b;
      if (!unsigned_value && b && (a & (1ull << (bits - 1))))
        $raw |= mask << (bits - b);
      break;
    default: raise %(bad-op (op $op));
  }
  $raw &= mask;
}

/*  Generates `$name`, which returns the `$integer.step` result for its
    arguments.
*/
macro Unit $integer.raw(Name $name) {
  static inline unsigned long long $name(
    Symbol op, unsigned long long a, unsigned long long b,
    int bits, int unsigned_value) {
    unsigned long long raw;
    $integer.step(raw, op, a, b, bits, unsigned_value);
    return raw;
  }
}

/*  Applies integer `$operator` to the signed `$type` element at `$slot`.
    The operation runs at the C-promoted width, `int` or a wider `$type`,
    and the result converts back to `$type` as a native compound assignment
    does. A shift count outside the promoted width raises `<bad-shift>`.
*/
macro Stmt $integer.update(
  Type $type, Expr $slot, Expr $operator, Expr $rhs
) {
  $type *slot = $slot, rhs = $rhs;
  Symbol op = $operator;
  int bits = sizeof($type) > sizeof(int) ? 64 : 32;
  unsigned long long mask = bits == 64 ? ~0ull : 0xFFFFFFFFull, raw;
  if ((op == <"<<"> || op == <">>">) &&
      (rhs < 0 || (long long) rhs >= bits)) {
    long long count = rhs;
    raise %(bad-shift (op $op) (count $count) (width $bits));
  }
  $integer.step(
    raw, op, (unsigned long long) slot[0] & mask,
    (unsigned long long) rhs & mask, bits, 0);
  return slot[0] = ($type) raw;
}

/*  Applies floating `$operator` to the `$type` element at `$slot`.
    An integer-only numeric operator raises `<bad-types>` and any other
    operator `<bad-op>`.
*/
macro Stmt $floating.update(
  Type $type, Expr $slot, Expr $operator, Expr $rhs
) {
  $type *slot = $slot, rhs = $rhs;
  Symbol op = $operator;
  switch (op) {
    case <+>: return slot[0] += rhs;
    case <->: return slot[0] -= rhs;
    case <*>: return slot[0] *= rhs;
    case </>: return slot[0] /= rhs;
    case <%>: case <&>: case <|>: case <^>: case <"<<">: case <">>">:
      raise %(bad-types (op $op));
  }
  raise %(bad-op (op $op));
}

/*  Concatenates `$rhs` onto the canonical String at `$slot`, the only
    String update; another operator raises `<bad-op>`.
*/
macro Stmt $string.update(Expr $slot, Expr $operator, Expr $rhs) {
  String *slot = $slot;
  Symbol op = $operator;
  if (op != <+>) raise %(bad-op (op $op));
  String result = slot[0] + $rhs;
  return slot[0] = result;
}
