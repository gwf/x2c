/*  derive.x -- record mapping, representation, and nested equality */
#include <derive.x>

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
  Person p = { 42, "Ada", 1.5, { 3, 4 }, ["x", 2] };
  Map m = p.to_map();
  printf("%s\n", m.repr());
  Person q = Person.from_map(m);
  printf("%s\n", q.repr().str());
  printf("equal %d\n", p.equal(q));
  q.home.y = 9;
  printf("equal %d %s\n", p.equal(q), q.repr().str());
  return 0;
}
