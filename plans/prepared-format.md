# Prepared literal formats

> Status: feasibility proved locally; production feature deferred, 2026-10-04.
> Based on origin/dev 12a095f9728796f5138278a3082f4e3e7b5e085e.
> Gary requested further investigation until there was a concrete result
> worth reviewing. No production source, bootstrap, or public API is changed.
> Recommendation: retain the experiment, but do not add the optional
> declaration without an actual checked-format workload that needs it.

## Result and recommendation

The prototype accelerates repeated checked formatting, but current repository
workloads do not establish a reason to ship its public surface. The earlier
recommendation relied too heavily on isolated formatter timings. A complete
native export saves 3.73 ms across 20,000 records. A complete Lisp export saves
4.00 ms across 20,000 records, about 5.8% of that formatting-heavy workload.
Neither export is an existing shipped application.

The current compiler and commands have no identified String.format call site
to migrate. Their formatting uses existing printf operations. For native
records with known types, those operations are substantially faster than
either checked formatter and require no new declaration. The prepared plan's
useful niche is repeated fixed-format output from runtime Lists of Vars that
need checked conversion. No current internal owner of that niche was found.

Defer the public macro. Preserve the prototype as feasibility evidence for a
future measured caller. This conclusion does not reject other implementations,
automatic specialization, or the broader metalanguage campaign. None of those
alternatives has an established workload benefit from this experiment.

A fixed valid format can become static data during translation. Execution
keeps checked Var conversion, private output staging, and process-locale
formatting. It does not scan the format or rebuild its native spelling.

The reviewable spelling is:

```x2c
$format.plan(item_format, "item=%d value=%.3f");

String show_item(List values) {
  return item_format.format(values);
}
```

This is an explicit file-scope declaration. It serves callers that repeatedly
format runtime Lists of Vars through one literal format. Ordinary
`String.format` remains available for dynamic formats and single-use calls.
There is no implicit cache, site registration, or new compiler syntax.
A valid plan with no conversion rows returns the format String after the
existing excess-argument check; it needs no output buffer.

The candidate declaration gives the caller one reusable description and
keeps dynamic input with its existing owner. It requires source changes and
file-scope storage. That adoption cost is not justified by an identified
internal workload. Automatic rewriting was not implemented or measured.

## Workload relevance and complete callers

A source census searched src, lib, etc, commands, tools, and examples for
String.format, String_format, and .format calls in x2c, macro, and Lisp files.
Matches were definitions, prototypes, native bindings, and documentation;
there was no production invocation. The unit suites exercise the operation.
The compiler's reporting functions in src/report.x use String.printf, and
Buffer.printf already stages native output before appending it. The compiler's
printf Var lowering in src/transform.x operates on native variadic calls;
it does not route those calls through String.format.

Two constructed application workloads test the strongest plausible use:
export fixed-format records. They are complete in-memory exports, not full
builds, file exports, or measurements of existing applications. Each includes
output construction and canonicalization. Nine interleaved warm samples use
the same native arm64 toolchain and -O2. All alternatives produce exactly the
same output; medians below are elapsed milliseconds per complete export.

| Native export, 20,000 records / 448,890 bytes | Median ms |
| --- | ---: |
| Built String.format, constructing a List per record | 18.470 |
| Shared ordinary formatter, constructing a List per record | 18.299 |
| Static plan, constructing a List per record | 14.738 |
| Existing String.printf, then append each String | 5.436 |
| Existing Buffer.printf directly into the output | 2.594 |

Each record contains its varying integer index and a double cycling across
64 values. Timing includes per-record argument construction, temporary
formatted Strings, Buffer appends, final output, and Scope release. Prepared
execution saves 3.732 ms against the built formatter, about 20.2%. Direct
Buffer.printf is about 5.7 times faster than prepared execution because this
native caller already knows its argument types. The printf alternatives do
not offer checked conversion for arbitrary runtime Vars. They are appropriate
for these known native values, not replacements for the checked contract.
The shared ordinary scanner changes this whole workload by only 0.171 ms;
that result does not justify a separate optimization campaign.

The Lisp export uses the actual interpreter, init.xlisp and lisp-values.xlisp.
It maps a lambda over 20,000 integer records, constructs each argument List,
calls a bound formatter, and joins the returned Strings into 468,889 bytes.
The parsed expression and initialized interpreter are reused. Timing includes
evaluation, lambda/native calls, List construction, formatting, joining, and
Scope release; startup, parsing, and file I/O are excluded. The expression is:

```lisp
(String.join "\n"
  (map (lambda (i)
         (format "item=%d value=%.3f" (list i 12.375)))
       records))
```

The ordinary binding calls shipped String.format. The prepared binding has
the same String/List signature and uses one predeclared descriptor; it asserts
that the supplied format matches. This deliberately favorable application
helper is not an implemented automatic specialization of String.format.

| Lisp export, 20,000 records / 468,889 bytes | Median ms | Range ms |
| --- | ---: | ---: |
| Built String.format binding | 68.707 | 65.560-69.285 |
| Prepared fixed-format binding | 64.706 | 61.817-65.279 |

The first whole export run saves 4.001 ms, about 5.8%. Every paired sample
improved, by 2.690-6.746 ms. A confirmation run took 68.741 ms ordinary and
65.943 ms prepared: 2.798 ms saved, about 4.1%. Every confirmation pair also
improved, by 0.829-5.632 ms. These runs support a roughly 4-6% improvement
on this favorable workload, not a precise universal percentage.
A prior 2,000-record run saved 0.352 ms at the medians,
but had a reversed noisy sample. The larger run strengthens the narrow
format-heavy result. Additional application work can dilute that benefit;
no typical compiler or general application speedup is inferred.

The probes are export-bench.x and lisp-bench.x in the local prototype directory.
Their build and execution logs are debug/format-export* and
debug/format-lisp-bench*; debug/format-workload-summary.json records both
large Lisp runs and the native results. A current production caller, its formatting share,
and its migration cost remain unestablished. Automatic specialization and
broader checked-format optimization remain untested.

## Implementation proved locally

The prototype is in `.context/prepared-format-spike/`:

- `runtime.x` uses the original formatting implementation with one shared
  conversion path. Ordinary parsing passes no saved spelling; prepared
  execution passes its row's spelling. Both use the same numeric and text
  conversion operations and Error nesting. Ordinary literal runs use strchr
  to find the next percent instead of inspecting each byte individually.
- `format_description` runs the same parser in native code. It returns
  canonical List rows containing only flags, width, precision, modifier,
  conversion, offsets, and native spelling. Temporary row storage and host
  addresses do not cross the compile-time boundary.
- `static-macros.xmacro` builds the typed declarations with ordinary x2c
  meta code and quotations. Empty or fallback plans emit no row array.
- The development build loads the analyzer through a native module. This
  makes the boundary testable without changing the shipped compiler.
  Production would link the analyzer with the runtime and expose its
  bodyless meta prototype through the existing native inventory. The
  feature would require no user-managed module.

Spec rows are immutable emitted data. A FormatPlan borrows those rows and
its canonical format String for the program lifetime. The proposed public
surface has no runtime factory, ownership flag, free operation, or cache.
`FormatPlan.prepare` in the prototype is experimental analysis/measurement
scaffolding, not a proposed public API.

## Preserved behavior and retained paths

The first feature prepares valid formats with fixed width and precision.
Formats containing `*`, and formats rejected during syntax preparation,
store the original format and call String.format when executed. Preparation
publishes no format diagnostic. This preserves the first runtime failure,
including a missing argument before a later malformed conversion.

A `*` is consumed while the current parser reads its specification. `%.*c`
also depends on its precision value. Optimizing those cases would require
more design; their fallback is deliberate. It does not reject future star
support. No deferred-error instruction stream is justified by this evidence.

The subject values, numeric conversion, `%s` display text, locale, output
allocation, and canonicalization remain runtime operations. Excess argument
errors retain the format-length offset; conversion errors retain the original
percent offset and complete nested cause. Pointer/write-count conversions
and the other existing unsupported forms keep their existing failures.

File-private generated descriptors work in ordinary source functions.
An included unit's ordinary exported function also passes. Referencing the
file-private descriptor from an exported inline function fails because the
emitted public header does not declare the generated global. That exact
placement is outside the proposed initial usage; broader header/inline
placement is not proved or claimed.

Calling formatting in a file-scope runtime initializer aborts before Error
initialization. The unmodified String.format reproduces the same failure.
This is an existing formatting limit, not a prepared-plan repair. Normal
post-initialization execution and Thread workers are verified.

## Evidence

The fresh seed was built with `make build-safe`. The current prototype builds
without translator or native warnings. All 43 static-plan cases match the
built runtime's output and complete raised error data. Four Context-backed
Thread workers share a descriptor across 4,000 successful calls. The ordinary
included-unit function passes. A reproducible local runner is
`.context/prepared-format-spike/run.sh`; it is not a recurring gate.

Nine interleaved samples of 100,000 calls, native arm64, configured cc, -O2:
conversion workloads vary their integer value across 64 prebuilt argument
Lists. Each mode gets 1,000 warm-up calls. Values, output construction,
conversion, and canonicalization are the same. Measurements are elapsed
nanoseconds per call, not CPU instruction counts.

| Format | Built String.format | Shared ordinary path | Static plan |
| --- | ---: | ---: | ---: |
| `item=%d` | 480.25 | 434.35 | 385.06 |
| `item=%d value=%.3f` | 852.45 | 806.57 | 642.60 |
| `[%s] %08d %.3s` | 1053.37 | 1041.72 | 771.82 |
| Literal without conversions | 390.39 | 299.92 | 2.49 |
| `%*.*f` fallback | 710.62 | 741.56 | 702.59 |

Against the shared ordinary path, static plans save about 11%, 20%, and
26% on the three conversion workloads. The literal-only plan now avoids all
formatting work; this is distinct from the conversion workload benefit.
Star fallback retains the ordinary call. Timings moved across runs with host
activity; no startup or full-application speedup is inferred from them. The
compiled plan consistently benefits the conversion workloads. The earlier
runtime-only spike separately attributed 6-8% to parsed specifications and
the additional gain to retained spelling.

Descriptors occupy 100, 176, and 252 bytes for those conversion workloads:
24 bytes plus 76 per row. No allocator metadata is needed for emitted rows.
The format String uses ordinary canonical literal storage.

A matched two-conversion caller object grows from 505 to 754 listed section
bytes. That adds 152 bytes of row data, 24 bytes of plan storage, 52 bytes of
machine code, and 21 bytes of other constants. With the ordinary formatter
retained, the prototype runtime object's machine-code section grows from
3,940 to 6,276 bytes; total listed sections grow from 5,224 to 7,800 bytes.
The analyzer and experimental runtime preparation are included. These are
object sections, not linked executable or whole-build size claims.

The native-module/helper setup adds development build work. Matched warm
builds took 222 ms for the ordinary caller and 419 ms for the prepared caller,
while their reported translation times were 41 and 38 ms. This is one build
pair with an external helper setup, not a production compile-cost estimate.
Linking the analyzer and shipped macro removes that prototype setup; its
final translation cost still needs measurement.

## Candidate production scope, deferred

1. Use direct percent search for ordinary literal runs. Factor the existing
   conversion operations to accept an optional saved
   native spelling. Keep one numeric/text conversion owner.
2. Add the internal native format-description operation beside the parser.
   Register its canonical List result through the existing meta inventory.
3. Add FormatPlan execution and the literal declaration macro. Keep rows
   borrowed and immutable, with no owning runtime API in this first change.
4. Document the explicit surface, fixed-field eligibility, runtime fallback,
   storage lifetime, and placement. Add focused coverage beside the current
   String tests and macro fixtures; keep checked-in behavior unchanged.
5. Review and fix the completed authored diff. Measure ordinary-path cost,
   translated caller cost, and object storage on the integrated source.
   Use the existing final-tree publication command for approved delivery.

No recurring check, new validation target, extra publication step, or expanded
precommit requirement is proposed. Full-suite, self-host, target portability,
and publication validation have not been attempted for this local prototype.

## Plan review

The existing Spec parser establishes fixed conversion legality. Var.convert,
Var.str, and the printing operations retain value checking and native-call
safety. Prepared execution consumes those facts without another parser or
validator. Malformed and value-dependent formats retain the original path.

The design reuses parsing, spelling, conversion, Buffer staging, exception
nesting, canonical Strings, meta bindings, quotations, and ordinary literal
initialization. A compact row array carries results across stages; no second
matcher, execution framework, cache, or initialization registry is needed.
Prototype runtime preparation and native-module packaging do not become
public feature machinery.

The source remains ordinary x2c functions and declarations. Meta code carries
canonical data to quotations; no raw host representation enters generated
code. No new validator, dedicated diagnostic, or earlier negative rejection
is proposed. Focused cases protect existing output, error order, native
conversion, and shared immutable storage.
