#include "x2c.x"

static int trace = 0;

static int step(int value) {
  trace = trace * 10 + value;
  return value;
}

/* The entries as `key=value`, sorted so Map order does not matter. */
static String show(Map options) {
  List entries = $();
  foreach (Var (key, value) in options)
    entries = entries.append($(%"$key=$value"));
  return String.join(",", entries.sort());
}

static String opts(int fixed, Map @options) => %"$fixed:$(show(options))";
static int count(Map @options) => options.len();
static String String.tag(String self, Map @options) =>
  %"$self/$(show(options))";

int main(void) {
  Map base = {mode: "r", size: 1};
  String key = "dyn";
  printf("%s\n", opts(1));
  printf("%s\n", opts(2, mode: "w", retries: 3));
  printf("%s\n", opts(3, (key): 7, "s": 8, <sym>: 9));
  printf("%s %s\n", opts(4, @base, size: 2), opts(5, size: 2, @base));
  printf("%s\n", opts(6, a: 1, a: 2));
  int entries = count(x: step(1), @(({ step(2); base; })), y: step(3));
  printf("%d trace %d\n", entries, trace);
  printf("%s\n", "t".tag(k: 1));
  String (*pointer)(int, Map @options) = opts;
  printf("%s\n", pointer(7, z: 0));
  Func dynamic = opts, counted = count;
  printf("%s\n", dynamic(8, q: 1, @base));
  FuncArg odd[1] = {FuncArg.value(<key>)};
  try counted.apply(1, odd);
  catch %(bad-arity *): puts("a key without a value is bad-arity");
  return 0;
}
