# Hooks spike: findings

> Status: reference
> Research spike on private branch `gwf/hooks-spike`, from dev `ae34288c`.
> Not for merge without Gary's approval.

## Question

Can an included x2c file add a language construct, string `switch`, as
cleanly as a built-in compiler feature? How do the two compare?

## Approaches

1. **User space** (`string-switch.x`, `trace.x`): a statement decorator whose
   meta function rewrites owned string labels to indices and dispatches with
   `selected == "label" ? N : ...`. The `hook` prototype (`src/macros.x`,
   `src/statements.x`, `src/parse.x`, +41 -7 lines) makes ordinary `switch`
   and every function definition invoke a registered decorator.
2. **Built-in** (branch `independent-case-design`, head `118189d2`): an
   independent agent, without seeing approach 1, added `_string_switch` to
   `Compiler._step_tag` in `src/transform.x` (+123 lines) with two
   diagnostics, three fixtures, and a book paragraph.

Both chose the same lowering: a real C `switch` over label indices, the
subject evaluated once into a temporary, ordinary `String ==` equality, and
string-literal labels only.

## Code size

| | Compiler lines | Extension lines |
| --- | ---: | ---: |
| Built-in string switch | 123 | 0 |
| User-space string switch | 41 (general hooks, shared by every extension) | 59 non-comment |
| User-space tracing | same 41 | 18 |

## Coverage

| | Built-in | User space |
| --- | --- | --- |
| `String` and aliases | yes | yes |
| C strings | yes, cast without allocation | converted to `String` |
| Null C string | `default` in the prototype; Gary decided it matches `case ""` | matches `case ""` |
| Non-literal label | diagnostic | left as an integer label: wrong dispatch |
| Duplicate labels | diagnostic | C compiler error |
| Plain `switch` syntax | yes | with `hook switch` |

## Translation cost per use

Same generator, instruction counts on converged compilers, slope from N=50 to
N=400 functions, each with one three-label switch:

| Form | Instructions per use |
| --- | ---: |
| Built-in `switch` | 6.55 M |
| Hand-written equivalent | 7.75 M |
| User-space decorator | 14.36 M |
| User-space through `hook switch` | 18.94 M |

The hook check costs nothing measurable when no hook is registered. The
hooked form pays for a second meta layer that passes non-string switches
through. One project meta call costs about 1.3 M compiler instructions and
0.17 ms of helper time. Library meta code runs in the compiler process.

## API gaps the user-space version exposed

- A meta quotation's declaration is renamed for hygiene, and a separately
  built quotation cannot refer to it, so the temporary needs a second
  decorator layer.
- `$(...)` Lisp forms cannot see template locals; x2c call syntax can.
- Project meta code cannot read compiler state such as source text.
- Extensions have no way to report a diagnostic at a node, so the
  non-literal-label check is missing.
- Unit support and file initialization have no x2c-level operations; string
  switch did not need them.
