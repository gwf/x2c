/*  adapters.x -- String adapters operations */

// conversions

/** Returns `str` itself as its display `String` without copying or retaining
    it.
*/
String String.str(String str) => str;

/** Appends `str` to `out` unchanged.
    A `String` is already its own display text, so this writes it directly
    instead of routing through `String.str`. `Null` `str` is a no-op. The
    borrowed `out` is returned and not retained.
    Raises: any cause from `Buffer.write`.
*/
Buffer String.write_str(String str, Buffer out) => str ? out.write(str) : out;

/** Returns the compact `Symbol` encoded from `str`, or zero for empty input.
    `Symbol`'s restricted spelling folds case and `_` with `-`; other spellings
    use seven-bit bytes, and input beyond the selected encoding's capacity is
    truncated. Use `Symbol.try_new` when every byte must be preserved.
*/
meta native Symbol String.symbol(String str) {
  if (!str || !*str) return 0;
  return Symbol.new(str);
}

// iteration

/** Initializes `dest` as a lazy iterator over the bytes of `x`.
    The caller owns `dest`; it borrows `x`, which must remain live through
    traversal. A null `dest` returns NULL, and null `x` is exhausted. Each pull
    yields the next byte as an `<i32>` `Var` in index order. The function
    retains neither argument.
    Foreach may convert each yielded byte to either `int` or `char`:

    ```x2c
    foreach (int byte, "abc") printf("%d\n", byte);
    foreach (char ch, "abc") printf("%c\n", ch);
    ```

    This is byte traversal, not Unicode character iteration.
*/
Iter String.iter(String x, Iter dest) {
  if (!dest) return NULL;
  return dest.init(x, _next, 0);
}

static int _next(Iter iter, Var *out) {
  int index = iter.state, String str = iter.obj;
  if (index < 0 || index >= str.len()) return 0;
  *out = str[index];
  iter.state = index + 1;
  return 1;
}

/** Writes the next byte, advances `cursor`, and returns one.
    Initialize the caller-owned cursor to zero. A null `String`, a null
    pointer, a negative cursor, or exhaustion returns zero without changing
    `cursor` or `out`. This is byte traversal, not Unicode characters.

    `foreach (int byte, str)` and `foreach (char ch, str)` compile to this
    loop.
*/
int String.try_next(String str, int &?cursor, int &?out) {
  if (!cursor) return 0;
  if (!out) return 0;
  if (!str || cursor < 0) return 0;
  if (cursor >= str.len()) return 0;
  out = str[cursor];
  cursor += 1;
  return 1;
}
