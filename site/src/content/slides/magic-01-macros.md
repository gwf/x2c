---
slug: macros
section: magic
home: true
order: 2
tab: templates
title: The rewrite stuff.
---

```x2c
~#include <derive.x>
~#include <assert.h>

// One template generates both directions of JSON conversion.
macro Unit $json.record(Type $type, Expr $read) {
  using $value, $text;
  String $type.json($type $value) => ((Var) $value.to_map()).json();
  $type $type.from_json(String $text) =>
    $read(Json.parse($text).map());
}

// Apply the template to a type that already converts to and from Maps.
class Point { int x, y; };
$derive(Point, <map>);
$json.record(Point, Point.from_map);

~int main(void) {
  Point start = Point.new(3, 4);
  String text = start.json();
  Point copy = Point.from_json(text);
  printf("%s\nequal: %d\n", copy.repr(), start == copy);
~  assert(start == copy);
~  return 0;
~}
```

A macro template receives syntax and produces declarations. Supply a type and its Map reader to generate a pair of ordinary functions. This example adapts the JSON conversion template used by [`$derive`](https://github.com/gwf/x2c/blob/main/lib/derive.x). `using` gives the generated parameter names fresh private identities.
