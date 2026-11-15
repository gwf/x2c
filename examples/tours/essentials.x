/*  essentials.x -- the ideas behind language.x, with fewer details.

    Run: x2c run examples/tours/essentials.x
    Read in order; main runs the sections. Each result exposes a distinction.
*/

/* 1. Dynamic values cross typed boundaries; native types still matter.
   is tests an exact tag. Conversion can succeed without that tag matching. */
static void values(void) {
  Var value = 42;
  double converted = value;
  printf("1. values: int tag %d, double tag %d, converted %.1f\n",
         value is int, value is double, converted);
  Var wide = 42L;
  printf("   numeric equality %d, identity %d\n", value == wide, value === wide);
}

/* 2. Immutable values and mutable objects have different copying rules.
   Canonical Strings and Lists share equal structure. An Array copy here is
   another handle to the same object; mutation is visible through both. */
static void sharing(void) {
  List tail = %(2 3), whole = %(1 @tail);
  Array numbers = [2, 3], same = numbers;
  same[0] = 9;
  printf("2. sharing: tail %d; array %s\n",
         whole.cdr() === tail, numbers.repr());
  String greeting = "hello" + " world", expected = "hello world";
  printf("   canonical text %d\n", greeting === expected);
  Map counts = {zero: 0};
  Var found;
  int present = counts.try_get(<zero>, found);
  printf("   zero present %d, value %s; missing %d\n",
         present, found, <missing> in counts);
}

/* 3. Quoted names are data, not variable reads.
   $ inserts one value; @ splices elements. Bare Map keys name Atoms. */
static void quoting(void) {
  int n = 2;
  List pair = $(n, n + 1);
  printf("3. quoting: %s versus %s\n", %(n).repr(), $(n).repr());
  printf("   nested %s; spliced %s\n", %($pair).repr(), %(@pair).repr());
  String key = "answer";
  Map named = {key: n}, evaluated = ${key: n};
  printf("   keys %s versus %s\n",
         named.keys().list().repr(), evaluated.keys().list().repr());
}

/* 4. Classes choose representations, not an object hierarchy.
   A record copies its fields. A pointer class copies its handle.
   Reference methods borrow the original record; no & is needed at the call. */
class Point { int x; int y; };
class Node { int value; } *;
static void Point.move(Point &p, int dx, int dy) { p.x += dx; p.y += dy; }

static void classes(void) {
  Point point = Point.new(2, 3), copy = point;
  point.move(1, 1);
  Node node = auto Node.new(7);
  Node same = node;
  same.value++;
  printf("4. classes: point %d,%d; copy %d,%d; shared node %d\n",
         point.x, point.y, copy.x, copy.y, node.value);
  // A record containing an Array would copy that handle, not its contents.
}

/* 5. Protocol adoption gives ordinary types shared operations.
   Set reuses Map storage. These methods make + a union, not arithmetic. */
typedef Map Set;
static Set Set.add(Set a, Set b) => a.copy().merge(b);
protocol Map(T) { T T.add(T, T); }
protocol Map(Set);

static void operators(void) {
  Set a = {apple: 1, pear: 1}, b = {pear: 1, bread: 1};
  Set combined = a + b;
  printf("5. operators: union %s; original size %d\n",
         combined.keys().list().sort().repr(), a.len());
}

/* 6. A pattern states the structure you need and names its parts.
   Typed captures test tags rather than converting; a double does not match
   ?(int n). Templates then build a result without manual List plumbing. */
static void patterns(void) {
  List command = %(move (3 4) fast quiet);
  match (command) {
    case %(move (?(int x) ?(int y)) *flags):
      printf("6. patterns: %s\n", %(at $x $y @flags).repr());
  }
  List real = %(move (3.0 4.0));
  printf("   doubles match int pattern %d\n",
         real ~= %(move (?(int x) ?(int y))));
}

/* 7. Copying a reference does not keep its owner alive.
   auto regions free allocations; initializer auto cleans an acquired value.
   Neither is garbage collection. A closure also copies handles, not objects. */
static void lifetime(void) {
  Scope saved = auto Scope.new();
  Array kept;
  auto {
    Array temporary = [1, 2];
    temporary.move_to(&saved);
    kept = temporary;
  }
  int count = 3;
  Func snapshot = %!() => count;
  Func shared = %!(int n) using &count => count += n;
  count = 10;
  Var before = snapshot(), after = shared(2);
  printf("7. lifetime: retained %s; snapshot %s; shared %s\n",
         kept.repr(), before, after);
  // alias substitutes an expression each time; with saves and restores storage.
  alias kept[0] as first;
  first += 4;
  with (count = 99) { printf("   temporary %d; alias %s\n", count, first); }
  try {
    defer puts("   cleanup before catch");
    raise %(bad-arg (operation "tour"));
  }
  catch %(bad-arg *): printf("   caught; restored %d\n", count);
}

/* 8. The same language computes values and constructs source at compile time.
   meta enables compilation-time calls; $ requests one. Macros capture syntax.
   Declared macro locals are private; free names normally come from the caller. */
meta static int cube(int n) => n * n * n;
macro Decorator $twice(Stmt $body) {
  { for (int repeat = 0; repeat < 2; repeat++) $body }
}
keyword twice $twice;

static void compile_time(void) {
  int n = 3, total = 0;
  twice { total += cube(n); }
  printf("8. compile time: cube %d; runtime total %d\n", $cube(3), total);
  // Lists can also be executable data. Lisp evaluates them at runtime.
  List expression = %(+ 2 3);
  Lisp lisp = auto Lisp.new();
  printf("   Lisp %s; native %d\n", lisp.eval(expression), 2 + 3);
}

/* 9. Threads share references; joining does not transfer their ownership.
   The parent owns counts. Only the consumer writes it, and main reads after
   both workers finish. Immutable text crosses the channel without copying. */
static void workers(void) {
  Channel lines = auto Channel.new(<string>, 2);
  Map counts = {};
  Thread.run([
    %!() => {
      defer lines.close();
      foreach (String line in %("tea and cake" "more cake")) lines.send(line);
    },
    %!() => {
      foreach (String line in lines)
        foreach (String word in line.words()) counts[word] += 1;
    }
  ]);
  printf("9. threads: cake %s, tea %s\n", counts["cake"], counts["tea"]);
}

int main(void) {
  auto {
    values();
    sharing();
    quoting();
    classes();
    operators();
    patterns();
    lifetime();
    compile_time();
    workers();
  }
  return 0;
}
