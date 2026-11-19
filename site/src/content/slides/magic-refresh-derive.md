---
slug: derive
section: magic
home: true
order: 1
tab: macros
title: The rewrite stuff.
---

```x2c
~#include <derive.x>
~#include <assert.h>

// Request operations from the declared fields.
class Point { int x, y; };
typedef struct Person { String name; Point home; } Person;
$derive(Point, <map>);
$derive(Person, <json>, <equal>, <repr>);

~int main(void) {
  // Map conversion preserves the nested record.
  Person ada = { "Ada", { 3, 4 } };
  Map fields = ada.to_map();
  Person copy = Person.from_map(fields);
  printf("equal: %d\n%s\n", ada.equal(copy), copy.repr());

  // The same fields also make a JSON round trip.
  String text = ada.json();
  Person restored = Person.from_json(text);
  printf("JSON equal: %d\n", ada.equal(restored));
~  assert(ada.equal(copy) && ada.equal(restored));
~  restored.home.y = 9;
~  assert(!ada.equal(restored));
~  return 0;
~}
```

Use shipped macros without writing a generator. `$derive` works with value classes and ordinary struct typedefs. Point gets equality and representation from its class declaration; Person requests them explicitly. The generated operations preserve nested fields through Map and JSON conversions.
