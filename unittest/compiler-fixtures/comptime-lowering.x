/*  comptime-lowering.x -- every construct the comptime lowering pass carries

    Each `meta` function is lowered to Lisp by `Compiler.lower_comptime`
    and installed in the macro session. `main` calls each one in expression
    position, so the printed value is what the lowered Lisp produced during
    translation. A construct the pass declines is absent from this fixture
    until the phase that adds it; see
    `plans/comptime-x2c-generalization.md`.
*/

#include "x2c.x"

/* Mutual recursion needs the names before the definitions, the way a C
   prototype does. */
$(def ct_odd (lambda (. rest) 0))

/* --- arithmetic and control flow ---------------------------------------- */

meta int ct_gcd(int a, int b) {
  while (b) {
    int t = a % b;
    a = b;
    b = t;
  }
  return a;
}

meta int ct_sum(int n) {
  int total = 0;
  for (int i = 1; i <= n; i++) total += i;
  return total;
}

meta int ct_fib(int n) {
  if (n < 2) return n;
  return ct_fib(n - 1) + ct_fib(n - 2);
}

meta int ct_even(int n) {
  if (n == 0) return 1;
  return ct_odd(n - 1);
}

meta int ct_odd(int n) {
  if (n == 0) return 0;
  return ct_even(n - 1);
}

meta int ct_bits(int n) => (n & 6) | (n << 2);

meta int ct_pick(int n) => n > 3 ? n * 2 : -n;

meta double ct_area(double r) => 3.141592653589793 * r * r;

/* --- control flow: break, continue, do/while, switch --------------------- */

/* A loop's exit is a function over its live locals, so a `break` reaches it
   with a call rather than a copy of the rest of the block. */
meta int ct_break(int n) {
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
meta int ct_continue(int n) {
  int s = 0;
  for (int i = 0; i < n; i++) {
    if (i % 2) continue;
    s = s + i;
  }
  return s;
}

/* `do` runs its body before the first test, so this body runs once even
   where the test is false from the start. */
meta int ct_do(int n) {
  int s = 0;
  do {
    s = s + n;
    n = n - 1;
  }
  while (n > 0);
  return s;
}

meta int ct_do_once(int n) {
  int s = 0;
  do { s = s + 1; }
  while (n > 100);
  return s;
}

/* A `continue` in a `do` reaches the test the same way the body's end does,
   because the test is the loop's step. */
meta int ct_do_continue(int n) {
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
meta int ct_switch(int n) {
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
meta int ct_switch_shared(int n) {
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
meta String ct_switch_symbol(Var form) {
  switch (Var.tag(form)) {
    case <list>:   return "a list";
    case <symbol>: return "a symbol";
  }
  return "other";
}

/* A `break` inside a `switch` leaves the switch, and a `continue` inside one
   still reaches the loop around it. */
meta int ct_switch_in_loop(int n) {
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
meta int ct_nested_break(int n) {
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
meta int ct_break_in_foreach(List xs) {
  int n = 0;
  foreach (Var item, xs) {
    if (Var.equal(item, <stop>)) break;
    n = n + 1;
  }
  return n;
}

/* --- cells: address-of, deref, and a loop-assigned local ----------------- */

meta int ct_through_pointer(int a) {
  int x = a;
  int *p = &x;
  *p = *p + 5;
  return x;
}

meta int ct_count(List xs) {
  int n = 0;
  foreach (Var item, xs) {
    (void) item;
    n = n + 1;
  }
  return n;
}

/* A cast to `void` discards the result, not the work. */
meta int ct_discard(int n) {
  Array values = [n];
  (void) values.push(n + 1);
  return n + values.len();
}

/* --- collection literals and indexing ------------------------------------ */

/* `[a, b]` is an array literal wherever it appears, so it lowers to an
   `Array`; a `List` destination converts, the way the transform would. */
meta int ct_array_len(int n) { Array xs = [n, n + 1, n + 2]; return (int) xs.len(); }

meta int ct_array_grow(int n) {
  Array xs = [];
  xs.push(n);
  xs.push(n);
  return (int) xs.len();
}

/* `Var.tag` answers a `Symbol`, so returning one where a `String` is
   declared needs the conversion the transform would otherwise insert. */
meta String ct_array_kind(int n) { Array xs = [n]; return Var.tag(xs); }

meta String ct_list_kind(int n) { List ys = [n]; return Var.tag(ys); }

meta String ct_to_array_kind(List ys) { Array xs = ys; return Var.tag(xs); }

meta String ct_to_list_kind(Array xs) { List ys = xs; return Var.tag(ys); }

/* An array literal in an argument position has no destination to read, so
   lowering it as a Lisp List would hand the callee the wrong container. */
meta int ct_takes_array(Array a) => (int) a.len();

meta int ct_array_argument(int n) => ct_takes_array([n, n, n]);

/* A bare name left of `:` is a Symbol key, which is x2c's map literal. */
meta int ct_map_symbol(int v) {
  Map m = { one: v, two: v + 1 };
  return Var.integer(m[<two>]);
}

meta int ct_map_string(int v) {
  Map m = { "a": v, "b": v + 1 };
  return Var.integer(m["b"]);
}

meta int ct_map_empty(void) { Map m = {}; return (int) m.len(); }

meta int ct_map_store(int v) {
  Map m = {};
  m[<k>] = v;
  return Var.integer(m[<k>]);
}

meta int ct_array_store(int n) {
  Array xs = [n, n];
  xs[1] = n + 5;
  return Var.integer(xs[1]);
}

meta int ct_index_list(List ys) => Var.integer(ys[1]);

meta int ct_index_string(String s) => s[1];

/* An absent element has no Lisp value, so it reads as nil rather than
   aborting the session the way a `void` crossing would. */
meta int ct_index_absent(List ys) => ys[9] ? 1 : 0;

/* A local C array is a cell holding an `Array`, zero-filled to its declared
   size the way C fills one. */
meta int ct_c_array(int n) {
  int a[4] = { 1, 2, 3, 4 };
  a[0] = a[3] + n;
  return a[0];
}

meta int ct_c_array_padded(void) { int a[4] = { 7 }; return a[0] + a[3]; }

meta int ct_c_array_bare(int n) {
  int a[3];
  a[1] = n;
  return a[1] + a[2];
}

/* An `Array` accumulated with `push` and returned where a `List` is
   declared: the return converts, the way a declaration does. */
meta List ct_accumulate(List items) {
  Array out = [];
  foreach (Var item, items) out.push(%($item $item));
  return out;
}

/* One `Map` lookup in place of a chain of string comparisons. */
meta Var ct_table(String name) {
  Map table = { "sin": %(cos), "cos": %(neg sin) };
  return table[name];
}

/* A `foreach` inside a `foreach`. The inner loop declares its output cell
   with no initializer, so the enclosing loop must fill the box it already
   allocated rather than bind a new one. */
meta List ct_flatten(List rows) {
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
meta int ct_letter(void) => 'A';

meta int ct_newline(void) => '\n';

meta int ct_is_dot(String s) => s[0] == '.' ? 1 : 0;

/* A loop carries only the locals it names. `before` is read inside, `after`
   only past the loop, and the `pad` locals nowhere after their own line, so
   dropping a local that is still needed would decline as an unbound local
   rather than answer wrongly. */
meta int ct_live_set(List xs, int seed) {
  int pad1 = seed + 1;
  int pad2 = pad1 + 1;
  int pad3 = pad2 + 1;
  int before = pad3;
  int after = 100;
  int n = 0;
  foreach (Var v, xs) {
    (void) v;
    n = n + before;
  }
  return n + after;
}

/* An uninitialized local keeps its own type's zero. */
meta int ct_scalar_zero(void) { int z; return z; }

/* --- destructuring and iteration over every container -------------------- */

/* `Var (a, b) = pair` reads each name out of the source by position, which
   is what the transform does with the same declaration. */
meta int ct_pair(List pair) {
  Var (a, b) = pair;
  return Var.integer(a) * 10 + Var.integer(b);
}

/* The same declaration with a type on each name. Neither spelling lets the
   type decide anything, because a Lisp value already is a `Var`. */
meta int ct_pair_typed(List pair) {
  (Var a, Var b) = pair;
  return Var.integer(a) * 10 + Var.integer(b);
}

/* A source that is not duplicable is held in one binding, so the call
   below runs once however many names read it. */
meta int ct_pair_held(List xs) {
  Var (a, b) = xs.cdr();
  return Var.integer(a) * 10 + Var.integer(b);
}

/* Fewer values than names is the absent element again: nil, not a `void`
   crossing that would end the session. */
meta int ct_pair_short(List one) {
  Var (a, b) = one;
  return Var.integer(a) + (b ? 100 : 0);
}

/* An `Array` source converts to a `List` first, the way the transform
   converts it. */
meta int ct_pair_array(Array xs) {
  Var (a, b) = xs;
  return Var.integer(a) * 10 + Var.integer(b);
}

/* `foreach` over an `Array` walks a counting cursor; over a `Map` the one
   name is the value, and two names are the key and the value. */
meta int ct_walk_array(Array xs) {
  int total = 0;
  foreach (Var x, xs) total = total + Var.integer(x);
  return total;
}

meta int ct_walk_map(Map m) {
  int total = 0;
  foreach (Var v, m) total = total + Var.integer(v);
  return total;
}

/* A sum, because a `Map` walks in bucket order and this has to report the
   same number whatever that order is. */
meta int ct_walk_map_pairs(Map m) {
  int total = 0;
  foreach (Var (k, v), m)
    total = total + Var.integer(k) * 100 + Var.integer(v);
  return total;
}

/* An empty container ends the walk on its first call. */
meta int ct_walk_empty(Map m, Array xs) {
  int n = 0;
  foreach (Var v, m) { (void) v; n = n + 1; }
  foreach (Var x, xs) { (void) x; n = n + 1; }
  return n;
}

/* --- value types --------------------------------------------------------- */

meta int ct_is_list(Var form) => form.is(<list>);

meta Var ct_head(List items) => items.car();

meta int ct_len(List items) => items.len();

meta String ct_suffix(String name) => name + "_dot";

meta int ct_same(List a, List b) => a.equal(b);

meta String ct_label(String stem, int n) => %"$stem-${n}";

meta List ct_doubled(List items) => items.map(%!(Var part) => %($part $part));

/* --- match and literal templates ----------------------------------------- */

meta List ct_rewrite(List form) {
  match (form) {
    case %(add ?a ?b): return %(sum $a $b);
    case %(neg ?a): {
      List zero = %(0);
      return %(sub @zero $a);
    }
  }
  return form;
}

meta Var ct_binding_name(List form) {
  match (form) {
    case %(expr ? (ident (binding ? ?name))): return name;
  }
  return void;
}

/* --- typed captures in match patterns ------------------------------------ */

/* A typed capture is a tag test as well as a binder, so each of these
   answers its fallback when the element has the wrong type. The pair of
   results per function is what proves the test survived folding. */

meta String ct_typed_string(List form) {
  match (form) {
    case %(call ?(String n)): return n;
  }
  return "none";
}

meta int ct_typed_int(List form) {
  match (form) {
    case %(call ?(int n)): return n;
  }
  return -1;
}

/* A typed capture inside a sublist folds with the cell around it. */
meta String ct_typed_nested(List form) {
  match (form) {
    case %(call (arg ?(String n)) ?rest): return n;
  }
  return "none";
}

meta String ct_typed_mixed(List form) {
  match (form) {
    case %(op ?name ?(String text)): return text;
  }
  return "none";
}

meta int ct_typed_symbol(List form) {
  match (form) {
    case %(tag ?(Symbol s)): return 1;
  }
  return 0;
}

/* --- the library names a call resolves against --------------------------- */

/* A call in a compile-time function resolves against a name in
   `etc/comptime.xlisp`, and an operation with no binding there declines the
   whole function. One function below per binding added for `String`,
   `Array` and `Map`. */

meta String ct_str_capitalize(String s) => s.capitalize();

meta int ct_str_count(String s) => s.count("ab");

meta String ct_str_escape(String s) => s.escape();

meta String ct_str_unescape(String s) => s.unescape();

meta int ct_str_find_all(String s) => s.find_all("a", 0, -1).len();

meta String ct_str_partition(String s) => "/".join(s.partition("="));

meta String ct_str_rpartition(String s) => "/".join(s.rpartition("="));

meta String ct_str_prefix(String s) => s.remove_prefix("ct_");

meta String ct_str_suffix(String s) => s.remove_suffix(".x");

meta String ct_str_repeat(String s) => s.repeat(3);

meta int ct_str_rfind(String s) => s.rfind("b");

meta String ct_str_lines(String s) => "|".join(s.split_lines(0));

meta int ct_arr_contains(int n) {
  Array xs = [n, n + 1];
  return xs.contains(n + 1);
}

meta int ct_arr_count(int n) {
  Array xs = [n, n, n + 1];
  return xs.count(n);
}

meta int ct_arr_find(int n) {
  Array xs = [n, n + 1];
  return xs.find(n + 1);
}

meta int ct_arr_unshift(int n) {
  Array xs = [n];
  xs.unshift(n + 1);
  return Var.integer(xs[0]);
}

/* `Array.shift`, `Array.take_last`, `Array.remove`, `Array.insert` and
   `Map.del` answer `void` where there is no element, and `void` has no Lisp
   value, so each is wrapped rather than aliased. Each function below reads a
   present element and then an absent one, which is where an alias would
   fail. */

meta int ct_arr_shift(int n) {
  Array xs = [n];
  int first = Var.integer(xs.shift());
  return xs.shift() ? -1 : first;
}

meta int ct_arr_take_last(int n) {
  Array xs = [n];
  int last = Var.integer(xs.take_last());
  return xs.take_last() ? -1 : last;
}

meta int ct_arr_remove(int n) {
  Array xs = [n, n + 1];
  int gone = Var.integer(xs.remove(-1));
  return xs.remove(9) ? -1 : gone;
}

meta int ct_arr_insert(int n) {
  Array xs = [n];
  xs.insert(0, n + 1);
  return xs.insert(9, n) ? -1 : Var.integer(xs[0]);
}

meta int ct_map_del(int n) {
  Map m = { "a": n };
  int gone = Var.integer(m.del("a"));
  return m.del("a") ? -1 : gone;
}

meta int ct_map_setdefault(int n) {
  Map m = { "a": n };
  m.setdefault("b", n + 1);
  return Var.integer(m.setdefault("b", 0));
}

/* --- compile-time and runtime agreement --------------------------------- */

meta int mt_poly(int n) => n * n + 3 * n + 1;

/* `meta` composes with a storage class rather than replacing one: `static`
   still says what it always said about the emitted function. */
meta static String mt_label(String stem, int n) => %"$stem:$n";

/* --- constant-argument folding ------------------------------------------- */

/* A call to a `meta` function whose arguments are all compile-time constants
   is answered here from the compile-time form. The answer is the same either
   way, which is the point, so this file cannot show which form produced it;
   `meta-folding.x` pins the generated C that does. `mt_fold` is `static` and
   its non-constant call keeps the emitted definition live. */
meta static int mt_fold(int n) => n * 2 + 1;

/* Everywhere else `meta` is an ordinary identifier. This is the fixture's
   claim that the word stays contextual: a file-scope name, an assignment
   target, and a struct field. */
List meta = %(a b);

struct MetaHolder { int meta; };

/* --- conversions and updates the lowering has to carry ------------------- */

/* An argument names the parameter type it has to reach and carries no
   conversion of its own, so an `Array` handed to a `List` parameter reached
   the native adapter as an `Array`. The adapter refused it by raising with
   the `Array` in the error detail, which is not an admissible detail value,
   so the compile terminated at the error floor with no diagnostic at all. */
meta static String mt_join_array(String a, String b) {
  Array out = [a, b];
  return "/".join(out);
}

/* A compound assignment to a local that lives in a cell reads through its
   box, the way every other read of that local does. Reading the slot itself
   handed `_binary` the box and answered `(no-member (tag array) (member
   add))`. `x` is a cell because its address is taken; `score` is one because
   a loop assigns it a call's result. */
meta static int mt_cell_update(int a) {
  int x = a;
  int *p = &x;
  x += 5;
  x++;
  return *p;
}

meta static int mt_loop_update(String text) {
  int score = 0;
  foreach (Var part, text.split(",")) {
    String piece = part;
    score += String.len(piece);
  }
  return score;
}

/* --- number spellings ---------------------------------------------------- */

/* A hexadecimal literal carries `e` and `E` as digits, and the exponent test
   read them as a floating spelling, so `0x000E` lowered to 14.0 and a switch
   label built from one was rejected by the C compiler as a double. Every
   answer below has to be an integer. */
meta static int mt_hex(void) => 0x000E + 0x00E0 + 0xE + 0x1E;

meta static int mt_hex_upper(void) => 0X00FE + 0XE1;

/* The floating spellings the same test still has to accept. */
meta static String mt_floats(void) =>
  %"${1e3} ${2.5E-1} ${0.75}";

/* --- callable values ----------------------------------------------------- */

/* `f(x)` is not a call in the AST. It expands to a stored callee, a
   reference-carrier probe and a boxed `FuncArg` per argument, and
   `Func.apply` last; a call with no arguments needs none of that and is the
   bare `Func.apply`. A compile-time `Func` is the Lisp lambda this pass
   lowered, so both spellings collapse back to the application they stand
   for. One applier per arity, because `src/expressions.x` builds them
   differently. */
meta static Var mt_apply0(Func f) => f();

meta static Var mt_apply1(Func f, Var v) => f(v);

meta static Var mt_apply2(Func f, int a, String b) => f(a, b);

meta static int mt_call_none(int bias) {
  Func k = %!() => 5;
  return bias + (int) mt_apply0(k);
}

meta static int mt_call_one(int n) {
  Func bump = %!(Var x) => x + 10;
  return mt_apply1(bump, n);
}

meta static String mt_call_two(int n, String tail) {
  Func join = %!(Var a, Var b) => %"$a-$b";
  return mt_apply2(join, n, tail);
}

/* A function named where a value is wanted is the definition this pass
   installed, so it reaches a `Func` without a lambda around it. */
meta static Var mt_bump(Var x) => x + 1;

meta static int mt_named(int n) {
  Func g = mt_bump;
  return mt_apply1(g, n);
}

/* The three shapes `etc/init.xlisp` needs, each calling its procedure from
   inside a loop. */
meta static List mt_map(List values, Func fn) {
  Array out = [];
  foreach (Var v, values) out.push(fn(v));
  return out;
}

meta static List mt_filter(List values, Func keep) {
  Array out = [];
  foreach (Var v, values) if (keep(v)) out.push(v);
  return out;
}

meta static Var mt_foldl(Func step, Var seed, List values) {
  Var total = seed;
  foreach (Var v, values) total = step(total, v);
  return total;
}

meta static int mt_higher(int seed) {
  List doubled = mt_map(%(1 2 3), %!(Var x) => (int) x * 2);
  List big = mt_filter(doubled, %!(Var x) => x > 2);
  return mt_foldl(%!(Var a, Var b) => (int) a + (int) b, seed, big);
}

/* A `Func` stored in a `Map` and read back: boxing it and reading it back
   are both the identity, because a Lisp lambda already is a value. */
meta static int mt_thunk(String which) {
  Func a = %!() => 1;
  Func b = %!() => 2;
  Map table = {};
  table["a"] = a;
  table["b"] = b;
  Func chosen = table[which];
  return chosen();
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
  printf("live-set     %d\n", $(ct_live_set '(a b c) 1));
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
  printf("str-case     %s\n", $(ct_str_capitalize "hi"));
  printf("str-count    %d\n", $(ct_str_count "abab"));
  printf("str-escape   %s\n", $(ct_str_escape "a\nb"));
  printf("str-unescape %s\n", $(ct_str_unescape "a\\tb"));
  printf("str-find-all %d\n", $(ct_str_find_all "abab"));
  printf("str-part     %s %s\n",
         $(ct_str_partition "a=b"), $(ct_str_partition "ab"));
  printf("str-rpart    %s %s\n",
         $(ct_str_rpartition "a=b=c"), $(ct_str_rpartition "ab"));
  printf("str-prefix   %s %s\n",
         $(ct_str_prefix "ct_name"), $(ct_str_prefix "name"));
  printf("str-suffix   %s %s\n",
         $(ct_str_suffix "unit.x"), $(ct_str_suffix "unit.c"));
  printf("str-repeat   %s\n", $(ct_str_repeat "ab"));
  printf("str-rfind    %d\n", $(ct_str_rfind "abcb"));
  printf("str-lines    %s\n", $(ct_str_lines "one\ntwo"));
  printf("arr-contains %d\n", $(ct_arr_contains 4));
  printf("arr-count    %d\n", $(ct_arr_count 4));
  printf("arr-find     %d\n", $(ct_arr_find 4));
  printf("arr-unshift  %d\n", $(ct_arr_unshift 4));
  printf("arr-shift    %d\n", $(ct_arr_shift 4));
  printf("arr-take     %d\n", $(ct_arr_take_last 4));
  printf("arr-remove   %d\n", $(ct_arr_remove 4));
  printf("arr-insert   %d\n", $(ct_arr_insert 4));
  printf("map-del      %d\n", $(ct_map_del 4));
  printf("map-default  %d\n", $(ct_map_setdefault 4));
  printf("meta-poly    %d %d\n", $(mt_poly 7), mt_poly(7));
  printf("meta-static  %s %s\n",
         $(mt_label "slot" 4), mt_label("slot", 4));
  int nine = 9;
  printf("meta-fold    %d %d\n", mt_fold(9), mt_fold(nine));
  /* Each run-time call takes a local, so a constant argument cannot fold it
     back into the compile-time answer the same line already prints. */
  int one = 1;
  String left = "x", right = "y", csv = "ab,cde";
  printf("join-array   %s %s\n",
         $(mt_join_array "x" "y"), mt_join_array(left, right));
  printf("cell-update  %d %d\n",
         $(mt_cell_update 1), mt_cell_update(one));
  printf("loop-update  %d %d\n",
         $(mt_loop_update "ab,cde"), mt_loop_update(csv));
  printf("hex          %d %d\n", $(mt_hex), mt_hex());
  printf("hex-upper    %d %d\n", $(mt_hex_upper), mt_hex_upper());
  printf("floats       %s %s\n", $(mt_floats), mt_floats());
  int zero = 0, seven = 7, three = 3, ten = 10;
  String ex = "x", ay = "a", bee = "b";
  printf("func-none    %d %d\n", $(mt_call_none 0), mt_call_none(zero));
  printf("func-one     %d %d\n", $(mt_call_one 7), mt_call_one(seven));
  printf("func-two     %s %s\n",
         $(mt_call_two 3 "x"), mt_call_two(three, ex));
  printf("func-named   %d %d\n", $(mt_named 10), mt_named(ten));
  printf("func-higher  %d %d\n", $(mt_higher 0), mt_higher(zero));
  printf("func-thunk   %d %d %d %d\n",
         $(mt_thunk "a"), $(mt_thunk "b"), mt_thunk(ay), mt_thunk(bee));
  meta = %(a b c);
  struct MetaHolder holder = { .meta = 3 };
  printf("meta-ident   %d %d\n", meta.len(), holder.meta);
  return 0;
}
