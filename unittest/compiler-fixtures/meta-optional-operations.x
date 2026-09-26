/* Canonical views and pure optional modules preserve native behavior. */
#include "x2c.x"
#include "typed-list.x"
#include "list-selectors.x"
#include "digest.x"
#include "json.x"

$(import "meta-optional-operations.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $optional_List_listchar(0),
    optional_List_listchar(argc - 1));
  printf("%d %d\n", $optional_List_listshort(0),
    optional_List_listshort(argc - 1));
  printf("%d %d\n", $optional_List_listint(0),
    optional_List_listint(argc - 1));
  printf("%d %d\n", $optional_List_listfloat(0),
    optional_List_listfloat(argc - 1));
  printf("%d %d\n", $optional_List_listdbl(0),
    optional_List_listdbl(argc - 1));
  printf("%d %d\n", $optional_List_liststring(0),
    optional_List_liststring(argc - 1));
  printf("%d %d\n", $optional_List_listsymbol(0),
    optional_List_listsymbol(argc - 1));
  printf("%d %d\n", $optional_List_cdddr(0),
    optional_List_cdddr(argc - 1));
  printf("%d %d\n", $optional_List_cddddr(0),
    optional_List_cddddr(argc - 1));
  printf("%d %d\n", $optional_Var_listchar(0),
    optional_Var_listchar(argc - 1));
  printf("%d %d\n", $optional_Var_listshort(0),
    optional_Var_listshort(argc - 1));
  printf("%d %d\n", $optional_Var_listint(0),
    optional_Var_listint(argc - 1));
  printf("%d %d\n", $optional_Var_listfloat(0),
    optional_Var_listfloat(argc - 1));
  printf("%d %d\n", $optional_Var_listdbl(0),
    optional_Var_listdbl(argc - 1));
  printf("%d %d\n", $optional_Var_liststring(0),
    optional_Var_liststring(argc - 1));
  printf("%d %d\n", $optional_Var_listsymbol(0),
    optional_Var_listsymbol(argc - 1));
  printf("%d %d\n", $optional_Var_cdddr(0),
    optional_Var_cdddr(argc - 1));
  printf("%d %d\n", $optional_Var_cddddr(0),
    optional_Var_cddddr(argc - 1));
  printf("%d %d\n", $optional_String_sha256(0),
    optional_String_sha256(argc - 1));
  printf("%d %d\n", $optional_Var_json(0),
    optional_Var_json(argc - 1));
  printf("%d %d\n", $optional_Var_pretty_json(0),
    optional_Var_pretty_json(argc - 1));
  printf("%d %d\n", $optional_String_new_len(0),
    optional_String_new_len(argc - 1));
  printf("%d %d\n", $optional_Symbol_new_len(0),
    optional_Symbol_new_len(argc - 1));
  printf("%d %d\n", $optional_Symbol_parse(0),
    optional_Symbol_parse(argc - 1));
  return 0;
}
