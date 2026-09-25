#!/usr/bin/env -S x2c script
/* Small steps from C to x2c.
   Run with: x2c script examples/tours/field-guide.x */

/* C declarations and calls still work. A script needs no main function. */
int count = 3;
printf("count: %d\n", count);

/* String values can be added and interpolated into other text. */
String first = "Ada", last = "Lovelace";
String name = first + " " + last;
printf("name: %s\n", name);
puts(%"Hello, $first! You have $count messages.");

/* Array is a growable sequence. Indexing can also change an item. */
Array numbers = [10, 20];
numbers.push(30);
numbers[1] = 25;
printf("array: %s; second: %s\n", numbers.repr(), numbers[1]);

/* Map associates keys with values. A missing key can have a fallback. */
Map scores = {"Ada": 10, "Lin": 20};
scores["Ada"] += 5;
printf("Ada: %s; Grace: %s\n", scores["Ada"],
       scores.getdefault("Grace", 0));

/* List adds a head without changing or copying its old tail. */
List steps = %("write" "compile" "run");
List with_plan = cons("plan", steps);
printf("list: %s; original: %s\n", with_plan.repr(), steps.repr());
printf("shared tail: %s\n", with_plan.cdr() == steps ? "yes" : "no");

/* Var holds values of different types, including collection elements. */
Var answer = 42;
answer += 1;
printf("answer: %s\n", answer);
answer = "forty-three";
printf("answer now: %s\n", answer);

/* Symbols are names; a SymbolSet is a fixed, ordered vocabulary. */
SymbolSet phases = %<<write compile run>>;
Symbol phase = <compile>;
printf("phase %s: member %d, index %d\n", phase.str(),
       phases.contains(phase), phases.index(phase));

/* A short lambda transforms a List without changing the source. */
List small = %(1 2 3);
List doubled = small.map(%!(value) => value * 2);
printf("doubled: %s; original: %s\n", doubled.str(), small.str());

/* Match picks apart a structured List by its shape. */
List event = %(score "Ada" 15);
match (event) {
  case %(score ?who ?points):
    printf("match: %s scored %d\n", who, points.int());
}
