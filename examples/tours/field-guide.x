/* x2c in small steps for someone who already knows C. */

#include <assert.h>
#include "typed-array.x"
#include "typed-map.x"
#include "typed-list.x"

int main(void) {
  $scope() {
    /* 1. Keep using C types and calls. */
    int count = 3;
    printf("count: %d\n", count);

    /* 2. String adds values, concatenation, and interpolation. */
    String first = "Ada", last = "Lovelace";
    String name = first + " " + last;
    printf("name: %s\n", name);
    puts(%"Hello, $first! You have $count messages.");

    /* 3. Var holds a value whose type can change at runtime. */
    Var answer = 42;
    answer += 1;
    printf("answer: %s\n", answer);
    answer = "forty-three";
    printf("answer now: %s\n", answer);

    /* 4. Array is a growable, mutable sequence. */
    Array numbers = [10, 20];
    numbers.push(30);
    numbers[1] = 25;
    printf("array: %s; item 1: %s\n", numbers.repr(), numbers[1]);

    /* 5. Map looks up values by key, including keys not present. */
    Map scores = {"Ada": 10, "Lin": 20};
    scores["Ada"] += 5;
    printf("Ada: %s; Grace: %s\n", scores["Ada"],
           scores.getdefault("Grace", 0));
    Var found;
    printf("Grace is present: %s\n",
           scores.try_get("Grace", &found) ? "yes" : "no");

    /* 6. List is immutable: adding a head shares the original tail. */
    List steps = %(write compile run);
    List with_plan = cons(<plan>, steps);
    assert(with_plan.cdr() == steps);
    printf("list: %s; original: %s\n", with_plan.str(), steps.str());

    /* 7. A Symbol is an interned name; SymbolSet is a fixed vocabulary. */
    SymbolSet phases = %<<write compile run>>;
    Symbol phase = <compile>;
    printf("phase %s: member %d, index %d\n", phase.str(),
           phases.contains(phase), phases.index(phase));

    /* 8. Typed collections keep concrete values at native widths. */
    ArrayInt samples = [2, 4, 6];
    samples[1] += 1;
    MapStringInt visits = {"Ada": 1};
    visits["Ada"] += 1;
    ListInt limits = %(3 6 9);
    printf("typed: %d, %d, %d\n", samples[1], visits["Ada"],
           limits.last());

    /* 9. A short lambda transforms values without changing the List. */
    int extra = 1;
    List raised = limits.map(%!(value) => value + extra);
    printf("mapped: %s; source: %s\n", raised.str(), limits.str());

    /* 10. Iter processes values lazily. */
    int large = samples.iter().filter(%!(value) => value >= 5).count();
    printf("at least five: %d\n", large);

    /* 11. Match reads a List's shape and binds its parts. */
    List event = %(score "Ada" 15);
    match (event) {
      case %(score ?who ?points):
        printf("match: %s scored %d\n", who, points.int());
    }

    /* 12. Buffer builds text when a loop would make many Strings. */
    Buffer text = $auto(Buffer.new(0));
    foreach (Var number, numbers) {
      if (text.len()) text.write(", ");
      text.write(number.str());
    }
    printf("buffer: %s\n", text.str());

    /* 13. $auto closes an owned File on every exit from this scope. */
    File file = $auto(tmpfile());
    file.puts(%"$name: $count\n");
    file.rewind();
    printf("file: %s", file.string());

    /* 14. The same List shape can be evaluated as Lisp code. */
    Lisp lisp = $auto(Lisp.new());
    printf("Lisp: %s\n", lisp.eval(%(+ 2 3)));
    int compiled = $(+ 2 3);
    printf("compile-time Lisp: %d\n", compiled);
  }
  return 0;
}
