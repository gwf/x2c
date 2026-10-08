# Lexical specification

This is an operational specification of `lib/scan.x`, `lib/tokenizer.x`,
and the token reclassification in `src/compiler.x` at the
[extraction revision](index.md). Rules are ordered where order affects
recognition. The [source grammar](grammar.md) consumes their output.
The same rules are available as [structured List data](data.md), with a
[generated inventory](lexical-data.md).

## Input and output

Input is a NUL-terminated byte sequence. The first NUL ends scanning in
every mode. There is no global UTF-8 validation pass. Identifiers use ASCII
classes; quoted text and atoms can contain other bytes subject to their
own delimiters. The separate `scan_utf8_length` helper is not such a pass.

A token is `(type, text, pos, len, line, col)`. `pos` is a zero-based byte
offset; `len` is a byte count. Lines and columns start at one. LF increments
the line and sets the next column to one. Every other byte, including CR
and tab, advances the column by one. Token text is copied from the input.

`space` and `comment` tokens remain in physical storage.
`Tokenizer.next` skips those two kinds, retaining `preproc`. Compiler token
navigation also skips directives where appropriate, preserving their source
and conditional context separately. End of input emits zero-width `eof`.
An unclosed lexical mode alone does not make EOF a lexical error: the parser
or Lisp reader diagnoses the missing delimiter.

## Byte classes and trivia

In the productions below, quoted characters denote bytes. `|` is choice,
`,` is concatenation, `[ ]` is optional, and `{ }` repeats zero or more times.
Range descriptions name ASCII bytes. The productions do not override the
ordered mode dispatch below.

```ebnf
letter = ? A-Z or a-z ? ;
digit = ? 0-9 ? ;
hex-digit = digit | ? A-F or a-f ? ;
octal-digit = ? 0-7 ? ;
binary-digit = "0" | "1" ;
identifier = ( letter | "_" ) , { letter | digit | "_" } ;
white-byte = ? SP HT CR VT FF LF ? ;
space = white-byte , { white-byte } ;
line-comment = "//" , { ? byte other than LF or NUL ? } ;
block-comment = "/*" , ? bytes through the first closing */ ? ;
```

Comments do not nest. A block comment without its closing delimiter reports
`incomplete`. A line comment excludes its final LF and may end at NUL.

Where common-token dispatch applies, `#` starts a `preproc` token without a
beginning-of-line requirement. The token ends before an uncontinued LF, or
at NUL. Backslash-LF and backslash-CRLF are included and continue scanning.
A backslash immediately before NUL is malformed. The scanner does not
expand the directive or validate its directive-specific grammar.

## Names, keywords, and punctuation

The initial keyword table is exactly:

```text
associated auto break case catch char const continue default defer delegate
 do double else enum extern finally float for goto if import in inline int
 long match protocol raise register restrict return short signed sizeof
 static struct switch threaded try typedef union unsigned void volatile while
```

Matching is case-sensitive. The following spellings normalize token type
while retaining original token text:

| Source spelling | Token type |
| --- | --- |
| `__inline`, `__inline__` | `inline` |
| `__restrict`, `__restrict__` | `restrict` |
| `thread_local`, `_Thread_local` | `threaded` |

Other words initially emit `ident`, including `is`, `not`, `with`, `as`,
`tag`, `macro`, `keyword`, `using`, `meta`, `native`, `Self`, `class`,
`foreach`, `_Static_assert`, `_Generic`, `offsetof`, and `va_arg`.
Parser context or visible macro definitions give these words their roles.
A named-reference sigil scans the immediately following identifier as
`ident` without applying the keyword table.

The C operator scanner chooses the longest supported prefix from this set:

```text
... >>= <<= === !==
-> ++ -- << >> <= >= == != && ||
+= -= *= /= %= &= ^= |=
- , ; : ! ? . ( ) [ ] { } * / & % ^ + < = > | ~ @
```

`=>` is two tokens: `=` then `>`. `$`, `$(`, `@(`, `${`, `@{`, `?(`,
`%(`, `%[`, `%{`, `%<<`, `%"`, and `%!` are handled by mode dispatch,
not by this operator scanner. The same bytes can therefore have different
roles in different modes.

## Numeric tokens

Numeric recognition first chooses a radix, then scans the selected form.
It is not simply the union of C numeric regular expressions.

1. An explicit `0x`/`0X`, `0b`/`0B`, or `0o`/`0O` selects hexadecimal,
   binary, or octal.
2. Otherwise, `0` immediately followed by `1` through `7` selects legacy
   octal, unless the run of decimal digits is followed by `.`, `e`, or `E`.
   Those three continuations select decimal floating recognition.
3. Every other numeric start selects decimal recognition.

After this dispatch, the following productions apply. A numeric token must
end before a byte outside `letter | digit | "_"`; a bad suffix or radix
continuation fails the token instead of splitting it into a number and name.

```ebnf
decimal-integer = digit , { digit } , integer-suffix ;
binary-integer = ( "0b" | "0B" ) , binary-digit , { binary-digit } ,
                 integer-suffix ;
octal-integer = ( "0o" | "0O" ) , octal-digit , { octal-digit } ,
                integer-suffix ;
legacy-octal = "0" , ? 1-7 ? , { octal-digit } , integer-suffix ;
hex-integer = ( "0x" | "0X" ) , hex-digit , { hex-digit } , integer-suffix ;
integer-suffix = [ unsigned , [ long , [ long ] ]
                 | long , [ long ] , [ unsigned ] ] ;
unsigned = "u" | "U" ;
long = "l" | "L" ;
float-suffix = [ "f" | "F" | "l" | "L" ] ;
exponent-digits = [ "+" | "-" ] , digit , { digit } ;
decimal-exponent = ( "e" | "E" ) , exponent-digits ;
decimal-float = ( digit , { digit } , "." , { digit } , [ decimal-exponent ]
                | "." , digit , { digit } , [ decimal-exponent ]
                | digit , { digit } , decimal-exponent ) , float-suffix ;
hex-float = ( "0x" | "0X" ) ,
            ( hex-digit , { hex-digit } , [ "." , { hex-digit } ]
            | "." , hex-digit , { hex-digit } ) ,
            ( "p" | "P" ) , exponent-digits , float-suffix ;
```

A hexadecimal point requires a `p`/`P` exponent. Integer suffix letters can
mix case. `1f` is malformed; `1.f` is a float. `08`, `09`, and `00` take
the decimal path, `018` is malformed, and `017e3` is decimal floating.
These are scanner facts, not promises that every spelling is valid native C
or fits its eventual value type.

The numeric helper accepts an optional leading sign. Code mode emits `+`
and `-` as operators. List, Lisp, and quoted Array/Map modes invoke signed
numeric recognition only when the sign immediately precedes a decimal digit.
Thus `-.5` is an atom in those modes, while `-0.5` is a numeric token.
An unsigned `.5` starts a number through common-token dispatch.

## Quoted bytes and escapes

A C string starts and ends with `"`. Its contents are ordinary bytes other
than NUL, raw CR/LF, quote, or backslash, plus accepted C escapes. NUL before
the close reports `incomplete`; raw CR/LF reports `malformed`.

A C character literal contains exactly one unescaped byte or one accepted
escape between apostrophes. Empty contents or multiple unescaped bytes fail.
The scanner does not combine wide/UTF-prefixed strings into a single token:
a prefix such as `L` is scanned separately as an identifier.

| Escape after backslash | C string/character | Percent string or quoted Symbol |
| --- | --- | --- |
| `a b f n r t v ' " ?` or backslash | One escaped byte spelling | Same |
| LF or CRLF | Source continuation | Source continuation |
| Lone CR | Rejected | Rejected |
| One to three octal digits | Three digits must start with `0` through `3` | Same |
| `x` or `X` and hex digits | One or more; consumes all following hex digits | One or two hex digits |
| `u` and hex digits | Exactly four | One or two |
| `U` and hex digits | Exactly eight | One or two |
| `$` | Rejected | Accepted only by the percent-string segment scanner |
| Any other escape | Rejected | Rejected |

Widths describe recognition. Unicode scalar validity, decoded numeric range,
and host compiler acceptance are separate questions. Percent-string decoding
removes continuations, normalizes raw CR and CRLF to LF, and decodes escapes.
See `Compiler._parse_text_segment` in `src/literals.x`.

A simple Symbol spelling is `<` followed by one or more non-whitespace,
non-NUL bytes, through the first `>`. A quoted spelling is `<"` followed by
quoted-Symbol contents, then `">`. Quoted Symbols permit raw line breaks
and x2c byte escapes. Compact-Symbol representability and exact round trips
are checked by literal processing, not this scanner.

## Atom boundaries

An ordinary List/Lisp atom stops before any of these unescaped boundaries:
`(`, `)`, apostrophe, backtick, comma, `"`, `$`, `@`, `{`, `[`, whitespace,
or a comment opener. Backslash quotes the next byte for boundary recognition;
a final backslash reports `incomplete`. Quoted Array/Map atoms additionally
stop before `:`, `]`, or `}`. Comma already ends an atom.

A bare SymbolSet atom stops before whitespace, `$`, `@`, or `>>`.
Backslash quotes the next byte. A leading `"` instead scans a quoted Symbol
spelling without angle brackets, so `>>` inside quotes is content.
Other punctuation can belong to a bare set atom. Dispatch still claims a
leading comment, digit, apostrophe, or `#` before the set-atom scanner runs.

## Ordered scanning by mode

Maintain a stack with root mode `x2c` for source or `lisp` for a standalone
Lisp reader. At each position, first test for NUL. Otherwise apply the first
matching successful rule in the current mode. Recognition of a malformed
prefix records failure. Some failure callbacks return zero, so chained
dispatch can still append later tokens; the first EOF ends semantic traversal.

**Common rules**, in order of starting byte, recognize whitespace, `#`
directives, `//` or `/*` comments, C characters at apostrophe, numbers at
a digit, and numbers at `.` followed by a digit.

| Mode | Ordered recognition |
| --- | --- |
| `x2c`, `x2c-par` | Common rules; `$(`/`@(` or `$`/`@` reference; percent forms; eligible angle Symbol; C string; identifier/keyword; C operator |
| `array`, `map` | Common rules; data prefixes; data punctuation; collection atom as `lit-atom` |
| `list` | Data prefixes; data punctuation; common rules; atom as `lit-atom` |
| `lisp`, `macro-lisp` | Lisp `$` reference; reader punctuation/signed number/Symbol; common rules; atom as `ident` |
| `symbol-set` | Common rules; `>>`; `$`/`@`; angle Symbol; set atom as `lit-atom` |
| `string` | `${` or `$` reference; closing `"`; segment scanner as `segment` |

Data-prefix rules recognize `void` as a keyword only in quoted Array/Map
mode, `?(` only in List mode, and `$` interpolation in all data modes.
Array/Map modes recognize `@` prefixes for template sequence slots.
List mode also recognizes runtime `@` splicing. A List `@` immediately
followed by EOF, whitespace, `)`, or `=` instead emits the data atom `@` or `@=`.

Data punctuation recognizes nested `(`, strings, arrays, and maps; collection
closers and colons; reader prefixes; angle Symbols; and a signed number when
the sign precedes a digit. Comma is an element separator in Array/Map mode
and a reader prefix elsewhere; `,@` is one reader-prefix token outside
Array/Map mode. Apostrophe therefore starts a reader form in List/Lisp mode
but a C character in Array/Map mode. Not every recognized reader token is
accepted by every data parser.

In Lisp-shaped modes, `<` stays an atom prefix when its next byte is EOF,
`=`, whitespace, or one of `()'`, backtick, or comma. Otherwise it attempts
a Symbol literal. Standalone Lisp `$` scanning does not provide the data-mode
`${expression}` escape; its reader rejects unsupported token kinds.

In String mode a segment stops before a closing quote or a single unescaped
`$`. Inside a segment, `$$` is consumed as literal content. Dispatch handles
a `$` at the beginning of a segment before calling the segment scanner;
see the implementation edges below.

## Mode transitions

A transition emits the opener/closer token as well as changing the stack.
Other recognized tokens leave the mode unchanged.

| Current mode | Input | Stack action / emitted kind |
| --- | --- | --- |
| Code | `{` | Push `x2c` |
| Code | `}` | Pop if stack depth exceeds one |
| Code | `%(`, `%[`, `%{`, `%<<`, `%"`, `$(`/`@(` | Push `list`, `array`, `map`, `symbol-set`, `string`, `macro-lisp`, respectively |
| Code | `%!` | Emit lambda prefix; remain in code |
| `x2c-par` | `(` / `)` | Push `x2c-par` / pop |
| Data (`list`, `array`, `map`) | `(` | Push `list` |
| Data | `[`, `{`, `"` | Push `array`, `map`, `string`; emit `%[`, `%{`, `%"` kind, retaining original text/width |
| Data | `${`, `@{` | Push `x2c` |
| `list` | `?(` | Push `x2c-par` |
| `list`, `array`, `map` | Matching `)`, `]`, `}` | Pop corresponding mode |
| `symbol-set` | `>>` | Pop |
| `string` | `${` / `"` | Push `x2c` / pop |
| `macro-lisp` | `(` / `)` | Push `macro-lisp` / pop |

Root `lisp` does not pop on `)`. The reader checks list structure.
Normal code parentheses do not change lexical mode. Nested quoted data uses
bare openers; writing a percent opener inside data is not the same transition.

## Operand context for percent and angle literals

Let `previous` be the preceding token excluding spaces and comments.
The tokenizer's operand-ending set is:

```text
ident lit-int lit-float lit-char* lit-char lit-atom lit-symbol
) ] } " ++ --
```

`%(`, `%{`, and `%!` scan `%` as modulo after an operand, except after a
control condition, a recognized statement block, or at a layout statement
start. `%"`, `%[`, and `%<<` open literals regardless of the previous token.
An eligible `%<` without the second `<` is malformed.

A control condition is a `)` whose matching ordinary `(` follows `if`,
`while`, `for`, or `switch`. A statement block is a `}` whose matching
ordinary `{` follows one of:

- `;`, `:`, `{`, `}`, `]`, an identifier, `else`, `do`, `try`, `finally`,
  or `defer`.
- `)` whose matching ordinary `(` follows an identifier, `match`, or one
  of the four control keywords above.

`<` may start a Symbol when no preceding operand exists. After an operand,
it may do so following identifier `tag`, or following an operand then
identifier `is` and optional identifier `not`.

For these two predicates only, a layout statement starts when the last
stored token is whitespace containing LF, and the current column is no
greater than the first significant token's column on the previous significant
token's physical line. A deeper continuation retains operand context.

## Indentation as a token transformation

Layout is enabled for `.xp` input by the compiler, or by exactly
`#pragma indent` before code. Trailing whitespace is allowed on that directive;
comments and other directives may precede it. The pass runs after raw scanning
and before compiler keyword reclassification. Its state comprises logical
lines, bracket depths, pending ternary colons, open indentation levels,
closing-token strings, and whether each block is an enum.

Apply the following transformation in order:

1. Remove spaces/comments from the working index, retaining physical storage.
   A directive always forms a separate logical line. Otherwise split at a
   physical line break at bracket depth zero when the next line is no deeper,
   or the previous line ends with a non-ternary colon. A leading `.` continues
   the prior line. Track `?` and its `:` at depth zero.
2. Use the first statement's column as the base indentation. For each line,
   find the next non-directive line's indentation, or the base at EOF.
3. If the line ends with a non-ternary `:` and the next statement is deeper,
   open a block. Replace the colon with `{`, except that `case`, `default`,
   and `catch` retain `:` and add `{`. Push the deeper indentation.
4. For a control header, use the last depth-zero `if`, `while`, `for`,
   `foreach`, `switch`, or `match` before the colon, excluding dotted member
   names. Add condition parentheses if the condition is not already wrapped.
   `for` uses its written clause parentheses. An inline body uses the first
   non-ternary, non-label colon and removes that body separator.
5. An aggregate header contains `struct`, `union`, or `enum` and no ordinary
   parameter `(`. Its closer is `};`, except a leading `typedef` or
   `static typedef` uses `}`. Other block closers are `}`.
6. A line consisting of `do:` becomes a bare block if the first following
   non-directive line at the same or lower indentation is not a same-indent
   `while` trailer without a final colon. Otherwise retain `do`.
7. Append `;` to an ordinary statement line unless it already ends with `;`,
   is in an enum body, or is one whole `$(...)` or `@(form)` form. A whole-line
   `$name`, `@name`, or computed `@producer(...)` hole also takes no semicolon,
   including a hole after a control header's `)`. The leading `@` in
   `@$decorator(...)` becomes trivia and suppresses the semicolon.
   Directive lines receive no semicolon; `#pragma indent` becomes a comment.
8. Append stored closers while the next indentation is lower than the stack
   top. If a following statement matches no remaining level, report `indent`.
   Close all outstanding blocks at EOF.

The pass checks tabs after the last LF in the whitespace token immediately
before a new statement line. That describes the current detector; the
supported spelling uses spaces for indentation. New punctuation has zero
width at its neighboring token's start or end. Reclassified source punctuation
retains its source extent. See `_Layout` in `lib/tokenizer.x` for the transition
owners and the [indentation guide](../../guide/indentation.md) for examples.

## Compiler reclassification and preprocessing

After scanning/layout, `Compiler.tokenize` reports malformed tokens, calls
`scan_conditionals`, then `_retag_keywords`. This last operation differs
from the raw tokenizer's operand-context predicate.

- An `in` token retains that type only if the preceding significant kind is
  one of `ident`, the six atomic literal kinds, `)`, or `]`, and the next
  kind can begin an operand. That beginning set is `ident`, the six atomic
  literal kinds, `(`, `%(`, `%[`, `%{`, `$(`, `${`, `$`, `!`, `-`, `*`, `&`,
  `~`, `++`, or `--`. Otherwise it becomes `ident`. The parser can still
  recognize the spelling in the relevant position.
- For `match`, inspect the next significant token, skipping a parenthesized
  group if one follows. Keep `match` when the inspected token is `case` or
  `{`; otherwise change it to `ident`.

Here the six atomic literal kinds are `lit-int`, `lit-float`, `lit-char`,
`lit-char*`, `lit-atom`, and `lit-symbol`.

Directives are not expanded by the tokenizer. Later conditional handling
hides selected inactive branches and retains conditional structure.
Lexical failures can therefore occur in inactive branches: scanning precedes
that selection. Host preprocessing for imported declarations is a separate
phase. A source shebang is handled by the frontend before ordinary lexing;
it substitutes the scripting include while retaining subsequent line numbers.
See [host preprocessing](../language.md#host-preprocessing).

## Failure and implementation edges

Most scanner helpers return a positive matched length, zero for no match,
or a negative failure, with some prefix preconditions enforced by `Error`.
The individual interfaces matter: `scan_keyword` and `scan_c_operator` use
`-1` for an unsupported start; `scan_white_space` also returns `-1` at NUL.
Status-aware scanners distinguish `incomplete` from `malformed`; wrappers
without a status preserve only `malformed`. The tokenizer records the first
failure status and appends zero-width `error` and `eof` at the refused
position. Physical storage can contain another sentinel pair or tokens after
that first EOF because failure callbacks return zero to chained dispatch.
`Tokenizer.next` stops at the first EOF. Layout failure uses `indent`.
Consumers must not equate lexical
success with balanced delimiters or a valid program.

Two dispatch/detection details need care in a future independent lexer:

- The segment scanner accepts `$$` inside a segment, but String dispatch
  consumes a leading `$` first. The book's doubled-dollar description alone
  does not describe that boundary case. `\$` has an unambiguous escape path.
- The tab detector examines the immediately preceding whitespace token only
  when it contains LF. This is narrower than a universal scan for indentation
  tabs, although the documented source convention requires spaces.

These are source-derived implementation observations. They do not silently
change the language contract or claim a repaired implementation.
