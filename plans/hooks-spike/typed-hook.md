# Typed node hook

> Status: reference
> Wave 1 entry W1-A of `execution.md`, on private branch
> `w1a-typed-hook` from `gwf/hooks-spike` `04a6fbeb`, 2026-10-07. The proof
> is `typed-switch.x` with `typed-switch-test.x`.

## Spelling

```x2c
hook <switch> string_switch;
```

The node kind is an angle Symbol, which keeps the typed phase visibly
distinct from the parse-phase `hook switch $macro;`. The target is a meta
function `List f(List node)`, not a decorator, so a component makes one meta
call per node. The tokenizer reads `<switch>` after `hook` as a Symbol
literal, as it already does after `tag`. Kinds are a closed set in
`src/macros.x` (`typed_hook_kinds`); this wave admits only `switch`.

The registration reuses keyword storage and export: it stores the function's
spelling in `kw_aliases` under `hook:<switch>` and records the same
`compile-time keyword` effect, so a nonstatic hook reaches includers and
`static` keeps it file-local. A `Compiler.typed_hooks` flag is set when a
registration is parsed or installed.

## Semantics

`Compiler._step_tag` checks `c.typed_hooks` before anything else. When it is
set and the tag is a registered kind, the meta function receives the bound,
typed node. A result equal to the node, or a call the project meta build
defers, declines and built-in dispatch continues. Any other result binds
with `bind_syntax` at a statement position: quotation holes keep the node's
bound children, and the template parts bind and type as an expansion's do.
The bound result re-enters `_step`, as a changed `next` already does, so the
hook sees its own output and must decline on it.

The meta call goes through `Compiler.apply_meta_function`
(`src/meta-native.x`), which shares the failure handling of an explicit
meta call.

## Proof

`typed-switch.x` rewrites a switch whose subject is a named type or a C
string (`char *`, `const char *`, `char[]`) and whose owned labels are
string literals: label indices, the subject evaluated once into a String
(a C string by a cast, without copying), and String `==`. A null C string
becomes a null String, which equals `""`. Integer and Symbol switches are
declined; their generated C is byte-identical to a unit without the hook.
Run it with `x2c run typed-switch.x typed-switch-test.x`, which prints `ok`.

## Measurements

Stage-1 compilers built from `04a6fbeb` and from this branch, in copies at
equal path lengths. Instructions retired by the compiler process, minimum
of five after a warm-up (`bench/measure.sh`).

| Translation, no typed hooks | Before | After |
| --- | ---: | ---: |
| `src/generate.x` | 5,741.4 M | 5,741.4 M |
| `src/parse.x` | 8,439.1 M | 8,437.7 M |

Per use, the slope from N=50 to N=400 functions with one three-label
switch (`bench/gen.py`, `bench/gen-typed.py`):

| Form | Instructions per use | Real time per use |
| --- | ---: | ---: |
| Hand-written equivalent | 7.76 M | 0.49 ms |
| Parse-phase `hook switch` (`string-switch.x`) | 18.88 M | 1.49 ms |
| Typed hook (`typed-switch.x`) | 16.42 M | 1.34 ms |
| int switch, no hook | 3.30 M | 0.20 ms |
| int switch, typed hook declines | 4.46 M | 0.34 ms |

A declined node costs one project helper call, about 1.2 M compiler
instructions and 0.14 ms.

## Limits

- Project meta code cannot call the typing queries (`x2c_type_resolve` and
  the rest fail in the helper), so the proof cannot tell whether a named
  type reaches String. It accepts any named subject with string-literal
  labels and lets binding convert it; a non-String named subject is then a
  conversion error rather than a C error. In-process meta code can call
  the typing queries; this was not tried.
- The temporary uses an exact spelling, `x2c_ident("_tswitch_subject")`,
  because no fresh-name API exists yet. It cannot capture user names,
  because every hole holds bound syntax; nested string switches shadow it
  in their own blocks.
- A failure the hook reports is located at the compiler's current token,
  the end of the unit, not at the node. Project meta calls require a token
  site; diagnostics at a node belong to W1-B.
- A typed hook whose meta function is defined in the same file as the
  switches it rewrites fails: the project meta build compiles that file's
  runtime functions without the hook. The hook belongs in an included file.
- Labels are compared as syntax, so duplicate labels reach the C compiler as
  duplicate cases, and non-literal labels are left as they are.
