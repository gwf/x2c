/*  language.x -- a language walkthrough, from values to generated code.

    Run: x2c run examples/tours/language.x
    Read in order; main at the end runs the numbered sections.
    The book's Language guide explains the details omitted here.
*/
#include "meta.x"

/* 1. Values and types
   Var carries a runtime tag. Typed destinations request conversions;
   ordinary int arithmetic remains native C arithmetic. */
static void values(void) {
  Var value = 42;
  value += 1;
  int count = value;
  double half = count / 2.0;
  printf("1. values: %s, native %d, half %.1f\n", value, count, half);
  value = "ready";
  printf("   now %s, String tag %d\n", value, value is String);
}

/* 2. Names and text
   Symbols encode short names. Atoms also represent longer exact names.
   Strings are immutable, canonical text; + and slices produce values. */
static void text(void) {
  Symbol phase = <ready>;
  Atom name = %(a-name-too-long-for-a-symbol).car();
  SymbolSet phases = %<ready running done>;
  String greeting = "hello" + " world", expected = "hello world";
  puts(%"2. text: $greeting; $(greeting[0:5]); $phase");
  printf("   %s; phase index %d\n", name, phases.index(phase));
  printf("   equal %d, identical %d\n",
         greeting == expected, greeting === expected);
}

/* 3. Collections and literals
   Lists are immutable and share tails. Arrays and Maps are mutable;
   copying a handle shares its object. Percent literals quote names as data. */
static void collections(void) {
  int n = 2;
  List quoted = %(n $n $(n + 1));
  List evaluated = $(n, n + 1), extended = %(1 @evaluated);
  Array numbers = [1, n, n + 1], shared = numbers;
  shared[0] = 9;
  String key = "answer";
  Map named = {key: n}, computed = ${key: n};
  printf("3. lists: %s; %s; %s\n",
         quoted.repr(), evaluated.repr(), extended.repr());
  printf("   array %s; last %s; slice %s\n",
         numbers.repr(), numbers[-1], numbers[1:].repr());
  printf("   map keys: %s / %s; member %d\n",
         named.keys().list().repr(), computed.keys().list().repr(),
         key in computed);
  printf("   shared tail %d; shared object %d\n",
         extended.cdr() === evaluated, numbers === shared);
  // Quoted Array/Map contents follow the same data-reading rule.
  Array tags = %[ready, done];
  Map settings = %{mode: fast};
  printf("   quoted: %s %s\n", tags.repr(), settings[<mode>]);
}

/* 4. Iteration and absence
   foreach converts each item to the declared type. try_get reports presence
   separately from its output: a stored zero is still a present value. */
static void iteration(void) {
  List numbers = %(1 2 3 4);
  int total = 0;
  foreach (int n in numbers) {
    if (n == 2) continue;
    total += n;
  }
  (int first, String label) = %(7 "seven");
  Map counts = {zero: 0};
  Var found;
  int present = counts.try_get(<zero>, found);
  printf("4. iteration: sum %d; unpacked %d %s\n", total, first, label);
  printf("   zero present %d, value %s; absent %d\n",
         present, found, <missing> in counts);
  // False does not mean absent: empty containers and numeric zero are false.
  Array empty = [];
  printf("   empty truth %d; null differs from void %d\n",
         empty ? 1 : 0, (Var) NULL !== void);
}

/* 5. Functions and closures
   References borrow caller storage; call without &. Rest parameters collect
   arguments into a List or Map. @ explicitly splices arguments. */
static int square(int n) => n * n;
static void increment(int &n) => n++;
static List collect(List @items) => items;
static String describe(String name, Map @options) =>
  %"$name: $(options.getdefault(<count>, 1))";

static void functions(void) {
  int count = 3;
  increment(count);
  List pair = %(2 3);
  printf("5. functions: %d; %s; %s\n",
         square(count), collect(1, @pair).repr(),
         describe("items", count: count));
  Func snapshot = %!() => count;
  Func update = %!(int n) using &count => count += n;
  count = 10;
  Var old = snapshot(), next = update(2);
  printf("   captured %s; shared %s; local %d\n", old, next, count);
  List doubled = pair.map(%!(int n) => n * 2);
  Var total = pair.iter().map(square).foldl(0, %!(int a, int b) => a + b);
  printf("   mapped %s; lazy squares total %s\n", doubled.repr(), total);
}

/* 6. Types and methods
   A method is a type-qualified function. A reference receiver updates the
   original record. delegate forwards unresolved methods through a field. */
typedef struct Counter { int value; } Counter;
static void Counter.add(Counter &c, int amount) => c.value += amount;
static int Counter.read(Counter c) => c.value;
typedef struct Meter { delegate Counter counter; } Meter;
typedef List Trail;
static Self Trail.record(Self trail, Var item) => cons(item, trail);

static void methods(void) {
  Counter counter = {2};
  counter.add(3);
  Counter copy = counter;
  copy.add(1);
  Meter meter = {counter};
  Trail trail = %(2);
  trail = trail.record(3).record(4);
  printf("6. methods: original %d, copy %d, delegated %d\n",
         counter.read(), copy.read(), meter.read());
  printf("   typedef keeps its methods: %s\n", trail.repr());
}

/* 7. Classes
   class generates operations for a chosen C representation. Point is a
   record value; Node is a pointer. Record copying is shallow, not recursive. */
class Point { int x; int y; };
class Node { int value; } *;
static void Point.move(Point &p, int dx, int dy) { p.x += dx; p.y += dy; }

static void classes(void) {
  Point point = Point.new(2, 3), copy = point;
  point.move(1, 1);
  Var boxed = point; // Boxing a record copies it into owned storage.
  Map labels = {};
  labels[boxed] = "here";
  printf("7. classes: moved %d,%d; copy %d,%d; equal key %s\n",
         point.x, point.y, copy.x, copy.y, labels[Point.new(3, 4)]);
  Node node = auto Node.new(7);
  Node same = node;
  same.value++;
  printf("   pointer copies share: %d\n", node.value);
}

/* 8. Protocols and operators
   A typedef can reuse storage while defining new operations. Explicit
   adoption connects those methods to a protocol; names alone do not. */
typedef Map Set;
static Set Set.new(List keys) {
  Set set = {};
  foreach (Var key in keys) set[key] = 1;
  return set;
}
static Set Set.add(Set a, Set b) => a.copy().merge(b);
static Set Set.mul(Set a, Set b) =>
  Set.new(a.keys().filter(%!(Var key) => key in b));
protocol Map(T) { T T.add(T, T); T T.mul(T, T); }
protocol Map(Set);

static void operators(void) {
  Set a = Set.new(%(apple pear)), b = Set.new(%(pear bread));
  Set combined = a + b, common = a * b;
  // Map traversal has no promised order; sort before presenting keys.
  printf("8. operators: union %s; intersection %s\n",
         combined.keys().list().sort().repr(),
         common.keys().list().sort().repr());
}

/* 9. Patterns and templates
   Match arms try in order without fallthrough. Typed captures test tags,
   not convertibility. A rest capture is a List; $ inserts and @ splices. */
static List simplify(List expression) {
  match (expression) {
    case %(add ?value 0): return %(value $value);
    case %(add ?(int a) ?(int b)): return %(value $(a + b));
    default: return expression;
  }
}

static void patterns(void) {
  List command = %(move (3 4) fast quiet);
  match (command) {
    case %(move (?(int x) ?(int y)) *flags) if (x > 0):
      printf("9. patterns: %s\n", %(at $x $y @flags).repr());
    default: puts("9. patterns: no move");
  }
  List result = simplify(%(add 2 3));
  if (result ~= %(value ?(int n))) printf("   simplified %d\n", n);
}

/* 10. Lifetime and errors
   A region frees mutable allocations together. Canonical text belongs to a
   pool, normally lasting until shutdown. Containers do not adopt references. */
static String make_label(void) {
  auto {
    Buffer out = Buffer.new();
    out.write("ready").write("!");
    return out; // The String conversion interns text before the region ends.
  }
  return NULL;
}

static void lifetime(void) {
  puts(%"10. lifetime: $(make_label())");
  Scope saved = auto Scope.new();
  Array kept;
  auto {
    Array temporary = [1, 2];
    temporary.move_to(&saved); // Preserve the container beyond this region.
    kept = temporary;
  }
  printf("   retained %s\n", kept.repr());
  int level = 1;
  with (level = 9) { printf("   temporary %d\n", level); }
  alias kept[0] as first;
  first += 4; // An alias substitutes its expression on each use.
  printf("   restored %d; aliased %s\n", level, kept[0]);
  try {
    defer puts("   cleanup before catch");
    raise %(bad-arg (operation "tour"));
  }
  catch %(bad-arg *details): puts("   caught bad-arg");
  finally puts("   finally");
}

/* 11. Compile-time code
   An ordinary call runs now; $ calls a meta function during translation.
   A macro receives syntax. Its declared locals are private per expansion;
   free names resolve at the call site unless kept with using. */
meta static int cube(int n) => n * n * n;
static int factor = 2;
macro Expression $scaled(Expr $n) => $n * factor;
macro Expression $fixed(Expr $n) using factor => $n * factor;

macro Decorator $twice(Stmt $body) {
  { for (int repeat = 0; repeat < 2; repeat++) $body }
}
keyword twice $twice;

// A quotation writes generated code in source form; the hole inserts syntax.
meta static List report_code(List value) =>
  $!{ printf("   generated report: %s\n", (Var) $value); };
macro Stmt $report(Expr $value) => $report_code($value);

static void compile_time(void) {
  int n = 3;
  printf("11. meta: runtime %d; compile time %d\n", cube(n), $cube(3));
  int factor = 10;
  printf("   caller name %d; kept name %d\n", $scaled(3), $fixed(3));
  int total = 0;
  twice { total++; }
  $report(total);
  // Lisp is a runtime library, not the implementation of meta functions.
  Lisp lisp = auto Lisp.new();
  printf("   runtime Lisp: %s\n", lisp.eval(%(+ 2 3)));
}

/* 12. Threads and channels
   One worker writes counts; main reads only after Thread.run joins both.
   The parent owns the Map and Channel throughout. Strings are canonical.
   Channel capacity bounds queued messages, not the canonical-value pool. */
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
  printf("12. threads: cake %s, tea %s\n", counts["cake"], counts["tea"]);
}

int main(void) {
  auto {
    values();
    text();
    collections();
    iteration();
    functions();
    methods();
    classes();
    operators();
    patterns();
    lifetime();
    compile_time();
    workers();
  }
  return 0;
}
