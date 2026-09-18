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
