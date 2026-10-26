/*  primitives.x -- Lisp primitives

    Copyright (c) 2026 Gary William Flake.
*/

/* primitives

   The native operations Lisp code reaches through `bind`. A predicate
   answers `<true>` or nil. */

static Var _bool(int x) { if (x) return <true>; return %(); }

/** Returns Lisp true for every value except nil and `void`. */
Var lisp_truth(Var value) => _bool(value is not void && !value.is_nil());

/** Returns Lisp true unless `value` is a nonempty `List`. */
Var lisp_atom(Var value) => _bool(value is not <list> || value.is_nil());

/* `Var.car` and `Var.cdr` read the raw payload as a cell, which is the right
   contract for a caller that already typed the value. Lisp applies these to
   whatever the program evaluated, so the tag is checked here first. */

/** Returns the first element of `value`, or `void` when it is `nil`.
    A nonlist operand raises `<bad-types>`.
*/
Var lisp_car(Var value) {
  if (value is not <list>)
    raise %(bad-types (operation "car") (kind $(value.kind())));
  return value.car();
}

/** Returns the tail of `value`, or `nil` when it is `nil`.
    A nonlist operand raises `<bad-types>`.
*/
Var lisp_cdr(Var value) {
  if (value is not <list>)
    raise %(bad-types (operation "cdr") (kind $(value.kind())));
  return value.cdr();
}

/** Returns Lisp true when `a` and `b` are equal by `Var.equal`. */
Var lisp_eq(Var a, Var b) => _bool(a.equal(b));

/** Returns Lisp true when `value` is a nonempty `List`. */
Var lisp_pair(Var value) => _bool(value is <list> && !value.is_nil());

/** Returns Lisp true when `value` is `List`-typed, including `nil`. */
Var lisp_list(Var value) => _bool(value is <list>);

static int _is_lisp_number(Var value) {
  Symbol kind = value.kind();
  return kind == <integer> || kind == <floating>;
}

/** Returns Lisp true when `value` has an integer or floating kind. */
Var lisp_number(Var value) => _bool(_is_lisp_number(value));

/** Returns Lisp true when `value` is a `String`. */
Var lisp_string(Var value) => _bool(value is <string>);

/** Returns Lisp true when `value` has `Symbol` kind. */
Var lisp_symbol(Var value) => _bool(value.kind() == <symbol>);

/** Returns Lisp true when `value` is a native function or Lambda. */
Var lisp_procedure(Var value) => _bool(value is <func> || value is <lambda>);

/** Returns the runtime tag of `value`. */
Symbol lisp_type(Var value) => value.tag();

// numbers

/* Orders the four number classes the total order uses:
   -inf < finite < +inf < NaN. */
static int _number_class(Var value, long double magnitude) {
  Symbol tag = value.tag();
  if (tag == <-inf>) return 0;
  if (tag == <+inf>) return 2;
  if (tag == <nan> || magnitude != magnitude) return 3;
  if (magnitude == 1.0L / 0.0L) return 2;
  if (magnitude == -1.0L / 0.0L) return 0;
  return 1;
}

/* `Var.compare` is a total order over every value, so it separates two
   encodings of the same number by rank to give each one its own place in a
   sort. Lisp `=`, `<`, and `<=` answer about numbers, so 1 and 1.0 are one
   number here and comparison stops at the value. */
static int _number_compare(Var a, Var b) {
  Symbol ak = a.kind(), bk = b.kind();
  long double da = ak == <floating> ? a.long_double() : 0.0L;
  long double db = bk == <floating> ? b.long_double() : 0.0L;
  int ca = _number_class(a, da), cb = _number_class(b, db);
  if (ca != cb) return ca < cb ? -1 : 1;
  if (ca != 1) return 0;
  if (ak == <integer> && bk == <integer>) return a.integer_compare(b);
  if (ak == <integer>) return a.integer_floating_compare(b);
  if (bk == <integer>) return -b.integer_floating_compare(a);
  return da < db ? -1 : da > db;
}

/** Compares Lisp numbers by value and returns a boxed negative, zero, or
    positive. Integer and floating encodings of one number compare equal.
    A nonnumeric operand raises `<bad-types>`.
*/
Var lisp_compare(Var a, Var b) {
  if (!_is_lisp_number(a) || !_is_lisp_number(b))
    raise %(bad-types (operation "lisp_compare") (left-kind $(a.kind()))
                       (right-kind $(b.kind())));
  return _number_compare(a, b);
}

/** Concatenates when either operand is `String`, otherwise adds dynamically.
*/
Var lisp_add(Var a, Var b) {
  if (a is <string> || b is <string>) return %"$a$b";
  return a.binary(<+>, b);
}

/** Adds or concatenates every value left to right; no values gives 0. */
Var lisp_plus(List values) {
  Var total = 0;
  if (values && values.car() is <string>) total = %"";
  foreach (Var value in values) total = lisp_add(total, value);
  return total;
}

/** Subtracts each later value from the first; one value negates it.
    An empty input raises `<bad-arity>`.
*/
Var lisp_minus(List values) {
  if (!values) raise %(bad-arity (operation "-") (expected 1) (actual 0));
  Var total = values.car();
  if (!values.cdr()) {
    Var zero = 0;
    return zero.binary(<->, total);
  }
  foreach (Var value in values.cdr()) total = total.binary(<->, value);
  return total;
}

/** Multiplies every value; no values gives 1. */
Var lisp_times(List values) {
  Var total = 1;
  foreach (Var value in values) total = total.binary(<*>, value);
  return total;
}

/** Divides the first value by each later one; one value reciprocates it.
    An empty input raises `<bad-arity>`.
*/
Var lisp_divide(List values) {
  if (!values) raise %(bad-arity (operation "/") (expected 1) (actual 0));
  Var total = values.car();
  if (!values.cdr()) {
    Var one = 1;
    return one.binary(</>, total);
  }
  foreach (Var value in values.cdr()) total = total.binary(</>, value);
  return total;
}

/* Every comparison holds pairwise along the whole chain. `want` is the
   order each neighbouring pair must have, or must avoid when `expect` is
   zero, so `<=` and `=` read as one rule. */
static Var _chain(List values, String operation, int want, int expect) {
  int actual = values.len();
  if (actual < 2)
    raise %(bad-arity (operation $operation) (expected 2) (actual $actual));
  for (List p = values; p.cdr(); p = p.cdr()) {
    Var (left, right) = p;
    int order = lisp_compare(left, right);
    if (expect ? order != want : order == want) return _bool(0);
  }
  return _bool(1);
}

/** Reports whether every neighbouring pair of numbers compares equal.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_eq_chain(List values) => _chain(values, "=", 0, 1);

/** Reports whether two or more numbers strictly increase.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_lt_chain(List values) => _chain(values, "<", -1, 1);

/** Reports whether two or more numbers never decrease.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_le_chain(List values) => _chain(values, "<=", 1, 0);

/** Reports whether two or more numbers strictly decrease.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_gt_chain(List values) => _chain(values, ">", 1, 1);

/** Reports whether two or more numbers never increase.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_ge_chain(List values) => _chain(values, ">=", -1, 0);

// strings and files

/** Boxes the display `String` of `value`. */
Var lisp_str(Var value) => value.str();

/** Boxes the readable representation of `value`. */
Var lisp_repr(Var value) => value.repr();

/** Returns the boxed concatenation of `left` and `right`. */
Var lisp_string_append(String left, String right) => left + right;

/** Returns the boxed unit-step slice `string[start:stop]`. */
Var lisp_substring(String string, int start, int stop) =>
  string.getslice(start, stop, 1);

/** Returns a boxed lower-case copy of `string`. */
Var lisp_string_downcase(String string) => string.lower();

static char *_string_charset(Var chars) =>
  chars.is_nil() || (chars.is_integer() && !chars.integer())
    ? NULL : chars.string();

/** Trims the bytes in `chars`, using whitespace for an empty String. */
String lisp_string_strip(String string, Var chars) =>
  string.strip(_string_charset(chars));

/** Trims leading bytes, accepting the same charset values as `strip`. */
String lisp_string_lstrip(String string, Var chars) =>
  string.lstrip(_string_charset(chars));

/** Trims trailing bytes, accepting the same charset values as `strip`. */
String lisp_string_rstrip(String string, Var chars) =>
  string.rstrip(_string_charset(chars));

/** Returns the instantiated `template` when `input` matches `pat`.
    `List.match_replace` returns a `List`, so a template that is a bare binder
    loses a scalar result. Lisp sees the replacement itself. A miss, malformed
    pattern, cache pressure, or machine error returns `input` unchanged.
*/
Var lisp_match_replace(List input, Var pat, Var template) {
  Var result;
  if (!input.try_match_replace(pat, template, result)) return input;
  return result;
}

/** Reads `path` completely, closes it, and returns its boxed `String`
    contents. Raises the open, read, size, or allocation cause reported by
    `File`. An opened stream is still closed on transfer.
*/
Var lisp_read_file(String path) => path.open("r").string_close();

/** Replaces `path` with `text` and reports Lisp success.
    The file is opened with truncation and always closed. A write or close
    failure returns `nil` after any accepted bytes; this operation is not
    atomic. An open failure transfers its `File` cause. `Null` text writes
    an empty file.
*/
Var lisp_write_file(String path, String text) {
  File file = path.open("w");
  int wrote = !text || file.puts(text) >= 0, closed = file.close() == 0;
  return _bool(wrote && closed);
}
