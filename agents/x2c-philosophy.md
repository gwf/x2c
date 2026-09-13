# The x2c Philosophy

x2c should make powerful programs shorter, clearer, and easier to verify than
their C equivalents.  Its compactness comes from a simple discipline:

> **Assign every invariant one owner.  Establish or validate it at that
> boundary, then let downstream code rely on it until data crosses a boundary
> that does not preserve the invariant.**

Duplicating enforcement does not make a contract stronger.  It creates a
second definition that can drift, encourages fallback paths, and obscures the
actual owner.  The remedy is not to remove checks indiscriminately; it is to
make ownership explicit and remove only checks made redundant by a proven
contract.

This document separates the design we want from the behavior the repository
currently proves.  That distinction is essential: an aspiration is not
permission to delete a check.

## How to read the ledger

Every contract that current code relies on has one of four statuses:

- **verified** - the owner, guarantee, and executable proof agree. Downstream
  code may rely on it.
- **partial** - a useful mechanism exists, but its domain or failure behavior
  is incomplete.  Rely only on the verified portion.
- **intended** - a chosen direction that is not yet enforced and tested.
- **decision** - current uses conflict or leave a semantic choice open. The
  author must decide the contract before related cleanup broadens it.

Only a verified contract justifies removing downstream enforcement.

## Boundary model

Contracts exist at different kinds of boundaries:

1. **External input** - source text, files, command-line data, C callers, and
   other untrusted values are validated and diagnosed here.
2. **Constructor or canonicalizer** - establishes a representation invariant
   such as interned identity or normalized slice bounds.
3. **Public module API** - states its accepted domain, result, and failure
   protocol.  It need not re-check an invariant already established by its
   input type or constructor.
4. **Compiler phase boundary** - establishes the AST shapes and annotations
   the next phase may consume.
5. **Internal consumer** - trusts the specific guarantees established by the
   preceding boundary.  It still handles legitimate base cases, optional
   values, and state transitions.

A type signature establishes only what the type system enforces.  A match
establishes only constraints encoded in its pattern.  A binder such as `?x`
captures a value; by itself it does not establish that value's type.

## Contract ledger

| Contract | Status | Owner | Proof |
| --- | --- | --- | --- |
| Index normalization | verified | `x2c_normalize_index` | index/slice suite |
| Slice normalization | verified | `x2c_normalize_slice` | index/slice suite |
| Runtime aggregator | verified | `lib/Makefile` | executable make rule |
| Operational compiler storage | verified | Compiler, Diagnostics, Emitter owners | fixtures, unit suite, symbol snapshot |
| List canonicalization | verified | `cons` | List identity suite |
| String canonicalization and bytes | verified | `String.intern` | String suite |
| Exact Atom canonicalization | verified | `Atom.intern` | Atom suite and compiler fixture |
| String numeric parsing | verified | `String.try_long`, `String.try_double` | String suite |
| `void`, Null, singular empty encoding | verified | constructors and `Var` | Var/String/List suites |
| Mutable empty container identity | verified | `Array.new`, `Map.new`, `Var.new` | Array/Map/Var suites and fixture |
| `void` exclusion | verified | containers/iterator | runtime suites and compiler fixtures |
| Fixed-width storage mutation | verified | `Block.*`; `Block.try_pop` for exhaustion | Block suite and Error fixtures |
| Text construction | verified | `Buffer` | Buffer suite and NUL fixture |
| Scalar identity | verified | `Type.scalar` | scalar fixture |
| Supported source-to-`Var` round trips | verified | `Type.var_tag`, typed Var constructors | Var suite and compiler fixtures |
| Missing and exhaustion API use | partial | individual public APIs | runtime suites |
| Iterator protocol | verified | `Iter.try_next`, status callbacks | runtime and compiler suites |
| Optimized Error transfer | verified | emitter/frame/cleanup chain | Error/defer fixtures |
| Native target Error transfer | verified | generated adapter is ordinary compiled C, so no landing pad or guard | Func/Error/exception suites, `func-adapt` fixture |
| Allocation lifetime | verified | `Scope` | scope suite and shutdown probes |
| Boxed identity and dispatch | verified | `Var.*`, typed descriptors | Var/Map/File suites |
| Streaming representation | verified | `Var.write_repr`, typed descriptors | Var and Logger suites |
| Logger delivery and ownership | verified | `Logger` | Logger and Diagnostics suites |
| Raw stream status and text conversion | verified | `File.*_into`, String adapters | File suite |
| Lexical scanner contracts | verified | `scan_*`, `Tokenizer` | scanner suite and fixtures |
| Source declaration collection | verified | `Compiler.collect_symbols`; CPP oracle | raw sweep, process probes, fixtures |
| Compiler-generated identifier space | verified | `_is_reserved_spelling` defines the set; minted by `Compiler.gensym`, `src/cache.x` (`_N`), `src/generate.x` (`_init_guard_`, `_file_init_`) | `reserved-namespace` and generated-name fixtures |
| Typed static callback adaptation | verified | `$x2c.callback.adapt`; compiler-owned typed thunks | callback adapter fixtures and dispatch/runtime suites |
| Source directive routing | verified | parser, generator, formatter | AST/C/runtime fixtures |
| Source/generated expression resolution and declaration publication | verified | `Compiler.resolve_expression`; shared declaration helpers in `src/parse.x` | `macro-source-parity` and macro fixture corpus |
| Error protocol | verified | `Error`, plain `raise`, filtered `catch`; private record regions and handler watermarks own lifetime | Error/exception suites, compiler fixtures, allocation/floor/fatal probes, self-host convergence |
| Allocation and size failure | verified | `Scope`, `Pool`, `Error`, and literal-raise emission | Error/exception suites, Scope and Error fatal probes, compiler fixtures |
| Lisp read/eval failures | verified | `Lisp.read`, evaluator, `Func` Type boundary | Lisp/Func suites |
| Serialized List syntax | verified | shared Atom/String/List spelling | Atom/Lisp cross-syntax and full snapshot probes |
| Compiler runtime symbols | verified | versioned Lisp snapshot plus live oracle | snapshot probes and compiler fixtures |
| Protocol adapter visibility | verified | least-public protocol dependency closure; descriptor registration remains process-wide | protocol fixtures, normal/live owner-consumer probes, self-host convergence |
| Fixture token stream | verified | `Tokenizer.scan` | token-mode fixture |
| Fixture parsed AST shapes | verified | `Compiler.full_parse` | AST fixtures |
| Fixture transforms | verified | `Compiler.transform` | transform fixtures |
| Fixture emission | verified | `Compiler.emit` | emit fixture |
| Fixture C/H output | verified | `generate_code` | C/H fixtures |
| Fixture native behavior | verified | generated programs | runtime fixtures |
| Parse diagnostic output | verified | `Compiler.full_parse` | error fixture |
| Type-owned initialization | verified | parser/generator | fixtures/example |
| Type-owned shutdown | verified | parser/generator and `Scope.shutdown_hook` | lifecycle fixtures and Scope probes |
| Typedef method and converter inheritance | verified | postfix parser and conversion lowering | fixtures/example |
| Numeric/`Var` String interpolation | verified | interpolation converter | interpolation suite/example |
| Static printf-family `Var` conversion | verified | printf transform | compiler fixtures |
| Structural `Var` decoding | verified | `lib/var.x` | VarOps suite |
| Cross-tag numeric conversion | verified | `Var.convert` | VarOps |
| Dynamic numeric operations | verified | `Var.binary` | VarOps/fixture |
| `Var` truthiness | verified | `Var.truthy` | VarOps/Error fixture |
| Single-call container update | verified | `Array.updateindex`, `Map.updateindex`, Var owners | atomic-container suite/fixtures |
| Atomic compound update | verified | typed VarOps adapters | VarOps/fixtures |
| Identity-only runtime state | verified | Scope, Exception, Machine, Match, Lisp, Func, Var owners | runtime suites and symbol snapshot |
| Match positional captures | verified | `MatchCaptureLayout`, capture buffers, Error retained regions | Match/exception suites, compiler fixtures, focused sanitizer, cache/capture benchmarks, self-host convergence |
| Malformed splice | verified | literal parser | diagnostic fixture |
| Promoted immutable literal caching | verified | expression lowering, cache and generator | promoted-string-cache fixture |
| Match transform dump | verified | `String.repr` | transform fixture |
| Pooled interning | verified | `lib/pool.x` (`Pool.retain*`/`.release`/`.insert`/`.lookup`/`.owns`), `String.pool_retain*`, `List.promote` | Pool suite |
| Header-symbol cache | verified | `header_symbols_write`/`header_symbols_open` (`src/collect.x`), `etc/header-symbols.xlisp` | `hdr-check`, `run-header-cache.sh` |
| Batch-compilation memory brackets | partial | `src/main.x` per-unit `Scope`/pool brackets | batch/solo output parity in `run-header-cache.sh`; no probe yet asserts the pool-release/no-leak discipline directly |

## Verified contracts

### Shared index semantics

`x2c_normalize_index` is the sole interpreter of ordinary element indices for
String and Array. Negative indices count once from the end, and the accepted
domain is exactly `[-length, length)`. List retains traversal-specific
normalization to avoid an extra length pass and proves the same boundary in the
index/slice suite. Insert positions, slice bounds, and wider Buffer offsets
remain with their specialized owners.

### Shared slice semantics

`x2c_normalize_slice` is the sole interpreter of slice bounds and direction.
String, List, and Array adapters delegate to it, and compiler lowering targets
those adapters.  A new slice-capable type should reuse this owner instead of
reimplementing negative-index or reverse-step rules.

### Generated aggregation

`lib/x2c.x` is generated from the standard runtime modules. The Makefile owns
its membership, exclusions, and ordering. Optional x2c system modules are
built with the runtime but require an explicit include. Change the source set
or generator; never hand-edit the derived file.

### Semantic values and operational storage

List owns persistent semantic sequences: ASTs, patterns, bindings, and values
whose canonical identity is part of their contract. It is not the default
representation for state merely because that state is sequence-shaped.

Mutable stacks, chronological queues, and indexed scratch collections belong
to the object that mutates them. Compiler scopes and initialization queues,
Diagnostics entries, and Emitter cleanup bookkeeping use Array or typed Block
storage at that owner. They convert to Lists only where a phase or callable API
promises a semantic snapshot. The mutable store is released or cleared at the
owner's existing lifetime boundary.

This distinction is about ownership, not a blanket preference for mutation.
Use a List when construction produces a persistent value or deliberately
shares a suffix. Use mutable storage when repeated mutation is the operation
and no consumer relies on intermediate List identity.

### Match positional capture ownership

`MatchCaptureLayout` is the sole owner of binder indexes, canonical
first-occurrence order, and definite/possible binder sets. Prepared machine
slots, recursive fallback state, compiler-generated locals, replacement
templates, and filtered catch arms consume that layout rather than infer a
second ordering. Presence bits remain separate from values because `void`
cannot represent an absent capture.

Every Match execution path keeps speculative bindings in invocation-owned
positional storage. Rollback changes only that private state, and failed
matches leave caller output untouched. A successful public API constructs an
association List only where its signature promises one; source `match`,
replacement internals, and generated catch-arm locals consume fixed capture
indexes directly. A source-literal pattern retains an immutable per-site
plan in Match's shutdown-owned scope; a pattern computed at run time
prepares a plan for the life of the call and frees it.

Filtered catch copies committed capture values into the selected Error
record's private region before transfer. The retained handler region therefore
owns indexed values across `siglongjmp`; generated code does not rely on
automatic capture storage after the jump. Lazy association-List publication
uses that retained positional state.

### Lists and identity

`cons` owns List canonicalization. Repeated construction with the same head and
tail returns the same cell. List hashing and equality use the identities of the
head and canonical tail, so nested Lists canonicalize from the tail outward.
Map key comparisons on boxed Lists lower from `Var == Var` to `Var.equal`.
Compiler transforms may rely on identity for Lists created through `cons`.

`cons` probes the pool chain for a canonical hit before allocating. That
lookup is not redundant: self-compilation is hit-heavy, and the one-probe
"simplification" that allocated a candidate cell first cost 27.9% of
translation time before it was reverted (restoring the probe cut translation
23.5%). The comment beside the probe pins this reason; do not remove either.
The hit/miss mix of the dominant workload decides such shapes — measure
self-compilation before simplifying a canonicalization path.

### Strings and identity

`String.new`, `String.intern`, and `String.intern_free` own String
canonicalization. The empty String canonicalizes to the native null pointer and
requires no allocation or intern-table entry. Equal non-empty content returns
the same interned String, including when the candidate begins as a separately
allocated buffer. Map key comparisons on boxed Strings lower from `Var == Var`
to content-aware `Var.equal`. `String.malloc` alone creates a transient mutable
buffer; `String.intern_free` finalizes that owned buffer and releases it when
canonical content already exists. `String.intern` copies borrowed C input into
canonical storage.

Strings are NUL-terminated byte sequences rather than Unicode character
containers. Their private headers cache exact byte length and a content hash
established during canonicalization. Canonical hashing is therefore constant
time; transient mutable buffers are not hash-stable until interned. Explicit
freeing applies to transient buffers only, while `String.free` safely leaves a
canonical process-lifetime String intact.

Empty String remains ordinary String data even though its native
representation is null. Search predicates and first/last search treat an empty
needle as matching at the normalized boundary. Enumeration and replacement do
not expand an empty pattern into every byte boundary.

`String.try_long` and `String.try_double` own status-bearing numeric parsing.
They write an output only after C-style conversion consumes a value without a
range error; the integer parser additionally recognizes signed `0b` and `0o`
prefixes.

### Atoms and closed symbol vocabularies

`Atom.intern` owns exact name representation. A spelling is an immediate
compact Symbol only when Symbol encoding round-trips every byte; otherwise the
private `<lsym>` value points directly at the canonical String. There is no
Atom wrapper, second interning Map, or reader-specific lifetime owner. Equal
Atoms therefore have identical Var bits, while long Atom hashing delegates to
the cached String hash. Long Atoms consequently share the canonical String's
pool lifetime. `List.promote` promotes `<lsym>` payload Strings alongside
ordinary String cars, preserving a promoted List's complete identity graph.
Standalone long Atoms use `String.promote(Atom.str(atom))` when they must
escape a child String pool.

Bare `%()` elements and Lisp identifiers use Atoms and preserve case and
length. Their representation escapes the union of both readers' delimiters,
comment openers, numeric-looking prefixes, whitespace, control bytes, and
backslashes. A bare Atom already uses the compact Symbol representation when
encoding and decoding reproduce its spelling exactly. Angle brackets inside a
`%()` List literal only quote text that bare syntax would interpret
differently; they do not select a different representation for an ordinary
name. The empty Symbol is the sole case with no bare Atom spelling and remains
`<"">`. Runtime `Symbol.new` retains normalization and truncation.

Compiler AST discriminants, matcher operators, and matcher predicate
vocabulary remain compact Symbols permanently. They are closed internal
control vocabularies, not user names. Downstream compiler and matcher code may
rely on that distinction.

Matcher binder names are the open-name boundary: anonymous `?` and `*` remain
compact wildcards, while named `?IDENT` and `*IDENT` keys are canonical Atoms.
The identifier suffix is deliberately restricted to the source identifier
grammar, so generated locals preserve the exact suffix without a second name
rewrite. Prepared machines freeze the raw eight-byte Atom keys; malformed
sigil-leading names are rejected rather than silently treated as literals.

### Zero and terminal representations

Native empty pointer-backed values use zero where their type supports that
representation. In particular, the empty String and nil/List are native null
pointers; nil requires no special cons cell. Boxing preserves the static type
as a `Var` tag with a zero pointer payload, and unboxing restores native zero.
The full boxed bits hash singular typed empties, so they do not all collapse to
hash zero; equality still resolves ordinary hash collisions.

Array and Map do not support that representation. They are mutable,
identity-bearing objects, so even their empty values are allocated by
`Array.new` and `Map.new`. Separate `%[]` and `%{}` evaluations produce
separate objects that may be mutated immediately. `Var.new` rejects a null
pointer for the Array and Map value tags; boxing and unboxing preserve the
allocated object identity. A raw null Array or Map pointer may still express
an internal absent or not-yet-initialized state, but it is not an empty
container value.

Successful allocation with satisfied preconditions returns initialized
storage. Every cause in `lib/error-macros.xmacro`'s shared table may transfer
to a matching filtered catch, but none of them return to the call that raised
them. Error locks their policies to `<abort>` and rejects `<log>` and
`<ignore>`; an observing handler also cannot consume one with `<handled>`.
Literal raises of these causes emit `__builtin_unreachable()` after the
runtime call.
Downstream code therefore does not check whether a valid Scope allocation,
growth operation, `%[]`, or `%{}` succeeded. Null remains meaningful only
where the API documents it, including empty String and nil/List, optional
inputs, absence, null-safe destruction, `Scope.memdup(NULL, 0)`, and
`Scope.realloc(ptr, 0)`.

`void` is the universal terminal/tombstone complement to empty and uses the
all-ones 64-bit representation. It is outside the ordinary value domain and
cannot be stored in Lists, Arrays, or Maps or yielded by an iterator. Null and
the verified typed empty String/List values remain non-`void` data. The finite
`double` value `-DBL_MAX` uses a reserved special-value escape because its
normal shifted encoding would be all ones; decoding restores the exact IEEE-754
value.

Expression-position `void` is the canonical sentinel literal; type-position
`void` retains its C meaning. Equality and identity may inspect the sentinel:
two sentinels match and a mixed pair does not. Both display and readable
rendering use lowercase `void`. Other dynamic operations retain their
ordinary-value requirement.

Non-empty Array and Map literals use counted bulk owners. Each dynamic value
therefore reaches `Array.push` or `Map.set`, which rejects `void`; it cannot be
mistaken for the terminator of a varargs adapter. Raw Null
remains legal collection data.

Automatic source-to-`Var` conversion is lossless for the source/tag pairs in
`Type.var_tag`; the Var suite verifies construction, decoded tag, and
extraction together. `long`, `unsigned long`, `long long`, `unsigned long
long`, and `long double` use immutable, scope-owned boxes because their full
native payload cannot share the immediate encoding. `Var` remains exactly
eight bytes, and narrower values retain their allocation-free encodings.
Explicit signed 48-bit construction is valid only from `-(1L << 47)` through
`(1L << 47) - 1`; out-of-range values and unknown construction tags terminate
explicitly instead of producing `void`.

### Scalar identity and typed crossings

`Type.scalar` is the compiler's sole normalizer for supported primitive C
scalar specifiers. A private typed ledger owns each scalar family's tag,
extractor, and atomic-update helper; the public queries derive their existing
views from that one table. The declaration parser collects the complete specifier
multiset, accepts equivalent legal orders, rejects invalid combinations, and
stores one compact spelling for each scalar family. `Type.scalar_tag` derives
the established Var-family identity for numeric scalars from that spelling.
`Var.numeric_info` then owns numeric category, signedness, native width,
and cross-family rank for conversion, operations, dispatch, and compiler Type
queries. C spelling selection remains Type-owned. `void` has no ordinary
payload tag.

`Type.numeric_literal` consumes the already lexically validated `Token.text`
and assigns its native source family from radix, magnitude, and suffix.
`scan_number_typed` remains the lexical-validity owner. A value outside the
supported native families is rejected at the original source token. The
preprocessed shallow pass contributes only declarations, so the original
positioned token stream owns that diagnostic.

Ordinary scalar typedefs resolve through this owner for arithmetic and Var
crossings without erasing semantic runtime types such as String or Symbol.
The native numeric tag names and their pointer forms are specified in the
[language reference](../docs/src/reference/language.md#var-null-and-void).
The runtime derives numeric widths from the corresponding C types.

### Numeric Var operations and truthiness

`Var.encoding_valid` is the representation owner's structural validator.
Dynamic Var operations raise `<bad-enc>` for the same malformed encodings.
Canonical numeric fast lanes recognize their valid encodings directly;
remaining paths use the shared validator before extraction. It rejects
reserved encodings, malformed narrow or discrete payloads, null wide boxes,
and null Array or Map value tags. It does not prove that an accepted nonnull
pointer is live or came from the right constructor; pointer provenance remains
the typed owner's precondition.

`Var.convert` converts among all 15 integer and floating families. An
integer-to-integer conversion retains the destination-width low bits and
interprets a signed destination as two's-complement. It never uses a floating
intermediary. Floating-to-integer conversion truncates toward zero only when
the truncated result is representable; NaN, infinities, and out-of-range
results raise `<conv-range>`. Integer-to-floating and floating
narrowing use the host floating-point conversion rules. A structurally valid
nonnumeric value converts to its own tag by identity; other nonnumeric
crossings remain with their typed owners. The scalar-named readers in
`lib/common.x` delegate nonmatching numeric tags to `Var.convert`, keeping
direct branches only as fast implementations of the same result; the raw
payload readers stay exact.

`Var.binary` owns the ten numeric operators, String/String `+`, comparison
operators, and eager direct-call `&&`/`||`. Compiler lowering uses it for
numeric and String-tagged Var operations, routes comparisons through their
established helpers, and preserves native C short-circuit control flow.
Integer operands use integer promotion and the common promoted lane;
arithmetic retains that lane's low bits and signed results use
two's-complement. Floating arithmetic uses the widest participating floating
family and host behavior. `String.add` implements the `add` row of
`protocol Var(String)`, is the canonicalization owner for String addition,
and raises `<size-limit>` when the result is unrepresentable; boxed dispatch
reaches the String branch in `Var.binary` before descriptor thunks so mixed
operands keep their exact raises.
`Var.integer_compare` compares integer lanes without converting them to
floating point. `Var.integer_floating_compare` supplies exact mixed
integer/floating comparison to `Var.compare`, while dispatch retains
total-order policy.

`Var.truthy` raises `<void-op>` for `void` and `<bad-enc>` for invalid encodings.
Numeric and Symbol zero, Null and null pointers, canonical empty String/List,
and empty Array/Map/Block/Bytes/Buffer values are false. NaN, infinities,
nonzero values, nonempty containers, and other nonnull objects are true. A
nonnull Iter is true without probing exhaustion or producer state.

`convert`, `binary`, `truthy`, and `update` raise once at the detecting owner.
Their shared causes transfer to a matching filtered `catch` or terminate;
they never resume the raising operation. See
[Errors and Cleanup](../docs/src/guide/exceptions.md#catching-by-cause).
Compiler compound lowering evaluates the lvalue once, selects a typed native
update adapter from its resolved storage type, and stores only after successful
operation and conversion. Plain `char` and `signed char` use distinct adapters
even though both box as `<i8>`. Direct Var
prefix/postfix increment and decrement use the same update owner. Native
String `+=` concatenates first and rebinds only after success. Native C-only
operations and short-circuit control flow remain native; enum and bitfield
targets remain unsupported.

Array and Map indexed compound and increment/decrement operations have checked
owners at the container boundary. Array normalizes one index and delegates its
slot pointer to Var. Map performs one lookup and delegates an existing
record-value pointer without a structural table change. For numeric `+`, that
same owner inserts a missing key from the right-hand side, giving counting a
single-call zero-initialized path; the insertion is structural. The typed
cross-container adapters capture a direct indexed source before invoking that
same destination owner, so same-slot aliasing uses the pre-update value. These
contracts mean one read/modify/write API call and unchanged storage on
failure. They do not add locking, synchronization, or a thread-safety
guarantee. List elements and String characters have no corresponding mutation
owner.

Identity-only runtime vocabularies use Symbols at their existing owners.
Scope, Exception, Machine, Match, and result APIs such as `Lisp.read` use them
for lifecycle, execution state, or ordinary outcomes. These values are
compared and propagated but never ordered, indexed, packed, or computed.
Numeric enums remain the owner for bytecode, ledger indexes, packed fields,
and external numeric protocols.

### Boxed identity and dispatch

Typed descriptors own `str`, `repr`, `hash`, `equal`, `compare`, and `iter`
callbacks for every built-in class tag and for 32 registered custom object
tags. They may also own `truth` and streaming `write_repr`; a nonnull custom
object without a truth callback uses the default true object rule.
`x2c_register_descriptor` installs typed `VarMethods` callbacks without boxing
function pointers; the granular registrar accepts a direct function pointer.
Dispatch never probes registration metadata.

Direct `Var.equal` and `Var.same` inspect `void` using the same rules as source
equality and identity. `Var.hash`, `Var.compare`, and `Var.iter` still reject
it instead of treating it as an ordinary dispatch value. The fail-fast probe
owns those terminal diagnostics.

`Var.write_repr` writes built-in scalar, pointer, String, Symbol, List, Array,
and Map representations directly to a caller-owned Buffer with the same bytes
as `Var.repr`. A custom descriptor may own that boundary; one that omits the
writer retains its canonical `repr` fallback.

Logger owns its opaque configuration, accepted-event clocks and sequence,
registration-ordered sink nodes, built-in contexts, and rendering scratch
Buffers. Every sink observes the same borrowed immutable event. Callback
mutations commit after the outermost reentrant delivery. Caller Files and
custom sink data remain borrowed, and cross-thread delivery remains outside
the verified contract.

Custom registration assigns the reserved `0x800C` through `0x800F` encodings
density-first. An eight-byte-aligned pointer then round-trips through
construction, tag and kind decoding, extraction, and all descriptor methods.
Unknown tags and misaligned custom pointers fail at the Var constructor.

Boxed Array and Map equality and ordering are structural, while their hashes
retain identity so mutable values remain stable, distinct Map keys. String
and List retain their established content semantics. File equality, hashing,
and ordering use stream-handle identity rather than the reusable file
descriptor; boxed File values delegate to that same owner. Every Var hash,
including a registered callback result, is normalized to a nonzero value.

Wide scalar boxes instead retain value semantics: equal tag and payload hash
and compare equally even when allocated separately, while `Var.same` exposes
their distinct box identities. Signed and unsigned integer boxes compare in
the integer domain without conversion through floating point, preserving
adjacent values above double precision and exact Map key lookup.

Source comparisons with either operand statically typed as `Var` have one
transform owner. `==`/`!=` use `Var.equal`, `===`/`!==` use `Var.same`, and
relational operators compare `Var.compare` with zero. Both operands cross to
`Var` exactly once. Without a `Var` operand, comparisons remain native C and
`===`/`!==` normalize to `==`/`!=`.

Typedef scope and conversion semantics are defined in
[Types and conversions](../docs/src/reference/language.md#types-and-conversions).
Local aliases resolve during declaration binding, while their lexical scopes
are available. File-scope semantic identities survive that resolution.

### Status-bearing collection boundaries

`Iter.try_next` owns iterator advancement. Callbacks return success separately
from a `Var` output, runtime adapters consume that status, and generated
`foreach` tests it before converting the payload. A callback that reports
success with a `void` output violates the iterator contract. Exhaustion is
represented by clearing the iterator callback, and an unsupported or null
callback is safely exhausted. `Iter.next` delegates to `Iter.try_next` and
returns `void` on exhaustion.
Integer ranges are inclusive and direction-sensitive; construction rejects a
zero step, and endpoint progression terminates before signed overflow.
Derived iterators preserve the same status owner: `Iter.unique` may not emit
`void`, while consuming collectors own their result container through the
ordinary `Scope` lifetime.

`Map.try_get` and `Map.try_del` likewise separate presence from their value
outputs. Map storage rejects `void` keys and values, and map literals use a
counted bulk owner so a dynamic `void` pair cannot be mistaken for a terminal
sentinel. `Map.try_next` traverses occupied slots with separate status, key,
and value outputs, including a raw `(Null, Null)` entry. Structural mutation
invalidates outstanding traversal state. `Map.get` and `Map.del` return `void`
when the key is absent.

`x2c_try_register_descriptor` reports whether descriptor registration
succeeded. `x2c_register_type` and `x2c_register_descriptor` are the ordinary
no-result registration calls. Descriptor registration accepts sparse
`VarMethods` values and merges their non-null callbacks into the type's
existing descriptor.

### Compiler phase fixtures

Compiler fixtures establish exact contracts at selected phase boundaries. Each
small source file declares the artifacts it owns: tokens, parsed AST,
transformed AST, emitted tokens, generated C/H, diagnostics, or native runtime
results. A verified row covers the checked-in fixture surface, not every
possible language program.

The harness invokes the real compiler CLI in a fresh process for every phase.
It does not reproduce the pipeline or expose compiler internals for testing.
Normal checks never rewrite expectations; intentional changes use the explicit
update target and require review of the resulting sidecar diffs.

Collection literals demonstrate the phase-boundary rule directly. The parser
preserves Array elements and Map pairs in source order with their raw parsed
expression types. The transform alone converts aggregate values to `Var`,
still in source order; cache generation delegates to that owner, and emission
does not compensate for an earlier phase.

Direct parsing and macro-generated Lists share the same expression resolver
and declaration publication operations. The token parser reads the grammar
and produces canonical Lists. `Compiler.bind_syntax` walks a substituted List
in source order to establish aggregate, function, parameter, and block scopes,
then delegates ordinary expression typing and declaration publication. It is
not a second expression parser.

Retained `protocol` and `adopt` nodes follow that same generated-source path.
Their source-order semantic effects publish protocol definitions and
adoptions, while later generation consumes them to produce adapters,
descriptors, declarations, and initialization. `macro-source-parity` compares
direct and generated protocols, typedefs, enums, structs, unions, variables,
prototypes, functions, inline functions, preprocessor forms, and a macro
definition used by later source. The broader macro fixture corpus owns List
expressions, calls, operators, placement, hygiene, rollback, and diagnostics.

Index and slice lowering follows the same boundary. Native C indices remain
native AST nodes. Collection keys and indices remain in their parsed types;
the get/set transform owns any Map-key boxing and produces ordinary helper
calls. The fixed-point driver, rather than each lowering helper, owns recursive
processing of the returned call arguments.

Generated identifiers belong to one compiler translation session shared by
the original-source and shallow declaration compilers. The reserved space is
whatever `_is_reserved_spelling` (`src/compiler.x`) accepts: the `_x2c_`
prefix, `_init_guard_`, `_file_init_`, and `_` followed only by digits. A
source declaration whose spelling falls in that space is rejected with a
located diagnostic — one check per declaration in
`Sym.declare`, with no prescan — so generated names can never
collide with user names. The `reserved-namespace` fixture pins the rejection
and `generated-name-hygiene` pins that ordinary names near the convention
still lower unchanged. The snapshot seeds the anonymous-type sequence. Lambda helpers, adapters, transfer frames, and
cleanup temporaries allocate names from that session. Emission keeps cleanup
and preserved-automatic bookkeeping in a stack-local owner, so failed or
repeated Compiler invocations cannot contaminate later output.

### Source declaration collection

`Compiler.collect_symbols` is the single owner of source-specific declaration
collection. It recursively splices quote-includes in source order, leaves
snapshot-covered runtime headers as trivia, and shallow-parses the resulting
raw stream. No host process participates: x2c resolves includes itself and
terminates cycles by real path.

The checked-in snapshot is that collector's proof. `etc/symbols.xlisp` is
defined as a cold raw walk of `lib/x2c.x`, `make sym-check` re-derives it and
diffs, and `make sym-ensure` rewrites it when its inputs change. A collector
change that alters the prelude environment therefore shows up as a diff in a
tracked file rather than as a silent divergence. The consequence to accept
deliberately: collection recognizes `#include` and nothing else, so it does
not expand macros and does not evaluate `#if`.

The declaration stream does not replace the user's source. The original positioned
token stream owns full parsing, diagnostics, and emission. The parser,
generator, and formatter retain source directives in order at top level and
within compound statements, except that generation consumes its control
pragmas and owns the generated header's `#pragma once`. `make sym-check` owns
prelude-environment identity; the symbol-snapshot and header-cache probes own
collection ordering and replay; compiler fixtures own structural AST, C, and
runtime evidence.

### Header-symbol cache

`collect.x` caches the per-file declaration walk it performs for source
declaration collection: `header_symbols_open` loads the tracked
`etc/header-symbols.xlisp` artifact keyed by file path and content hash, and
warm replay from that cache must be byte-identical to a cold walk.
`header_symbols_write` regenerates the artifact from a live walk
(`make hdr-sync`); `make hdr-check` diffs a fresh
dump against the tracked copy so drift fails the gate instead of silently
committing. A stale entry (path present, hash mismatched) is rejected rather
than trusted, and an unreadable include fails loudly rather than caching a
partial result. `run-header-cache.sh` covers merge order across a
re-declared type, gensym consumption through anonymous aggregates, stale-hash
rejection, unreadable-include failure, and batch-vs-solo output parity.

### Error transfer state

Generated `try` uses POSIX `sigsetjmp(env, 0)`/`siglongjmp`, so Error
transfer preserves registers and stack state without restoring a signal mask.
The emitter owns the C rule that automatic state changed across that boundary
must be volatile. It qualifies directly modified named locals and parameters,
and emits volatile cleanup guards. `ExceptionFrame` owns the volatile
transfer state and unwind target written before transfer and read afterward.
Native-runtime fixtures compile with the active repository build flags, so
optimized behavior and signal-mask semantics are executable boundaries rather
than build-mode accidents.

Generated `defer` normally registers a stack cleanup record containing a
callable thunk and an environment that points into the still-live caller
frame. Normal exits unlink and call the record. Each real `ExceptionFrame`
saves the cleanup-chain watermark current at its push; transfer drains records
to that watermark before the existing `siglongjmp` frame hop. A defer-only
function therefore emits no `ExceptionFrame`, `sigsetjmp`, or defer-caused
`volatile`.

Emitting cleanup only on locally visible exit edges cannot satisfy a transfer
originating in a callee. The 2026-07-26 relowering experiment proved that
failure. The callable cleanup chain proved the equivalent executable
unwinding without a defer landing frame on 2026-07-27. Deferred statements
whose lexical control flow (`return`, `break`, `continue`, or `goto`) or
capture type cannot move safely into a callable thunk retain the synthetic
`try`/`finally` lowering. The nested callee-transfer fixture remains the
boundary for either lowering.

Every label also has a statically computed cleanup ancestry. A same-ancestry
`goto` runs no cleanup, while an outward jump drains exactly the exited
regions through the established cleanup wrapper. Entering an unregistered
protected region, including a sibling region, is rejected. Return lowering
evaluates and saves its expression before draining cleanup and returning the
saved value.

### Pooled interning

A `Pool` pairs a `Scope` that owns storage with a `Map` that owns canonical
identities, linked to an enclosing parent pool. `lib/pool.x` owns lookup
(shadowing outward through the parent chain), creation (always landing in the
innermost pool), and release. `String.pool_retain`/`pool_retain_named` and
`List.pool_retain`/`pool_retain_named` establish a named pooling scope for
their respective canonicalization tables; `String.promote` and `List.promote`
move a value owned by an inner pool up to an ancestor pool so it survives that
inner pool's release. `String.try_own` and `List.try_own` report whether the
complete value is proven safe beyond every active pool; zero means not proven
safe, while any promotion failure cause remains in the ambient Error channel.
The Pool suite verifies parent/child lookup shadowing, ownership queries,
reclaiming pool-local storage on release, promotion across pool boundaries,
and the ownership-safety result.

### Lifetimes

Scopes own allocations; callers choose lifetimes.  Inner scopes are the normal
way to release groups of temporary mutable storage.  Explicit `free` remains a
supported way to shorten the lifetime of scope-owned backing storage or a
resource object.  It is therefore wrong to claim either that every value must
be manually freed or that no caller ever frees a runtime value.

The active scope owns `Scope.malloc`, `Scope.calloc`, and `Scope.memdup`
results.  Their `*_in` forms target an explicit scope slot without changing
the active-scope stack.  Named scopes copy diagnostic names but retain the
published `Scope` representation. `Scope.destroy` accepts only a detached
scope-chain root; root, stacked, and attached lower scopes remain owned by
their active lifetime boundary. `Scope.release` closes only a region recorded
by a matching `Scope.retain` on the same active slot; empty retained scopes
remain valid, while an extra release cannot destroy the process root or a
region owned through a different pushed slot. Shutdown hooks may use Scope
while shutdown is in progress; completed shutdown is terminal and idempotent,
and only `Scope_shutdown` and `Scope.stats` remain valid afterward. The scope
suite and subprocess probes verify allocation-list updates, nested and pushed
lifetimes, balance rejection, zero and overflow behavior, hook order, leak
diagnostics, and the terminal boundary.

### Diagnostic and transform presentation

Tokens establish one-based lines and columns. Compiler locations preserve
`file`, `line`, `column`, `length`, and absolute `position`; the source
renderer uses the token `length` as the caret width. The compiler records one
ordinary error by default and then its limit notice. Exact diagnostic fixtures
own this output boundary.

`String.repr` is total for the canonical empty String: it prints the quoted
empty literal `""`, while `String.str` and empty-String canonicalization remain
unchanged. Transformed match and loop ASTs therefore render through their
representation owner without an AST-specific fallback. The match/loop-control
transform fixture owns that presentation boundary.

### Type-owned initialization

A translation unit owns initialization through one
`void TYPE.initialize(void)` method. The parser recognizes that exact
signature; generation owns the once-only guard, literal initialization, and
calls at non-static function boundaries. Static helpers trust that boundary or
the initializer body, which runs only after the guard is set, and do not repeat
the same check. The method body owns the visible runtime assignments.

### Type-owned shutdown

One exact `void TYPE.shutdown(void)` definition owns a translation unit's
process-lifetime cleanup. Generation registers it once through
`Scope.shutdown_hook` after the unit's complete generated initialization
sequence, using the matching type initializer when one exists or the unit's
synthetic initializer otherwise. The Scope runner remains the ordering owner
and invokes hooks in reverse registration order. A type therefore acquires its
resources before its shutdown enters the stack; generated registration does
not derive or reorder startup.

The process-wide hook runner is the plain `Scope_shutdown` function, not a
type-owned shutdown member. This keeps the registration mechanism distinct
from the functions it invokes while preserving the existing C ABI.

### Typedef method inheritance

Dotted method lookup on a typedef value tries the declared receiver first,
then follows each typedef parent in order until it finds a method. Internal
`(typedef Name)` semantic keys describe the chain but are not method owners.
The first declared method wins, and its return type owns any following postfix
operation. A method that explicitly spells `Self` binds those result and
parameter positions to the original static receiver typedef, not the ancestor
where lookup found it. An unmarked result keeps its declared type.

This is compile-time lowering to an ordinary function with the receiver
prepended as its first argument. `Self` metadata changes dotted type checking,
not the emitted function ABI. This is not runtime dispatch and does not add a
second method registry.

### Compiler crossings

Numeric source types registered by `Type.var_tag` round-trip through matching
tags, and cross-tag numeric conversion is verified through `Var.convert`.
Numeric-to-String interpolation boxes through those tags and renders with
`Var.str`; a segment statically typed as `Var`, including a file-scope alias,
also renders through `Var.str` for every runtime tag.
The interpolation suite provides executable evidence.

Static printf-family formats provide a separate presentation crossing for
`Var`. The transform recognizes `printf`, `fprintf`, `sprintf`, `snprintf`,
and the `printf` methods on String, File, and Buffer. Numeric conversions use
checked `Var.convert`, while `%s` uses `Var.str`; the compiler fixtures own
the exact supported format grammar and its diagnostics.

Neither crossing establishes a universal nonnumeric conversion policy. The
separately classified `examples/love/values.x` showcase includes
typed nonnumeric observations and is not a broader conversion contract.

### Errors

The verified mechanism is the `Error` handler and accumulation stack, a plain
`raise` statement, and filtered `catch` transfer. Failures enter this one
cause-based channel; genuine absence, exhaustion, text conversion, matching,
and machine-state results retain their natural return channel. Codes classify
the cause at its detecting owner, while handlers and policy own recovery,
rendering, collection, or termination. Relabelling is installed before a
lower-level call by a filtered catch; a post-call mutation is too late because
dispatch is synchronous. Runtime suites and fixtures prove frame-by-frame
cleanup, watermark consumption, relabelling privacy, policy behavior, and
self-host convergence.

Each accumulated Error owns a private Scope plus List and String pools. Error
details are immutable/value-only graphs: nil, numeric or enum values, Symbols,
Atoms, Strings, and recursively admissible Lists. Static crossings are checked
by the compiler and dynamic `Var` contents remain runtime-authoritative.
One record exists per in-flight raise; the dispatch that created it reclaims
it, or a selected filtered catch retains it. Observing handlers and selected
catch bindings borrow that record, and `Error.snapshot` is the explicit
crossing into the caller's ordinary Scope and canonical pools.

Policy accepts only `<abort>`, `<log>`, and `<ignore>`; an invalid
disposition raises `<bad-arg>` without mutating prior policy, while unknown
codes remain legal and default to `<abort>`. Every cause in
`lib/error-macros.xmacro`'s shared table is the exception to configurable
policy: each remains `<abort>`, cannot be consumed by an observing handler,
and either transfers to a filtered catch or enters the fatal floor. Error
initializes before Logger
so reverse-order shutdown leaves Error usable to later subsystem hooks, lets
Logger report and truncate root collection, and destroys Error state before
the raw Scope leak report.

## Partial contracts and open decisions

### Sentinels

The bit-level distinction between zero-like empties and all-ones `void` is
verified, as is its exclusion from collection and iterator value domains.
Status-bearing iterator and Map APIs separate the most common exhaustion and
absence cases from payload values. Public APIs vary in whether `void` means
missing, exhausted, or invalid;
each must document that terminal meaning. This is the open **Missing and
exhaustion API use** row in the ledger above.

### Batch-compilation memory brackets

`src/main.x` wraps a multi-file compile in nested lifetime brackets: an
outer `String`/`List` pool retained for "header symbols" survives the whole
batch so cached header contributions promote out of a unit's pools and stay
live, while each translation unit runs inside its own `Scope.retain()` plus
per-unit named `String`/`List` pools that release when the unit finishes, so
batch peak memory stays near single-file peak. Nothing in `Match` has to be
flushed before those pools release: a compiler-owned pattern site keeps its
plan in `Match`'s own shutdown-owned scope, and every other pattern's plan
dies with the call. `run-header-cache.sh` verifies batch-vs-solo output
parity, which
exercises this bracketing incidentally, but no probe directly asserts the
retain/release discipline itself -- that a unit's transient allocations are
actually reclaimed at release, or that a leak in one unit's bracket cannot
survive into the next. Treat this as executable evidence of output parity,
not of the memory-bracket contract.

## Working rules

### Trust what was actually established

- Do not re-check a precondition already established by a type, constructor,
  canonicalizer, or typed match constraint.
- Do check external input and legitimate optional states at their owner.
- Do not treat a binder, warning-only conversion, or undocumented convention
  as proof of a stronger invariant.
- When the same check appears repeatedly, find the missing owner before
  deleting the copies.

### Use the language

- Prefer compiler-inserted conversions where the source/target pair and
  context are supported.  Do not manually unbox merely to reproduce a proven
  conversion, and do not assume an unsupported conversion exists.
- Prefer current source forms such as `value is not Type`, receiver methods,
  literals, and direct patterns when they express the operation directly.
- Prefer `match`, `match_replace`, foreach, and List/Iter folds when they state
  the transformation directly.
- Use explicit traversal when order, state, ownership, or performance makes it
  clearer.  Pattern matching and traversal compose; they are not alternatives.
- Choose scopes by lifetime.  Pair an inner `Scope.retain` with guaranteed
  release.  Do not create a scope solely to hold values whose existing owner
  already provides the required lifetime.

### Keep the surface honest

- Avoid trivial getters, setters, and wrappers that own no invariant.  Use an
  accessor when it is the enforcement site or protects representation.
- Reserve public `x2c_*` names for the deliberate C interface used by generated
  code, native callers, or process-wide setup. Put ordinary public operations
  on their owning types and make private helpers `static`.
- Delete a protocol, macro, or adapter family when it only regenerates
  forwarding calls to an existing conversion and operation.
- Delete dead code; Git is the archive.
- Do not commit debug/watch scaffolding or fallback behavior that bypasses a
  contract failure.
- Comments explain intent, ownership, or a non-obvious constraint.  They do
  not restate the next line or maintain a second catalog of the module.
- Do not broaden a public contract or resolve a ledger decision without author
  approval and tests that make the new rule executable.

## The bloat test

Compactness is an architectural result, not a line-count contest.  The best
changes usually reduce one or more of:

- independent invariant owners,
- branches and fallback paths,
- representations of the same concept,
- manual conversions or cleanup sites,
- code needed to express a transformation.

The practical value of a strong contract is the work its consumers no longer
perform. If every consumer still validates, translates, mirrors, or repairs
the same fact, either the contract is not yet verified or the consumers are
not using it. Strengthen the existing owner and its proof first; then delete
the repeated work. Do not add a second owner to make the first one easier to
ignore.

Look first for a whole path that can disappear through current language
syntax or an existing owner. Do not force unlike loops through one callback or
mode merely because their control tokens look similar; an unchanged audit
score is correct when the behaviors differ.

Compile-time generation should share an implementation or project fixed facts,
not conceal policy differences. Count the generator, ledger, adapters, and
invocations as authored source, and inspect the generated C and public symbols
as part of the result. A generated family is worth its size when several
current families obey the same operation, failure, representation, and lifetime
rules; one speculative future consumer does not.

Report lines added and removed as useful evidence, but preserve or increase
behavioral coverage.  A net-negative diff that erases a distinction or a test
is not simplification.  A small net-positive diff that establishes one owner
and deletes downstream boilerplate over time may be.

## Exemplars

Exemplars endorse a property, not every line in a file:

- `lib/common.x` - `x2c_normalize_index` and `x2c_normalize_slice` centralize
  cross-type semantic contracts.
- `lib/scope.x` - scope registration and release centralize allocation
  lifetimes.
- `lib/exception.x` - compact structured control flow with a narrow runtime
  mechanism.
- `lib/match.x` - the self-hosting matcher, including the distinction between
  binding and typed constraints.
- `src/statements.x` - parser code shaped like the grammar it recognizes.
- `src/cache.x` - initialization rewrites match expression structure while
  the surrounding code manages placement and cached storage.
- `lib/symbolset.x` - a closed vocabulary compiled once into static
  perfect-hash storage; the literal owns membership, index, and order.
- `lib/array-generics.xmacro` - one imported implementation shared by ordinary
  `Array` and six explicitly instantiated packed numeric families; `%[...]`
  remains the ordinary `Var` Array path.
- `lib/map-generics.xmacro` - one Robin Hood implementation shared by ordinary
  `Map` and explicitly instantiated native numeric families; hashing, equality,
  errors, boxing, and iteration remain visible per-family choices.

Related guides: `agents/x2c-coding-style-guide.md` for mechanical style,
`agents/skills/execute-x2c-plan` for ordinary development,
`agents/skills/simplify-x2c-source` for systematic audits, and
`plans/README.md` for durable planning.
