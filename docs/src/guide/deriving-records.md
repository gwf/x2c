# Deriving record mappings

Include `derive.x` to generate conversions and operations from a struct's
fields. `$derive` uses the declared field order and writes ordinary public
methods in the unit that invokes the macro.

```x2c
#include "derive.x"

typedef struct Point { int x, y; } Point;
typedef struct Person {
  int age;
  String name;
  double score;
  Point home;
  Array tags;
} Person;

$derive(Point, <map>, <equal>, <repr>);
$derive(Person, <json>, <equal>, <repr>);

int main(void) {
  Person person = { 42, "Ada", 1.5, { 3, 4 }, ["x", 2] };
  printf("%s\n", person.to_map().repr());
  Person copy = Person.from_json(person.json());
  printf("%s\n", copy.repr());
  printf("equal %d\n", person.equal(copy));
  copy.home.y = 9;
  printf("equal %d %s\n", person.equal(copy), copy.repr());
  return 0;
}
```

```text
{ "home": { "x": 3, "y": 4 }, "name": "Ada", "tags": [ "x", 2 ], "age": 42, "score": 1.5 }
Person{ age: 42, name: "Ada", score: 1.5, home: Point{ x: 3, y: 4 }, tags: [ "x", 2 ] }
equal 1
equal 0 Person{ age: 42, name: "Ada", score: 1.5, home: Point{ x: 3, y: 9 }, tags: [ "x", 2 ] }
```

Each requested kind is a Symbol literal. `<json>`, `<args>`, and `<row>`
also generate `<map>`, so the caller does not need to repeat it.
Request each kind once per type.

| Kind | Generated methods |
| --- | --- |
| `<map>` | `Map Type.to_map(Type value)`, `Type Type.from_map(Map map)` |
| `<json>` | `String Type.json(Type value)`, `Type Type.from_json(String text)` |
| `<equal>` | `int Type.equal(Type a, Type b)` |
| `<repr>` | `String Type.repr(Type value)` |
| `<args>` | `List Type.args_spec(void)`, `Type Type.from_args(List args)` |
| `<row>` | `List Type.columns(void)`, `List Type.row(Type value)`, `Type Type.from_row(List row)` |

## Maps, JSON, and equality

`to_map` writes each field under its name. A nested struct becomes a nested
Map. `from_map` reads every field, raising `<bad-arg>` with
`(operation "from_map") (field NAME) (reason "missing")` for an absent key.
Wrong value types raise the existing conversion's `<no-convert>` error.
Extra Map keys are ignored.

`json` writes the Map with `Var.json`; `from_json` reads an object with
`Json.parse` and passes its Map to `from_map`. JSON writes Symbol fields as Strings and List fields as arrays. Parsing
returns Strings and Arrays, so records with Symbol or List fields do not
round-trip through these JSON methods. Use the Map methods to preserve
those field types.

`equal` compares numbers and Symbols with `==`, Strings with `String.equal`,
and Array, List, and Map fields with `Var.equal`. A nested struct uses its
own `equal`. `repr` writes the type name, field names, and field values in
declaration order. Nested structs use their own `repr`.

Supported fields are numeric scalars, enums, String, Symbol, Array, List,
Map, and nested structs. Derive a nested struct earlier in the same unit
with the methods its containing record uses. The generated `from_map`
calls the nested method's ordinary flat spelling, such as `Point_from_map`.
A missing nested method receives the ordinary compiler diagnostic.

Pointer fields, including `char *`, fail at the invocation. For example,
`typedef struct Bad { int *raw; } Bad;` followed by `$derive(Bad, <map>);`
reports `derive: field 'raw' of Bad has pointer type (* int)`.

## Program arguments

Argument fields must be numeric scalars, enums, String, or Symbol.
Every field has a required `--field` option and a `(value "FIELD")`
placeholder. Array, List, Map, and nested struct fields are rejected.

```x2c
#include "derive.x"
typedef struct Options { int count; String name; Symbol mode; } Options;
$derive(Options, <args>);
~int main(void) {
Options options = Options.from_args(
  %("--count" "3" "--name" "sample" "--mode" "fast"));
printf("%d %s %s\n", options.count, options.name, options.mode.str());
~return 0;
~}
```

```text
3 sample fast
```

`args_spec` returns an ordinary spec accepted by `Args.parse`. That parser
returns String values. `from_args` reads numeric fields as JSON numbers and
Symbol fields with `Symbol.parse`, then calls `from_map`. String fields
retain their original text. Invalid option syntax and missing required
options keep `Args.parse`'s `<bad-arg>` behavior.

## Positional rows

`columns` returns field names; `row` returns field values in the same
order. `from_row` reads those positional values using the same conversions
as `from_map`. Nested structs are rejected for `<row>`.

```x2c
#include "derive.x"
typedef struct Reading { String station; double value; } Reading;
$derive(Reading, <row>);
~int main(void) {
Reading reading = { "north", 1.5 };
printf("%s\n", Reading.columns().repr());
Reading copy = Reading.from_row(reading.row());
printf("%s %.1f\n", copy.station, copy.value);
~return 0;
~}
```

```text
("station" "value")
north 1.5
```

These methods depend only on List, so database packages can consume them
without a dependency from the runtime to a database. For example,
`insert.bind(reading.row())` binds the record's fields to SQLite parameters.
Select columns in declaration order before passing a returned row to
`Reading.from_row`.

## Boxing a record

Derivation does not adopt a protocol. Choose the runtime tag and the
unboxing policy explicitly when a record needs `Var` participation:

```x2c
~#include "derive.x"
~typedef struct Reading { int count; String label; } Reading;
~$derive(Reading, <map>, <equal>, <repr>);
Var Reading.var(Reading value) => Var.new(<reading>, value.to_map());
Reading Var.reading(Var value) => Reading.from_map((Map) value.pointer());
protocol Var(Reading);
~int main(void) {
~Reading value = { 3, "ok" };
~Var boxed = value;
~Reading copy = boxed;
~return value.equal(copy) ? 0 : 1;
~}
```

This policy boxes a new Map snapshot and reads that Map when unboxing.
The [protocol chapter](protocols.md) describes descriptor behavior and
alternative representations.
