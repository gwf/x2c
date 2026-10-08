# Typing queries from project meta code (W2-A)

> Status: reference
> Spike on private branch `gwf/hooks-spike`, worker W2-A, 2026-10-07.
> The proof is `typed-switch.x` with `typed-switch-test.x`.

## Design

A query is a nested request inside a meta call. The helper's operation,
such as `x2c_type_resolve`, writes `(query OPERATION (ARG ...))` on the
reply stream and reads requests until `(answer V)` arrives. The client's
reply loop (`Compiler.meta_helper_call`) answers it with
`Compiler.apply_meta_function`, the call the typed hook already uses. That
call applies the compiler's own operation of that name at the call's site.
The call is still waiting, so the answer comes from the call site's state.

- The helper forwards every operation that reads compiler state:
  `x2c_syntax_type`, `x2c_type_resolve`, `x2c_type_fields`,
  `x2c_type_members`, `x2c_type_layout`, `x2c_type_element`,
  `x2c_type_parameters`, `x2c_type_return`, `x2c_type_is_*`,
  `x2c_type_tag_name`, `x2c_type_reverse_name`, `x2c_method_resolve`,
  `x2c_protocol_member`, `x2c_function_parameter`, `x2c_literal_value`,
  `x2c_invocation_*`, and `x2c_meta_definition_hashes`. Each is one line.
  `x2c_source_text` still reads only a `Source` description, because a
  capture is found by identity and identity does not cross the pipe.
- A failed query reports as the in-process call does, at the call's site.
  When the failure raises instead of exiting, as it does under recovery,
  the client kills the helper first, because the helper is waiting for the
  answer. The next call starts a new helper.
- While the helper waits, it serves any other request with the main
  loop's code (`_serve`), and `(quit)` ends the helper. A query whose
  answer runs another project meta call would be served in order; no test
  reaches that case.
- `apply_meta_function` now restores `meta_call_form`, so a failure of
  the outer call after a query names the outer call.

## Alternatives

- Passing facts in, as `TypeInfo` does: the caller must know beforehand
  which questions the body asks. A component that asks about a type it
  finds in the syntax, such as a typedef chain, cannot be served. It also
  pays for facts the body does not use.
- Running the query in the helper with a copy of the symbol table: the
  table is large and changes during the parse, so the copy would cost more
  than the calls it saves.
- A separate query channel: the reply stream already carries
  intermediate frames (warnings, dependencies), so one more frame kind
  needs no new descriptor.

The nested request is general, because it uses the compiler's own
operations unchanged. It is also correct, because those operations run at
the waiting call's site.

## Proof

`string_switch` asks `x2c_type_resolve` for a named subject. It asks only
after it finds string-literal labels, so integer and Symbol switches make
no query. A subject whose type resolves to a C string, which String, its
typedefs, and `char *` do, becomes a string switch, with the subject cast
to String. A named subject of another type is declined. Its string labels
then reach C's own switch rules:

```text
declined.c:11:10: error: integer constant expression must have integer
type, not 'char[4]'
```

Before this change, that case was an x2c conversion error: "cannot convert
the integer c to pointer type ("String")". A declined case of that kind
cannot be a passing test, because C rejects string labels on an integer
subject.

## Cost

The stage-0 compiler of this branch, measured with `bench/measure.sh` (one
warm-up, minimum of five). Instructions are the compiler process's; user
time includes the helper. The branch's `src/` differs from its bootstrap,
so each translation also parses the prelude; slopes cancel that constant.

One query, from one meta call that asks `x2c_type_resolve` 0 and 2,000
times:

| Measure | 0 queries | 2,000 queries | Per query |
| --- | ---: | ---: | ---: |
| Instructions | 9,399,304,428 | 9,732,538,128 | 0.167 M |
| Real time | 0.68 s | 0.74 s | 30 us |
| User time | 0.61 s | 0.65 s | 20 us |

Typed switch per use, the slope from N=50 to N=400 (`bench/gen-typed.py`;
`sw-color` is the same unit over `typedef String Color`):

| Unit | Before | After |
| --- | ---: | ---: |
| `sw-typed` (String subject) | 17.09 M | 17.50 M |
| `sw-color` (typedef subject) | 17.13 M | 17.45 M |
| `int-typed` (declined) | 4.46 M | 4.42 M |
| `int-plain` (no hook, control) | 3.30 M | 3.33 M |

A string switch costs about 0.4 M more per use: 0.17 M for the query, and
a remainder that was not attributed (the subject is now always cast).
A declined switch costs nothing more.

## Limits

- `x2c_source_text` of raw captured syntax still fails in the helper.
- A failed query that raises restarts the helper, so the unit's
  `meta static` values start again at the next call.
- `meta-globals` and `meta-records` fail their `ast` phase with any
  `src/` change until the bootstrap is refreshed. The prelude is then
  parsed in process, which moves binding and origin numbers. A one-line
  change to `src/meta-native.x` alone reproduces this.
