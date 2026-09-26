/* Canonical views and pure optional modules preserve native behavior. */
#include "x2c.x"
#include "typed-list.x"
#include "list-selectors.x"
#include "digest.x"
#include "json.x"

meta int optional_List_listchar(int unused) {
  (void) unused;
  List xs = %(${(char) 65});
  ListChar view = xs.listchar(), empty = %().listchar();
  return view === xs
    && empty.len() == 0;
}
meta int optional_List_listshort(int unused) {
  (void) unused;
  List xs = %(${(short) 65});
  ListShort view = xs.listshort(), empty = %().listshort();
  return view === xs
    && empty.len() == 0;
}
meta int optional_List_listint(int unused) {
  (void) unused;
  List xs = %(${65});
  ListInt view = xs.listint(), empty = %().listint();
  return view === xs
    && empty.len() == 0;
}
meta int optional_List_listfloat(int unused) {
  (void) unused;
  List xs = %(${(float) 1.5});
  ListFloat view = xs.listfloat(), empty = %().listfloat();
  return view === xs
    && empty.len() == 0;
}
meta int optional_List_listdbl(int unused) {
  (void) unused;
  List xs = %(${1.5});
  ListDbl view = xs.listdbl(), empty = %().listdbl();
  return view === xs
    && empty.len() == 0;
}
meta int optional_List_liststring(int unused) {
  (void) unused;
  List xs = %(${"abc"});
  ListString view = xs.liststring(), empty = %().liststring();
  return view === xs
    && empty.len() == 0;
}
meta int optional_List_listsymbol(int unused) {
  (void) unused;
  List xs = %(${<abc>});
  ListSymbol view = xs.listsymbol(), empty = %().listsymbol();
  return view === xs
    && empty.len() == 0;
}
meta int optional_List_cdddr(int unused) {
  (void) unused;
  List xs = %(1 2 3 4 5), short_list = %(1);
  return xs.cdddr().equal(%(4 5))
    && short_list.cdddr().len() == 0;
}
meta int optional_List_cddddr(int unused) {
  (void) unused;
  List xs = %(1 2 3 4 5), short_list = %(1);
  return xs.cddddr().equal(%(5))
    && short_list.cddddr().len() == 0;
}
meta int optional_Var_listchar(int unused) {
  (void) unused;
  List xs = %(${(char) 65});
  Var value = xs, other = 7;
  ListChar view = value.listchar(), empty = other.listchar();
  return view === xs
    && empty.len() == 0;
}
meta int optional_Var_listshort(int unused) {
  (void) unused;
  List xs = %(${(short) 65});
  Var value = xs, other = 7;
  ListShort view = value.listshort(), empty = other.listshort();
  return view === xs
    && empty.len() == 0;
}
meta int optional_Var_listint(int unused) {
  (void) unused;
  List xs = %(${65});
  Var value = xs, other = 7;
  ListInt view = value.listint(), empty = other.listint();
  return view === xs
    && empty.len() == 0;
}
meta int optional_Var_listfloat(int unused) {
  (void) unused;
  List xs = %(${(float) 1.5});
  Var value = xs, other = 7;
  ListFloat view = value.listfloat(), empty = other.listfloat();
  return view === xs
    && empty.len() == 0;
}
meta int optional_Var_listdbl(int unused) {
  (void) unused;
  List xs = %(${1.5});
  Var value = xs, other = 7;
  ListDbl view = value.listdbl(), empty = other.listdbl();
  return view === xs
    && empty.len() == 0;
}
meta int optional_Var_liststring(int unused) {
  (void) unused;
  List xs = %(${"abc"});
  Var value = xs, other = 7;
  ListString view = value.liststring(), empty = other.liststring();
  return view === xs
    && empty.len() == 0;
}
meta int optional_Var_listsymbol(int unused) {
  (void) unused;
  List xs = %(${<abc>});
  Var value = xs, other = 7;
  ListSymbol view = value.listsymbol(), empty = other.listsymbol();
  return view === xs
    && empty.len() == 0;
}
meta int optional_Var_cdddr(int unused) {
  (void) unused;
  Var xs = %(1 2 3 4 5), short_list = %(1);
  return xs.cdddr().equal(%(4 5))
    && short_list.cdddr().len() == 0;
}
meta int optional_Var_cddddr(int unused) {
  (void) unused;
  Var xs = %(1 2 3 4 5), short_list = %(1);
  return xs.cddddr().equal(%(5))
    && short_list.cddddr().len() == 0;
}
meta int optional_String_sha256(int unused) {
  (void) unused;
  return "abc".sha256().equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    && "".sha256().equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
}
meta int optional_Var_json(int unused) {
  (void) unused;
  Var v = {"b": 2, "a": 1};
  return v.json().equal("{\"a\":1,\"b\":2}");
}
meta int optional_Var_pretty_json(int unused) {
  (void) unused;
  Var v = [1, 2];
  return v.pretty_json().contains("\n")
    && v.pretty_json().contains("1");
}
meta int optional_String_new_len(int unused) {
  (void) unused;
  return String.new_len("abcd", 2).equal("ab")
    && String.new_len("abcd", 0).len() == 0;
}
meta int optional_Symbol_new_len(int unused) {
  (void) unused;
  return Symbol.new_len("abcdef", 3) == <abc>
    && Symbol.new_len("abc", 0) == "".symbol();
}
meta int optional_Symbol_parse(int unused) {
  (void) unused;
  return Symbol.parse("<abc>") == <abc>
    && Symbol.parse("abc") == <abc>;
}
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
