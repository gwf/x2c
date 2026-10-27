/*  operations.x -- List matching through the current cache */

/* the List.match family

   Each operation prepares its pattern through the active default cache on
   first use and reuses the program afterward. `try_*` output pointers are
   required, remain unchanged on failure, and receive `nil` bindings for a
   successful match with no user binders. */

/** Matches a runtime pattern into positional storage.
    The active default cache prepares the pattern on its first use and
    reuses that program afterward. Returns 1 on success and 0 on a miss,
    malformed pattern, invalid buffer, cache pressure, or machine error. A
    nonnull buffer is written atomically as described by
    `MatchCaptureBuffer`; NULL returns 0.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or matching.
*/
int x2c_match_try_capture(
  List input, Var pattern, MatchCaptureBuffer &?captures) {
  if (!captures) return 0;
  return MatchCache.current().try_capture(input, pattern, captures, "match");
}

/** Matches `input` against `pat`, writing bindings on success.
    Returns 1 on a match and writes a reverse-slot-order association `List`, or
    returns 0 and leaves `out_bindings` unchanged. A successful binder-free
    match writes `nil`. A null output pointer returns 0.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing captures, or publishing bindings.
*/
int List.try_match(List input, Var pat, List &?out_bindings) => out_bindings &&
  MatchCache.current().try_match(input, pat, out_bindings, "List.try_match");

/** Returns bindings when `input` matches `pat`, or `nil` on a miss.
    A binder-free success returns the nonnull `%(())` sentinel
    with no associations. Binding order and failures follow `List.try_match`.
*/
List List.match(List input, Var pat) {
  List bindings;
  if (!input.try_match(pat, bindings)) return NULL;
  return bindings ? bindings : %(());
}

/** Matches `input` and writes the instantiated `template` on success.
    The output may be any `Var`, including typed `nil` or a scalar. A template
    that is one binder the match left unbound, such as the binder of an `!or`
    alternative another alternative satisfied, writes that binder. Returns 0
    for a miss, malformed pattern, invalid output, or machine error and leaves
    `out` unchanged.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing, or replacing.
*/
int List.try_match_replace(List input, Var pat, Var template, Var &?out) =>
  out && MatchCache.current().try_match_replace(
    input, pat, template, out, "List.try_match_replace");

/** Returns the `List` replacement when `input` matches `pat`.
    A miss returns `input` unchanged. A successful scalar replacement cannot
    inhabit the `List` result and returns `nil`. Matching and replacement
    failures follow `List.try_match_replace`.
*/
meta native List List.match_replace(List input, Var pat, Var template) {
  Var result;
  if (!input.try_match_replace(pat, template, result)) return input;
  return result is <list> ? result : NULL;
}

/** Returns every matching subtree of `input` with its bindings.
    Each result begins with `(* matched)` followed by reverse-slot-order binder
    pairs. Traversal visits a `List`'s head, then tail, then the `List` itself;
    results are prepended and therefore returned in reverse visitation order.
    Explicit `nil` values are nodes, but a proper `List`'s terminal cdr is not.
    A miss, malformed pattern, or machine error returns `nil`.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or constructing results.
*/
List List.search(List input, Var pat) {
  List results;
  MatchCache.current().search(input, pat, results, "List.search");
  return results;
}

/** Searches `input` for `pat`, writing the first match and bindings.
    The depth-first order is head, tail, then containing `List`, with the same
    explicit-`nil` rule as `List.search`. Returns 1 on success; otherwise
    returns 0 and leaves both outputs unchanged. Either null output returns 0.
    Raises: the same causes as `List.search`.
*/
int List.try_search(
  List input, Var pat, Var &?out_match, List &?out_bindings) =>
    out_match && out_bindings && MatchCache.current().try_search(
      input, pat, out_match, out_bindings, "List.try_search");

/** Replaces every matching subtree in `input` from the leaves upward.
    Children are rewritten before their reconstructed containing `List` is
    tested. A miss, malformed pattern, or machine error returns `input`
    unchanged. New structure follows the module pool-chain lifetime above.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, traversing, or replacing.
*/
List List.search_replace(List input, Var pat, Var template) {
  List result;
  MatchCache.current().search_replace(
    input, pat, template, result, "List.search_replace");
  return result;
}
