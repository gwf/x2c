> Status: needs author scoping
> Drafted 2026-10-28 from a working probe set kept under
> `plans/reference/probes-2026-10-28/derive/` (`p4f.x`, `r8.x`, `r10.x`;
> run each with `builds/0/x2c run FILE`). The probes establish
> every generation technique the plan relies on. Gary has not yet reviewed
> the public surface or the three decisions listed under "Decisions for
> Gary".

# Derive library and test runner

Two shipped deliverables, no language syntax changes:

- (A) `lib/derive.x`: a `$derive` macro family that generates record
  mappings for a user struct from `Type.fields`.
- (B) `lib/test.x` plus the external command `x2c test`: a test library
  for user projects and a runner that finds, builds, and runs test files.

## What the probe established

All probes ran with `builds/0/x2c run` on `dev` `9aeeef265`.

- `Type.fields` returns `(NAME TYPE)` rows with the declared spelling:
  `("String")`, `("Symbol")`, `("Array")`, `(* int)`, `("Point")`.
  `Type.resolve` reaches `(* char)`, `(struct "Point")`,
  `(* struct "Block")`; `Type.is_value` is 1 for numbers, String, Symbol,
  and List, 0 for Array, Map, structs, and pointers.
- A pattern `%(* ?)` matches every type row (`*` is not a literal star
  there). Classify pointers with `Type.resolve(t).car() == <*>` and
  nested structs with `.car() == <struct>`.
- `x2c_ident` rejects a dotted spelling (`"Point.to_map"`), and a Type
  hole in expression position (`$type.from_map(m)`) is reported as an
  ambiguous hole kind. A dotted method is therefore written by the direct
  `Unit` macro body (`Map $type.to_map($type $value) { ... }`), which the
  compiler discovers as a method, while meta helpers supply only the
  statements and expressions inside it. The macro shares its private
  names with the helpers through `using $value, $out, $map, $a, $b;`.
- The flat spelling of a dotted method is callable from source and from
  `x2c_ident`: `Point_from_map(map)` is `Point.from_map(map)`. Nested
  struct conversion uses it, so the nested type must be derived earlier
  in the unit; otherwise the ordinary undeclared-name diagnostic reports
  the spelling.
- A method definition returned by a meta function through a deferred
  named template (`$derive.method(type, name, body)`) compiles to
  `int(P v){` in C: the dotted declarator loses its name. This is a
  compiler defect to record separately; the plan does not use that form.
- A `meta static` helper reached only through an include fails with
  `explicit meta call cannot be resolved: no binding for probe_make`
  (the known gap). A nonstatic `meta` helper in an included module works
  with `x2c run main.x module.x` and with `x2c script main.x`. A shipped
  `lib/` module needs neither: `tools/gen-linked-meta.sh` copies every
  bodied `meta` function under `lib/` into `src/linked-meta.x`, so the
  helpers run inside the compiler as `system-macros.x` helpers do.
- `x2c_diagnostic_fail` from the helper reports at the `$derive(Bad);`
  invocation with the field name and type, and stops the expansion.
- The full probe generated `to_map`, `from_map`, `equal`, and `repr` for
  `Person { int age; String name; double score; Point home; Array tags; }`
  with `Point` derived first. Output:

```text
{ "home": { "x": 3, "y": 4 }, "name": "Ada", "tags": [ "x", 2 ], "age": 42, "score": 1.5 }
Person{ age: 42, name: "Ada", score: 1.5, home: Point{ x: 3, y: 4 }, tags: [ "x", 2 ] }
equal 1
equal 0 Person{ age: 42, name: "Ada", score: 1.5, home: Point{ x: 3, y: 9 }, tags: [ "x", 2 ] }
```

  Removing `name` from the Map made `from_map` raise
  `<bad-arg>` with `operation from_map, field name, reason missing`.
- Inside a quotation, `%"$key: "` and `%(... (field $key))` insert `key`
  when the generated code runs, not while building. Build such Strings in
  the helper (`String label = %"$(field.car()): ";`) or write
  `$($(key))` inside the percent literal.
- A decorator that keeps its target and registers it at startup works as
  `macro Decorator $test(Unit $function) { @test_register($function) }`
  with the helper placing `x2c_place(%(unit-init), $!{ ... });` and
  returning `$(function)`. Two decorated functions registered and ran in
  declaration order before `main`.

## Deliverable A: `lib/derive.x`

### Location and shipping

`lib/derive.x`, included explicitly like `json.x` and `path.x`. Add the
row `lib/derive.x|optional|Generated record mappings from struct fields;
explicitly include derive.x to use them.` to `docs/library-manifest.txt`.
The module includes `meta.x` and `json.x`. It is not a package: it depends
only on the runtime, its helpers become linked meta automatically, and a
user includes one file. Regenerate `src/linked-meta.x` with the documented
target when the helpers change.

### Public surface (book chapter excerpt)

```x2c
#include "derive.x"

typedef struct Point { int x, y; } Point;
typedef struct Person {
  int age; String name; double score; Point home; Array tags;
} Person;

$derive(Point, <map>, <equal>, <repr>);
$derive(Person, <map>, <json>, <equal>, <repr>, <args>, <row>);
```

`$derive(Type, kinds...)` writes methods on `Type` from its fields. Each
kind is a Symbol literal; `<map>` is implied by `<json>`, `<args>`, and
`<row>`. Field order is declaration order everywhere.

| Kind | Methods written | Behavior |
| --- | --- | --- |
| `<map>` | `Map Type.to_map(Type)`, `Type Type.from_map(Map)` | Keys are field names. `from_map` raises `<bad-arg>` with `(operation "from_map") (field NAME) (reason "missing")` for an absent key; a wrong value type raises the conversion's own `<conv-type>`. |
| `<json>` | `String Type.json(Type)`, `Type Type.from_json(String)` | `to_map().json()` and `from_map(Json.parse(text))`. |
| `<equal>` | `int Type.equal(Type, Type)` | Fieldwise: `==` for numbers and Symbols, `String.equal`, `Var.equal` for Array, List, and Map, the nested type's `equal` for a struct. |
| `<repr>` | `String Type.repr(Type)` | `Person{ age: 42, name: "Ada", ... }` using each field's `repr`. |
| `<args>` | `List Type.args_spec(void)`, `Type Type.from_args(List)` | One `--field` row per field with `(value "FIELD")`; `from_args` runs `Args.parse` and `from_map`. Array, List, Map, and nested fields are rejected for this kind. |
| `<row>` | `List Type.columns(void)`, `List Type.row(Type)`, `Type Type.from_row(List)` | Column names, positional values, and the reverse, for `Prepared.bind(p.row())` and the `List` rows SQLite returns. Nested fields are rejected for this kind. |

Field type coverage: `int`, `long`, `double`, other numeric scalars and
enums, `String`, `Symbol`, `Array`, `List`, `Map`, and a struct that was
derived earlier in the same unit with the kinds the outer type requests.
A pointer field, including `char *`, fails the expansion with
`derive: field 'raw' of Bad has pointer type (* int)` at the invocation.

Generated methods are ordinary public methods of the unit that invoked the
macro. The nested call inside `from_map` is spelled `Point_from_map`, the
flat spelling of `Point.from_map`.

### Design

- The public `$derive` is one direct `Unit` macro:
  `macro Unit $derive(Type $type, Literal @kinds)`. Its body declares
  `using $value, $out, $map, $a, $b, $row, $args;` and writes each method
  skeleton with `$type.name` declarators, as the probe does. One helper
  per kind returns the statement or expression pieces:
  `derive_puts`, `derive_gets`, `derive_equal`, `derive_repr`,
  `derive_spec`, `derive_columns`, `derive_row`, `derive_from_row`.
- Kind selection: the body passes `$kinds` to `derive_wants(kinds, <json>)`
  for each optional method. A method the caller did not request expands to
  an empty item sequence, so one macro body serves every combination
  without a template per kind. Verify in implementation that an empty
  `@helper(...)` at unit scope is accepted; if not, use one `Unit` macro
  per kind invoked from `$derive` through `$derive.map($type)` and so on.
- `derive_field_kind(Type)` is the single classifier, returning
  `<scalar>`, `<string>`, `<symbol>`, `<value>`, `<struct>`, or `<pointer>`
  by the rules the probe established. `derive_fields(type, kind)` calls it
  once per field, raises the pointer diagnostic, and also rejects the
  fields a kind cannot carry (`<args>`, `<row>`), with the kind in the
  message.
- Generated names are hygienic by construction: the macro's `using $name`
  bindings are private per expansion, and field identifiers come from
  `x2c_ident(field.car())`.
- Protocol adoption is not generated. A user who wants `Var(Person)`
  writes the two converters and the adoption on top of `to_map` and
  `from_map`; the chapter shows that in four lines. Reason: the converters
  need a Var tag name and an unboxing policy the macro cannot choose.
- No `.flags` or extra unit is needed by includers: the helpers are
  linked meta and the runtime support lives in `lib/`.

## Deliverable B: `lib/test.x` and `x2c test`

### `lib/test.x`

Add the row `lib/test.x|optional|Test registration, assertions, and a test
program entry; explicitly include test.x to use them.` The module includes
`diff.x` and `system-macros.x`.

```x2c
#include "test.x"
#include "../src/stack.x"

$test()
static void push_then_pop(void) {
  Stack s = Stack.new();
  s.push(1);
  $expect_eq(s.pop(), 1);
  $expect(s.empty());
}

$test.main();
```

- `$test()` decorates a `static void name(void)` and registers it when the
  unit initializes; there is no central list. The registration row holds
  the name, the function, and `x2c_invocation_file` / `_line`.
- `$expect(cond)` records a failure with the expression text and location.
  `$expect_eq(actual, expected)` compares with `Var.equal` after boxing,
  prints both `repr` values, and, when both render with a newline, the
  `Diff.unified` of the two texts. `$expect_raises(cause, stmt)` fails
  unless `stmt` raises the Error whose cause is `cause`. These three cover
  the harness macros that user tests need; typed variants are not added.
- `$test.main()` writes `int main(int argc, char **argv) => Test.main(argc,
  argv);`. `Test.main` reads `--filter SUBSTRING` (repeatable), `--list`,
  and `--quiet`; runs each test in a `try`, so an uncaught Error is a
  failure that names the cause; prints one line per test, `ok NAME` or
  `FAIL NAME (file:line)` followed by the recorded failures; ends with
  `N passed, M failed, K skipped` and exits 1 when `M > 0`, 2 when no
  test matched a filter. `Test.skip(reason)` inside a test marks it
  skipped.
- A test file is a complete program: `x2c run tests/stack_test.x -- --filter
  pop` works without the command.

### `x2c test`

A new command `commands/test/` with `test|shipped|Build and run project
tests` in `commands/manifest.txt`. It follows `new` and `package`: it
initializes the command environment with the embedded identity and spawns
the matching driver from `Compiler.driver_executable()`.

- Discovery: operands are files or directories; with none, the project
  root is the directory of the nearest `x2c.toml` (or the current
  directory). It selects `*_test.x`, `test_*.x`, and `tests/**/*.x`,
  sorted bytewise, excluding `.x2c-build/`.
- Build and run: for each file it runs `x2c run -q --build-dir
  <root>/.x2c-build/tests/<stem> <file> -- <program args>`. `run` compiles
  the file; the file's own includes compile as local modules exactly as
  `x2c script` documents, and the project's `--package-dir` and
  `--x-include-dir` from the selected manifest target are forwarded.
  Nothing in `commands/build` changes.
- Options: `--filter`, `--list`, and `--quiet` pass through to every test
  program; `-j N` runs files concurrently through `Process` jobs with
  output captured per file and printed in order.
- Output: each program's lines as they finish, then a summary line
  `files: 3 passed, 1 failed; tests: 41 passed, 2 failed`. Exit status is
  1 when any file fails to build or reports a failure, 2 when no test
  files were found.
- `unittest/` does not migrate. It keeps `test-support.x`, `test-all.x`,
  and the Scope-balance rules. Sharing the assertion implementation is a
  later candidate once `lib/test.x` has users.

## Validation

- `unittest/test-derive.x`: a fixture struct set (`Point`, `Person`, an
  enum field, a Symbol field, a `Map` field) exercising round trips through
  `to_map`, `json`, `equal`, `repr`, `args_spec` with `Args.parse`, and
  `columns`/`row`/`from_row`; register `derive_suite` in `test-all.x`.
- `unittest/test-test.x`: the library's own asserts, filter selection, the
  diff output for two multi-line Strings, and `Test.main` exit codes,
  driven in-process by calling `Test.main` with argument Lists.
- Compiler fixture `unittest/compiler-fixtures/derive-pointer-field`
  owning the located `derive:` diagnostic text, and one for the `<args>`
  rejection of a nested field.
- `examples/power/derive.x` (`showcase|run`) printing the chapter's output,
  and `examples/power/tests/stack_test.x` as a probe row; `make examples`
  checks the first.
- `commands/test/tests/run.sh` builds a temporary project with one passing
  and one failing test file and checks the summary and exit status;
  `make commands-check` runs it.
- Book: `docs/src/guide/deriving-records.md` (the excerpt above, field
  coverage, the nested-first rule, the diagnostic) and
  `docs/src/guide/testing.md` (library and command), both in `SUMMARY.md`;
  `docs/src/reference/cli.md` gains a `test` entry under Commands.
  `make doc-generate` after the manifest rows.
- Publication gate: `tools/gate-state.py ensure agent-pr-check`.

## Phases

1. `lib/derive.x` with `<map>`, `<json>`, `<equal>`, `<repr>`; the
   classifier and pointer diagnostic; `test-derive.x`; the fixture; the
   example; the chapter. Expected size: about 220 lines of library, 150 of
   tests, 120 of chapter.
2. `<args>` and `<row>`; their rejections; test additions; the sqlite
   README gains a `$derive(..., <row>)` paragraph showing
   `insert.bind(reading.row())` and `Reading.from_row(row)`. About 90
   lines of library and 60 of tests.
3. `lib/test.x`, `commands/test/`, `test-test.x`, the smoke test, the
   testing chapter, the CLI entry. About 200 lines of library, 180 of
   command, 100 of tests.

Each phase is one coherent publication batch. Phase 3 does not depend on
phases 1 and 2.

## Decisions for Gary

1. `<row>` lives in `lib/derive.x` and generates only `List` values, so
   the core never names `Prepared`. The task suggested placing the SQL
   target in `packages/sqlite`; this plan keeps the package untouched
   except for documentation. Confirm or move it.
2. The command ships as `shipped` in the manifest. `external-commands.md`
   says to choose `experimental` unless shipping is already decided; the
   request says shipped, so the plan records that choice.
3. The `$derive` spelling takes Symbol literals (`<map>`). The alternative
   of one macro per kind (`$derive.map(Point)`) was not chosen because the
   combination then repeats the type name and cannot imply `<map>`.

## Plan review

- Established facts relied on: `Type.fields` and `Type.resolve` give field
  names and canonical types; macro bodies get private bindings for the
  names they declare; free names resolve at the expansion site; shipped
  `lib/` meta helpers are linked into the compiler by the generator;
  `(unit-init)` runs before `main`. No consumer rechecks these.
- Reuse: `Json.parse`, `Var.json`, `Args.parse`, `Var.equal`,
  `String.equal`, `Diff.unified`, `Process`, `Compiler.driver_executable`,
  and the `run` build path are reused as they are. New lasting mechanisms
  are the field classifier, the per-kind piece helpers, the test registry
  with its runner, and the discovery loop; each is the smallest owner of a
  behavior that nothing else supplies.
- Idiom: generated methods are ordinary dotted methods written by a direct
  macro body; helpers return quotations; the runner is a program that
  spawns the driver like `package` does. No origin tracking, no second
  validator, no central test list.
- Validators and diagnostics: the pointer-field diagnostic protects
  against generating a `Map` entry from an address that `Var` cannot
  carry; the `<args>` and `<row>` field rejections protect against a spec
  or row that the consumer cannot read back. Negative fixtures: the two
  compiler fixtures above and the failing test file in the smoke test.
  The `from_map` missing-key raise is public behavior, not a validator.

## Last step

Before publication validation, review the completed authored diff for the
same facts: delete any check that repeats what `Type.fields` or the macro
hygiene already guarantees, fold helpers that one quotation can express,
confirm every generated signature appears in the chapter, and fix what the
review finds before running the gate.
