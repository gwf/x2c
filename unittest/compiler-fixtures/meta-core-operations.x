/* Native and meta scalar payloads and mutable containers agree. */
#include "x2c.x"

meta int core_String_intern(int unused) {
  (void) unused;
  String s = "abc";
  return s.intern() === s;
}
meta int core_String_parse(int unused) {
  (void) unused;
  return "\"a\\nb\"".parse().equal("a\nb")
    && "".parse().len() == 0;
}
meta int core_String_parse_char(int unused) {
  (void) unused;
  return "'a'tail".parse_char() == 'a'
    && "'\\n'".parse_char() == '\n'
    && "bad".parse_char() == -1;
}
meta int core_String_withindex(int unused) {
  (void) unused;
  return "abc".withindex(-1, 'x').equal("abx")
    && "abc".withindex(5, 'x').equal("abc");
}
meta int core_String_truth(int unused) {
  (void) unused;
  String empty = "";
  return "x".truth()
    && !empty.truth();
}
meta int core_Array_capacity(int unused) {
  (void) unused;
  Array a = [1, 2];
  return a.capacity() >= a.len();
}
meta int core_Array_remslice(int unused) {
  (void) unused;
  Array a = [0, 1, 2, 3];
  Array removed = a.remslice(1, 3);
  return !(removed === a)
    && removed.list().equal(%(1 2))
    && a.list().equal(%(0 3));
}
meta int core_Array_setslice(int unused) {
  (void) unused;
  Array a = [0, 1, 2];
  Array b = [8, 9];
  return a.setslice(1, 2, b) === a
    && a.list().equal(%(0 8 9 2));
}
meta int core_Array_splice(int unused) {
  (void) unused;
  Array a = [0, 1, 2];
  Array b = [8];
  Array removed = a.splice(1, 1, b);
  return removed.list().equal(%(1))
    && !(removed === a)
    && a.list().equal(%(0 8 2));
}
meta int core_Array_updateindex(int unused) {
  (void) unused;
  Array a = [1, 2];
  return a.updateindex(-1, <+>, 3) == 5
    && a[1] == 5;
}
meta int core_Array_postfixindex(int unused) {
  (void) unused;
  Array a = [1, 2];
  return a.postfixindex(-1, <++>) == 2
    && a[1] == 3;
}
meta int core_Array_clear(int unused) {
  (void) unused;
  Array a = [1, 2];
  a.clear();
  a.push(3);
  return a.list().equal(%(3));
}
meta int core_Array_heap_push(int unused) {
  (void) unused;
  Array a = [];
  a.heap_push(3);
  a.heap_push(1);
  a.heap_push(2);
  return a[0] == 1
    && a.len() == 3;
}
meta int core_Array_heapify(int unused) {
  (void) unused;
  Array a = [3, 1, 2];
  a.heapify();
  return a[0] == 1
    && a.len() == 3;
}
meta int core_Array_pop(int unused) {
  (void) unused;
  Array a = [1, 2];
  a.pop();
  return a.list().equal(%(1));
}
meta int core_Array_resize(int unused) {
  (void) unused;
  Array a = [1];
  a.resize(3);
  Var v = a[2];
  a.resize(1);
  return v.is_null()
    && a.list().equal(%(1));
}
meta int core_Array_truncate(int unused) {
  (void) unused;
  Array a = [1, 2, 3];
  a.truncate(1);
  return a.list().equal(%(1));
}
meta int core_Map_new_capacity(int unused) {
  (void) unused;
  Map m = Map.new_capacity(8);
  m.set("x", 7);
  return m.len() == 1
    && m["x"] == 7;
}
meta int core_Map_updateindex(int unused) {
  (void) unused;
  Map m = {"x": 2};
  return m.updateindex("x", <+>, 3) == 5
    && m["x"] == 5;
}
meta int core_Map_postfixindex(int unused) {
  (void) unused;
  Map m = {"x": 2};
  return m.postfixindex("x", <++>) == 2
    && m["x"] == 3;
}
meta int core_Map_set(int unused) {
  (void) unused;
  Map m = {};
  m.set("x", 2);
  m.set("x", 3);
  return m.len() == 1
    && m["x"] == 3;
}
meta int core_Var_array(int unused) {
  (void) unused;
  Array a = [1];
  Var v = a;
  return v.array() === a;
}
meta int core_Var_map(int unused) {
  (void) unused;
  Map m = {"x": 1};
  Var v = m;
  return v.map() === m;
}
meta int core_Var_string(int unused) {
  (void) unused;
  Var v = "abc";
  return v.string().equal("abc");
}
meta int core_Var_symbol(int unused) {
  (void) unused;
  Var v = <abc>;
  return v.symbol() == <abc>;
}
meta int core_Var_compare(int unused) {
  (void) unused;
  Var a = 1, b = 2;
  return a.compare(b) < 0
    && b.compare(a) > 0
    && a.compare(a) == 0;
}
meta int core_Var_contains(int unused) {
  (void) unused;
  Var a = %(1 2);
  return a.contains(2)
    && !a.contains(3);
}
meta int core_Var_hash(int unused) {
  (void) unused;
  Var a = "abc";
  return a.hash() != 0;
}
meta int core_Var_same(int unused) {
  (void) unused;
  Array a = [1], b = [1];
  Var x = a, y = b;
  return x.same(x)
    && !x.same(y);
}
meta int core_Var_is_atom(int unused) {
  (void) unused;
  Var a = %(abc).car(), b = 1;
  return a.is_atom()
    && !b.is_atom();
}
meta int core_Var_is_atom_binder(int unused) {
  (void) unused;
  Var a = %(?x).car(), b = %(abc).car();
  return a.is_atom_binder()
    && !b.is_atom_binder();
}
meta int core_Var_is_binder(int unused) {
  (void) unused;
  Var a = %(?x).car(), b = %(*xs).car(), c = 1;
  return a.is_binder()
    && b.is_binder()
    && !c.is_binder();
}
meta int core_Var_is_list_binder(int unused) {
  (void) unused;
  Var a = %(*xs).car(), b = %(?x).car();
  return a.is_list_binder()
    && !b.is_list_binder();
}
meta int core_Var_is_match_op(int unused) {
  (void) unused;
  Var a = <!is>, b = 1;
  return a.is_match_op()
    && !b.is_match_op();
}
meta int core_Var_is_floating(int unused) {
  (void) unused;
  Var a = 1.5, b = 1;
  return a.is_floating()
    && !b.is_floating();
}
meta int core_Var_is_integer(int unused) {
  (void) unused;
  Var a = 1, b = 1.5;
  return a.is_integer()
    && !b.is_integer();
}
meta int core_Var_is_object(int unused) {
  (void) unused;
  Var a = "x", b = 1;
  return a.is_object()
    && !b.is_object();
}
meta int core_Var_is_wide(int unused) {
  (void) unused;
  Var a = 1L, b = 1;
  return a.is_wide()
    && !b.is_wide();
}
meta int core_Var_is_nil(int unused) {
  (void) unused;
  Var a = %(), b = %(1);
  return a.is_nil()
    && !b.is_nil();
}
meta int core_Var_is_null(int unused) {
  (void) unused;
  Array a = [];
  a.resize(1);
  Var v = a[0], b = %();
  return v.is_null()
    && !b.is_null();
}
meta int core_Var_add(int unused) {
  (void) unused;
  Var a = 7;
  return a.add(2) == 9;
}
meta int core_Var_sub(int unused) {
  (void) unused;
  Var a = 7;
  return a.sub(2) == 5;
}
meta int core_Var_mul(int unused) {
  (void) unused;
  Var a = 7;
  return a.mul(2) == 14;
}
meta int core_Var_div(int unused) {
  (void) unused;
  Var a = 7;
  return a.div(2) == 3;
}
meta int core_Var_mod(int unused) {
  (void) unused;
  Var a = 7;
  return a.mod(2) == 1;
}
meta int core_Var_neg(int unused) {
  (void) unused;
  Var a = 7;
  return a.neg() == -7;
}
meta int core_Var_truth(int unused) {
  (void) unused;
  Var a = 0, b = 1, c = %();
  return !a.truth()
    && b.truth()
    && !c.truth();
}
meta int core_Var_setindex(int unused) {
  (void) unused;
  Array a = [1];
  Var v = a;
  v.setindex(0, 3);
  return a[0] == 3;
}
meta int core_Var_updateindex(int unused) {
  (void) unused;
  Array a = [1];
  Var v = a;
  return v.updateindex(0, <+>, 3) == 4
    && a[0] == 4;
}
meta int core_Var_postfixindex(int unused) {
  (void) unused;
  Array a = [1];
  Var v = a;
  return v.postfixindex(0, <++>) == 1
    && a[0] == 2;
}
meta int core_List_truth(int unused) {
  (void) unused;
  return !%().truth()
    && %(1).truth();
}
meta int core_Var_char(int unused) {
  (void) unused;
  Var v = 65;
  return (int) v.char() == 65;
}
meta int core_Var_short(int unused) {
  (void) unused;
  Var v = 65537;
  return (int) v.short() == 1;
}
meta int core_Var_int(int unused) {
  (void) unused;
  Var v = 65;
  return (int) v.int() == 65;
}
meta int core_Var_long(int unused) {
  (void) unused;
  Var v = 65;
  return (int) v.long() == 65;
}
meta int core_Var_long_long(int unused) {
  (void) unused;
  Var v = 65;
  return (int) v.long_long() == 65;
}
meta int core_Var_unsigned(int unused) {
  (void) unused;
  Var v = 65;
  return (int) v.unsigned() == 65;
}
meta int core_Var_ushort(int unused) {
  (void) unused;
  Var v = 65537;
  return (int) v.ushort() == 1;
}
meta int core_Var_uchar(int unused) {
  (void) unused;
  Var v = 257;
  return (int) v.uchar() == 1;
}
meta int core_Var_uint(int unused) {
  (void) unused;
  Var v = 65;
  return (int) v.uint() == 65;
}
meta int core_Var_ulong(int unused) {
  (void) unused;
  Var v = 65;
  return (int) v.ulong() == 65;
}
meta int core_Var_ulong_long(int unused) {
  (void) unused;
  Var v = 65;
  return (int) v.ulong_long() == 65;
}
meta int core_Var_float(int unused) {
  (void) unused;
  Var v = 1.5;
  return v.float() == 1.5;
}
meta int core_Var_double(int unused) {
  (void) unused;
  Var v = 1.5;
  return v.double() == 1.5;
}
meta int core_Var_long_double(int unused) {
  (void) unused;
  Var v = 1.5;
  return v.long_double() == 1.5;
}
meta int core_Var_long_value(int unused) {
  (void) unused;
  Var a = (long) 7, b = "x";
  return (int) a.long_value() == 7
    && (int) b.long_value() == 0;
}
meta int core_Var_ulong_value(int unused) {
  (void) unused;
  Var a = (unsigned long) 7, b = "x";
  return (int) a.ulong_value() == 7
    && (int) b.ulong_value() == 0;
}
meta int core_Var_long_long_value(int unused) {
  (void) unused;
  Var a = (long long) 7, b = "x";
  return (int) a.long_long_value() == 7
    && (int) b.long_long_value() == 0;
}
meta int core_Var_ulong_long_value(int unused) {
  (void) unused;
  Var a = (unsigned long long) 7, b = "x";
  return (int) a.ulong_long_value() == 7
    && (int) b.ulong_long_value() == 0;
}
meta int core_Var_long_double_value(int unused) {
  (void) unused;
  Var a = (long double) 7, b = "x";
  return (int) a.long_double_value() == 7
    && (int) b.long_double_value() == 0;
}
meta int core_Symbol_first(int unused) {
  (void) unused;
  Symbol empty = "".symbol();
  return <abc>.first() == 'a'
    && empty.first() == 0;
}
meta int core_Symbol_last(int unused) {
  (void) unused;
  Symbol empty = "".symbol();
  return <abc>.last() == 'c'
    && empty.last() == 0;
}
int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $core_String_intern(0),
    core_String_intern(argc - 1));
  printf("%d %d\n", $core_String_parse(0),
    core_String_parse(argc - 1));
  printf("%d %d\n", $core_String_parse_char(0),
    core_String_parse_char(argc - 1));
  printf("%d %d\n", $core_String_withindex(0),
    core_String_withindex(argc - 1));
  printf("%d %d\n", $core_String_truth(0),
    core_String_truth(argc - 1));
  printf("%d %d\n", $core_Array_capacity(0),
    core_Array_capacity(argc - 1));
  printf("%d %d\n", $core_Array_remslice(0),
    core_Array_remslice(argc - 1));
  printf("%d %d\n", $core_Array_setslice(0),
    core_Array_setslice(argc - 1));
  printf("%d %d\n", $core_Array_splice(0),
    core_Array_splice(argc - 1));
  printf("%d %d\n", $core_Array_updateindex(0),
    core_Array_updateindex(argc - 1));
  printf("%d %d\n", $core_Array_postfixindex(0),
    core_Array_postfixindex(argc - 1));
  printf("%d %d\n", $core_Array_clear(0),
    core_Array_clear(argc - 1));
  printf("%d %d\n", $core_Array_heap_push(0),
    core_Array_heap_push(argc - 1));
  printf("%d %d\n", $core_Array_heapify(0),
    core_Array_heapify(argc - 1));
  printf("%d %d\n", $core_Array_pop(0),
    core_Array_pop(argc - 1));
  printf("%d %d\n", $core_Array_resize(0),
    core_Array_resize(argc - 1));
  printf("%d %d\n", $core_Array_truncate(0),
    core_Array_truncate(argc - 1));
  printf("%d %d\n", $core_Map_new_capacity(0),
    core_Map_new_capacity(argc - 1));
  printf("%d %d\n", $core_Map_updateindex(0),
    core_Map_updateindex(argc - 1));
  printf("%d %d\n", $core_Map_postfixindex(0),
    core_Map_postfixindex(argc - 1));
  printf("%d %d\n", $core_Map_set(0),
    core_Map_set(argc - 1));
  printf("%d %d\n", $core_Var_array(0),
    core_Var_array(argc - 1));
  printf("%d %d\n", $core_Var_map(0),
    core_Var_map(argc - 1));
  printf("%d %d\n", $core_Var_string(0),
    core_Var_string(argc - 1));
  printf("%d %d\n", $core_Var_symbol(0),
    core_Var_symbol(argc - 1));
  printf("%d %d\n", $core_Var_compare(0),
    core_Var_compare(argc - 1));
  printf("%d %d\n", $core_Var_contains(0),
    core_Var_contains(argc - 1));
  printf("%d %d\n", $core_Var_hash(0),
    core_Var_hash(argc - 1));
  printf("%d %d\n", $core_Var_same(0),
    core_Var_same(argc - 1));
  printf("%d %d\n", $core_Var_is_atom(0),
    core_Var_is_atom(argc - 1));
  printf("%d %d\n", $core_Var_is_atom_binder(0),
    core_Var_is_atom_binder(argc - 1));
  printf("%d %d\n", $core_Var_is_binder(0),
    core_Var_is_binder(argc - 1));
  printf("%d %d\n", $core_Var_is_list_binder(0),
    core_Var_is_list_binder(argc - 1));
  printf("%d %d\n", $core_Var_is_match_op(0),
    core_Var_is_match_op(argc - 1));
  printf("%d %d\n", $core_Var_is_floating(0),
    core_Var_is_floating(argc - 1));
  printf("%d %d\n", $core_Var_is_integer(0),
    core_Var_is_integer(argc - 1));
  printf("%d %d\n", $core_Var_is_object(0),
    core_Var_is_object(argc - 1));
  printf("%d %d\n", $core_Var_is_wide(0),
    core_Var_is_wide(argc - 1));
  printf("%d %d\n", $core_Var_is_nil(0),
    core_Var_is_nil(argc - 1));
  printf("%d %d\n", $core_Var_is_null(0),
    core_Var_is_null(argc - 1));
  printf("%d %d\n", $core_Var_add(0),
    core_Var_add(argc - 1));
  printf("%d %d\n", $core_Var_sub(0),
    core_Var_sub(argc - 1));
  printf("%d %d\n", $core_Var_mul(0),
    core_Var_mul(argc - 1));
  printf("%d %d\n", $core_Var_div(0),
    core_Var_div(argc - 1));
  printf("%d %d\n", $core_Var_mod(0),
    core_Var_mod(argc - 1));
  printf("%d %d\n", $core_Var_neg(0),
    core_Var_neg(argc - 1));
  printf("%d %d\n", $core_Var_truth(0),
    core_Var_truth(argc - 1));
  printf("%d %d\n", $core_Var_setindex(0),
    core_Var_setindex(argc - 1));
  printf("%d %d\n", $core_Var_updateindex(0),
    core_Var_updateindex(argc - 1));
  printf("%d %d\n", $core_Var_postfixindex(0),
    core_Var_postfixindex(argc - 1));
  printf("%d %d\n", $core_List_truth(0),
    core_List_truth(argc - 1));
  printf("%d %d\n", $core_Var_char(0),
    core_Var_char(argc - 1));
  printf("%d %d\n", $core_Var_short(0),
    core_Var_short(argc - 1));
  printf("%d %d\n", $core_Var_int(0),
    core_Var_int(argc - 1));
  printf("%d %d\n", $core_Var_long(0),
    core_Var_long(argc - 1));
  printf("%d %d\n", $core_Var_long_long(0),
    core_Var_long_long(argc - 1));
  printf("%d %d\n", $core_Var_unsigned(0),
    core_Var_unsigned(argc - 1));
  printf("%d %d\n", $core_Var_ushort(0),
    core_Var_ushort(argc - 1));
  printf("%d %d\n", $core_Var_uchar(0),
    core_Var_uchar(argc - 1));
  printf("%d %d\n", $core_Var_uint(0),
    core_Var_uint(argc - 1));
  printf("%d %d\n", $core_Var_ulong(0),
    core_Var_ulong(argc - 1));
  printf("%d %d\n", $core_Var_ulong_long(0),
    core_Var_ulong_long(argc - 1));
  printf("%d %d\n", $core_Var_float(0),
    core_Var_float(argc - 1));
  printf("%d %d\n", $core_Var_double(0),
    core_Var_double(argc - 1));
  printf("%d %d\n", $core_Var_long_double(0),
    core_Var_long_double(argc - 1));
  printf("%d %d\n", $core_Var_long_value(0),
    core_Var_long_value(argc - 1));
  printf("%d %d\n", $core_Var_ulong_value(0),
    core_Var_ulong_value(argc - 1));
  printf("%d %d\n", $core_Var_long_long_value(0),
    core_Var_long_long_value(argc - 1));
  printf("%d %d\n", $core_Var_ulong_long_value(0),
    core_Var_ulong_long_value(argc - 1));
  printf("%d %d\n", $core_Var_long_double_value(0),
    core_Var_long_double_value(argc - 1));
  printf("%d %d\n", $core_Symbol_first(0),
    core_Symbol_first(argc - 1));
  printf("%d %d\n", $core_Symbol_last(0),
    core_Symbol_last(argc - 1));
  return 0;
}
