#include <assert.h>
#include <derive.x>

typedef struct Point { int x, y; } Point;
typedef struct Person { String name; int age; Point home; Array tags; } Person;

// Ask for the mappings you want; the declared fields supply the rest.
$derive(Point, <map>, <equal>, <repr>);
$derive(Person, <json>, <equal>, <repr>);

int main(void) {
  Person ada = { "Ada", 36, { 3, 4 }, ["math", "engines"] };

  // A struct becomes JSON and comes back as the same struct.
  String text = ada.json();
  Person copy = Person.from_json(text);
  assert(ada.equal(copy));
  puts(text);

  // Representation and nested equality follow the declared fields.
  copy.home.y = 9;
  printf("%d %s\n", ada.equal(copy), copy.repr());
  return 0;
}
