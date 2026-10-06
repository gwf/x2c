> Status: reference
> Reviewed 2026-10-06 at dev cb67de5ec658af4f9108433f24f062543c6087d4.
> Catalog and mitigation recommendations only. No production source changed.
> Delivery uses the shared integration agent; implementation remains unperformed.

# Explicit protocol-call catalog

The most useful first cleanup is membership and indexed access. The requested
narrower pattern covers 147 occurrences in 34 files when the trailing `.*;`
restriction is removed. Only 83 match the exact pattern. Conditions and
multiline calls account for the difference; requiring a semicolon misses useful
candidates.

```regex
\.\s*(?:contains|getindex|setindex|updateindex|postfixindex)\s*\(
```

The [full catalog](var-protocol-call-catalog.csv) records every occurrence of
the original 16 method names, including definitions and comments. Filter its
`method` column for these five names. Each row gives its source location,
receiver, disposition, suggested spelling, reason, and evidence. Locations
refer to the recorded baseline. Non-ASCII source characters use `\u` escapes
in this ASCII export.

## Membership and indexed access

| Method | Syntax candidates | Need probes | Retain calls | Definitions |
| --- | ---: | ---: | ---: | ---: |
| `contains` | 57 | 0 | 1 | 15 |
| `getindex` | 1 | 1 | 8 | 19 |
| `setindex` | 2 | 1 | 1 | 11 |
| `updateindex` | 2 | 0 | 1 | 14 |
| `postfixindex` | 0 | 0 | 1 | 12 |

A syntax candidate has a source-level reason to use an operator. It is not a
validated patch. Preserve operand types, negation, evaluation, and result use
when implementing a replacement. `safe_candidate` is the CSV name for this
category; `required_call` means retain the current call in this cleanup.

- Replace ordinary `collection.contains(key)` with `key in collection`.
  Negation needs `!(key in collection)`. The 57 candidates span String, List,
  Array, Map, and SymbolSet. The compiler resolves `in` against the collection
  and rebuilds the call with collection first (`src/expressions.x:2570-2645`).
- Replace the ordinary `getindex` call in SymbolSet's iterator helper at
  `lib/symbolset.x:132` with brackets. Its index already passed a bounds check.
- Retain the six RegexCapture getter calls at `lib/regex.x:803-818` for now.
  A direct bracket rewrite fails to compile. Bracket lookup seeks `RegexCapture_getindex`, which does not exist, then
  falls back to native `struct List *` indexing. Direct member calls instead
  resolve `List_getindex` (`src/expressions.x:1397-1455`). Keep these calls;
  adding an adoption only to change their spelling is not justified here.
- Replace the two Map `setindex` calls at `lib/error.x:657,762` with bracket
  assignments. Keep the same key and value expressions.
- Probe `src/meta-sdk-reports.xmacro:65` before using brackets. Its macro
  parameters must retain the List/int types after substitution.
- Probe `lib/map-generics.xmacro:934` before using bracket assignment. Confirm
  the generated key/value boxing and evaluation order.

Two `updateindex` calls in `lib/array-generics.xmacro:33-34` can use
`array[index] += 1` and `array[index] -= 1`. Compound assignment resolves
`updateindex` (`src/transform.x:1508,1611-1642`), preserving the saved old
value returned by the enclosing method. Postfix `array[index]++` would instead
recurse through that enclosing `postfixindex` method.

Negative indexing does not prevent the ordinary replacements above. SymbolSet
brackets select the same getter; typed array compound updates retain raw indexing.
The RegexCapture exception concerns protocol selection, not negative indexing.
This conclusion is specific to these methods, not every `.get` API.

Five calls in `lib/dispatch.x` invoke selected protocol function pointers.
Operators would dispatch again instead of calling those pointers. Retain them.
`Map.getindex` at `lib/native-scalar-types.xmacro:75` is compile-time Lisp;
x2c bracket syntax is not a replacement inside that form. The definitions
implement the protocol and are not cleanup targets.

## Original scan coverage

The original pattern named `str`, `equal`, `truth`, `iter`, `contains`, `add`,
`sub`, `mul`, `div`, `mod`, `matmul`, `neg`, `getindex`, `setindex`,
`updateindex`, and `postfixindex`. This catalog is exhaustive for those names
in tracked `.x`, `.xmacro`, and `.xlisp` files under `lib/` and `src/` at the
baseline. It is not an audit of every conversion or every protocol method.

The original greedy regex produces 406 matches, covering 424 individual
occurrences. A match can consume multiple calls on one line. Removing `.*;`
finds 601 occurrences in 81 files, including multiline declarations and calls.
Three Sol workers reviewed disjoint groups: 299 runtime rows, 142 compiler
core rows, and 160 other compiler rows. The combined inventory was checked
against the current source for exact occurrence-ID coverage and duplicates.

| Disposition | Occurrences |
| --- | ---: |
| Source-reviewed syntax candidates | 160 |
| Candidates needing further proof | 29 |
| Retain current calls | 220 |
| Declarations and definitions | 174 |
| Comments and generated strings | 18 |

Most candidate changes improve source spelling while generating the same
runtime calls. No compiler speedup, executable-size saving, or removal of
protocol implementations is claimed.

## Conversion and dispatch boundaries

- `Var.str()` displays a value. Implicit Var-to-String conversion extracts
  its String payload. They are not interchangeable.
- `Atom` aliases Var, but `Atom.str()` calls `Atom_str`. Implicit conversion
  calls `Var_string`. A compact Atom spelling can become an empty String.
- Static Symbol arguments to native `printf("%s", ...)` still need text
  conversion. Automatic `%s` formatting handles static Var arguments, not
  numeric Symbol values (`src/transform.x:1293`).
- A Buffer or Symbol assigned to a typed String destination can use the same
  implicit conversion. Boxing into Var, constructing an AST literal token,
  or passing native variadic arguments requires separate analysis.
- Typed List and String equality can use `==`; `===` tests identity.
  Mixed Var/typed operands need their own binding proof.
- Boolean conditions can use values directly. A stored truth result may need
  `!!value`. Replacing two eager truth initializers with `lhs && rhs` would
  skip evaluation of the right operand.
- `String.add(Var)` converts the argument with `Var_string`. `String + Var`
  takes the dynamic `Var_binary` path. A textual rewrite changes behavior.
- Operators inside their own implementing methods can recurse. Compiler
  helper code containing operators is not itself such a recursion boundary.
- Custom `add` methods on compiler state are not arithmetic operations.
  Explicit iterator storage arguments also have no plain foreach equivalent.

## Focused verification

After `make build-safe`, focused scratch programs were compiled with the
baseline compiler. Generated C was inspected where target selection mattered.
The programs and complete logs remain in the originating workspace under
`/tmp/x2c-var-call-audit/` and `debug/var-call-catalog/`; they are not permanent
fixtures or new checks.

| Comparison | Observed result |
| --- | --- |
| Typed List `.equal` / `==` | Both emit `List_equal`; both return 1 for the probe's matching lists. |
| Typed String `.equal` / `==` | Both emit `String_equal`; both return 1 for transient and interned `abc`. |
| RegexCapture `.getindex(0).int()` / `[0].int()` | Direct call compiles; bracket variant fails with `type (struct "List") has no method int`. Six proposed bracket rewrites were removed from the straightforward group. |
| List `.contains` / `in` | Both emit `List_contains`; both return 1 for member 2. |
| Buffer/Symbol explicit conversion / typed String destination | Same `Buffer_str` / `Symbol_str` calls; equal resulting strings. |
| Var `.truth()` / `!!value` | Same `Var_truth` boundary; both return 1 for 42. |
| Static Var `%s` with / without `.str()` | Both format 42 using `Var_str`. |
| Atom explicit / implicit String conversion | `Atom.intern("hello")` displays `hello` explicitly; implicit String length is zero. |
| Static Symbol `%s` without `.str()` | Generated C passes the numeric Symbol directly. Inspected only; unsafe variant was not executed. |
| `String.add(Var)` / `String + Var` | Generated targets differ: `String_add(a, Var_string(b))` versus `Var_string(Var_binary(String_var(a), 56, b))`. |

These are representative semantic probes, not validation of every proposed
replacement. No production diff, complete cleanup build, or performance
comparison exists yet.

## Recommended mitigation

Start with the five-method subset above, then typed equality, truth conditions,
and identity String conversions from the larger catalog. Review each receiver
and macro expansion rather than replacing text across files. Resolve the
conditional rows with generated-code and behavior comparisons before editing.
Retain the RegexCapture calls. Their direct rewrite is already disproved by
the focused compilation probe; a broader indexing change needs its own design.

The compiler already warns about certain unnecessary explicit conversions in
`src/expressions.x:3050-3168`. The probes exercised those warnings for typed
String destinations and static Var `%s` formatting. Reuse that mechanism for
conversion cleanup. This audit does not justify another linter or recurring
gate. Submit coherent implementation batches to the shared integrator under
the existing validation workflow.
