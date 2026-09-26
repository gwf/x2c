/* Native and meta collection operations preserve order and identity. */
#include "x2c.x"

meta int collection_List_unique(int unused) {
  (void) unused;
  List xs = %(2 1 2 3 1);
  return xs.unique().equal(%(2 1 3))
    && %().unique().len() == 0;
}
meta int collection_List_sublis(int unused) {
  (void) unused;
  List rules = %((a 7) (b (8 9)));
  return rules.sublis(%(a (b c))).equal(%(7 ((8 9) c)));
}
meta int collection_List_flatten(int unused) {
  (void) unused;
  return %(1 (2 (3)) ()).flatten().equal(%(1 2 (3)));
}
meta int collection_List_flatten_all(int unused) {
  (void) unused;
  return %(1 (2 (3)) ()).flatten_all().equal(%(1 2 3));
}
meta int collection_List_nth_cdr(int unused) {
  (void) unused;
  List xs = %(1 2 3);
  return xs.nth_cdr(1).equal(%(2 3))
    && xs.nth_cdr(9).len() == 0
    && xs.nth_cdr(-1) === xs;
}
meta int collection_List_tail(int unused) {
  (void) unused;
  List xs = %(1 2 3);
  return xs.tail(2).equal(%(2 3))
    && xs.tail(9) === xs
    && xs.tail(0).len() == 0;
}
meta int collection_List_head(int unused) {
  (void) unused;
  List xs = %(1 2 3);
  return xs.head(2).equal(%(1 2))
    && xs.head(9) === xs
    && xs.head(0).len() == 0;
}
meta int collection_List_subseq(int unused) {
  (void) unused;
  return %(0 1 2 3 4 5).subseq(-4, -1, 2).equal(%(2 4));
}
meta int collection_List_getslice(int unused) {
  (void) unused;
  return %(0 1 2 3 4 5).getslice(5, 1, -2).equal(%(5 3));
}
meta int collection_List_hash(int unused) {
  (void) unused;
  return %(1 2).hash() != 0;
}
meta int collection_List_compare(int unused) {
  (void) unused;
  return %(1 2).compare(%(1 3)) < 0
    && %().compare(%()) == 0;
}
meta int collection_List_replace(int unused) {
  (void) unused;
  return %(a *m b).replace(%((*m (1 2)))).equal(%(a 1 2 b));
}
meta int collection_List_match_replace(int unused) {
  (void) unused;
  return %(a 7).match_replace(%(a ?x), %(b ?x)).equal(%(b 7));
}
meta int collection_Array_copy(int unused) {
  (void) unused;
  Array a = [1, 2];
  Array b = a.copy();
  b[0] = 9;
  return a[0] == 1
    && b[0] == 9
    && !(a === b);
}
meta int collection_Array_getslice(int unused) {
  (void) unused;
  Array a = [0, 1, 2, 3];
  Array b = a.getslice(3, 0, -2);
  return b.list().equal(%(3 1))
    && !(a === b);
}
meta int collection_Array_concat(int unused) {
  (void) unused;
  Array a = [1];
  Array b = [2];
  Array c = a.concat(b);
  return c.list().equal(%(1 2))
    && a.len() == 1
    && b.len() == 1
    && !(a === c);
}
meta int collection_Array_reverse(int unused) {
  (void) unused;
  Array a = [1, 2, 3];
  Array b = a.reverse();
  return a === b
    && a.list().equal(%(3 2 1));
}
meta int collection_Array_compare(int unused) {
  (void) unused;
  Array a = [1, 2];
  Array b = [1, 3];
  return a.compare(b) < 0;
}
meta int collection_Array_sort(int unused) {
  (void) unused;
  Array a = [3, 1, 2];
  Array b = a.sort();
  return a === b
    && a.list().equal(%(1 2 3));
}
meta int collection_Array_equal(int unused) {
  (void) unused;
  Array a = [1, 2];
  Array b = [1, 2];
  return a.equal(b)
    && !(a === b);
}
meta int collection_Array_indexof(int unused) {
  (void) unused;
  Array a = [1, 2, 1];
  return a.indexof(1) == 0
    && a.indexof(9) == -1;
}
meta int collection_Array_truth(int unused) {
  (void) unused;
  Array a = [];
  Array b = [1];
  return !a.truth()
    && b.truth();
}
meta int collection_Map_copy(int unused) {
  (void) unused;
  Map a = {"x": 1};
  Map b = a.copy();
  b["x"] = 2;
  return a["x"] == 1
    && b["x"] == 2
    && !(a === b);
}
meta int collection_Map_merge(int unused) {
  (void) unused;
  Map a = {"x": 1};
  Map b = {"x": 2, "y": 3};
  Map c = a.merge(b);
  return a === c
    && a["x"] == 2
    && a["y"] == 3
    && b.len() == 2;
}
meta int collection_Map_compare(int unused) {
  (void) unused;
  Map a = {"x": 1};
  Map b = {"x": 1};
  return a.compare(b) == 0;
}
meta int collection_Map_equal(int unused) {
  (void) unused;
  Map a = {"x": 1};
  Map b = {"x": 1};
  return a.equal(b)
    && !(a === b);
}
meta int collection_Map_truth(int unused) {
  (void) unused;
  Map a = {};
  Map b = {"x": 1};
  return !a.truth()
    && b.truth();
}
int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $collection_List_unique(0),
    collection_List_unique(argc - 1));
  printf("%d %d\n", $collection_List_sublis(0),
    collection_List_sublis(argc - 1));
  printf("%d %d\n", $collection_List_flatten(0),
    collection_List_flatten(argc - 1));
  printf("%d %d\n", $collection_List_flatten_all(0),
    collection_List_flatten_all(argc - 1));
  printf("%d %d\n", $collection_List_nth_cdr(0),
    collection_List_nth_cdr(argc - 1));
  printf("%d %d\n", $collection_List_tail(0),
    collection_List_tail(argc - 1));
  printf("%d %d\n", $collection_List_head(0),
    collection_List_head(argc - 1));
  printf("%d %d\n", $collection_List_subseq(0),
    collection_List_subseq(argc - 1));
  printf("%d %d\n", $collection_List_getslice(0),
    collection_List_getslice(argc - 1));
  printf("%d %d\n", $collection_List_hash(0),
    collection_List_hash(argc - 1));
  printf("%d %d\n", $collection_List_compare(0),
    collection_List_compare(argc - 1));
  printf("%d %d\n", $collection_List_replace(0),
    collection_List_replace(argc - 1));
  printf("%d %d\n", $collection_List_match_replace(0),
    collection_List_match_replace(argc - 1));
  printf("%d %d\n", $collection_Array_copy(0),
    collection_Array_copy(argc - 1));
  printf("%d %d\n", $collection_Array_getslice(0),
    collection_Array_getslice(argc - 1));
  printf("%d %d\n", $collection_Array_concat(0),
    collection_Array_concat(argc - 1));
  printf("%d %d\n", $collection_Array_reverse(0),
    collection_Array_reverse(argc - 1));
  printf("%d %d\n", $collection_Array_compare(0),
    collection_Array_compare(argc - 1));
  printf("%d %d\n", $collection_Array_sort(0),
    collection_Array_sort(argc - 1));
  printf("%d %d\n", $collection_Array_equal(0),
    collection_Array_equal(argc - 1));
  printf("%d %d\n", $collection_Array_indexof(0),
    collection_Array_indexof(argc - 1));
  printf("%d %d\n", $collection_Array_truth(0),
    collection_Array_truth(argc - 1));
  printf("%d %d\n", $collection_Map_copy(0),
    collection_Map_copy(argc - 1));
  printf("%d %d\n", $collection_Map_merge(0),
    collection_Map_merge(argc - 1));
  printf("%d %d\n", $collection_Map_compare(0),
    collection_Map_compare(argc - 1));
  printf("%d %d\n", $collection_Map_equal(0),
    collection_Map_equal(argc - 1));
  printf("%d %d\n", $collection_Map_truth(0),
    collection_Map_truth(argc - 1));
  return 0;
}
