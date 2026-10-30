# x2c Source Style Examples

[The code standard](x2c-code-standard.md) is the source style authority.
These illustrative fragments preserve the worked examples for its rules.
Each example shows the named property; fragments are not complete programs.

## PR-1 - The governing test

See PR-1 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
// The artifact may be absent, but a present directory is not a readable
// source file and must fail before its declarations are cached.
if (!_includable_file(path))
  c.report_error(<input>, "unreadable include", token, %($path));
```

Avoid:

```x2c
// Check if the path is a regular file.
if (!_regular_file(path))
  // Report an error.
  c.report_error(<input>, "unreadable include", token, %($path));
```

## PR-4 - Trust established facts

See PR-4, EX-4, VT-3, and CM-3 in [the standard](x2c-code-standard.md).

Close the producer chain before narrowing a private `Var` parameter. Include
every caller, recursive transition, callback registration, stored-value
writer, and relevant alias. Stop at the established owner, not a fixed call
depth. A graph's missing edge does not establish an impossible input.

| Pattern | Simplification and retained boundary |
| --- | --- |
| Private container holds only Lists | Trace every insertion and replacement, then type its consumers as List. Keep semantic shape recognition. |
| Dispatcher already returns nil | Remove the helper's repeated nil test; keep tail exhaustion and ownership checks. |
| Earlier branch establishes a fact | Remove a later test only while the value and predicate remain unchanged and the predicate has no observable effects. |
| Existing operation owns failure | Delegate the duplicate check while preserving preparation order, failure status, callbacks, and output atomicity. |
| Callback constructor supplies userdata | Rely on its established type and lifetime; preserve the callback ABI. |
| Existing exact tag guard precedes extraction | Read the established object payload without repeating checked conversion. Keep the input guard. |
| Destination already supplies nil fallback | Use the typed destination instead of another tag-test ternary. This preserves mixed inputs rather than proving them impossible. |

For example, a sequence slot can be absent or contain another tag. Prefer:

```x2c
/* Missing or non-List sequence slots read as nil. */
List order = rows[<order>];
return order.reverse();
```

Over:

```x2c
Var order = rows[<order>];
return order is <list> ? order.list().reverse() : NULL;
```

The List destination preserves the same nil fallback. `List.len(nil)` is
zero and `List.reverse(nil)` is nil; neither needs a separate absence path.
Other operations need their own contract. `Iter.try_next(NULL, out)` reports
exhaustion before invoking a callback, but dropping zip's right-input guard
would consume the left input before discovering that absence.

An exact String branch can use `value.string_payload()` after `value is
<string>`. Do not replace a general `value.str()` or a String destination:
those can render another tag through a registered callback. Preserve
materialization such as `Array.list()` when it changes representation or
ownership.

Three source owners illustrate the limits:

- [Header projection](../src/generate/projection.x): all private header
  writers and pending replacements supply Lists; not every item declares a
  type, so declaration recognition remains.
- [Match execution](../lib/match/execution.x): a checked buffer address can
  pass through required references. An equality callback can still change
  aliased capacity after entry validation; the later capacity check remains.
- [Context export](../lib/context.x): the dispatcher excludes nil before its
  private List helper; the helper still checks pool ownership and tail ends.

Distinguish null from empty and inspect actual dispatch. `!map` also accepts
an empty Map; removing that guard before `try_get` can add key hashing and
registered callbacks. Symbol and Atom equality may dispatch too. A String
type alone does not establish nonempty text, and a List type does not
establish every element's shape. Typed pattern captures establish only the
constraints that their emitted recognition actually enforces.

State the precondition once for each connected removal. Report whether the
proof establishes an impossible input, repeats validation, or delegates to
an equivalent operation. Smaller source does not establish a speedup.

## LY-1 - Indentation, width, and text

See LY-1 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
if (index < 0)
  index += length;
return index >= 0 && index < length;
```

Avoid:

```x2c
if(index<0)
    index+=length;
return ( index>=0&&index<length );
```

## LY-4 - Signatures and calls

See LY-4 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
static int _same_slot(Map m, Var key, Var expected) =>
  m.lookup(key).same(expected);

static int _compile_bind_and_leaf(
  MatchLower m, Var binder, Var leaf) {
  // ...
}
```

Avoid:

```x2c
static int _compile_bind_and_leaf(MatchLower m,
                                  Var binder,
                                  Var leaf) {
  // ...
}
```

Example:

```x2c
c.report_error(
  <protocol>, message, declaration_token,
  %("participant:" $participant "member:" $member));
```

Example:

```x2c
c.report_error(<protocol>, message, declaration_token,
               %("participant:" $participant
                 "member:" $member));
```

Example:

```x2c
c.report_error(
  <protocol>, message,
  %(
    "participant:" $participant
    "member:" $member
  )
);
```

## LY-6 - Vertical space

See LY-6 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
static int _is_digit(int ch) => ch >= '0' && ch <= '9';

static int _is_hex(int ch) =>
  _is_digit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');

// public scanning

int scan_number(char *text) {
  // ...
}
```

Avoid:

```x2c
static int _is_digit(int ch) => ch >= '0' && ch <= '9';



// PUBLIC SCANNING ----------------------------------------------------------


int scan_number(char *text) {
  // ...
}
```

## ST-1 - Control flow

See ST-1 in [the standard](x2c-code-standard.md).

Example:

```x2c
if (!node) return NULL;

if (node is List)
  visit(node.list());
else if (node is Array) {
  Array values = node.array();
  visit_all(values);
}
else
  visit_leaf(node);
```

Example:

```x2c
if (value is not <list>) return 0;
```

Avoid:

```x2c
if (!(value is <list>)) return 0;
```

Example:

```x2c
if (!out) return 0;
if (head is List) normalized_head = _normalize_pattern(head);
foreach(Var part, parts) if (!_collect(part)) return 0;
```

Example:

```x2c
if (c.peek(0) == <eof>)
  $fail.compiler_token_eof(c, c.token);
```

Avoid:

```x2c
if (!out) {
  return 0;
}
```

Prefer:

```x2c
int swap = left; left = right; right = swap;
```

Avoid:

```x2c
int swap = left;
left = right;
right = swap;
```

Example:

```x2c
(void) map; (void) source;
```

## ST-7 - Declarations

See ST-7 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
List result = c.parse_expression();
if (!result) return NULL;

Type type = result.cadr();
return c.convert_expression(result, type);
```

Avoid:

```x2c
List result;
Type type;

result = c.parse_expression();
if (!result) return NULL;
type = result.cadr();
return c.convert_expression(result, type);
```

Example:

```x2c
static size_t pool_allocation_calls, pool_free_calls;

struct Token {
  String text, Symbol type, int line, column;
};

String source_path, List dependencies, int failed = 0;
```

Example:

```x2c
List result = c.parse_expression();
if (!result) return NULL;
Type type = result.cadr();
```

Example:

```x2c
return %(!set $binder ($op @(args.cdr())));
```

## ST-13 - Switches and compact tables

See ST-13 in [the standard](x2c-code-standard.md).

Example:

```x2c
switch (token.type) {
  case <if>:       return _parse_if(c);
  case <while>:    return _parse_while(c);
  case <return>:   return _parse_return(c);
  case <{>: {
    c.next();
    return c.parse_compound_statement();
  }
}
```

## EX-1 - Literals, strings, and formatting

See EX-1 in [the standard](x2c-code-standard.md).

Example:

```x2c
String text = "";
Array values = [];
Map index = {};
```

Example:

```x2c
String text = String.new("");
Array values = Array.new();
Map index = Map.new();
```

Example:

```x2c
String path = %"$(root.rstrip("/"))/$name";
```

Example:

```x2c
output.printf("%08x", hash);
```

## EX-4 - Trust supported conversions

See EX-4 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
static Var _publish_label(
  Var input, String replacement, Array labels, Map fields) {
  String text = input;
  fields[<label>] = replacement;
  labels.push(text);
  return replacement;
}
```

Avoid:

```x2c
static Var _publish_label(
  Var input, String replacement, Array labels, Map fields) {
  String text = input.as_string();
  fields[<label>] = replacement.var();
  labels.push(text.var());
  return replacement.var();
}
```

## EX-5 - Prefer public receiver chains

See EX-5 in [the standard](x2c-code-standard.md). Ordinary static helpers
use explicit arguments, including when public methods surround the call:

```x2c
String name = _stem(path.rstrip("/")).lower();
```

Prefer:

```x2c
String stem = path.rstrip("/").split("/").last();
```

Example:

```x2c
String clean = String.rstrip(path, "/");
List parts = String.split(clean, "/");
String stem = parts.last().string();
```

## EX-7 - Standard predicates

See EX-7 in [the standard](x2c-code-standard.md).

Example:

```x2c
unsigned char first = (unsigned char) spelling[1];
if (!(isalpha(first) || first == '_')) return 0;
```

## EX-10 - Lists and ordered construction

See EX-10 in [the standard](x2c-code-standard.md).

Example:

```x2c
return %(expr $type (call $function $arguments));
```

Example:

```x2c
Var (tag, type, body) = node;
List parameters = signature.cadr();
```

Example:

```x2c
Array statements = [];
while (c.peek() != <}>) statements.push(c.parse_statement());
List body = statements.list_free();
```

## FN-3 - Functions

See FN-3 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
switch (id) {
  case LISP_QUOTE: return _special_quote(args);
  case LISP_DEF:   return _special_def(lisp, args, env);
  case LISP_COND:  return _special_cond(lisp, args, env);
}
```

Avoid:

```x2c
switch (id) {
  case LISP_QUOTE: {
    if (args.len() != 1) {
      int actual = args.len();
      raise %(bad-arity (operation "quote") (expected 1) (actual $actual));
    }
    return args.car();
  }
  // ...
}
```

## FN-8 - Values and borrowed parameters

See FN-8 in [the standard](x2c-code-standard.md).

Example:

```x2c
typedef struct Counter { int count; } Counter;
static void _step(Counter &c) => c.count++;

Counter counter = {0};
_step(counter);
```

Example:

```x2c
static void _advance(int &count) {
  count++;
}
```

## FN-10 - Status results

See FN-10 in [the standard](x2c-code-standard.md).

Example:

```x2c
Var owned = value.clone_wide();
if (owned is void) return void;
```

## FN-11 - Incidental work

See FN-11 in [the standard](x2c-code-standard.md).

Example:

```x2c
int Path.is_dir(Path p) => S_ISDIR(_mode(p));
int Path.is_file(Path p) => S_ISREG(_mode(p));
long Path.size(Path path) => (long) _stat("Path.size", path).st_size;
```

## FN-12 - Grammar and generated syntax

See FN-12 in [the standard](x2c-code-standard.md).

Example:

```x2c
List Compiler.parse_conditional(Compiler c) {
  List condition = _parse_binary_ops(c);
  Token origin = c.token;
  if (!c.test(<?>)) return condition;
  List ontrue = c.parse_expression();
  c.expect(<:>);
  return c.resolve_expression(
    %(expr () (op ? $condition $ontrue $(c.parse_conditional()))), origin);
}
```

## FI-2 - Module headers

See FI-2 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
/*  deps.x -- Make dependency output for x2c translation units

    Copyright (c) 2026 Gary William Flake.

    Translation owns the prerequisite set. This module owns its stable Make
    spelling and atomic publication.
*/
```

Avoid:

```x2c
/*  deps.x -- dependency helpers

    This module contains all of the dependency functions. It parses
    dependency files, writes dependency files, escapes paths, sorts paths,
    creates temporary files, renames them, and handles errors. The functions
    below are:

      Compiler.write_depfile
      translation_depfile_parse
      ...
*/
```

## FI-3 - Prologue order

See FI-3 in [the standard](x2c-code-standard.md).

Example:

```x2c
/*  widget.x -- checked widgets over Block storage

    Copyright (c) 2026 Gary William Flake.

    Widget owns element validation; Block owns capacity and allocation.
*/

#pragma once
#include "common.x"

typedef Block Widget;

#include <limits.h>
#include <string.h>

#include "block.x"
#include "exception.x"
```

## FI-4 - Reading order

See FI-4 and FI-5 in [the standard](x2c-code-standard.md). Use
[order-x2c-functions](skills/order-x2c-functions/SKILL.md) to check an existing
file or revise its order without changing function bodies.

The following fragment is illustrative. Two public operations precede their
private groups. The first operation claims the shared `_normalize` helper.
The later comparison group calls that helper upward rather than duplicating
it or scattering the parsing group.

```x2c
// values

int read_value(int depth) => _parse(depth);

int compare_values(int left, int right) => _compare(left, right);

// parsing

static int _parse(int depth) =>
  depth > 0 ? _parse_group(depth - 1) : _normalize(depth);

static int _parse_group(int depth) => _parse(depth);

static int _normalize(int value) => value % 10;

// comparison

static int _compare(int left, int right) =>
  _normalize(left) - _normalize(right);
```

`_parse` and `_parse_group` are mutually recursive. Their component follows
`read_value`; inside it, the parser entry precedes the group step that calls
back. No internal order can make every recursive call point downward.
If one public operation calls another, put the caller first, accounting for
paths through private functions too. Leave independent public operations in
their existing order unless a clearer explanation warrants a different tie.

In [regex.x](../lib/regex.x), compilation claims pattern construction and
shared byte tests. Matching follows with `_run` and `_resume` together so
the reader learns continuation behavior before the individual node actions.
Traversal and replacement reuse the earlier search machinery. These upward
cross-group calls conform to FI-4; moving the shared machinery after its
last caller would weaken the thematic groups.

Source-order-sensitive code is a boundary, not another function to sort.
Preserve macro availability, preprocessing regions, top-level script work,
and required declarations. Check module members through their containing
unit, while keeping definitions in their current physical files.

Place section introductions at their operations. A parsing introduction
belongs above the parser entry, while a representation comment belongs by
the parser's type. Avoid labels that merely mirror visibility tiers or
remain attached to a former first function after the section changes.

Prefer a short lower-case label:

```x2c
// immutable programs
```

When the reader needs a constraint, give the section one focused explanation:

```x2c
/* file walks

   A cold walk splits a file at its includes and visibility boundaries and
   records each segment's declarations in source order. */
```

Avoid rulers and a comment table of contents:

```x2c
// PRIVATE HELPERS ===========================================================
// PUBLIC INTERFACE ---------------------------------------------------------
// ARRAY METHODS ============================================================
// SLICE METHODS ============================================================
```

## CM-1 - Choose the narrowest comment form

See CM-1 in [the standard](x2c-code-standard.md).

Example:

```x2c
/* Symbol values are encodings, not lexical ordinals. Keep this table in
   encoded order because lookup uses a lower bound. */
static VarDescriptor descriptors[] = {
  // ...
};
```

Example:

```x2c
/* Symbol values are encodings, not lexical ordinals. Keep this table in
   encoded order because lookup uses a lower bound.
*/
static VarDescriptor descriptors[] = {
  // ...
};
```

Example:

```x2c
scan_prefix(input);

/* The suffix scanner starts after the delimiter but reports lengths from the
   original input boundary. */

scan_suffix(input, delimiter_length);
```

Avoid:

```x2c
// Symbol values are encodings.
// They are not lexical ordinals.
// This table is in encoded order.
// Lookup uses a lower bound.
static VarDescriptor descriptors[] = {
  // ...
};
```

## CM-2 - Local comments explain decisions

See CM-2 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
// The selected arm's captures are copied out, so the pattern pool can go.
_catch_commit_captures(h, record, layout, &captures);
Pool.release();
_catch_retain(h);
```

Avoid:

```x2c
// Commit captures.
_catch_commit_captures(h, record, layout, &captures);

// Release pool.
Pool.release();

// Retain the handler.
_catch_retain(h);
```

Example:

```x2c
if (!source.len()) {
  // Empty String is native zero; scanning still needs one addressable byte.
  tokenizer.text = xcalloc(1, 1);
}
```

Avoid:

```x2c
if (!source.len()) {
  // Allocate one byte.
  tokenizer.text = xcalloc(1, 1);
}
```

## CM-3 - Internal functions and contracts

See CM-3 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
static int _ascii_digit(int ch) => (unsigned) (ch - '0') < 10;
```

Avoid:

```x2c
// Check if a character is a digit.
static int _ascii_digit(int ch) => (unsigned) (ch - '0') < 10;
```

Example:

```x2c
/* Return a spelling only when the operand is provably nonzero without
   constant folding. Unknown forms stay silent so legal C is never rejected. */
static String _known_nonzero_integer(List expression) {
  // ...
}
```

## CM-4 - Comments describe the present

See CM-4 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
// Shallow macro collection retains public declarations but discards private
// helpers with the generated bodies.
```

Avoid:

```x2c
// NB: Added this third clause after macros broke the old logic.
```

Prefer:

```x2c
// The checked-in bootstrap does not accept this declaration form.
```

Avoid:

```x2c
// TODO: clean this up later.
```

## CM-5 - Public API documentation

See CM-5 in [the standard](x2c-code-standard.md).

Example:

```x2c
/** Returns the number of elements stored in `b`. */
inline size_t Block.len(Block b) => b != NULL ? b.length : 0;
```

Example:

```x2c
/** Removes and returns the element at normalized `index`.
    Negative indices count from the end; following elements shift left.
    Boxed `Array` returns `void` for a null array or out-of-range index.
*/
Var Array.remove(Array array, int index) {
  // ...
}
```

Avoid:

```x2c
/** Removes an element from an Array.

    Parameters:
    - array: the Array
    - index: the index

    Returns: the removed element.
    See: Array.
*/
Var Array.remove(Array array, int index) {
  // ...
}
```

## CM-6 - Inline and field comments

See CM-6 in [the standard](x2c-code-standard.md).

Example:

```x2c
struct Iter {
  Var obj;
  Var state;
  IterNextFn next;  // NULL once the source is exhausted
  Func aux;         // callback state for lazy stages
};
```

Avoid:

```x2c
struct Token {
  String text;  // token text
  Symbol type;  // token type
  int line;     // line number
};
```

## CM-7 - Representation and lifetime stay visible

See CM-7 in [the standard](x2c-code-standard.md).

Example:

```x2c
/* Presence bits stay separate because raw Null is valid captured data and
   void cannot enter the value array. */
typedef struct MatchCaptureBuffer {
  Var *values;
  unsigned long *present;
} MatchCaptureBuffer;
```

Example:

```x2c
// Canonical storage belongs to the Pool, not the caller's active scope.
return Scope.malloc_in(&inner.scope, size);
```

## NM-1 - Names distinguish public operations and static helpers

See NM-1 in [the standard](x2c-code-standard.md). State remains an explicit
parameter; the helper's name does not need its record's prefix.

Example:

```x2c
static List _declarator(
  Emitter &e, List declaration, List modifiers) {
  // ...
}
```

Example:

```x2c
static int _is_reserved_spelling(String s) {
  // ...
}
```

Example:

```x2c
typedef struct Expansion {
  Compiler c, List definition, input, template, direct, Token invocation;
} Expansion;

static List _bind(Expansion &x, AstPos position) {
  // ...
}
```

Prefer:

```x2c
static int _readable_file(String path);
```

Avoid:

```x2c
// Check whether p is a readable regular file.
static int _check(String p);
```

Example:

```x2c
for (List p = values; p; p = p.cdr())
  output.push(p.car());
```

Semantic qualifiers distinguish operations that formerly had different owners:

```x2c
static Var _read_value(Reader &r);
static void _write_value(Writer &w, Var value, int depth);
```

Generated family helpers have two narrow lookup exceptions under NM-1.
For example, `$array.shift_element` lets typed operations inherit a base
family's helper through typedef method lookup. In contrast,
`$array.compare_elements` supplies a stable name from the core observation
expansion to its typed consumer; this use does not depend on aliases. Keep
expansion-local helpers such as `_normalize_span` undotted; they use normal
macro hygiene.

## VT-5 - Closed identities

See VT-5 in [the standard](x2c-code-standard.md).

Example:

```x2c
const SymbolSet x2c_var_tags = $var.tag.symbolset();
static TagId _tag2id(Symbol tag) => (TagId) x2c_var_tags.index(tag);
```

## VT-9 - Separate storage ownership from typed crossings

See VT-9 in [the standard](x2c-code-standard.md). These static converters
retain their dotted names because conversion and protocol lookup require them
(the NM-1 exception). Ordinary helpers such as `_next` use free names.

Example:

```x2c
typedef LocalState *LocalStateRef;

static inline Var LocalStateRef.var(LocalStateRef l) => (Var) { .p64 = l };
static inline LocalStateRef Var.localstateref(Var v) => v.p64;
protocol Var(LocalStateRef);

static int _next(Iter i, Var *out) {
  LocalStateRef state = i.obj.localstateref();
  // ...
}
```

## LT-1 - Acquire and clean up in one construct

See LT-1 in [the standard](x2c-code-standard.md).

Prefer:

```x2c
auto {
  File output = auto File.open(path, "w");
  output.puts(report);
}
```

Avoid:

```x2c
Scope.retain();
defer Scope.release();
File output = File.open(path, "w");
defer output.close();
```
