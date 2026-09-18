/*  comptime-lowering.x -- every construct the comptime lowering pass carries

    Each `$comptime()` function is lowered to Lisp by `Compiler.lower_comptime`
    and installed in the macro session. `main` calls each one in expression
    position, so the printed value is what the lowered Lisp produced during
    translation. A construct the pass declines is absent from this fixture
    until the phase that adds it; see
    `plans/comptime-x2c-generalization.md`.
*/

#include "x2c.x"

macro Decorator $comptime(Unit $fn) => { $(x2c.comptime.install $fn)... }

/* Mutual recursion needs the names before the definitions, the way a C
   prototype does. */
$(def ct_odd (lambda (. rest) 0))

/* --- arithmetic and control flow ---------------------------------------- */

$comptime()
int ct_gcd(int a, int b) {
  while (b) {
    int t = a % b;
    a = b;
    b = t;
  }
  return a;
}

$comptime()
int ct_sum(int n) {
  int total = 0;
  for (int i = 1; i <= n; i++) total += i;
  return total;
}

$comptime()
int ct_fib(int n) {
  if (n < 2) return n;
  return ct_fib(n - 1) + ct_fib(n - 2);
}

$comptime()
int ct_even(int n) {
  if (n == 0) return 1;
  return ct_odd(n - 1);
}

$comptime()
int ct_odd(int n) {
  if (n == 0) return 0;
  return ct_even(n - 1);
}

$comptime()
int ct_bits(int n) => (n & 6) | (n << 2);

$comptime()
int ct_pick(int n) => n > 3 ? n * 2 : -n;

$comptime()
double ct_area(double r) => 3.141592653589793 * r * r;

/* --- file-scope state ---------------------------------------------------- */

static int ct_counter;

$comptime()
int ct_next(void) {
  ct_counter = ct_counter + 1;
  return ct_counter;
}

/* --- cells: address-of, deref, and a loop-assigned local ----------------- */

$comptime()
int ct_through_pointer(int a) {
  int x = a;
  int *p = &x;
  *p = *p + 5;
  return x;
}

$comptime()
int ct_count(List xs) {
  int n = 0;
  foreach (Var item, xs) {
    (void) item;
    n = n + 1;
  }
  return n;
}

/* A cast to `void` discards the result, not the work. */
$comptime()
int ct_discard(int n) {
  (void) n;
  (void) ct_next();
  return ct_counter;
}

/* --- collection literals and indexing ------------------------------------ */

/* `[a, b]` is an array literal wherever it appears, so it lowers to an
   `Array`; a `List` destination converts, the way the transform would. */
$comptime()
int ct_array_len(int n) { Array xs = [n, n + 1, n + 2]; return (int) xs.len(); }

$comptime()
int ct_array_grow(int n) {
  Array xs = [];
  xs.push(n);
  xs.push(n);
  return (int) xs.len();
}

/* `Var.tag` answers a `Symbol`, so returning one where a `String` is
   declared needs the conversion the transform would otherwise insert. */
$comptime()
String ct_array_kind(int n) { Array xs = [n]; return Var.tag(xs); }

$comptime()
String ct_list_kind(int n) { List ys = [n]; return Var.tag(ys); }

$comptime()
String ct_to_array_kind(List ys) { Array xs = ys; return Var.tag(xs); }

$comptime()
String ct_to_list_kind(Array xs) { List ys = xs; return Var.tag(ys); }

/* An array literal in an argument position has no destination to read, so
   lowering it as a Lisp List would hand the callee the wrong container. */
$comptime()
int ct_takes_array(Array a) => (int) a.len();

$comptime()
int ct_array_argument(int n) => ct_takes_array([n, n, n]);

/* A bare name left of `:` is a Symbol key, which is x2c's map literal. */
$comptime()
int ct_map_symbol(int v) {
  Map m = { one: v, two: v + 1 };
  return Var.integer(m[<two>]);
}

$comptime()
int ct_map_string(int v) {
  Map m = { "a": v, "b": v + 1 };
  return Var.integer(m["b"]);
}

$comptime()
int ct_map_empty(void) { Map m = {}; return (int) m.len(); }

$comptime()
int ct_map_store(int v) {
  Map m = {};
  m[<k>] = v;
  return Var.integer(m[<k>]);
}

$comptime()
int ct_array_store(int n) {
  Array xs = [n, n];
  xs[1] = n + 5;
  return Var.integer(xs[1]);
}

$comptime()
int ct_index_list(List ys) => Var.integer(ys[1]);

$comptime()
int ct_index_string(String s) => s[1];

/* An absent element has no Lisp value, so it reads as nil rather than
   aborting the session the way a `void` crossing would. */
$comptime()
int ct_index_absent(List ys) => ys[9] ? 1 : 0;

/* A local C array is a cell holding an `Array`, zero-filled to its declared
   size the way C fills one. */
$comptime()
int ct_c_array(int n) {
  int a[4] = { 1, 2, 3, 4 };
  a[0] = a[3] + n;
  return a[0];
}

$comptime()
int ct_c_array_padded(void) { int a[4] = { 7 }; return a[0] + a[3]; }

$comptime()
int ct_c_array_bare(int n) {
  int a[3];
  a[1] = n;
  return a[1] + a[2];
}

/* An `Array` accumulated with `push` and returned where a `List` is
   declared: the return converts, the way a declaration does. */
$comptime()
List ct_accumulate(List items) {
  Array out = [];
  foreach (Var item, items) out.push(%($item $item));
  return out;
}

/* One `Map` lookup in place of a chain of string comparisons. */
$comptime()
Var ct_table(String name) {
  Map table = { "sin": %(cos), "cos": %(neg sin) };
  return table[name];
}

/* An uninitialized local keeps its own type's zero. */
$comptime()
int ct_scalar_zero(void) { int z; return z; }

/* --- destructuring and iteration over every container -------------------- */

/* `Var (a, b) = pair` reads each name out of the source by position, which
   is what the transform does with the same declaration. */
$comptime()
int ct_pair(List pair) {
  Var (a, b) = pair;
  return Var.integer(a) * 10 + Var.integer(b);
}

/* The same declaration with a type on each name. Neither spelling lets the
   type decide anything, because a Lisp value already is a `Var`. */
$comptime()
int ct_pair_typed(List pair) {
  (Var a, Var b) = pair;
  return Var.integer(a) * 10 + Var.integer(b);
}

/* A source that is not duplicable is held in one binding, so the call
   below runs once however many names read it. */
$comptime()
int ct_pair_held(List xs) {
  Var (a, b) = xs.cdr();
  return Var.integer(a) * 10 + Var.integer(b);
}

/* Fewer values than names is the absent element again: nil, not a `void`
   crossing that would end the session. */
$comptime()
int ct_pair_short(List one) {
  Var (a, b) = one;
  return Var.integer(a) + (b ? 100 : 0);
}

/* An `Array` source converts to a `List` first, the way the transform
   converts it. */
$comptime()
int ct_pair_array(Array xs) {
  Var (a, b) = xs;
  return Var.integer(a) * 10 + Var.integer(b);
}

/* `foreach` over an `Array` walks a counting cursor; over a `Map` the one
   name is the value, and two names are the key and the value. */
$comptime()
int ct_walk_array(Array xs) {
  int total = 0;
  foreach (Var x, xs) total = total + Var.integer(x);
  return total;
}

$comptime()
int ct_walk_map(Map m) {
  int total = 0;
  foreach (Var v, m) total = total + Var.integer(v);
  return total;
}

/* A sum, because a `Map` walks in bucket order and this has to report the
   same number whatever that order is. */
$comptime()
int ct_walk_map_pairs(Map m) {
  int total = 0;
  foreach (Var (k, v), m)
    total = total + Var.integer(k) * 100 + Var.integer(v);
  return total;
}

/* An empty container ends the walk on its first call. */
$comptime()
int ct_walk_empty(Map m, Array xs) {
  int n = 0;
  foreach (Var v, m) { (void) v; n = n + 1; }
  foreach (Var x, xs) { (void) x; n = n + 1; }
  return n;
}

/* --- value types --------------------------------------------------------- */

$comptime()
int ct_is_list(Var form) => form.is(<list>);

$comptime()
Var ct_head(List items) => items.car();

$comptime()
int ct_len(List items) => items.len();

$comptime()
String ct_suffix(String name) => name + "_dot";

$comptime()
int ct_same(List a, List b) => a.equal(b);

$comptime()
String ct_label(String stem, int n) => %"$stem-${n}";

$comptime()
List ct_doubled(List items) => items.map(%!(Var part) => %($part $part));

/* --- match and literal templates ----------------------------------------- */

$comptime()
List ct_rewrite(List form) {
  match (form) {
    case %(add ?a ?b): return %(sum $a $b);
    case %(neg ?a): {
      List zero = %(0);
      return %(sub @zero $a);
    }
  }
  return form;
}

$comptime()
Var ct_binding_name(List form) {
  match (form) {
    case %(expr ? (ident (binding ? ?name))): return name;
  }
  return void;
}

/* --- the program reports what the pass produced -------------------------- */

int main(void) {
  printf("gcd          %d\n", $(ct_gcd 1071 462));
  printf("sum          %d\n", $(ct_sum 100));
  printf("fib          %d\n", $(ct_fib 12));
  printf("mutual       %d %d\n", $(ct_even 10), $(ct_odd 10));
  printf("bits         %d\n", $(ct_bits 7));
  printf("ternary      %d %d\n", $(ct_pick 5), $(ct_pick 2));
  printf("area         %s\n", $(str (ct_area 3.0)));
  printf("globals      %d %d\n", $(ct_next), $(ct_next));
  printf("pointer      %d\n", $(ct_through_pointer 7));
  printf("foreach      %d\n", $(ct_count '(a b c d)));
  printf("discard      %d\n", $(ct_discard 1));
  printf("array-len    %d\n", $(ct_array_len 1));
  printf("array-grow   %d\n", $(ct_array_grow 1));
  printf("array-kind   %s %s\n", $(ct_array_kind 1), $(ct_list_kind 1));
  printf("convert-kind %s %s\n", $(ct_to_array_kind '(1 2)),
         $(ct_to_list_kind (List.array '(1 2))));
  printf("array-arg    %d\n", $(ct_array_argument 1));
  printf("map-symbol   %d\n", $(ct_map_symbol 5));
  printf("map-string   %d\n", $(ct_map_string 4));
  printf("map-empty    %d\n", $(ct_map_empty));
  printf("map-store    %d\n", $(ct_map_store 9));
  printf("array-store  %d\n", $(ct_array_store 1));
  printf("index-list   %d\n", $(ct_index_list '(7 8 9)));
  printf("index-string %d\n", $(ct_index_string "abc"));
  printf("index-absent %d\n", $(ct_index_absent '(1 2)));
  printf("c-array      %d\n", $(ct_c_array 10));
  printf("c-array-pad  %d\n", $(ct_c_array_padded));
  printf("c-array-bare %d\n", $(ct_c_array_bare 4));
  printf("scalar-zero  %d\n", $(ct_scalar_zero));
  printf("accumulate   %s\n", $(repr (ct_accumulate '(1 2))));
  printf("table        %s %s\n",
         $(repr (ct_table "cos")), $(repr (ct_table "nope")));
  printf("pair         %d\n", $(ct_pair '(3 4)));
  printf("pair-typed   %d\n", $(ct_pair_typed '(3 4)));
  printf("pair-held    %d\n", $(ct_pair_held '(9 3 4)));
  printf("pair-short   %d\n", $(ct_pair_short '(7)));
  printf("pair-array   %d\n", $(ct_pair_array (List.array '(5 6))));
  printf("walk-array   %d\n", $(ct_walk_array (List.array '(4 5 6))));
  printf("walk-map     %d\n", $(ct_walk_map (Map_of '(1 2 3 4))));
  printf("walk-pairs   %d\n", $(ct_walk_map_pairs (Map_of '(1 2 3 4))));
  printf("walk-empty   %d\n", $(ct_walk_empty (Map.new) (List.array '())));
  printf("is-list      %d\n", $(ct_is_list '(a b)));
  printf("head         %s\n", $(str (ct_head '(a b))));
  printf("len          %d\n", $(ct_len '(a b c)));
  printf("suffix       %s\n", $(ct_suffix "t"));
  printf("equal        %d\n", $(ct_same '(double) '(double)));
  printf("interpolate  %s\n", $(ct_label "slot" 4));
  printf("map          %s\n", $(repr (ct_doubled '(1 2))));
  printf("match-add    %s\n", $(repr (ct_rewrite '(add 1 2))));
  printf("match-neg    %s\n", $(repr (ct_rewrite '(neg 7))));
  printf("match-miss   %s\n", $(repr (ct_rewrite '(other 5))));
  printf("binding      %s\n",
         $(str (ct_binding_name '(expr (int) (ident (binding 5 "t"))))));
  return 0;
}
