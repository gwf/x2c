/* Native and meta collection operations preserve order and identity. */
#include "x2c.x"

$(import "meta-collection-operations.xmacro")

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
