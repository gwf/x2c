/*  comptime-lowering.x -- the constructs compile-time code has used

    Each `meta` function once went through the retired Lisp lowering; it now
    runs as the native code the unit's staged `meta` group compiles. `main`
    calls each one in expression position, so the printed value is what the
    function computed during translation. Compile-time Lisp calls reach the
    same native functions by name.
*/

#include "x2c.x"

/* A Map from alternating keys and values. */
$(defun ct_map_of (flat)
  (if (null? flat) (Map.new)
    (let ((map (ct_map_of (cddr flat))))
      (begin (Map.setindex map (car flat) (cadr flat)) map))))

/* Mutual recursion needs the names before the definitions, the way a C
   prototype does. */
$(def ct_odd (lambda (. rest) 0))

$(import "comptime-lowering.xmacro")

/* --- control flow: break, continue, do/while, switch --------------------- */

/* --- collection literals and indexing ------------------------------------ */

/* --- destructuring and iteration over every container -------------------- */

/* --- typed captures in match patterns ------------------------------------ */

/* --- the library names a call resolves against --------------------------- */

/* Everywhere else `meta` is an ordinary identifier. This is the fixture's
   claim that the word stays contextual: a file-scope name, an assignment
   target, and a struct field. */
List meta = %(a b);

struct MetaHolder { int meta; };

/* --- conversions and updates the lowering has to carry ------------------- */

/* --- number spellings ---------------------------------------------------- */

/* --- callable values ----------------------------------------------------- */

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
  printf("void-return  %d\n", $(ct_void_calls));
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
  printf("c-array      %d\n", $(ct_c_array 10));
  printf("c-array-pad  %d\n", $(ct_c_array_padded));
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
  printf("pair-array   %d\n", $(ct_pair_array (List.array '(5 6))));
  printf("walk-array   %d\n", $(ct_walk_array (List.array '(4 5 6))));
  printf("walk-map     %d\n", $(ct_walk_map (ct_map_of '(1 2 3 4))));
  printf("walk-pairs   %d\n", $(ct_walk_map_pairs (ct_map_of '(1 2 3 4))));
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
  printf("map-default  %d\n", $(ct_map_setdefault 4));
  printf("meta-poly    %d %d\n", $(mt_poly 7), mt_poly(7));
  printf("meta-static  %s %s\n",
         $(mt_label "slot" 4), mt_label("slot", 4));
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
