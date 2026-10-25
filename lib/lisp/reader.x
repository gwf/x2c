/*  reader.x -- Lisp reader

    Copyright (c) 2026 Gary William Flake.
*/

/** Reads one Lisp form and returns `<value>` or `<eof>`.
    A nonnull `out` receives the form only for `<value>`; it is otherwise
    unchanged. New result storage uses the caller's active `Scope` and
    canonical pools, not the temporary token `Scope`, and remains valid
    until those owners are released. On success `cursor` advances past the
    form, at EOF it becomes the source length, and on a reader error it
    identifies the failing form's first token. A null source or cursor
    returns `<eof>` without raising. A nonnull cursor must initially hold a
    byte offset no greater than the source length. Reading needs no session:
    `lisp` is not consulted and may be null, including before any session has
    been constructed.
    Raises: `<incomplete>` for a truncated form, `<malformed>` for invalid
    reader syntax, or `<alloc-fail>`, `<size-limit>`, or `<bad-enc>` while
    tokenizing, constructing, interning, or boxing the form.
*/
Symbol Lisp.read(Lisp lisp, String source, unsigned &?cursor, Var &?out) {
  (void) lisp;
  if (!source) return <eof>;
  if (!cursor) return <eof>;
  unsigned base = cursor;
  Scope tokens_scope = auto Scope.new_named("Lisp tokens");
  Tokenizer tokenizer = datum_scan_tokens(source + base, &tokens_scope);
  return datum_read_token_form(tokenizer, source, base, cursor, out);
}
