> Status: done
> Implemented and validated, 2026-10-31, in `f701f2703` and `c84a2828`.
> Gary selected result-kind preservation and decorator continuation.
> The keyword is `expand`; the final integrated publication gate passed.

# Macro-target decorators and mapping code

## Purpose and source form

Add a `Macro` decorator target. A decorator can receive the following macro
as a value, then generate code by applying it to compile-time data. Mapping
follows the supplied macro's result kind, rather than always making statements.
The examples below are implemented and covered by compiler fixtures.

```c
expand %(
  (string "_export_string")
  (list   "_export_list")
  (array  "_export_array")
  (map    "_export_map")
)
macro Stmt(Expr $tag, Name $export) {
  if (v is $tag) return $export(c, v);
}
```

The first decorator captures the rows expression. It returns a zero-explicit-
argument Macro-target decorator that captures the following macro.
The anonymous macro introduces no callable name. Its braces delimit its
template; they do not introduce a block around the generated statements.

Use the existing `keyword NAME $macro;` mechanism for the selected spelling.
Keep the direct `$NAME(...)` spelling available. Keep the spelling contextual.
Give `expand` a contextual lexical spelling, retagged to `ident` before parsing,
so an adjacent percent literal enters quoted-data mode. This is the same lexical
exception as `raise`. The visible alias retains ordinary keyword-alias
invocation precedence. Other
decorator names can parenthesize a List target. No `expand` parser production
or token rescanning is needed.
Put the mapper and alias in the existing syntax prelude so ordinary programs
can use the selected keyword without an extra include.

## Macro capture and producer contract

Add `Macro` as an explicit, singular hole kind and decorator target. It
supplies the canonical Macro value, including its existing captured macro
environment. It does not supply an expression that must be executed at run time.
Permit the same hole kind as an explicit macro argument for consistency.

A Macro target accepts an anonymous definition, a named definition, a bare
`$name` macro value, or a parenthesized compile-time Macro expression. A
parenthesized expression makes the boundary explicit; arbitrary adjacent
runtime expressions are not captured. Reuse ordinary macro-definition and
expression parsing. No source string is reparsed.

Capturing a named definition stages its publication. Its own body can use
the provisional self binding as today. The original definition must not
become visible after mapping consumes it. If a transformation returns a
definition, publish that result through ordinary definition binding. Reading
an existing `$name` value does not change its registered definition.

A Macro-target decorator uses an arrow body that computes its result at
compile time. The compiler must not try to parse a fixed statement or unit
template before it knows the captured macro's kind. For example:

```c
macro Decorator $expand(Expr $rows) =>
  macro Decorator(Macro $generator) => $_x2c_expand_rows($generator, $rows);
keyword expand $expand;
```

The returned decorator's producer calls a mapping meta helper. The Macro hole
passes the value directly. The Expr hole passes captured syntax to a `Code`
parameter. The helper reads its constant List value through the existing
constant-decoding owner (`Code.value`), once per application. A meta-produced
List is also allowed. A runtime-dependent input is an ordinary compile-time
evaluation error. Do not treat a captured List expression as its List value
without evaluating it.

The result has two structurally distinct forms, using existing representations:

- A bare canonical `macrodef` is a transformed Macro. A named definition
  target publishes the returned definition in its declaration scope. An
  anonymous or value target yields a Macro value in an expression position.
  Returning an ordinary Macro does not invoke it. A Decorator returned during
  decorator application continues decoration as specified below.
- Ordinary canonical syntax, including `(seq ...)`, generates code. Its
  result kind is the captured macro's result kind. Bind it through the ordinary
  operation for the insertion position. A sequence containing definitions is
  generated code, distinct from returning one bare Macro value.

Do not infer result kind from the first generated node. Empty output has
the same kind as populated output. No new public result envelope, AST-origin
marker, interpreter, or runtime class is needed.

The mapper returns a canonical sequence of pending applications. It does not
return a Macro transformation. Mapping a `Decorator` itself is not defined:
its implicit target is still missing. Report that mismatch rather than
consuming another source item for each row.

## Input rows and applications

Keep the structural convention already demonstrated in the working helper:

- Each non-List item supplies one argument.
- Each List item supplies a complete argument row.
- A List passed as one argument requires an enclosing one-element row.
- An empty input makes no applications. An empty row invokes a zero-argument
  macro. A trailing sequence parameter receives the remaining row items using
  ordinary macro-value grouping.

Thus `%(1 2 3)` maps a one-argument macro, while `%((1 2) (3 4))` maps a
two-argument macro. The convention does not change according to arity, and
one-argument macros may also use explicit one-element rows.

Evaluate the outer List once. Build applications in row order, then expand
and bind them in that order at the insertion site. Each application receives
ordinary fresh names. Free names resolve where the output lands; explicit
`using` and captured macro identities retain their existing meaning.

Use `Macro_apply` for pending applications. Its current `_group` walks the
signature and can discard extra supplied values; it does not establish a
checked argument-count contract. The mapper must reject incorrect row arity
at its new row-supply boundary before calling it. Keep this check in the
mapper, using canonical parameter rows, without changing existing callers of
`Macro_apply` or adding another syntax validator. Diagnostics identify the
row number, expected arguments, and supplied arguments. Ordinary insertion
owns hole-kind, binding, type, and placement errors.

## Result kinds and delimiters

Preserve all ordinary code-producing result kinds:

| Supplied macro | Generated items and allowed position |
| --- | --- |
| `Stmt` | Block items; a governed single-statement position still requires exactly one statement. |
| `Unit` | File-scope declarations and definitions. |
| `Declaration` | File-scope declarations with the existing retained-signature contract. |
| `Field` | Struct or union fields. |
| `Enumerator` | Enum entries. |
| `Entry` | Map entries. |
| `Expression` | Expressions; multiple results require an expression-sequence splice. |

The decorator chain ends at its final target. A braced anonymous Macro target
ends at `}` without a following semicolon. An anonymous arrow macro's expression
ends at the enclosing delimiter, or `;` at unit, block, statement, and field
positions. There is no semicolon between stages of a decorator chain. Preserve
existing terminators for ordinary macro invocations and named definitions.

An ordinary expression position requires exactly one generated expression.
Zero or several expressions are errors there. Do not reduce them with the
comma operator or manufacture an Array or List. In an existing template
argument/element sequence slot, extend the existing `@` splice path to accept
this Macro-target decorator. For example, inside an enclosing template:

```c
consume(@expand (%(1 2 3))
        macro Expression(Expr $n) => $n * $n);
```

This supplies three arguments. Empty input supplies none. This proposal adds
no general runtime splice or rest-parameter behavior. Direct ordinary calls
retain their current splice rules; the example is a compile-time template
sequence slot. Ordinary single-expression use also works for one input row.

Anonymous `Unit` and `Declaration` generators are needed here. Current
definition reading marks anonymous macros local and rejects those result
kinds. Separate anonymity from named-local placement: constructing an
anonymous macro value does not emit file-scope code. Keep the prohibition on
named local Unit macros. Emission remains subject to ordinary placement.

Collection and full parsing must expose the same generated declarations,
signatures, includes, and compile-time definitions in source order. Preserve
Declaration's existing public-signature machinery. Each mapped application
must retain `src/macros/expansion.x:_construct` and its `declaration-bundle`
handling for Declaration results and collected Unit results. The outer
decorator's dynamic result routing must not replace that per-application path.
Do not implement a second,
reduced expansion just to discover generated prototypes. Use the owning
collection/overlay mechanism and its existing cached effects. Do not introduce
a process-wide expansion cache or eagerly run mapping during recognition.

## Transforming a macro into a decorator

A Macro-target decorator may return a valid Decorator definition as a Macro
transformation. Changing only `(kind ...)` is insufficient: target captures,
template category, patterns, fresh names, and rebuild data must agree. Reuse
the normal definition-construction operations or a source-defined anonymous
Decorator; do not hand-patch stale derived fields on a finalized macrodef.

Defining and applying remain distinct. A transformed named definition can
make subsequent invocations decorate their following source. Publishing a
named definition does not itself apply it. For example, schematically:

```c
$make_guard()
macro Stmt $guard(Stmt $body) { $body }

$guard()
{ work(); }
```

The explicit `$guard()` is the application. A transformation of an existing
Macro value produces a new value; it does not mutate all references or
retarget keyword aliases that already captured the earlier definition.

During decorator application, a returned Decorator value with no remaining
explicit parameters immediately consumes its following source target. Its
target kind chooses the ordinary parser. Continue until a stage produces
terminal code or a non-Decorator Macro. A returned decorator with explicit
parameters is diagnosed rather than guessing arguments. An absent or
incompatible following target is an error. Ordinary expression evaluation of
a Macro value does not consume source. Defining a named Decorator stays inert.
The anonymous returned decorator embeds the first stage's data through template
substitution; do not introduce arbitrary local-data closures.
Nested definitions can refer to explicitly enclosing template holes. Give
nested and anonymous definitions scoped identities for holes and private
locals, so shadowing and forwarding remain correct. Infer an enclosing hole's
kind in its owning map. Keep global named definitions quoted during outer
substitution; only local captured definitions expose their scoped templates.

Macro-target stacking reduces the closest decorator first. The next outer Macro
target requires that result to remain a Macro; generated terminal code cannot
silently become another Macro target.

An outer decorator sees the completed result after the returned decorator
consumes its target. Collection must consume exactly the same source extent.
Initial target kind does not constrain the final result kind: `expand` first
captures an Expr but can finally generate fields, statements, or declarations.

## Naming options

`expand` is selected. These are recorded alternatives, not additional aliases.
Only the selected spelling is installed.

| Name | Reading or tradeoff |
| --- | --- |
| `mapcode` | Directly names the map-over-code operation; strongest precise option. |
| `generate` | Plain and readable; broader than this particular operation. |
| `instantiate` | Applies a template to each argument row. |
| `emit` | Short; can suggest the compiler's final output stage. |
| `produce` | Plain, but does not convey repeated application. |
| `unroll` | Familiar compile-time repetition; can suggest loop optimization. |
| `each` | Short and row-oriented; reads like iteration. |
| `for_each` | Explicit iteration; can suggest a runtime callback. |
| `codegen` | Familiar abbreviation for code generation. |
| `codemap` | Explicit code mapping; word order is less natural as a verb. |
| `project` | Each input row becomes output syntax; has other project meanings. |
| `render` | Template-oriented; can suggest text output. |
| `replicate` | Emphasizes repetition more than different arguments. |
| `stamp` | Suggests repeated template application; less conventional. |
| `weave` | Suggests composing code; less precise about row mapping. |

Earlier recommendations were `mapcode` for precision or `generate` for ordinary
reading. Gary's staged form uses `expand`.

## Evidence and implementation steps

Investigated at `c77b6020c1c7b7c2f9cd061b706f8b664b500410`.
The current `builds/0/x2c` compiled and ran temporary flat-list and row-list
helpers. Flat input summed to 6; two rows changed the sum to 32; empty input
left 32 unchanged. Symbol input emitted `string list array map`. A separate
export-dispatch probe returned `11 12 13 14`. These establish mapping and
pending application today, not the proposed syntax or result-kind routing.

Current owners:

- `src/macros/definitions/reading.x`: categories, target eligibility, anonymous
  definition restrictions, and body parsing.
- `src/macros/definitions/templates.x`: canonical macrodef construction and
  definition publication.
- `src/macros/invocations/recognition.x`: fixed result-kind selection,
  position recognition, keyword aliases, and collection classification.
- `src/macros/invocations/targets.x` and `expressions.x`: target capture,
  argument parsing, transactions, and expression decoration.
- `src/macros/definitions/slots.x`: computed syntax and sequence splices.
- `src/macros/expansion.x`: per-application expansion and retained declaration
  bundles for Declaration and collected Unit output.
- `src/expressions/syntax.x` and `src/macros/values.x`: Macro values and captures.
- `src/parse/binding.x` and `units.x`: ordinary syntax and definition binding.
- `src/collect/walk.x` and the compiler declaration projection owners:
  collection, included definitions, and portable compile-time effects.
- `lib/macrovalue/construction.x`: pending application and signature grouping.
- `src/stage.x`, `src/meta-sdk/syntax.x`: captured syntax versus constant values.
- `src/grammar.x`, `src/collect/walk.x`: the existing syntax prelude.

Implementation sequence:

1. Add Macro capture and the arrow producer contract through the existing
   definition, invocation, and meta-call owners. Preserve existing target
   behavior. Support capture-time publication, returned-Decorator continuation,
   and closest-first stacking. Continuation uses the ordinary recursion budget.
2. Route generated output by the captured result kind after capture, including
   anonymous file-scope generators and template expression sequence slots.
   Keep lookahead side-effect-free. Handle bare Macro transformations through
   ordinary value/definition construction and binding.
3. Implement the mapper as a meta helper plus a Macro-target decorator and
   the selected keyword alias. Share the input normalization and row-arity
   boundary. Avoid exposing new runtime ABI merely for this helper.
4. Add focused compiler fixtures using the existing harness. Cover flat and
   row inputs, empty input and zero-argument rows, a List as one argument,
   trailing sequences, wrong arity, runtime-dependent data, every result kind,
   expression cardinality/splices, named and anonymous targets, visibility,
   hygiene, nesting, failure rollback, macro transformations, returned-Decorator
   continuation, and inert named definitions and ordinary Macro values. Include a cross-unit
   Declaration generator and header-cache/collection parity case.
5. Document the target/result distinction, row convention, result positions,
   terminators, keyword spelling, and definition-versus-application rule in
   the book. Update the authoritative syntax grammar and editor syntax/tests
   where necessary. Refresh generated artifacts only through repository targets.
6. Review and fix the complete authored diff before publication validation.
   Check especially for duplicated binders, validators, temporary publication
   leaks, producer-dependent collection, and implicit source consumption.
   Then use the existing delivery and validation workflow. Bootstrap the new
   capability before adopting it in self-hosted source. Do not add gates or
   recurring checks. Measure compiler-throughput effects using the existing
   performance policy; no runtime hot-path work is intended.

## Design review

The compiler addition captures a Macro and places its result. The meta helper
owns mapping. Canonical definitions, pending invocations, sequences, ordinary
binding, and existing transactions own the rest. Mapping does not add a
runtime dependency, lock, caller lifetime obligation, origin requirement, or
new AST validator. Required parser changes are localized but span collection,
expression slots, and declaration signatures; a statements-only prototype
would not establish the requested full result-kind behavior. Returned-Decorator
continuation is selected in decorator application only; ordinary value and
definition semantics remain unchanged. No special grammar for `expand` is
needed beyond general Macro-target capture and decorator continuation.

## Implementation and evidence

Implemented in `f701f2703`, with the final compiler and bootstrap refresh in
`c84a2828`. The syntax prelude defines the two-stage `$expand` decorator and
its keyword alias. The meta helper builds ordinary pending applications;
existing insertion, placement, hygiene, and declaration retention place them.
The compiler supports Macro capture, scoped nested substitutions, and returned
Decorator continuation. Named definitions and ordinary Macro values stay inert.

The package bundler's private `expand` function was renamed to
`expand_variables`, because the selected keyword alias claims that call form.
No public runtime signature or recurring validation requirement was added.

The complete authored diff and the nested-substitution fix were reviewed.
Global named definitions retain their quotation boundary. Local captured
definitions expose scoped templates to existing substitution. Generated
artifacts were refreshed through repository targets.

Validation on the completed compiler tree:

- `tools/gate-state.py ensure agent-pr-check` passed, including shipped
  bootstrap and self-host comparisons, cold collection, command/package probes,
  1,373 compiler fixtures with 3,032 artifacts, and 1,135 unit tests with
  99,373 assertions.
- All 138 executable book samples compiled and matched their expected output.
- Editor grammar and TextMate tests passed. Generated syntax specifications
  checked with zero stale outputs.
- The exact export example, all seven result kinds, enclosing row holes,
  per-row hygiene, once-only declaration generation, native Macro factories,
  cross-unit interfaces, and script placement have executable coverage.

The compiler checkpoint compared baseline `b627bb039` with candidate
`7ee0f1b63` on the same Mac. Both trees were rebuilt from refreshed bootstrap;
both reported a nonempty prelude and no missing prelude units. Five alternating
runs translated the seven units from the existing compiler benchmark in each
tree. The workload includes compiling the added parser code. Median retired
instructions were 29,310,581,784 before and 29,339,694,552 after: an increase
of 0.10%, within the observed sample variation. This is advisory evidence,
not a claim about every compiler workload. Raw samples and environment records
are in `/tmp/x2c-macro-performance-20261031/`; the local run log is
`debug/macro-target-performance.log`.
