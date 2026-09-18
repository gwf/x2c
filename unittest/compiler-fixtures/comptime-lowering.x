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

/* --- control flow: break, continue, do/while, switch --------------------- */

/* A loop's exit is a function over its live locals, so a `break` reaches it
   with a call rather than a copy of the rest of the block. */
$comptime()
int ct_break(int n) {
  int s = 0;
  int i = 0;
  while (1) {
    if (i >= n) break;
    s = s + i;
    i = i + 1;
  }
  return s;
}

/* A `for` carries its step as the continuation the body and every
   `continue` reach, so nothing can skip it. */
$comptime()
int ct_continue(int n) {
  int s = 0;
  for (int i = 0; i < n; i++) {
    if (i % 2) continue;
    s = s + i;
  }
  return s;
}

/* `do` runs its body before the first test, so this body runs once even
   where the test is false from the start. */
$comptime()
int ct_do(int n) {
  int s = 0;
  do {
    s = s + n;
    n = n - 1;
  }
  while (n > 0);
  return s;
}

$comptime()
int ct_do_once(int n) {
  int s = 0;
  do { s = s + 1; }
  while (n > 100);
  return s;
}

/* A `continue` in a `do` reaches the test the same way the body's end does,
   because the test is the loop's step. */
$comptime()
int ct_do_continue(int n) {
  int s = 0;
  do {
    n = n - 1;
    if (n % 2) continue;
    s = s + n;
  }
  while (n > 0);
  return s;
}

/* A `switch` is a `cond` chain over its subject. An arm ends in `break` or
   `return`; the last needs neither, since nothing follows it to fall into. */
$comptime()
int ct_switch(int n) {
  int s = 0;
  switch (n) {
    case 1:
      s = 10;
      break;
    case 2: {
      s = 20;
      break;
    }
    case 3:
      return 33;
    default:
      s = 99;
  }
  return s + 1;
}

/* Labels with no statements between them share one arm, and a `switch` with
   no `default` falls out to the rest of the block. */
$comptime()
int ct_switch_shared(int n) {
  switch (n) {
    case 1:
    case 2:
      return 12;
    case 3:
      return 3;
  }
  return 0;
}

/* A subject that cannot be repeated is bound once, and a `Symbol` compares
   the way every other value does. */
$comptime()
String ct_switch_symbol(Var form) {
  switch (Var.tag(form)) {
    case <list>:   return "a list";
    case <symbol>: return "a symbol";
  }
  return "other";
}

/* A `break` inside a `switch` leaves the switch, and a `continue` inside one
   still reaches the loop around it. */
$comptime()
int ct_switch_in_loop(int n) {
  int total = 0;
  for (int i = 0; i < n; i++) {
    switch (i) {
      case 2:
        break;
      case 3:
        continue;
      default:
        total = total + 1;
        break;
    }
    total = total + 1000;
  }
  return total;
}

/* A `break` binds to the loop nearest it. */
$comptime()
int ct_nested_break(int n) {
  int s = 0;
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      if (j > 1) break;
      s = s + 1;
    }
    s = s + 100;
  }
  return s;
}

/* `foreach` is an ordinary `while`, so a `break` leaves it too. */
$comptime()
int ct_break_in_foreach(List xs) {
  int n = 0;
  foreach (Var item, xs) {
    if (Var.equal(item, <stop>)) break;
    n = n + 1;
  }
  return n;
}

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

/* A `foreach` inside a `foreach`. The inner loop declares its output cell
   with no initializer, so the enclosing loop must fill the box it already
   allocated rather than bind a new one. */
$comptime()
List ct_flatten(List rows) {
  Array out = [];
  foreach (Var row, rows) {
    List cells = row;
    foreach (Var cell, cells) out.push(cell);
  }
  return out;
}

/* A character literal is its code. The pattern that selects a C string is
   `(* char)`, and `*` is a sequence binder, so it matches a plain `(char)`
   too; without the spelling test a character lowered to its own text and
   read as a different number on every run. `main` prints each answer beside
   the same function's run-time answer, because agreement between the two is
   what the defect broke. */
$comptime()
int ct_letter(void) => 'A';

$comptime()
int ct_newline(void) => '\n';

$comptime()
int ct_is_dot(String s) => s[0] == '.' ? 1 : 0;

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

/* --- typed captures in match patterns ------------------------------------ */

/* A typed capture is a tag test as well as a binder, so each of these
   answers its fallback when the element has the wrong type. The pair of
   results per function is what proves the test survived folding. */

$comptime()
String ct_typed_string(List form) {
  match (form) {
    case %(call ?(String n)): return n;
  }
  return "none";
}

$comptime()
int ct_typed_int(List form) {
  match (form) {
    case %(call ?(int n)): return n;
  }
  return -1;
}

/* A typed capture inside a sublist folds with the cell around it. */
$comptime()
String ct_typed_nested(List form) {
  match (form) {
    case %(call (arg ?(String n)) ?rest): return n;
  }
  return "none";
}

$comptime()
String ct_typed_mixed(List form) {
  match (form) {
    case %(op ?name ?(String text)): return text;
  }
  return "none";
}

$comptime()
int ct_typed_symbol(List form) {
  match (form) {
    case %(tag ?(Symbol s)): return 1;
  }
  return 0;
}

/* --- `meta`, the second spelling ----------------------------------------- */

/* `meta` marks a function the compiler runs as well as emits. The parser
   recognizes it on the declaration, so it does what `$comptime()` does
   without going through a macro. Both spellings are live; see
   `plans/meta-functions.md`. */
meta int mt_poly(int n) => n * n + 3 * n + 1;

/* The same computation through the decorator. `main` prints all four
   answers, so the two spellings have to agree at compile time and at run
   time or the fixture says so. */
$comptime()
int ct_poly(int n) => n * n + 3 * n + 1;

/* `meta` composes with a storage class rather than replacing one: `static`
   still says what it always said about the emitted function. */
meta static String mt_label(String stem, int n) => %"$stem:$n";

/* Everywhere else `meta` is an ordinary identifier. This is the fixture's
   claim that the word stays contextual: a file-scope name, an assignment
   target, and a struct field. */
List meta = %(a b);

struct MetaHolder { int meta; };

/* --- the program reports what the pass produced -------------------------- */

int main(void) {
  printf("gcd          %d\n", $(ct_gcd 1071 462));
  printf("sum          %d\n", $(ct_sum 100));
  printf("fib          %d\n", $(ct_fib 12));
  printf("mutual       %d %d\n", $(ct_even 10), $(ct_odd 10));
  printf("bits         %d\n", $(ct_bits 7));
  printf("ternary      %d %d\n", $(ct_pick 5), $(ct_pick 2));
  printf("area         %s\n", $(str (ct_area 3.0)));
  printf("break        %d\n", $(ct_break 5));
  printf("continue     %d\n", $(ct_continue 7));
  printf("do           %d %d\n", $(ct_do 4), $(ct_do_once 1));
  printf("do-continue  %d\n", $(ct_do_continue 6));
  printf("switch       %d %d %d %d\n", $(ct_switch 1), $(ct_switch 2),
         $(ct_switch 3), $(ct_switch 9));
  printf("switch-share %d %d %d\n", $(ct_switch_shared 1),
         $(ct_switch_shared 2), $(ct_switch_shared 5));
  printf("switch-sym   %s / %s / %s\n", $(ct_switch_symbol '(a)),
         $(ct_switch_symbol 'a), $(ct_switch_symbol "x"));
  printf("switch-loop  %d\n", $(ct_switch_in_loop 5));
  printf("nested-break %d\n", $(ct_nested_break 3));
  printf("foreach-brk  %d\n", $(ct_break_in_foreach '(a b stop c)));
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
  printf("character    %d %d  %d %d  %d %d\n",
         $(ct_letter), ct_letter(),
         $(ct_newline), ct_newline(),
         $(ct_is_dot "."), ct_is_dot("."));
  printf("flatten      %s\n", $(repr (ct_flatten '((a b) (c) (d e)))));
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
  printf("typed-string %s %s\n",
         $(ct_typed_string '(call "x")), $(ct_typed_string '(call 42)));
  printf("typed-int    %d %d\n",
         $(ct_typed_int '(call 42)), $(ct_typed_int '(call "x")));
  printf("typed-nested %s %s\n",
         $(ct_typed_nested '(call (arg "y") 1)),
         $(ct_typed_nested '(call (arg 3) 1)));
  printf("typed-mixed  %s %s\n",
         $(ct_typed_mixed '(op add "z")), $(ct_typed_mixed '(op add 5)));
  printf("typed-symbol %d %d\n",
         $(ct_typed_symbol '(tag a)), $(ct_typed_symbol '(tag "a")));
  printf("meta-poly    %d %d %d %d\n",
         $(mt_poly 7), mt_poly(7), $(ct_poly 7), ct_poly(7));
  printf("meta-static  %s %s\n",
         $(mt_label "slot" 4), mt_label("slot", 4));
  meta = %(a b c);
  struct MetaHolder holder = { .meta = 3 };
  printf("meta-ident   %d %d\n", meta.len(), holder.meta);
  return 0;
}
